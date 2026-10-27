package co.local.personas.data

import android.graphics.Bitmap
import android.graphics.RectF
import kotlin.math.roundToInt

/** Call outside Main. Derived preview remains in memory only. */
fun faceThumbnail(source: Bitmap,bounds: RectF): Bitmap {
    val margin=maxOf(bounds.width(),bounds.height())*0.15f
    val left=(bounds.left-margin).toInt().coerceIn(0,source.width-1)
    val top=(bounds.top-margin).toInt().coerceIn(0,source.height-1)
    val right=(bounds.right+margin).roundToInt().coerceIn(left+1,source.width)
    val bottom=(bounds.bottom+margin).roundToInt().coerceIn(top+1,source.height)
    val extracted=Bitmap.createBitmap(source,left,top,right-left,bottom-top)
    val factor=minOf(1f,256f/maxOf(extracted.width,extracted.height))
    val scaled=Bitmap.createScaledBitmap(extracted,(extracted.width*factor).roundToInt().coerceAtLeast(1),(extracted.height*factor).roundToInt().coerceAtLeast(1),true)
    if(extracted!==scaled && extracted!==source) extracted.recycle()
    return scaled
}
