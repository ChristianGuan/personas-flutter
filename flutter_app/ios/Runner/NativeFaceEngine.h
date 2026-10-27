#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Called exclusively on the inference queue. Embeddings never cross to Dart.
@interface NativeFaceEngine : NSObject
- (nullable instancetype)initWithModels:(NSString *)directory error:(NSError **)error;
- (nullable NSDictionary *)referenceRGBA:(NSData *)pixels width:(int)width height:(int)height error:(NSError **)error;
- (BOOL)prepareFaces:(NSArray<NSString *> *)faces error:(NSError **)error;
- (nullable NSDictionary *)matchRGBA:(NSData *)pixels width:(int)width height:(int)height key:(NSString *)key error:(NSError **)error;
- (nullable NSDictionary *)cachedMatch:(NSString *)key;
- (void)releaseReference:(NSString *)token;
- (void)clearAnalysisCache;
- (void)clear;
@end
NS_ASSUME_NONNULL_END
