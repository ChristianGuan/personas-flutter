package co.local.personas.data

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorSpace

/** Owns a software-decoded bitmap. The returned image is ready for OpenCV and Compose. */
internal fun softwareSrgb8888(source: Bitmap): Bitmap {
    if(source.config==Bitmap.Config.ARGB_8888 && source.colorSpace?.isSrgb!=false) return source
    try {
        val target=Bitmap.createBitmap(source.width,source.height,Bitmap.Config.ARGB_8888)
        try {
            // Canvas performs color-space conversion; copy(config) alone can retain Display P3.
            Canvas(target).drawBitmap(source,0f,0f,null)
            check(target.colorSpace==ColorSpace.get(ColorSpace.Named.SRGB))
            return target
        } catch(e: Throwable) {target.recycle();throw e}
    } finally {source.recycle()}
}
