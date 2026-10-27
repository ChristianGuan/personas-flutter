package co.local.personas.flutter

import android.os.Looper
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.RectF
import android.net.Uri
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.data.FoundFace
import java.io.File
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch

@RunWith(AndroidJUnit4::class)
class AnalysisCompletionTest {
    @Test fun cancellationStillPersistsAndPublishesOnMainExactlyOnce()=runBlocking {
        val storage=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val started=CompletableDeferred<Unit>()
        var persisted=false;var publications=0
        try {
            val job=launch(Dispatchers.Main.immediate) {
                try {started.complete(Unit);awaitCancellation()}
                finally {finishAnalysis(storage,{Thread.sleep(25);persisted=true}) {
                    assertTrue(Looper.getMainLooper().isCurrentThread)
                    assertTrue(persisted);publications++
                }}
            }
            started.await();job.cancel()
            withTimeout(5000){job.join()}
            assertTrue(job.isCancelled);assertEquals(1,publications)
        }finally{storage.close()}
    }
    @Test fun repeatedCancellationDuringDiskWriteCannotSkipPublication()=runBlocking {
        val storage=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val started=CompletableDeferred<Unit>();val persisting=CompletableDeferred<Unit>()
        val gate=CountDownLatch(1);var publications=0
        try {
            val job=launch(Dispatchers.Main.immediate) {
                try{started.complete(Unit);awaitCancellation()}
                finally{finishAnalysis(storage,{persisting.complete(Unit);gate.await()}){publications++}}
            }
            started.await();job.cancel();withTimeout(5000){persisting.await()}
            job.cancel();gate.countDown();withTimeout(5000){job.join()}
            assertEquals(1,publications)
        }finally{gate.countDown();storage.close()}
    }
    @Test fun failedPersistenceStillReleasesTheLogicalRun()=runBlocking {
        val storage=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        var publications=0;var failed=false
        try {
            try {withContext(Dispatchers.Main.immediate){finishAnalysis(storage,{throw IOException("Synthetic disk failure")}) {
                assertTrue(Looper.getMainLooper().isCurrentThread);publications++
            }}}catch(_:IOException){failed=true}
            assertTrue(failed);assertEquals(1,publications)
        }finally{storage.close()}
    }
    @Test fun runtimeCancellationPublishesDoneAndAllowsAnotherRun()=runBlocking {
        val original=InstrumentationRegistry.getInstrumentation().targetContext
        val dir=File(original.cacheDir,"qa-cancellation-isolated").apply{mkdirs()}
        val context=object:ContextWrapper(original){override fun getCacheDir()=dir}
        val runtime=AnalysisRuntime(context)
        val file=File(dir,"blank.png")
        val bitmap=Bitmap.createBitmap(128,128,Bitmap.Config.ARGB_8888)
        file.outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
        val gate=CountDownLatch(1);val entered=CompletableDeferred<Unit>()
        val first=CompletableDeferred<Map<String,Any?>>()
        val second=CompletableDeferred<Map<String,Any?>>()
        var publications=0
        val listener:(Map<String,Any?>)->Unit={event->
            if(event["type"]=="done") {
                assertTrue(Looper.getMainLooper().isCurrentThread);publications++
                when(event["runId"]){1->first.complete(event);2->second.complete(event)}
            }
        }
        val blocker=launch(runtime.worker){entered.complete(Unit);gate.await()}
        try {
            entered.await()
            withContext(Dispatchers.Main.immediate){
                runtime.observe(listener)
                runtime.refs["fixture"]=listOf(FoundFace(RectF(),FloatArray(128){if(it==0)1f else 0f}))
                val token=runtime.prepare(1,listOf(Uri.fromFile(file)),listOf("fixture:0"),emptyMap())
                runtime.launch(token);runtime.cancel(1);runtime.cancel(1)
            }
            assertEquals(true,withTimeout(5000){first.await()}["cancelled"])
            assertFalse(runtime.active)
            gate.countDown();blocker.join()
            withContext(Dispatchers.Main.immediate){
                runtime.prepare(2,listOf(Uri.fromFile(file)),listOf("fixture:0"),emptyMap())
                runtime.cancel(2)
            }
            assertEquals(true,withTimeout(5000){second.await()}["cancelled"])
            assertFalse(runtime.active);assertEquals(2,publications)
        }finally{
            gate.countDown();blocker.join()
            withContext(Dispatchers.Main.immediate){runtime.detach(listener);if(!runtime.active)runtime.clear()}
            runtime.worker.close();dir.deleteRecursively()
        }
    }

}
