package co.local.personas.data

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.net.Uri
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.domain.Matching
import co.local.personas.domain.MatchDecision
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

/** Optional public fixtures only. Measures decisions and native work, not product accuracy. */
@RunWith(AndroidJUnit4::class)
class SearchPerformanceTest {
    private val context get()=InstrumentationRegistry.getInstrumentation().targetContext
    private fun sample(): File {
        val name=InstrumentationRegistry.getArguments().getString("faceFixture")
        assumeTrue(name!=null)
        return File(context.cacheDir,name!!).also {assertTrue(it.isFile)}
    }
    private fun blank(name: String): File {
        val file=File(context.cacheDir,name)
        val bitmap=Bitmap.createBitmap(256,256,Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.LTGRAY)
        file.outputStream().use {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
        return file
    }
    private fun group(): Bitmap {
        val face=BitmapFactory.decodeFile(sample().absolutePath)
        return Bitmap.createBitmap(face.width*3,face.height*3,Bitmap.Config.ARGB_8888).also {group ->
            val canvas=Canvas(group)
            for(y in 0..2) for(x in 0..2) canvas.drawBitmap(face,(x*face.width).toFloat(),(y*face.height).toFloat(),null)
            face.recycle()
        }
    }

    @Test fun earlyMatchAndPartialCachePreserveOtherPeopleAndChangedContent() = runBlocking {
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val bitmap=group()
        val changed=File(context.cacheDir,"qa-performance-change.png")
        try {withContext(worker) {
            val full=OpenCvFaces(context,cacheEnabled=false)
            val all=full.analyze(bitmap)
            assertEquals(9,all.size)
            val references=listOf(all.first().embedding)
            val opposite=listOf(FloatArray(128) {-references.first()[it]})
            val fast=OpenCvFaces(context)
            val first=fast.match(bitmap,references)
            assertEquals(Matching.matchesAny(references,all.map {it.embedding}),first.matched)
            assertEquals(1,first.computedEmbeddings);assertFalse(first.reusedDetections)
            val repeated=fast.match(bitmap,references)
            assertTrue(repeated.matched);assertTrue(repeated.reusedDetections);assertEquals(0,repeated.computedEmbeddings)
            val anotherPerson=fast.match(bitmap,opposite)
            assertEquals(Matching.matchesAny(opposite,all.map {it.embedding}),anotherPerson.matched)
            assertFalse(anotherPerson.matched)
            assertEquals(8,anotherPerson.computedEmbeddings)
            assertEquals(0,fast.match(bitmap,opposite).computedEmbeddings)
            val oldPixel=bitmap.getPixel(0,0)
            bitmap.setPixel(0,0,oldPixel xor 0x00ffffff)
            assertFalse(fast.match(bitmap,references).reusedDetections)
            bitmap.setPixel(0,0,oldPixel)
            // Same URI with different pixels must not reuse a previous identity decision.
            bitmap.compressTo(changed)
            val source=ContentPhotos(context.contentResolver)
            val original=source.decode(Uri.fromFile(changed))
            assertTrue(fast.match(original,references).matched);original.recycle()
            val plain=blank("qa-performance-change.png")
            val edited=source.decode(Uri.fromFile(plain))
            val result=fast.match(edited,references);edited.recycle()
            assertFalse(result.hasFaces);assertFalse(result.matched);assertFalse(result.reusedDetections)
            val samePixelsDifferentShape=Bitmap.createBitmap(128,512,Bitmap.Config.ARGB_8888).apply {eraseColor(android.graphics.Color.LTGRAY)}
            assertFalse(fast.match(samePixelsDifferentShape,references).reusedDetections)
            samePixelsDifferentShape.recycle()
            fast.clearAnalysisCache()
            assertFalse(fast.match(bitmap,references).reusedDetections)
        }} finally {bitmap.recycle();changed.delete();worker.close()}
    }

    private fun Bitmap.compressTo(file: File) {file.outputStream().use {compress(Bitmap.CompressFormat.PNG,100,it)}}

    @Test fun firstAndRepeatedBatchHaveExactlyTheFullSearchDecisions() = runBlocking {
        val dirName=InstrumentationRegistry.getArguments().getString("identityFixtures")
        assumeTrue(dirName!=null)
        val dir=File(context.cacheDir,dirName!!)
        val uris=dir.listFiles()!!.filter {it.name.startsWith("positive-") || it.name.startsWith("negative-")}.sortedBy {it.name}.map {Uri.fromFile(it)}
        assertEquals(13,uris.size)
        val groupFile=File(context.cacheDir,"qa-performance-group.png")
        val group=group();group.compressTo(groupFile);group.recycle()
        val empty=blank("qa-performance-blank.png")
        val scope=uris.take(6)+Uri.fromFile(File(context.cacheDir,"qa-performance-missing.png"))+uris.drop(6)+Uri.fromFile(groupFile)+Uri.fromFile(empty)
        val source=ContentPhotos(context.contentResolver)
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        try {
            val baseline=OpenCvFaces(context,cacheEnabled=false);val optimized=OpenCvFaces(context)
            val reference=source.decode(Uri.fromFile(File(dir,"ref-front.jpg")))
            val references=withContext(worker) {
                val embeddings=baseline.analyzeReference(reference).map {it.embedding}
                optimized.analyzeReference(reference) // Exclude model initialization from each timed search.
                embeddings
            };reference.recycle()
            val times=mutableMapOf("full" to mutableListOf<Long>(),"first" to mutableListOf(),"repeated" to mutableListOf())
            var expected: List<Pair<Boolean,MatchDecision>?>?=null
            repeat(3) {
                val before=mutableListOf<Pair<Boolean,MatchDecision>?>()
                val start=SystemClock.elapsedRealtime()
                for(uri in scope) {
                    try {
                        val image=source.decode(uri)
                        val faces=try {withContext(worker) {baseline.analyze(image)}} finally {image.recycle()}
                        before.add(faces.isNotEmpty() to Matching.prepare(references).decide(faces.map {it.embedding}))
                    } catch(e: CancellationException) {throw e} catch(_: Exception) {before.add(null)}
                }
                times.getValue("full").add(SystemClock.elapsedRealtime()-start);expected=before
                withContext(worker) {optimized.clearAnalysisCache()}
                for(phase in listOf("first","repeated")) {
                    val actual=mutableListOf<Pair<Boolean,MatchDecision>?>()
                    val runStart=SystemClock.elapsedRealtime()
                    BatchPhotoSearch(source,optimized,worker).run(scope,references) {uri,result ->
                        assertEquals(scope[actual.size],uri)
                        actual.add(result.getOrNull()?.let {it.hasFaces to it.decision})
                    }
                    times.getValue(phase).add(SystemClock.elapsedRealtime()-runStart)
                    assertEquals(before,actual)
                }
            }
            val metrics=JSONObject().apply {
                put("scope","Public regression, 13 distinct photos plus synthetic nine-copy group, blank and missing file; not user album")
                put("photos",scope.size);put("api",android.os.Build.VERSION.SDK_INT)
                put("fullMs",org.json.JSONArray(times.getValue("full")));put("firstMs",org.json.JSONArray(times.getValue("first")));put("repeatedMs",org.json.JSONArray(times.getValue("repeated")))
                put("matchingOutcomes",expected!!.count {it?.second==MatchDecision.MATCH});put("equalDecisions",true);put("reviewOutcomes",expected!!.count {it?.second==MatchDecision.REVIEW})
            }
            File(context.cacheDir,"qa-performance-metrics.json").writeText(metrics.toString())
        } finally {groupFile.delete();empty.delete();worker.close()}
    }

    @Test fun cancellingPrefetchRecyclesCurrentAndPreparedPhotos() = runBlocking {
        val file=blank("qa-performance-cancel.png")
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val gate=CountDownLatch(1)
        val observed=ConcurrentLinkedQueue<Bitmap>()
        val real=ContentPhotos(context.contentResolver)
        val tracked=object: PhotoSource {
            override suspend fun decode(uri: Uri)=real.decode(uri).also {observed.add(it)}
        }
        try {
            val blocker=launch(worker) {gate.await()}
            val batch=launch {BatchPhotoSearch(tracked,OpenCvFaces(context),worker).run(List(3) {Uri.fromFile(file)},emptyList()) {_,_ -> fail("Cancelled work must not become a result")}}
            try {
                withTimeout(10_000) {while(observed.size<2) delay(5)}
                assertEquals(2,observed.size)
                batch.cancel()
            } finally {gate.countDown();batch.cancelAndJoin();blocker.join()}
            assertEquals(2,observed.size)
            assertTrue(observed.all {it.isRecycled})
        } finally {gate.countDown();file.delete();worker.close()}
    }

    @Test fun nativeThreadBudgetPreservesDecisionsOnThePublicBatch() = runBlocking {
        val dirName=InstrumentationRegistry.getArguments().getString("identityFixtures")
        assumeTrue(dirName!=null)
        val dir=File(context.cacheDir,dirName!!)
        val uris=dir.listFiles()!!.filter {it.name.startsWith("positive-") || it.name.startsWith("negative-")}.sortedBy {it.name}.map {Uri.fromFile(it)}
        val groupFile=File(context.cacheDir,"qa-performance-thread-group.png")
        val group=group();group.compressTo(groupFile);group.recycle()
        val scope=uris+Uri.fromFile(groupFile)
        val source=ContentPhotos(context.contentResolver)
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        try {
            val engine=OpenCvFaces(context)
            val reference=source.decode(Uri.fromFile(File(dir,"ref-front.jpg")))
            val refs=withContext(worker) {engine.analyzeReference(reference).map {it.embedding}};reference.recycle()
            val times=mutableMapOf(1 to mutableListOf<Long>(),2 to mutableListOf(),4 to mutableListOf())
            var expected: List<Pair<Boolean,MatchDecision>>?=null
            val orders=listOf(listOf(2,1,4),listOf(4,2,1),listOf(1,4,2))
            for(order in orders) for(threads in order) {
                withContext(worker) {engine.clearAnalysisCache();org.opencv.core.Core.setNumThreads(threads)}
                val actual=mutableListOf<Pair<Boolean,MatchDecision>>()
                val start=SystemClock.elapsedRealtime()
                BatchPhotoSearch(source,engine,worker).run(scope,refs) {_,found -> actual.add(found.getOrThrow().let {it.hasFaces to it.decision})}
                times.getValue(threads).add(SystemClock.elapsedRealtime()-start)
                if(expected==null) expected=actual else assertEquals(expected,actual)
            }
            File(context.cacheDir,"qa-native-thread-metrics.json").writeText(JSONObject().apply {
                put("scope","14 public inputs, including a synthetic nine-copy group; three interleaved cold-cache rounds, not a user album")
                for((threads,samples) in times) put(threads.toString(),org.json.JSONArray(samples))
                put("equalDecisions",true)
            }.toString())
        } finally {withContext(worker) {org.opencv.core.Core.setNumThreads(2)};groupFile.delete();worker.close()}
    }
}
