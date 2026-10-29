#import "NativeFaceEngine.h"
#import <CommonCrypto/CommonDigest.h>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/objdetect.hpp>
#include <array>
#include <algorithm>
#include <stdexcept>
#include <cmath>
#include <optional>
#include <unordered_map>
#include <vector>

namespace {
using Vector=std::vector<float>;
using Row=std::array<float,15>;
struct Photo {std::vector<Row> rows;std::vector<std::optional<Vector>> vectors;uint64_t touched=0;};
Vector normalize(const Vector& input) {
    double sum=0;for(float v:input) {if(!std::isfinite(v)) throw std::runtime_error("Invalid embedding");sum+=double(v)*v;}
    const double norm=std::sqrt(sum);if(norm<=1e-12) throw std::runtime_error("Empty embedding");
    Vector out;out.reserve(input.size());for(float v:input) out.push_back(float(v/norm));return out;
}
float cosinePrepared(const Vector& a,const Vector& b) {
    double sum=0;for(size_t i=0;i<a.size();i++) sum+=double(a[i])*b[i];return std::clamp(float(sum),-1.f,1.f);
}
float iou(const Row& a,const Row& b) {
    const float w=std::max(0.f,std::min(a[0]+a[2],b[0]+b[2])-std::max(a[0],b[0]));
    const float h=std::max(0.f,std::min(a[1]+a[3],b[1]+b[3])-std::max(a[1],b[1]));
    const float intersection=w*h,area=a[2]*a[3]+b[2]*b[3]-intersection;return area>0?intersection/area:0;
}
cv::Mat bgr(NSData *pixels,int width,int height) {
    if(width<=0 || height<=0 || width>3200 || height>3200 || pixels.length!=size_t(width)*height*4) throw std::runtime_error("Invalid pixels");
    cv::Mat rgba(height,width,CV_8UC4,const_cast<void *>(pixels.bytes)),out;
    cv::cvtColor(rgba,out,cv::COLOR_RGBA2BGR);return out;
}
NSError *nativeError(const std::exception& error) {
    return [NSError errorWithDomain:@"Personas.Inference" code:1 userInfo:@{NSLocalizedDescriptionKey:@"No se pudo analizar la imagen. Prueba otra foto clara."}];
}
bool modelValid(NSString *path,NSString *expected) {
    NSData *bytes=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if(!bytes) return false;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(bytes.bytes,CC_LONG(bytes.length),digest);
    NSMutableString *actual=[NSMutableString string];for(auto v:digest) [actual appendFormat:@"%02x",v];
    return [actual isEqualToString:expected];
}
}

