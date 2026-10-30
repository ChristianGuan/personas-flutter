package co.local.personas.speedbench
import android.net.Uri
import co.local.personas.data.*
import co.local.personas.domain.Matching
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.sync.Semaphore
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Experimental bounded three-slot preparation. No changes to the production scheduler. */
class ParallelPrepareSearch(private val source:PhotoSource,private val engine:FaceEngine,private val worker:CoroutineDispatcher) {
 private class Ready(val index:Int,val uri:Uri,val photo:PreparedPhoto?,private val slots:Semaphore) {
  private val released=AtomicBoolean()
  fun release(){if(released.compareAndSet(false,true)){photo?.release();slots.release()}}
 }
 suspend fun run(uris:List<Uri>,refs:List<FloatArray>,onPhoto:(Uri,Result<FaceMatch>)->Unit)=coroutineScope {
  val slots=Semaphore(3);val next=AtomicInteger();val profile=Matching.prepare(refs)
  val channel=Channel<Ready>(Channel.RENDEZVOUS,onUndeliveredElement={it.release()})
  val producer=launch(Dispatchers.IO) {
   try {coroutineScope {
    repeat(2){launch {
     while(true) {
      val index=next.getAndIncrement();if(index>=uris.size)break
      slots.acquire();var item:Ready?=null;var handedOff=false
      try {
       val photo=try{source.prepare(uris[index],engine::mayReuseEncoded)}catch(e:CancellationException){throw e}catch(_:Exception){null}
       item=Ready(index,uris[index],photo,slots);channel.send(item);handedOff=true
      }finally{if(!handedOff){if(item!=null)item.release()else slots.release()}}
     }
    }}
   }}finally{channel.close()}
  }
  val pending=mutableMapOf<Int,Ready>()
  try {
   for(index in uris.indices) {
    while(index !in pending){val item=channel.receive();pending[item.index]=item}
    val item=pending.remove(index)!!
    val result=try {
     val photo=item.photo ?: throw IOException("Photo unavailable")
     val cached=if(photo.bitmap==null)photo.encodedKey?.let {withContext(worker){engine.matchEncoded(it,profile)}}else null
     Result.success(cached ?: run {
      val bitmap=photo.bitmap ?: source.decodePrepared(item.uri,photo)
      try{withContext(worker){engine.matchPrepared(bitmap,profile,photo.encodedKey)}}finally{if(photo.bitmap==null)bitmap.recycle()}
     })
    }catch(e:CancellationException){throw e}catch(e:Exception){Result.failure(e)}finally{item.release()}
    ensureActive();onPhoto(item.uri,result)
   }
  }finally{channel.cancel();producer.cancel();pending.values.forEach {it.release()}}
 }
}
