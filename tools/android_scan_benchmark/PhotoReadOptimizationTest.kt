package co.local.personas.flutter
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.data.*
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.*
import java.io.File

@RunWith(AndroidJUnit4::class)
class PhotoReadOptimizationTest {
 @Test fun sameDecodedPixelsAndKeysWithoutReadingDiscardedSnapshots()=runBlocking {
  val inst=InstrumentationRegistry.getInstrumentation();val context=inst.targetContext
  val old=LegacyContentPhotos(context.contentResolver);val current=ContentPhotos(context.contentResolver)
  val small=File(context.cacheDir,"qa-public-small.png");val large=File(context.cacheDir,"qa-public-large.png")
  inst.context.assets.open("face.png").use {input->small.outputStream().use {input.copyTo(it)}}
  large.outputStream().use {out->out.write(small.readBytes());val padding=ByteArray(64*1024);repeat(192){out.write(padding)}}
  val samples=JSONArray()
  try {
   for(file in listOf(small,large)) {
    val uri=Uri.fromFile(file)
    val a=old.prepare(uri){false};val b=current.prepare(uri){false}
    try {assertEquals(a.encodedKey,b.encodedKey);assertTrue(a.bitmap!!.sameAs(b.bitmap!!))}finally{a.release();b.release()}
    for(round in 0..3)for(fast in if(round%2==0)listOf(false,true)else listOf(true,false)) {
     val source=if(fast)current else old;val start=System.nanoTime()
     repeat(10){source.prepare(uri){false}.release()}
     samples.put(JSONObject().put("round",round).put("optimized",fast).put("oversized",file==large).put("photos",10).put("ms",(System.nanoTime()-start)/1e6))
    }
   }
   val report=JSONObject().put("samePixelsAndCacheKeys",true).put("scope","Public 92x112 PNG, also padded above 12 MiB; synthetic IO benchmark, not full album latency").put("samples",samples).toString()
   inst.sendStatus(0,android.os.Bundle().apply{putString("metrics",report)})
  } finally{small.delete();large.delete()}
 }
}
