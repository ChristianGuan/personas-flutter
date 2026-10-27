package co.local.personas.data

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.domain.MatchDecision
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.CvException
import org.opencv.core.Mat
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

@RunWith(AndroidJUnit4::class)
class HeicPhotoTest {
    private val context get()=InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixtures(): File {
        val name=InstrumentationRegistry.getArguments().getString("heicFixtures")
        assumeTrue("Provide the real, public HEIC fixtures outside the APK",name!=null)
        return File(context.cacheDir,name!!).also {assertTrue(it.isDirectory)}
    }
    private fun assertCompatible(bitmap: Bitmap) {
        assertEquals(Bitmap.Config.ARGB_8888,bitmap.config)
        assertTrue(bitmap.colorSpace!!.isSrgb)
        assertFalse(bitmap.isRecycled)
    }

    @Test fun compatibleSrgbBitmapIsReusedWithoutAnExtraImageAllocation() {
        val source=Bitmap.createBitmap(24,32,Bitmap.Config.ARGB_8888)
        try {assertSame(source,softwareSrgb8888(source));assertFalse(source.isRecycled)} finally {source.recycle()}
    }

    @Test fun f16AndWideColorBecomeNativeCompatibleAndReleaseTheSource() {
        assertTrue(OpenCVLoader.initLocal())
        for(config in listOf(Bitmap.Config.RGBA_F16,Bitmap.Config.ARGB_8888)) {
            val wide=Bitmap.createBitmap(48,64,config,true,ColorSpace.get(ColorSpace.Named.DISPLAY_P3))
            wide.eraseColor(Color.rgb(180,70,35))
            val expected=if(android.os.Build.VERSION.SDK_INT>=29) wide.getColor(0,0).convert(ColorSpace.get(ColorSpace.Named.SRGB)).toArgb() else null
            val mat=Mat()
            if(config==Bitmap.Config.RGBA_F16) {
                val incompatible=wide.copy(config,false)
                try {assertThrows(CvException::class.java) {Utils.bitmapToMat(incompatible,mat)}} finally {incompatible.recycle()}
            }
            val converted=softwareSrgb8888(wide)
            try {
                assertTrue(wide.isRecycled);assertCompatible(converted)
                assertEquals(48,converted.width);assertEquals(64,converted.height)
                val actual=converted.getPixel(0,0)
                if(expected!=null) {
                    assertTrue("Red channel $config: expected=$expected actual=$actual",kotlin.math.abs(Color.red(expected)-Color.red(actual))<=2)
                    assertTrue("Green channel $config: expected=$expected actual=$actual",kotlin.math.abs(Color.green(expected)-Color.green(actual))<=2)
                    assertTrue("Blue channel $config: expected=$expected actual=$actual",kotlin.math.abs(Color.blue(expected)-Color.blue(actual))<=2)
                }
                Utils.bitmapToMat(converted,mat)
                assertEquals(4,mat.channels());assertEquals(48,mat.cols());assertEquals(64,mat.rows())
            } finally {converted.recycle();mat.release()}
        }
    }

    @Test fun ordinaryJpegAndPngKeepThePreviousDecoderPixels() = runBlocking {
        val image=Bitmap.createBitmap(96,128,Bitmap.Config.ARGB_8888)
        image.setPixels(IntArray(96*128) {i -> Color.rgb(i%255,(i/4)%255,(i/8)%255)},0,96,0,0,96,128)
        try {for((extension,format) in listOf("jpg" to Bitmap.CompressFormat.JPEG,"png" to Bitmap.CompressFormat.PNG)) {
            val file=File(context.cacheDir,"qa-heic-baseline.$extension")
            try {
                file.outputStream().use {image.compress(format,95,it)}
                val original=ImageDecoder.decodeBitmap(ImageDecoder.createSource(file)) {decoder,_,_ ->
                    decoder.allocator=ImageDecoder.ALLOCATOR_SOFTWARE;decoder.setTargetSize(48,64)
                }
                val actual=ContentPhotos(context.contentResolver,64).decode(Uri.fromFile(file))
                try {assertCompatible(actual);assertTrue(original.sameAs(actual))} finally {original.recycle();actual.recycle()}
            } finally {file.delete()}
        }} finally {image.recycle()}
    }

