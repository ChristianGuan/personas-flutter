package co.local.personas.data

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.domain.Matching
import co.local.personas.domain.MatchDecision
import kotlinx.coroutines.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.Executors

/** Public AT&T data is supplied at runtime in private QA cache; never bundled in the app. */
@RunWith(AndroidJUnit4::class)
class FilteringTest {
    private val context get()=InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixtures(): File {
        val name=InstrumentationRegistry.getArguments().getString("filterFixtures")
        assumeTrue(name!=null)
        return File(context.cacheDir,name!!).also {assertTrue(it.isDirectory)}
    }
    private fun image(dir: File,subject: Int,index: Int)=File(dir,"s%02d-%02d.png".format(subject,index))

    @Test fun calibrationAndHeldOutSubjectsKeepAutomaticAndReviewCountsSeparate() = runBlocking {
        val dir=fixtures()
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        try {withContext(worker) {
            val engine=OpenCvFaces(context,cacheEnabled=false)
            val candidates=mutableMapOf<Pair<Int,Int>,List<FloatArray>>()
            val references=mutableMapOf<Pair<Int,Int>,FloatArray>()
            for(subject in 1..40) for(index in 1..10) {
                val bitmap=BitmapFactory.decodeFile(image(dir,subject,index).absolutePath)
                try {
                    val faces=engine.analyze(bitmap)
                    assertTrue("Public query must have a usable face",faces.isNotEmpty())
                    candidates[subject to index]=faces.map {it.embedding}
                    if(index<=4) {
                        val found=engine.analyzeReference(bitmap)
                        references[subject to index]=found.maxBy {it.bounds.width()*it.bounds.height()}.embedding
                    }
                } finally {bitmap.recycle()}
            }
            val report=JSONObject().put("source","AT&T Laboratories Cambridge; 20 calibration identities and 20 distinct evaluation identities; frontal low-resolution controlled data, not family albums")
            for((name,subjects) in listOf("calibration" to (1..20),"evaluation" to (21..40))) {
                val protocols=JSONObject()
                for(count in listOf(1,2,4)) {
                    var tp=0;var fp=0;var reviewPositive=0;var reviewNegative=0;var oldTp=0;var oldFp=0;var positives=0;var negatives=0
                    for(target in subjects) {
                        val refs=(1..count).map {references.getValue(target to it)}
                        val profile=Matching.prepare(refs)
                        for(subject in subjects) for(index in count+1..10) {
                            val faces=candidates.getValue(subject to index)
                            val same=target==subject
                            if(same) positives++ else negatives++
                            val decision=profile.decide(faces)
                            val old=Matching.matchesAny(refs,faces,Matching.REVIEW_THRESHOLD)
                            if(old && same) oldTp++ else if(old) oldFp++
                            if(decision==MatchDecision.MATCH) {if(same) tp++ else fp++}
                            if(decision==MatchDecision.REVIEW) {if(same) reviewPositive++ else reviewNegative++}
                        }
                    }
                    assertEquals("Regression: automatic false positives",0,fp)
                    assertEquals("Existing candidate positives must remain available for review",oldTp,tp+reviewPositive)
                    protocols.put(count.toString(),JSONObject().put("TP",tp).put("FP",fp).put("FN",positives-tp).put("TN",negatives-fp)
                        .put("reviewPositive",reviewPositive).put("reviewNegative",reviewNegative).put("previousTP",oldTp).put("previousFP",oldFp))
                }
                report.put(name,protocols)
            }
            File(context.cacheDir,"qa-filter-metrics.json").writeText(report.toString())
        }} finally {worker.close()}
    }

    @Test fun encodedCacheSkipsDecodeButNeverTrustsUriOrIncompleteEntries() = runBlocking {
        val dir=fixtures()
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val real=ContentPhotos(context.contentResolver)
        val engine=OpenCvFaces(context)
        var deferredDecodes=0
        var initialDecodes=0
        val tracked=object: PhotoSource {
            override suspend fun decode(uri: Uri)=real.decode(uri)
            override suspend fun prepare(uri: Uri,mayReuse: (String)->Boolean)=real.prepare(uri,mayReuse).also {if(it.bitmap!=null) initialDecodes++}
            override suspend fun decodePrepared(uri: Uri,photo: PreparedPhoto)=real.decodePrepared(uri,photo).also {deferredDecodes++}
        }
        val edited=File(context.cacheDir,"qa-filter-edited.png")
        try {
            val reference=real.decode(Uri.fromFile(image(dir,1,1)))
            val refs=withContext(worker) {engine.analyzeReference(reference).map {it.embedding}};reference.recycle()
            val target=Uri.fromFile(edited)
            image(dir,1,1).copyTo(edited,overwrite=true)
            suspend fun run(): FaceMatch {
                var result: FaceMatch?=null
                BatchPhotoSearch(tracked,engine,worker).run(listOf(target),refs) {_,found -> result=found.getOrThrow()}
                return result!!
            }
            assertTrue(run().matched);assertEquals(1,initialDecodes)
            assertTrue(run().matched);assertEquals(1,initialDecodes);assertEquals(0,deferredDecodes)
            // Replacing content under the same URI invalidates both encoded and native caches.
            val blank=Bitmap.createBitmap(92,112,Bitmap.Config.ARGB_8888)
            blank.eraseColor(android.graphics.Color.LTGRAY)
            edited.outputStream().use {blank.compress(Bitmap.CompressFormat.PNG,100,it)};blank.recycle()
            assertFalse(run().hasFaces);assertEquals(2,initialDecodes)
            assertFalse(run().hasFaces);assertEquals(2,initialDecodes)
            edited.delete()
            var failure=false
            BatchPhotoSearch(tracked,engine,worker).run(listOf(target),refs) {_,found -> failure=found.isFailure}
            assertTrue("A revoked/missing input must never get a cached result",failure)
            withContext(worker) {engine.clearAnalysisCache()}
            image(dir,1,1).copyTo(edited,overwrite=true)
            assertTrue(run().matched);assertEquals(3,initialDecodes)
        } finally {edited.delete();worker.close()}
    }