@implementation NativeFaceEngine {
    cv::Ptr<cv::FaceDetectorYN> _detector;
    cv::Ptr<cv::FaceRecognizerSF> _recognizer;
    std::unordered_map<std::string,std::vector<Vector>> _references;
    std::vector<Vector> _prepared;
    std::unordered_map<std::string,Photo> _cache;
    uint64_t _clock;
    size_t _bytes;
}
- (instancetype)initWithModels:(NSString *)directory error:(NSError **)error {
    self=[super init];if(!self) return nil;
    try {
        NSString *yunet=[directory stringByAppendingPathComponent:@"yunet.onnx"];
        NSString *sface=[directory stringByAppendingPathComponent:@"sface.onnx"];
        if(!modelValid(yunet,@"8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4") ||
           !modelValid(sface,@"0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79")) throw std::runtime_error("Model integrity");
        cv::setNumThreads(2);
        _detector=cv::FaceDetectorYN::create(yunet.UTF8String,"",{320,320},.85f,.3f,5000);
        _recognizer=cv::FaceRecognizerSF::create(sface.UTF8String,"");
        _clock=0;_bytes=0;
    } catch(const std::exception& e) {if(error) *error=nativeError(e);return nil;}
    return self;
}
- (std::vector<Row>)detect:(const cv::Mat&)image threshold:(float)threshold {
    _detector->setScoreThreshold(threshold);
    std::vector<Row> candidates;
    int longest=std::max(image.cols,image.rows);
    for(double scale:longest>960?std::vector<double>{1.,960./longest}:std::vector<double>{1.}) {
        cv::Mat resized,detections;
        const cv::Mat *input=&image;
        if(scale!=1.) {cv::resize(image,resized,{std::max(1,int(image.cols*scale)),std::max(1,int(image.rows*scale))});input=&resized;}
        _detector->setInputSize(input->size());_detector->detect(*input,detections);
        float sx=float(image.cols)/input->cols,sy=float(image.rows)/input->rows;
        for(int i=0;i<detections.rows;i++) {
            Row row;std::copy_n(detections.ptr<float>(i),15,row.begin());
            row[0]*=sx;row[1]*=sy;row[2]*=sx;row[3]*=sy;
            for(int j=4;j<=12;j+=2) {row[j]*=sx;row[j+1]*=sy;}
            if(row[2]>=24 && row[3]>=24) candidates.push_back(row);
        }
    }
    std::stable_sort(candidates.begin(),candidates.end(),[](auto& a,auto& b){return a[14]>b[14];});
    std::vector<Row> kept;
    for(auto& row:candidates) if(std::none_of(kept.begin(),kept.end(),[&](auto& other){return iou(row,other)>.4f;})) kept.push_back(row);
    std::stable_sort(kept.begin(),kept.end(),[](auto& a,auto& b){return a[1]==b[1]?a[0]<b[0]:a[1]<b[1];});
    return kept;
}
- (Vector)embedding:(const cv::Mat&)image row:(const Row&)row {
    cv::Mat box(1,15,CV_32F,const_cast<float *>(row.data())),crop,feature,reflected,reflectedFeature;
    _recognizer->alignCrop(image,box,crop);_recognizer->feature(crop,feature);
    if(feature.total()!=128) throw std::runtime_error("SFace dimension");
    auto original=normalize(Vector(feature.ptr<float>(),feature.ptr<float>()+128));
    cv::flip(crop,reflected,1);_recognizer->feature(reflected,reflectedFeature);
    if(reflectedFeature.total()!=128) throw std::runtime_error("SFace dimension");
    auto mirrored=normalize(Vector(reflectedFeature.ptr<float>(),reflectedFeature.ptr<float>()+128));
    Vector merged(128);double norm=0;
    for(size_t i=0;i<128;i++) {merged[i]=original[i]+mirrored[i];norm+=double(merged[i])*merged[i];}
    return norm<=1e-24?original:normalize(merged);
}
- (NSDictionary *)referenceRGBA:(NSData *)pixels width:(int)width height:(int)height error:(NSError **)error {
    try {
        auto image=bgr(pixels,width,height);auto rows=[self detect:image threshold:.65f];
        NSString *token=NSUUID.UUID.UUIDString;std::vector<Vector> vectors;NSMutableArray *faces=[NSMutableArray array];
        for(size_t index=0;index<rows.size();index++) {
            auto& row=rows[index];vectors.push_back([self embedding:image row:row]);
            [faces addObject:@{@"id":[NSString stringWithFormat:@"%@:%zu",token,index],@"x":@(row[0]/width),@"y":@(row[1]/height),@"width":@(row[2]/width),@"height":@(row[3]/height)}];
        }
        _references[token.UTF8String]=std::move(vectors);
        return @{@"token":token,@"width":@(width),@"height":@(height),@"faces":faces};
    } catch(const std::exception& e) {if(error) *error=nativeError(e);return nil;}
}
- (BOOL)prepareFaces:(NSArray<NSString *> *)faces error:(NSError **)error {
    try {
        std::vector<Vector> prepared;
        for(NSString *handle in faces) {
            NSRange separator=[handle rangeOfString:@":" options:NSBackwardsSearch];
            if(separator.location==NSNotFound) throw std::runtime_error("Invalid reference");
            auto token=[[handle substringToIndex:separator.location] UTF8String];
            auto index=[[handle substringFromIndex:separator.location+1] integerValue];
            auto entry=_references.find(token);
            if(entry==_references.end() || index<0 || size_t(index)>=entry->second.size()) throw std::runtime_error("Expired reference");
            prepared.push_back(normalize(entry->second[index]));
        }
        if(prepared.empty()) throw std::runtime_error("Missing references");_prepared=std::move(prepared);return YES;
    } catch(const std::exception& e) {if(error) *error=nativeError(e);return NO;}
}
- (NSDictionary *)decision:(Photo&)photo image:(const cv::Mat *)image key:(NSString *)key {
    float best=-1;bool missing=false;
    for(size_t i=0;i<photo.rows.size();i++) {
        if(!photo.vectors[i]) {
            if(!image) {missing=true;continue;}
            photo.vectors[i]=normalize([self embedding:*image row:photo.rows[i]]);
        }
        for(auto& reference:_prepared) best=std::max(best,cosinePrepared(reference,*photo.vectors[i]));
        if(best>=.50f) return @{@"outcome":@"match",@"key":key};
    }
    if(missing) return nil;
    return @{@"outcome":photo.rows.empty()?@"noFace":best>=.363f?@"review":@"none",@"key":key};
}
- (NSDictionary *)cachedMatch:(NSString *)key {
    auto entry=_cache.find(key.UTF8String);if(entry==_cache.end()) return nil;
    entry->second.touched=++_clock;return [self decision:entry->second image:nullptr key:key];
}
- (NSDictionary *)matchRGBA:(NSData *)pixels width:(int)width height:(int)height key:(NSString *)key error:(NSError **)error {
    try {
        auto image=bgr(pixels,width,height);auto entry=_cache.find(key.UTF8String);
        if(entry!=_cache.end()) {entry->second.touched=++_clock;return [self decision:entry->second image:&image key:key];}
        Photo photo;photo.rows=[self detect:image threshold:.85f];photo.vectors.resize(photo.rows.size());photo.touched=++_clock;
        const size_t cost=photo.rows.size()*(15+128)*sizeof(float);
        auto result=[self decision:photo image:&image key:key];
        if(cost<=20*1024*1024) {
            while(!_cache.empty() && (_cache.size()>=1024 || _bytes+cost>20*1024*1024)) {
                auto oldest=std::min_element(_cache.begin(),_cache.end(),[](auto& a,auto& b){return a.second.touched<b.second.touched;});
                _bytes-=oldest->second.rows.size()*(15+128)*sizeof(float);_cache.erase(oldest);
            }
            _bytes+=cost;_cache[key.UTF8String]=std::move(photo);
        }
        return result;
    } catch(const std::exception& e) {if(error) *error=nativeError(e);return nil;}
}
- (void)releaseReference:(NSString *)token {_references.erase(token.UTF8String);}
- (void)clearAnalysisCache {_cache.clear();_bytes=0;}
- (void)clear {_cache.clear();_references.clear();_prepared.clear();_bytes=0;}
@end
