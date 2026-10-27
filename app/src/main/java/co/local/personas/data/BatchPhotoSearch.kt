package co.local.personas.data

import android.net.Uri
import co.local.personas.domain.Matching
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import java.io.IOException

/** One native consumer; bounded IO prefetch, with no bitmap decode on a valid encoded cache hit. */
class BatchPhotoSearch(private val source: PhotoSource,private val engine: FaceEngine,private val worker: CoroutineDispatcher,private val prefetchBitmapBytes: Int=16*1024*1024) {
    companion object {
        /** Threshold for the current bitmap, not a promise about total process memory. */
        fun recommendedPrefetchBitmapBytes(maxHeapBytes: Long,lowMemory: Boolean): Int =
            minOf(if(lowMemory)16L*1024*1024 else 32L*1024*1024,(maxHeapBytes/8).coerceAtLeast(0)).toInt()
    }
    init {require(prefetchBitmapBytes>=0)}
    private data class Prepared(val uri: Uri,val photo: PreparedPhoto?) {
        val released=CompletableDeferred<Unit>()
        fun release() {photo?.release();released.complete(Unit)}
    }
    suspend fun run(uris: List<Uri>,references: List<FloatArray>,onMetrics: (Map<String,Long>)->Unit = {},onPhoto: (Uri,Result<FaceMatch>)->Unit) = coroutineScope {
        val profile=Matching.prepare(references)
        val channel=Channel<Prepared>(Channel.RENDEZVOUS,onUndeliveredElement={it.release()})
        val producer=launch(Dispatchers.IO) {
            try {
                for(uri in uris) {
                    ensureActive()
                    val photo=try {source.prepare(uri,engine::mayReuseEncoded)} catch(e: CancellationException) {throw e} catch(_: Exception) {null}
                    val prepared=Prepared(uri,photo)
                    channel.send(prepared)
                    // Keep at most current + next. Defer large/deferred inputs until the current one is released.
                    if(photo!=null && (photo.bitmap==null || photo.bitmap.allocationByteCount>prefetchBitmapBytes)) prepared.released.await()
                }
            } finally {channel.close()}
        }
        try {
            for(prepared in channel) {
                val metrics=mutableMapOf<String,Long>()
                val result=try {
                    val photo=prepared.photo ?: throw IOException("Foto no disponible")
                    photo.readMs?.let {metrics["readMs"]=it}
                    photo.decodeMs?.let {metrics["decodeMs"]=it}
                    var engineMs=0L
                    val cacheStart=System.nanoTime()
                    val cached=if(photo.bitmap==null) photo.encodedKey?.let {withContext(worker) {engine.matchEncoded(it,profile)}} else null
                    engineMs+=(System.nanoTime()-cacheStart)/1_000_000
                    val found=cached ?: run {
                        val decodeStart=System.nanoTime()
                        val bitmap=photo.bitmap ?: source.decodePrepared(prepared.uri,photo)
                        if(photo.bitmap==null) metrics["decodeMs"]=(metrics["decodeMs"] ?: 0)+(System.nanoTime()-decodeStart)/1_000_000
                        val engineStart=System.nanoTime()
                        try {withContext(worker) {engine.matchPrepared(bitmap,profile,photo.encodedKey)}
                            .also {engineMs+=(System.nanoTime()-engineStart)/1_000_000}}
                        finally {if(photo.bitmap==null) bitmap.recycle()}
                    }
                    metrics["engineMs"]=engineMs
                    metrics["cacheHits"]=if(cached!=null || found.reusedDetections)1L else 0L
                    metrics["cacheMisses"]=if(metrics["cacheHits"]==1L)0L else 1L
                    Result.success(found)
                } catch(e: CancellationException) {throw e}
                catch(e: Exception) {Result.failure(e)}
                finally {prepared.release()}
                ensureActive()
                onMetrics(metrics)
                onPhoto(prepared.uri,result)
            }
        } finally {channel.cancel();producer.cancel()}
    }
}
