package co.local.personas.data

import android.content.Context
import android.os.SystemClock
import android.graphics.Bitmap
import android.graphics.RectF
import co.local.personas.domain.Matching
import co.local.personas.domain.MatchDecision
import co.local.personas.domain.PreparedReferences
import java.util.concurrent.ConcurrentHashMap
import co.local.personas.domain.FaceDetections
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import org.opencv.objdetect.FaceDetectorYN
import org.opencv.objdetect.FaceRecognizerSF
import java.io.File
import java.security.MessageDigest

// Llamar en un solo worker: las instancias nativas no se comparten concurrentemente.
class ScaleDetectorExperiment(private val context: Context,private val cacheEnabled: Boolean=true,private val performance: FacePerformance?=null,private val separateScaleDetector: Boolean=true) : FaceEngine {
    private var detector: FaceDetectorYN? = null
    private var recognizer: FaceRecognizerSF? = null
    private var scaledDetector: FaceDetectorYN? = null
    private val cache=AnalysisCache()
    // Hints may be read by the IO producer; native cache and aliases stay on the worker.
    private val hints=ConcurrentHashMap.newKeySet<String>()
    private val encodedAliases=LinkedHashMap<String,String>(16,0.75f,true)
    private fun alias(encoded: String?,pixels: String?) {
        if(encoded==null || pixels==null) return
        encodedAliases[encoded]=pixels;hints.add(encoded)
        while(encodedAliases.size>2048) {
            val iterator=encodedAliases.entries.iterator()
            hints.remove(iterator.next().key);iterator.remove()
        }
    }
    override fun mayReuseEncoded(key: String)=hints.contains(key)
    override fun matchEncoded(key: String,references: PreparedReferences): FaceMatch? {
        val pixels=encodedAliases[key] ?: return null
        val photo=cache[pixels] ?: return null
        var best=-1f
        for(vector in photo.embeddings) if(vector!=null) best=maxOf(best,references.bestScore(vector))
        if(Matching.decision(best)!=MatchDecision.MATCH && photo.embeddings.any {it==null}) return null
        return FaceMatch(photo.rows.isNotEmpty(),Matching.decision(best),0,true,pixels)
    }
    companion object {
        const val YUNET_HASH="8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4"
        const val SFACE_HASH="0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79"
        private const val PIPELINE="opencv4.12.0/$YUNET_HASH/$SFACE_HASH/bgr/srgb-argb8888-heif3.0.0-orientation-v5/max3200/full+960/det0.85/min24/iou0.4/align5/flip-mean-l2-comparison-f32-v3"
    }
    private fun model(name: String, hash: String): String {
        val file = File(context.noBackupFilesDir, name)
        fun valid(): Boolean {
            if(!file.isFile) return false
            val digest=MessageDigest.getInstance("SHA-256")
            val block=ByteArray(64*1024)
            file.inputStream().use {input ->
                while(true) {
                    val count=input.read(block)
                    if(count<0) break
                    digest.update(block,0,count)
                }
            }
            return digest.digest().hexDigest()==hash
        }
        if (!valid()) {
            context.assets.open("models/$name").use { input -> file.outputStream().use { input.copyTo(it) } }
            check(valid()) { "El modelo instalado no supera la verificación SHA-256" }
        }
        return file.absolutePath
    }
    override fun analyze(bitmap: Bitmap): List<FoundFace> = evaluate(bitmap,0.85f,null).faces
    // The user explicitly reviews these candidates; never use this looser score for album search.
    override fun analyzeReference(bitmap: Bitmap): List<FoundFace> = evaluate(bitmap,0.65f,null).faces
    override fun matchPrepared(bitmap: Bitmap,references: PreparedReferences,encodedKey: String?): FaceMatch = evaluate(bitmap,0.85f,references,encodedKey).match!!
    override fun clearAnalysisCache() {cache.clear();encodedAliases.clear();hints.clear()}
    private data class Evaluation(val faces: List<FoundFace> = emptyList(),val match: FaceMatch?=null)

    private fun imageKey(bgr: Mat): String {
        val hash=MessageDigest.getInstance("SHA-256")
        hash.update(PIPELINE.toByteArray(Charsets.UTF_8))
        hash.update("/${bgr.cols()}/${bgr.rows()}/${bgr.type()}/".toByteArray(Charsets.UTF_8))
        // Hash exactly the native input, including orientation/resize/color conversion.
        // Small row blocks avoid allocating a second image-sized byte buffer.
        val rowsPerBlock=if(bgr.isContinuous) 64 else 1
        val rowBytes=bgr.cols()*bgr.channels()
        val block=ByteArray(rowBytes*minOf(rowsPerBlock,bgr.rows()))
        var row=0
        while(row<bgr.rows()) {
            val bytes=minOf(rowsPerBlock,bgr.rows()-row)*rowBytes
            if(bytes==block.size) {
                check(bgr.get(row,0,block)==bytes)
                hash.update(block)
            } else {
                val tail=ByteArray(bytes)
                check(bgr.get(row,0,tail)==bytes)
                hash.update(tail)
            }
            row+=rowsPerBlock
        }
        return hash.digest().hexDigest()
    }