    @Test fun byteSnapshotsPreserveExifAndOversizeFallback() = runBlocking {
        val dir=fixtures()
        val source=ContentPhotos(context.contentResolver,64)
        val jpeg=File(context.cacheDir,"qa-filter-orientation.jpg")
        val large=File(context.cacheDir,"qa-filter-large.png")
        try {
            val bitmap=BitmapFactory.decodeFile(image(dir,1,1).absolutePath)
            val stream=java.io.ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG,95,stream);bitmap.recycle()
            val raw=stream.toByteArray()
            for(orientation in 1..8) {
                // Valid APP1 EXIF: little-endian TIFF with one SHORT orientation entry.
                val exif=byteArrayOf(69,120,105,102,0,0,73,73,42,0,8,0,0,0,1,0,18,1,3,0,1,0,0,0,orientation.toByte(),0,0,0,0,0,0,0)
                jpeg.outputStream().use {out ->
                    out.write(raw,0,2);out.write(byteArrayOf(0xff.toByte(),0xe1.toByte(),0, (exif.size+2).toByte()));out.write(exif);out.write(raw,2,raw.size-2)
                }
                val uri=Uri.fromFile(jpeg)
                val original=source.decode(uri)
                val prepared=source.prepare(uri) {true}
                assertNull(prepared.bitmap);assertNotNull(prepared.encodedKey)
                val snapshot=source.decodePrepared(uri,prepared)
                assertTrue("Orientation $orientation must preserve exact ImageDecoder output",original.sameAs(snapshot))
                assertEquals(64,maxOf(snapshot.width,snapshot.height))
                original.recycle();snapshot.recycle()
            }
            large.outputStream().use {out ->
                out.write(image(dir,1,1).readBytes())
                val padding=ByteArray(1024*1024)
                repeat(9) {out.write(padding)}
            }
            val prepared=source.prepare(Uri.fromFile(large)) {fail("Oversize content must not use an encoded alias");true}
            assertNull(prepared.encoded);assertNull(prepared.encodedKey);assertNotNull(prepared.bitmap)
            prepared.release()
        } finally {jpeg.delete();large.delete()}
    }

    @Test fun encodedAliasesNeverFinalizePartiallyComputedFacesForANewPerson() = runBlocking {
        val name=InstrumentationRegistry.getArguments().getString("faceFixture")
        assumeTrue(name!=null)
        val face=BitmapFactory.decodeFile(File(context.cacheDir,name!!).absolutePath)
        val group=Bitmap.createBitmap(face.width*3,face.height*3,Bitmap.Config.ARGB_8888)
        val canvas=android.graphics.Canvas(group)
        for(y in 0..2) for(x in 0..2) canvas.drawBitmap(face,x*face.width.toFloat(),y*face.height.toFloat(),null)
        face.recycle()
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        try {withContext(worker) {
            val engine=OpenCvFaces(context)
            val faces=engine.analyze(group)
            assertEquals(9,faces.size)
            val profile=Matching.prepare(listOf(faces.first().embedding))
            val different=Matching.prepare(listOf(FloatArray(128) {-faces.first().embedding[it]}))
            val first=engine.matchPrepared(group,profile,"test-public-encoded-key")
            assertEquals(1,first.computedEmbeddings)
            assertTrue(engine.matchEncoded("test-public-encoded-key",profile)!!.matched)
            assertNull("Incomplete embeddings must request a decode for a different person",engine.matchEncoded("test-public-encoded-key",different))
            val complete=engine.matchPrepared(group,different,"test-public-encoded-key")
            assertEquals(8,complete.computedEmbeddings);assertFalse(complete.matched)
            assertEquals(complete.decision,engine.matchEncoded("test-public-encoded-key",different)!!.decision)
            engine.clearAnalysisCache()
            assertFalse(engine.mayReuseEncoded("test-public-encoded-key"))
        }} finally {group.recycle();worker.close()}
    }
}
