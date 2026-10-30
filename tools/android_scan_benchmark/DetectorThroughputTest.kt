package co.local.personas.flutter

import android.graphics.BitmapFactory
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONArray
import org.json.JSONObject
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import org.opencv.objdetect.FaceDetectorYN
import org.opencv.objdetect.FaceRecognizerSF
import java.io.File

/** Explicit local profiling with a public QA image packaged only in the test APK. */
@RunWith(AndroidJUnit4::class)
class DetectorThroughputTest {
 @Test fun compareCpuProfilesWithIdenticalInputs() {
  val inst=InstrumentationRegistry.getInstrumentation();val context=inst.targetContext
  check(InstrumentationRegistry.getArguments().getString("localBenchmark")=="true")
  check(OpenCVLoader.initLocal())
  fun model(name:String):String=File(context.noBackupFilesDir,name).also {file ->
   if(!file.exists()) context.assets.open("models/$name").use {input->file.outputStream().use {input.copyTo(it)}}
  }.absolutePath
  val bitmap=inst.context.assets.open("face.png").use {BitmapFactory.decodeStream(it)}
  val rgba=Mat();val face=Mat();Utils.bitmapToMat(bitmap,rgba);bitmap.recycle();Imgproc.cvtColor(rgba,face,Imgproc.COLOR_RGBA2BGR);rgba.release()
  val full=Mat();val scaled=Mat();Imgproc.resize(face,full,Size(2400.0,3200.0));Imgproc.resize(full,scaled,Size(720.0,960.0))
  val path=model("yunet.onnx")
  fun detector()=FaceDetectorYN.create(path,"",Size(320.0,320.0),.85f,.3f,5000)
  val shared=detector();val large=detector();val small=detector();val result=Mat()
  val samples=JSONArray();var expected:List<FloatArray>?=null
  for(round in 0..2) for(profile in if(round%2==0)listOf("shared2","split2","shared1","shared4") else listOf("shared4","shared1","split2","shared2")) {
   val threads=profile.last().digitToInt();Core.setNumThreads(threads)
   val outputs=mutableListOf<FloatArray>();val start=SystemClock.elapsedRealtimeNanos()
   repeat(3) {
    for((i,image) in listOf(full,scaled).withIndex()) {
     val d=if(profile.startsWith("split"))if(i==0)large else small else shared
     d.setInputSize(image.size());d.detect(image,result)
     val data=FloatArray((result.total()*result.channels()).toInt());if(data.isNotEmpty())result.get(0,0,data);outputs.add(data)
    }
   }
   val ms=(SystemClock.elapsedRealtimeNanos()-start)/1e6
   if(expected==null)expected=outputs else {assertEquals(expected!!.size,outputs.size);for(i in outputs.indices)assertArrayEquals("Detector output changed",expected!![i],outputs[i],0f)}
   samples.put(JSONObject().put("round",round).put("profile",profile).put("ms",ms))
  }
  // SFace can have a different best thread count from full-resolution detection.
  shared.setInputSize(face.size());shared.detect(face,result);assertTrue(result.rows()>0)
  val recognizer=FaceRecognizerSF.create(model("sface.onnx"),"");val crop=Mat();val feature=Mat();recognizer.alignCrop(face,result.row(0),crop)
  var original:FloatArray?=null
  for(round in 0..2)for(threads in if(round%2==0)listOf(2,1,4)else listOf(4,1,2)) {
   Core.setNumThreads(threads);val start=SystemClock.elapsedRealtimeNanos()
   repeat(40){recognizer.feature(crop,feature)}
   val values=FloatArray(128);feature.get(0,0,values)
   if(original==null)original=values else assertArrayEquals(original,values,0f)
   samples.put(JSONObject().put("round",round).put("profile","sface$threads").put("ms",(SystemClock.elapsedRealtimeNanos()-start)/1e6))
  }
  val report=JSONObject().put("identicalFloatOutputs",true).put("samples",samples).toString()
  File(context.cacheDir,"qa-throughput.json").writeText(report)
  inst.sendStatus(0,android.os.Bundle().apply {putString("metrics",report)})
  Core.setNumThreads(2);face.release();full.release();scaled.release();result.release();crop.release();feature.release()
 }
}