    private fun evaluate(bitmap: Bitmap,detectionThreshold: Float,references: PreparedReferences?,encodedKey: String?=null): Evaluation {
        if (detector == null) {
            check(OpenCVLoader.initLocal()) { "No se pudo iniciar OpenCV" }
            Core.setNumThreads(2)
            val newDetector = FaceDetectorYN.create(model("yunet.onnx", YUNET_HASH), "", Size(320.0, 320.0), 0.85f, 0.3f, 5000)
            val newRecognizer = FaceRecognizerSF.create(model("sface.onnx", SFACE_HASH), "")
            detector = newDetector
            recognizer = newRecognizer
        }
        // Explicitly reset on every call because the detector is reused between reference and search.
        detector!!.setScoreThreshold(detectionThreshold)
        val rgba = Mat(); val bgr = Mat()
        try {
            val conversionStart=if(performance!=null) SystemClock.elapsedRealtimeNanos() else 0L
            Utils.bitmapToMat(bitmap, rgba)
            Imgproc.cvtColor(rgba, bgr, Imgproc.COLOR_RGBA2BGR)
            performance?.let {it.conversionNs+=SystemClock.elapsedRealtimeNanos()-conversionStart}
            val key=if(cacheEnabled && references!=null) (encodedKey?.let {encodedInputKey(PIPELINE,it)} ?: imageKey(bgr)) else null
            alias(encodedKey,key)
            val reused=key?.let {cache[it]}
            val photo=reused ?: detect(bgr).let(::DetectedPhoto).also {if(key!=null) cache.put(key,it)}
            val row=Mat(1,15,CvType.CV_32F);val crop=Mat();val feature=Mat();val reflected=Mat();val reflectedFeature=Mat()
            var computed=0
            fun embedding(index: Int): FloatArray = photo.embeddings[index] ?: run {
                row.put(0,0,photo.rows[index])
                val embeddingStart=if(performance!=null) SystemClock.elapsedRealtimeNanos() else 0L
                recognizer!!.alignCrop(bgr,row,crop)
                recognizer!!.feature(crop,feature)
                check(feature.total()==128L) {"Dimensión inesperada del modelo SFace"}
                val vector=FloatArray(128);feature.get(0,0,vector)
                // Reflect the ALIGNED crop: never mirror the source landmarks or
                // merge identities. Cache the fused descriptor for subsequent searches.
                Core.flip(crop,reflected,1)
                recognizer!!.feature(reflected,reflectedFeature)
                check(reflectedFeature.total()==128L) {"Dimensión inesperada del modelo SFace"}
                val reflectedVector=FloatArray(128);reflectedFeature.get(0,0,reflectedVector)
                val normalized=Matching.mergeViews(vector,reflectedVector)
                performance?.let {it.embeddingNs+=SystemClock.elapsedRealtimeNanos()-embeddingStart;it.embeddings+=2}
                (if(references!=null) Matching.normalize(normalized) else normalized).also {photo.embeddings[index]=it;computed++}
            }
            try {
                if(references!=null) {
                    var best=-1f
                    for(index in photo.rows.indices) {
                        best=maxOf(best,references.bestScore(embedding(index)))
                        if(Matching.decision(best)==MatchDecision.MATCH)
                            return Evaluation(match=FaceMatch(true,MatchDecision.MATCH,computed,reused!=null,key))
                    }
                    return Evaluation(match=FaceMatch(photo.rows.isNotEmpty(),Matching.decision(best),computed,reused!=null,key))
                }
                return Evaluation(faces=photo.rows.mapIndexed {index,box ->
                    FoundFace(RectF(box[0],box[1],box[0]+box[2],box[1]+box[3]),embedding(index).copyOf())
                })
            } finally {row.release();crop.release();feature.release();reflected.release();reflectedFeature.release()}
        } finally { rgba.release(); bgr.release() }
    }

    private fun detect(bgr: Mat): List<FloatArray> {
            val candidates=mutableListOf<FloatArray>()
            // Keep the full-resolution pass for small faces; a reduced pass also
            // brings very large faces into YuNet's useful scale range.
            val longest=maxOf(bgr.cols(),bgr.rows())
            val scales=if(longest>960) listOf(1.0,960.0/longest) else listOf(1.0)
            for(scale in scales) {
                val resized=Mat(); val detections=Mat()
                try {
                    val input=if(scale==1.0) bgr else resized.also {
                        Imgproc.resize(bgr,it,Size((bgr.cols()*scale).toInt().coerceAtLeast(1).toDouble(),(bgr.rows()*scale).toInt().coerceAtLeast(1).toDouble()))
                    }
                    val activeDetector=if(scale!=1.0 && separateScaleDetector) {
                        (scaledDetector ?: FaceDetectorYN.create(model("yunet.onnx",YUNET_HASH),"",input.size(),0.85f,0.3f,5000).also {scaledDetector=it})
                            .also {it.setScoreThreshold(detector!!.scoreThreshold)}
                    } else detector!!
                    activeDetector.setInputSize(input.size())
                    val detectionStart=if(performance!=null) SystemClock.elapsedRealtimeNanos() else 0L
                    activeDetector.detect(input,detections)
                    performance?.let {val elapsed=SystemClock.elapsedRealtimeNanos()-detectionStart;if(scale==1.0)it.fullDetectionNs+=elapsed else it.scaledDetectionNs+=elapsed;it.detections++}
                    val sx=bgr.cols().toFloat()/input.cols();val sy=bgr.rows().toFloat()/input.rows()
                    for(i in 0 until detections.rows()) {
                        val box=FloatArray(15);detections.get(i,0,box)
                        box[0]*=sx;box[1]*=sy;box[2]*=sx;box[3]*=sy
                        for(j in 4..12 step 2) {box[j]*=sx;box[j+1]*=sy}
                        if(box[2]>=24 && box[3]>=24) candidates.add(box)
                    }
                } finally {resized.release();detections.release()}
            }
            return FaceDetections.merge(candidates)
    }
}
