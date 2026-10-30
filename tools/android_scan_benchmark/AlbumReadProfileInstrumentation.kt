package co.local.personas.speedbench
import android.app.Instrumentation
import android.app.Activity
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import co.local.personas.data.*
import co.local.personas.domain.MatchDecision
import kotlinx.coroutines.*
import org.json.*
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

/** Explicit developer tool. Reads only an inactive selection already authorized in .pruebas. */
class AlbumReadProfileInstrumentation:Instrumentation() {
 override fun onCreate(arguments:Bundle?) {super.onCreate(arguments);check(arguments?.getString("localBenchmark")=="true");start()}
 override fun onStart() {
  try {runBlocking {profile()}} catch(e:Exception){finish(Activity.RESULT_CANCELED,Bundle().apply{putString("failure",e.javaClass.simpleName)})}
 }
 private suspend fun profile() {
  val ctx=targetContext;val snapshot=JSONObject(File(ctx.cacheDir,"personas-last-analysis.json").readText());check(!snapshot.optBoolean("active"))
  val state=snapshot.getJSONObject("context");val current=ContentPhotos(ctx.contentResolver);val old=LegacyContentPhotos(ctx.contentResolver)
  val engine=OpenCvFaces(ctx);val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
  suspend fun reference(ref:JSONObject,face:JSONObject):FloatArray {
   val bitmap=current.decode(Uri.parse(ref.getString("image")))
   try {
    val faces=withContext(worker){engine.analyzeReference(bitmap)}
    val x=face.getDouble("x");val y=face.getDouble("y")
    val chosen=faces.minByOrNull {abs(it.bounds.left/bitmap.width-x)+abs(it.bounds.top/bitmap.height-y)}
    check(chosen!=null && abs(chosen.bounds.left/bitmap.width-x)+abs(chosen.bounds.top/bitmap.height-y)<0.05)
    return chosen.embedding.copyOf()
   }finally{bitmap.recycle()}
  }
  try {
   val refs=mutableListOf(reference(state.getJSONObject("reference"),state.getJSONObject("chosen")))
   val examples=state.optJSONArray("examples") ?: JSONArray()
   for(i in 0 until examples.length()){val e=examples.getJSONObject(i);refs.add(reference(e.getJSONObject("reference"),e.getJSONObject("face")))}
   val photos=state.getJSONArray("photos");val n=minOf(6,photos.length());check(n>0)
   val uris=(0 until n).map {Uri.parse(photos.getString(if(n==1)0 else it*(photos.length()-1)/(n-1)))}
   val samples=JSONArray();var expected:List<Pair<Boolean,MatchDecision>?>?=null
   for(round in 0..1)for(mode in if(round==0)listOf("legacy","serial","parallel")else listOf("parallel","serial","legacy")) {
    withContext(worker){engine.clearAnalysisCache()}
    val source=if(mode=="legacy")old else current;val preparation=AtomicLong()
    val measured=object:PhotoSource {
     override suspend fun decode(uri:Uri)=source.decode(uri)
     override suspend fun prepare(uri:Uri,mayReuse:(String)->Boolean):PreparedPhoto {val start=System.nanoTime();try{return source.prepare(uri,mayReuse)}finally{preparation.addAndGet(System.nanoTime()-start)}}
     override suspend fun decodePrepared(uri:Uri,photo:PreparedPhoto)=source.decodePrepared(uri,photo)
    }
    val actual=mutableListOf<Pair<Boolean,MatchDecision>?>();val metrics=mutableMapOf<String,Long>();val start=System.nanoTime()
    if(mode=="parallel")ParallelPrepareSearch(measured,engine,worker).run(uris,refs){_,r->actual.add(r.getOrNull()?.let {it.hasFaces to it.decision})}
    else BatchPhotoSearch(measured,engine,worker,32*1024*1024).run(uris,refs,onMetrics={values->for((k,v)in values)metrics[k]=(metrics[k] ?: 0)+v}){_,r->actual.add(r.getOrNull()?.let {it.hasFaces to it.decision})}
    val elapsed=(System.nanoTime()-start)/1e6
    if(expected==null)expected=actual else check(expected==actual)
    samples.put(JSONObject().put("round",round).put("mode",mode).put("photos",n).put("totalMs",elapsed).put("prepareMs",preparation.get()/1e6).put("unreadable",actual.count{it==null}).put("matches",actual.count{it?.second==MatchDecision.MATCH}).put("metrics",JSONObject(metrics as Map<*,*>)))
   }
   val report=JSONObject().put("equalDecisions",true).put("scope","Six spaced entries of the last inactive authorized selection; empty face cache each run, provider cache not cleared; no images/IDs exported").put("samples",samples).toString()
   finish(Activity.RESULT_OK,Bundle().apply {putString("metrics",report)})
  }finally{withContext(worker){engine.clearAnalysisCache()};worker.close()}
 }
}
