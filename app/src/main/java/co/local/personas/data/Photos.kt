package co.local.personas.data

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.ColorSpace
import java.io.IOException
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.security.MessageDigest

class PhotoDecodeException(cause: Throwable): IOException("No se pudo decodificar la imagen",cause)

class PreparedPhoto(val bitmap: Bitmap?=null,val encoded: ByteArray?=null,val encodedKey: String?=null,val readMs: Long?=null,val decodeMs: Long?=null) {
    fun release() {bitmap?.recycle()}
}
interface PhotoSource {
    suspend fun decode(uri: Uri): Bitmap
    suspend fun prepare(uri: Uri,mayReuse: (String)->Boolean): PreparedPhoto = PreparedPhoto(bitmap=decode(uri))
    suspend fun decodePrepared(uri: Uri,photo: PreparedPhoto): Bitmap = decode(uri)
}

class ContentPhotos(private val resolver: ContentResolver, private val maxEdge: Int = 3200) : PhotoSource {
    companion object {const val MAX_SNAPSHOT_BYTES=8*1024*1024}
    private suspend fun decodeSource(source: ()->ImageDecoder.Source): Bitmap {
        var decoded: Bitmap?=null
        try {return withContext(Dispatchers.IO) {
            // EXIF and target sizing are identical for URI and byte snapshots.
            // High-depth HEIC/HEIF can otherwise return F16, unsupported by bitmapToMat.
            ImageDecoder.decodeBitmap(source()) {decoder,info,_ ->
                decoder.allocator=ImageDecoder.ALLOCATOR_SOFTWARE
                decoder.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
                val longest=maxOf(info.size.width,info.size.height)
                if(longest>maxEdge) {
                    val scale=maxEdge.toDouble()/longest
                    decoder.setTargetSize((info.size.width*scale).toInt().coerceAtLeast(1),(info.size.height*scale).toInt().coerceAtLeast(1))
                }
            }.also {decoded=it}.let(::softwareSrgb8888).also {decoded=it}
        }} catch(e: CancellationException) {decoded?.recycle();throw e}
        // Some device codecs throw plain IOException from getPixels, not DecodeException.
        catch(e: IOException) {throw PhotoDecodeException(e)}
    }
    override suspend fun decode(uri: Uri): Bitmap = try {
        decodeSource {ImageDecoder.createSource(resolver,uri)}
    } catch(e: PhotoDecodeException) {
        val bytes=readLimited(uri,HeifFallback.MAX_ENCODED_BYTES,heifOnly=true) ?: throw e
        HeifFallback.decode(bytes,maxEdge,e)
    }
    override suspend fun decodePrepared(uri: Uri,photo: PreparedPhoto): Bitmap =
        photo.encoded?.let {bytes ->
            try {decodeSource {ImageDecoder.createSource(ByteBuffer.wrap(bytes))}}
            catch(e: PhotoDecodeException) {HeifFallback.decode(bytes,maxEdge,e)}
        } ?: decode(uri)

    private suspend fun readLimited(uri: Uri,limit: Int,heifOnly: Boolean=false): ByteArray? = withContext(Dispatchers.IO) {
        resolver.openInputStream(uri)?.use {input ->
            val output=ByteArrayOutputStream(64*1024)
            val block=ByteArray(64*1024)
            while(true) {
                currentCoroutineContext().ensureActive()
                val count=input.read(block)
                if(count<0) return@use output.toByteArray()
                if(output.size()+count>limit) return@use null
                val checkingHeader=heifOnly && output.size()<64
                output.write(block,0,count)
                if(checkingHeader && output.size()>=64 && !HeifFallback.hasHeifHeader(output.toByteArray())) return@use null
            }
            @Suppress("UNREACHABLE_CODE") null
        }
    }

    override suspend fun prepare(uri: Uri,mayReuse: (String)->Boolean): PreparedPhoto {
        val readStart=System.nanoTime()
        val bytes=try {readLimited(uri,MAX_SNAPSHOT_BYTES)} catch(e: CancellationException) {throw e}
        catch(_: Exception) {null} // Typed-descriptor providers keep the original URI path.
            ?: return PreparedPhoto(bitmap=decode(uri))
        val key=withContext(Dispatchers.Default) {
            val hash=MessageDigest.getInstance("SHA-256")
            hash.update("ImageDecoder/software/srgb/argb8888/native+heif-coder3.0.0-orientation/max$maxEdge/v4/".toByteArray())
            hash.update(bytes)
            hash.digest().hexDigest()
        }
        val readMs=(System.nanoTime()-readStart)/1_000_000
        val snapshot=PreparedPhoto(encoded=bytes,encodedKey=key,readMs=readMs,decodeMs=0)
        if(mayReuse(key)) return snapshot
        val decodeStart=System.nanoTime()
        val bitmap=decodePrepared(uri,snapshot)
        // The bitmap is now sufficient; do not keep the encoded copy during native inference.
        return PreparedPhoto(bitmap=bitmap,encodedKey=key,readMs=readMs,decodeMs=(System.nanoTime()-decodeStart)/1_000_000)
    }
}
