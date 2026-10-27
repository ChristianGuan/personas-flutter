package co.local.personas.flutter

import android.graphics.Bitmap
import android.net.Uri
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.data.*
import co.local.personas.domain.MatchDecision
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import org.json.JSONArray
import org.opencv.core.Core
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

/** Opt-in developer profiling, entirely on-device. Only aggregate timings leave the app. */
@RunWith(AndroidJUnit4::class)
class ColdSearchBenchmarkTest {
    @Test fun profileLastAuthorizedSelection() = runBlocking {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val context=instrumentation.targetContext
        val args=InstrumentationRegistry.getArguments()
        check(args.getString("localBenchmark")=="true") {"Local benchmark requires explicit invocation"}
        val snapshot=JSONObject(File(context.cacheDir,"personas-last-analysis.json").readText())
        check(!snapshot.optBoolean("active")) {"Do not interrupt an active search"}
        val state=snapshot.getJSONObject("context")
        val source=ContentPhotos(context.contentResolver)
        val counters=FacePerformance()
        val engine=OpenCvFaces(context,performance=counters)
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val preparation=AtomicLong();val deferredDecode=AtomicLong()
        val measured=object:PhotoSource {
            override suspend fun decode(uri: Uri): Bitmap=source.decode(uri)
            override suspend fun prepare(uri: Uri,mayReuse:(String)->Boolean):PreparedPhoto {
                val start=SystemClock.elapsedRealtimeNanos()
                try{return source.prepare(uri,mayReuse)}finally{preparation.addAndGet(SystemClock.elapsedRealtimeNanos()-start)}
            }
            override suspend fun decodePrepared(uri: Uri,photo:PreparedPhoto):Bitmap {
                val start=SystemClock.elapsedRealtimeNanos()
                try{return source.decodePrepared(uri,photo)}finally{deferredDecode.addAndGet(SystemClock.elapsedRealtimeNanos()-start)}
            }
        }
        suspend fun reference(reference:JSONObject,face:JSONObject):FloatArray {
            val bitmap=source.decode(Uri.parse(reference.getString("image")))
            try {
                val faces=withContext(worker){engine.analyzeReference(bitmap)}
                val expectedX=face.getDouble("x");val expectedY=face.getDouble("y")
                val best=faces.minByOrNull {abs(it.bounds.left/bitmap.width-expectedX)+abs(it.bounds.top/bitmap.height-expectedY)}
                check(best!=null && abs(best.bounds.left/bitmap.width-expectedX)+abs(best.bounds.top/bitmap.height-expectedY)<0.05) {"Reference no longer available"}
                return best.embedding.copyOf()
            }finally{bitmap.recycle()}
        }
        try {
            val refs=mutableListOf(reference(state.getJSONObject("reference"),state.getJSONObject("chosen")))
            val examples=state.optJSONArray("examples") ?: JSONArray()
            for(i in 0 until examples.length()){val e=examples.getJSONObject(i);refs.add(reference(e.getJSONObject("reference"),e.getJSONObject("face")))}
            val photos=state.getJSONArray("photos")
            val n=minOf(args.getString("sample")?.toInt() ?: 6,photos.length())
            check(n>0)
            val uris=(0 until n).map {Uri.parse(photos.getString(if(n==1)0 else it*(photos.length()-1)/(n-1)))}
            val rounds=(args.getString("rounds")?.toInt() ?: 2).coerceIn(1,3)
            val budgets=(args.getString("profiles") ?: "2:16,2:32,4:32").split(',').map {val p=it.split(':');p[0].toInt().coerceIn(1,4) to p[1].toInt().coerceIn(8,32)}
            var expected:List<Pair<Boolean,MatchDecision>?>?=null
            val results=JSONArray()
            repeat(rounds){round->
                val order=if(round%2==0)budgets else budgets.reversed()
                for((threads,prefetchMiB) in order){
                    withContext(worker){engine.clearAnalysisCache();Core.setNumThreads(threads);counters.reset()}
                    preparation.set(0);deferredDecode.set(0)
                    val actual=mutableListOf<Pair<Boolean,MatchDecision>?>();var cached=0
                    val start=SystemClock.elapsedRealtimeNanos()
                    BatchPhotoSearch(measured,engine,worker,prefetchMiB*1024*1024).run(uris,refs){_,r->
                        actual.add(r.getOrNull()?.let {if(it.reusedDetections)cached++;it.hasFaces to it.decision})
                    }
                    val total=SystemClock.elapsedRealtimeNanos()-start
                    if(expected==null)expected=actual else assertEquals(expected,actual)
                    results.put(JSONObject().apply {
                        put("round",round);put("threads",threads);put("prefetchMiB",prefetchMiB);put("photos",n);put("totalMs",total/1e6)
                        put("prepareMs",preparation.get()/1e6);put("deferredDecodeMs",deferredDecode.get()/1e6)
                        put("conversionMs",counters.conversionNs/1e6);put("fullDetectionMs",counters.fullDetectionNs/1e6)
                        put("scaledDetectionMs",counters.scaledDetectionNs/1e6);put("embeddingMs",counters.embeddingNs/1e6)
                        put("embeddings",counters.embeddings);put("cached",cached);put("optimized",Core.useOptimized());put("maxHeapMiB",Runtime.getRuntime().maxMemory()/1024/1024)
                        put("unreadable",actual.count {it==null});put("matches",actual.count {it?.second==MatchDecision.MATCH})
                    })
                    File(context.cacheDir,"qa-cold-search-metrics.json").writeText(JSONObject().put("equalDecisions",true).put("samples",results).toString())
                }
            }
        }finally{withContext(worker){Core.setNumThreads(2);engine.clearAnalysisCache()};worker.close()}
    }
}
