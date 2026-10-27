package co.local.personas.flutter

import android.graphics.Bitmap
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import co.local.personas.data.*
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.io.IOException

@RunWith(AndroidJUnit4::class)
class PrefetchSafetyTest {
    @Test fun boundedPrefetchAndCancellationReleaseEveryBitmap()=runBlocking {
        for(limit in listOf(0,1024*1024)) {
            val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
            val gate=CountDownLatch(1)
            val observed=ConcurrentLinkedQueue<Bitmap>()
            val source=object:PhotoSource {
                override suspend fun decode(uri:Uri)=Bitmap.createBitmap(128,128,Bitmap.Config.ARGB_8888).also {
                    observed.add(it);check(observed.count {!it.isRecycled}<=2)
                }
            }
            val engine=object:FaceEngine {override fun analyze(bitmap:Bitmap)=emptyList<FoundFace>()}
            val blocker=launch(worker){gate.await()}
            val batch=launch {BatchPhotoSearch(source,engine,worker,limit).run(List(3){Uri.parse("content://test/$it")},emptyList()){_,_->fail("Cancelled work cannot be reported")}}
            try {
                val expected=if(limit==0)1 else 2
                withTimeout(5000){while(observed.size<expected)delay(5)}
                delay(100);assertEquals(expected,observed.size)
                batch.cancel()
            }finally{gate.countDown();batch.cancelAndJoin();blocker.join();worker.close()}
            assertTrue(observed.all {it.isRecycled})
        }
    }
    @Test fun providerFailurePreservesOrderAndReleasesPreparedImages()=runBlocking {
        val worker=Executors.newSingleThreadExecutor().asCoroutineDispatcher()
        val observed=ConcurrentLinkedQueue<Bitmap>()
        val uris=List(3){Uri.parse("content://test/$it")}
        val source=object:PhotoSource {
            override suspend fun decode(uri:Uri):Bitmap {
                if(uri==uris[1])throw IOException("Synthetic provider failure")
                return Bitmap.createBitmap(128,128,Bitmap.Config.ARGB_8888).also {observed.add(it)}
            }
        }
        val engine=object:FaceEngine {override fun analyze(bitmap:Bitmap)=emptyList<FoundFace>()}
        val actual=mutableListOf<Pair<Uri,Boolean>>()
        try{BatchPhotoSearch(source,engine,worker,1024*1024).run(uris,emptyList()){uri,r->actual.add(uri to r.isSuccess)}}finally{worker.close()}
        assertEquals(uris,actual.map {it.first});assertEquals(listOf(true,false,true),actual.map {it.second})
        assertTrue(observed.all {it.isRecycled})
    }
}