    @Test fun realHeic8And10BitAndP3HaveTheSameUriAndSnapshotPixels() = runBlocking {
        val dir=fixtures()
        val source=ContentPhotos(context.contentResolver,256)
        val details=JSONArray()
        for(name in listOf("face-srgb.HEIC","face-10bit.heic","face-p3.heic","face-p3-10bit.heic","face-rotated-10bit.heic","face-mirrored-10bit.heic")) {
            val uri=Uri.fromFile(File(dir,name))
            val before=File(dir,name).readBytes()
            val detail=JSONObject().put("fixture",name)
            try {
                val original=ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver,uri)) {decoder,_,_ ->decoder.allocator=ImageDecoder.ALLOCATOR_SOFTWARE}
                detail.put("originalBitmapConfig",original.config.toString()).put("originalColorSpace",original.colorSpace.toString());original.recycle()
            } catch(_: IOException) {detail.put("androidDecoderRejected",true)}
            details.put(detail)
            val decoded=source.decode(uri)
            val prepared=source.prepare(uri) {true}
            val snapshot=source.decodePrepared(uri,prepared)
            try {
                assertCompatible(decoded);assertCompatible(snapshot)
                assertEquals(256,maxOf(decoded.width,decoded.height))
                assertTrue(decoded.sameAs(snapshot))
                assertArrayEquals("Original encoded file must remain unchanged",before,File(dir,name).readBytes())
            } finally {decoded.recycle();snapshot.recycle();prepared.release()}
        }
        File(context.cacheDir,"qa-heic-decoder-metrics.json").writeText(JSONObject().put("publicFixtures",details).toString())
    }

    @Test fun heicReferenceAndBatchUseRealInferenceAndRepeatedCache() = runBlocking {
        val dir=fixtures()
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val engine=OpenCvFaces(context)
        val source=ContentPhotos(context.contentResolver)
        try {
            val reference=source.decode(Uri.fromFile(File(dir,"face-srgb.HEIC")))
            val refs=try {withContext(worker) {
                listOf(engine.analyzeReference(reference).maxBy {it.bounds.width()*it.bounds.height()}.embedding)
            }} finally {reference.recycle()}
            val scope=listOf("face-srgb.HEIC","face-10bit.heic","face-p3.heic","face-p3-10bit.heic","face-rotated-10bit.heic","face-mirrored-10bit.heic","blank.heic","broken.heic").map {Uri.fromFile(File(dir,it))}
            repeat(2) {round ->
                val outcomes=mutableListOf<FaceMatch?>()
                BatchPhotoSearch(source,engine,worker).run(scope,refs) {uri,result ->
                    assertEquals(scope[outcomes.size],uri);outcomes.add(result.getOrNull())
                }
                assertEquals(8,outcomes.size)
                for(result in outcomes.take(6)) {
                    assertNotNull(result);assertTrue(result!!.hasFaces);assertEquals(MatchDecision.MATCH,result.decision)
                    if(round==1) {assertEquals(0,result.computedEmbeddings);assertTrue(result.reusedDetections)}
                }
                assertFalse(outcomes[6]!!.hasFaces)
                assertNull("A broken file is unreadable, not a negative identity comparison",outcomes[7])
            }
        } finally {worker.close()}
    }

    @Test fun fallbackRotationAndMirrorPreserveUprightPixels() = runBlocking {
        val dir=fixtures()
        val error=PhotoDecodeException(IOException("Public codec regression"))
        val baseline=HeifFallback.decode(File(dir,"orientation-1.heic").readBytes(),256,error)
        try {
            for(name in (2..8).map {"orientation-$it.heic"}) {
                val actual=HeifFallback.decode(File(dir,name).readBytes(),256,error)
                try {
                    assertCompatible(actual)
                    assertEquals(baseline.width,actual.width);assertEquals(baseline.height,actual.height)
                    val a=IntArray(actual.width*actual.height)
                    val b=IntArray(a.size)
                    actual.getPixels(a,0,actual.width,0,0,actual.width,actual.height)
                    baseline.getPixels(b,0,baseline.width,0,0,baseline.width,baseline.height)
                    val difference=a.indices.sumOf {i ->
                        kotlin.math.abs(Color.red(a[i])-Color.red(b[i])).toLong()+
                            kotlin.math.abs(Color.green(a[i])-Color.green(b[i]))+
                            kotlin.math.abs(Color.blue(a[i])-Color.blue(b[i]))
                    }.toDouble()/(a.size*3)
                    assertTrue("Orientation/color regression $name: mean channel difference=$difference",difference<6)
                } finally {actual.recycle()}
            }
        } finally {baseline.recycle()}
    }
}
