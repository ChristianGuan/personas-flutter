package co.local.personas.data

import android.graphics.Bitmap
import android.graphics.Matrix
import com.radzivon.bartoshyk.avif.coder.Coder
import com.radzivon.bartoshyk.avif.coder.PreferredColorConfig
import com.radzivon.bartoshyk.avif.coder.ScaleMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** Only used after Android rejects a HEIF container. No file conversion or network. */
internal object HeifFallback {
    const val MAX_ENCODED_BYTES=64*1024*1024
    private const val MAX_PIXELS=100_000_000L
    private val slot=Semaphore(1)
    private val coder by lazy {Coder()}
    private val brands=setOf("heic","heix","hevc","hevx","heim","heis","hevm","hevs","mif1","msf1")
    fun hasHeifHeader(bytes: ByteArray): Boolean {
        if(bytes.size<16 || String(bytes,4,4,Charsets.US_ASCII)!="ftyp") return false
        return (8 until minOf(bytes.size,64) step 4).filter {it!=12 && it+4<=bytes.size}.any {
            String(bytes,it,4,Charsets.US_ASCII) in brands
        }
    }
    suspend fun decode(bytes: ByteArray,maxEdge: Int,original: PhotoDecodeException): Bitmap {
        if(bytes.size>MAX_ENCODED_BYTES || !hasHeifHeader(bytes)) throw original
        var decoded: Bitmap?=null
        var completed=false
        try {val result=slot.withPermit {withContext(Dispatchers.IO) {
            if(!coder.isHeif(bytes)) throw original
            val input=HeifOrientation.detach(bytes)
            val size=coder.getSize(input.bytes) ?: throw original
            if(size.width<=0 || size.height<=0 || size.width.toLong()*size.height>MAX_PIXELS) throw original
            val edge=minOf(maxEdge,maxOf(size.width,size.height))
            val image=coder.decodeSampled(input.bytes,edge,edge,PreferredColorConfig.RGBA_8888,ScaleMode.FIT)
                .also {decoded=it}.let(::softwareSrgb8888).also {decoded=it}
            val matrix=Matrix()
            input.transforms.forEach {
                if(it.ccwQuarterTurns!=0) matrix.postRotate(-90f*it.ccwQuarterTurns)
                // HEIF imir axis=1 mirrors left/right; axis=0 mirrors top/bottom.
                if(it.mirrorAxis!=null) matrix.postScale(if(it.mirrorAxis==1) -1f else 1f,if(it.mirrorAxis==0) -1f else 1f)
            }
            if(matrix.isIdentity) image else Bitmap.createBitmap(image,0,0,image.width,image.height,matrix,false)
                .also {decoded=it;if(it!==image) image.recycle()}
        }};completed=true;return result
        } catch(e: CancellationException) {throw e}
        catch(e: PhotoDecodeException) {throw e}
        catch(e: Exception) {throw PhotoDecodeException(e)}
        catch(e: LinkageError) {throw PhotoDecodeException(e)}
        finally {if(!completed) decoded?.recycle()}
    }
}
