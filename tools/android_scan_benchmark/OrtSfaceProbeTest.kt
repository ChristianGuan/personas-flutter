package co.local.personas.flutter
import android.graphics.BitmapFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import ai.onnxruntime.*
import co.local.personas.domain.Matching
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.*
import org.opencv.android.*
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import org.opencv.dnn.Dnn
import org.opencv.objdetect.*
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.abs

/** Research only: reports numerical differences, never enables another backend in Halladin. */
@RunWith(AndroidJUnit4::class)
class OrtSfaceProbeTest {
 @Test fun compareSameModelBackends() {
  val inst=InstrumentationRegistry.getInstrumentation();val ctx=inst.targetContext;check(OpenCVLoader.initLocal());Core.setNumThreads(2)
  fun model(name:String)=File(ctx.noBackupFilesDir,name).also {f->if(!f.exists())ctx.assets.open("models/$name").use {input->f.outputStream().use {input.copyTo(it)}}}.absolutePath
  val bitmap=inst.context.assets.open("face.png").use {BitmapFactory.decodeStream(it)};val rgba=Mat();val bgr=Mat();Utils.bitmapToMat(bitmap,rgba);bitmap.recycle();Imgproc.cvtColor(rgba,bgr,Imgproc.COLOR_RGBA2BGR)
  val d=FaceDetectorYN.create(model("yunet.onnx"),"",bgr.size(),.85f,.3f,5000);val boxes=Mat();d.detect(bgr,boxes);assertTrue(boxes.rows()>0)
  val r=FaceRecognizerSF.create(model("sface.onnx"),"");val crop=Mat();val feature=Mat();r.alignCrop(bgr,boxes.row(0),crop);r.feature(crop,feature);val baseline=FloatArray(128);feature.get(0,0,baseline)
  val blob=Dnn.blobFromImage(crop,1.0,Size(112.0,112.0),Scalar(0.0,0.0,0.0),true,false);val pixels=FloatArray((blob.total()*blob.channels()).toInt());blob.get(intArrayOf(0,0,0,0),pixels)
  val samples=JSONArray();var start=System.nanoTime();repeat(40){r.feature(crop,feature)};samples.put(JSONObject().put("backend","opencv2threads").put("inferenceMs40",(System.nanoTime()-start)/1e6))
  val env=OrtEnvironment.getEnvironment()
  for(backend in listOf("cpu","xnnpack","nnapi")) {
   try {
    OrtSession.SessionOptions().use {options->
     options.setIntraOpNumThreads(if(backend=="xnnpack")1 else 2);options.setInterOpNumThreads(1)
     options.addConfigEntry("session.intra_op.allow_spinning","0")
     if(backend=="xnnpack")options.addXnnpack(mapOf("intra_op_num_threads" to "2"))
     if(backend=="nnapi")options.addNnapi()
     start=System.nanoTime()
     env.createSession(model("sface.onnx"),options).use {session->
      val initMs=(System.nanoTime()-start)/1e6
      OnnxTensor.createTensor(env,FloatBuffer.wrap(pixels),longArrayOf(1,3,112,112)).use {tensor->
       fun infer():FloatArray=session.run(mapOf(session.inputNames.first() to tensor)).use {result->(result[0] as OnnxTensor).floatBuffer.let {f->FloatArray(f.remaining()).also {f.get(it)}}}
       val values=infer();assertEquals(128,values.size);start=System.nanoTime();repeat(40){infer()}
       samples.put(JSONObject().put("backend",backend).put("initMs",initMs).put("inferenceMs40",(System.nanoTime()-start)/1e6).put("cosineVsOpenCV",Matching.cosine(baseline,values)).put("maxAbsDifference",values.indices.maxOf {abs(values[it]-baseline[it]).toDouble()}))
      }
     }
    }
   }catch(e:Exception){samples.put(JSONObject().put("backend",backend).put("error",e.javaClass.simpleName))}
  }
  inst.sendStatus(0,android.os.Bundle().apply {putString("metrics",JSONObject().put("scope","Same SFace FP32 model, one public aligned face; research only, no accuracy claim").put("samples",samples).toString())})
  rgba.release();bgr.release();boxes.release();crop.release();feature.release();blob.release()
 }
}
