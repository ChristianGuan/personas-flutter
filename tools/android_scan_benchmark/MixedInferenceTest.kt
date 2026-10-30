package co.local.personas.flutter
import android.graphics.*
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.data.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.*
import java.io.File

@RunWith(AndroidJUnit4::class)
class MixedInferenceTest {
 @Test fun compareFullPipelineWithoutSkippingFaces() {
  val inst=InstrumentationRegistry.getInstrumentation();val context=inst.targetContext
  val fixture=inst.context.assets.open("face.png").use {BitmapFactory.decodeStream(it)}
  val counters=FacePerformance()
  val baseline=OpenCvFaces(context,false,counters);val candidate=ScaleDetectorExperiment(context,false,counters)
  baseline.analyzeReference(fixture);candidate.analyzeReference(fixture)
  val samples=JSONArray();val expected=mutableMapOf<Int,List<FoundFace>>()
  for(round in 0..3)for(threads in if(round%2==0)listOf(2,4)else listOf(4,2)) {
   val engine=if(threads==2)baseline else candidate
   counters.reset();var total=0.0;var count=0
   for(i in 0..5) {
    val w=if(i%2==0)2400 else 3200;val h=if(i%2==0)3200 else 2400
    val bitmap=Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888);val canvas=Canvas(bitmap);canvas.drawColor(Color.LTGRAY)
    val paint=Paint(Paint.FILTER_BITMAP_FLAG)
    for((j,size)in listOf(112,280,560).withIndex()) {
     val x=100+j*650;val y=100+(i*181+j*383)%(h-700)
     canvas.drawBitmap(fixture,null,Rect(x,y,x+(size*92/112),y+size),paint)
    }
    val start=System.nanoTime();val faces=try {engine.analyze(bitmap)}finally{bitmap.recycle()};total+=(System.nanoTime()-start)/1e6
    assertTrue(faces.isNotEmpty());count+=faces.size
    if(!expected.containsKey(i))expected[i]=faces else {
     val old=expected.getValue(i);assertEquals(old.size,faces.size)
     for(j in faces.indices){assertEquals(old[j].bounds,faces[j].bounds);assertArrayEquals(old[j].embedding,faces[j].embedding,0f)}
    }
   }
   samples.put(JSONObject().put("round",round).put("separateScaleDetector",threads==4).put("photos",6).put("faces",count).put("totalMs",total).put("conversionMs",counters.conversionNs/1e6).put("fullDetectionMs",counters.fullDetectionNs/1e6).put("scaledDetectionMs",counters.scaledDetectionNs/1e6).put("embeddingMs",counters.embeddingNs/1e6))
  }
  fixture.recycle()
  val report=JSONObject().put("identicalBoundsAndEmbeddings",true).put("scope","Synthetic compositions from one public AT&T image; models warmed, no face cache; not album accuracy").put("samples",samples).toString()
  File(context.cacheDir,"qa-mixed.json").writeText(report);inst.sendStatus(0,android.os.Bundle().apply{putString("metrics",report)})
 }
}
