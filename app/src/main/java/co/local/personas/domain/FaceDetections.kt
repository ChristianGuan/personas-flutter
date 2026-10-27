package co.local.personas.domain

/** YuNet rows in original-image coordinates: bbox, 5 landmarks, confidence. */
object FaceDetections {
    fun merge(rows: List<FloatArray>): List<FloatArray> {
        val kept=mutableListOf<FloatArray>()
        for(row in rows.sortedByDescending {it[14]}) {
            if(kept.none {iou(it,row)>0.4f}) kept.add(row)
        }
        return kept.sortedWith(compareBy({it[1]},{it[0]}))
    }
    private fun iou(a: FloatArray,b: FloatArray): Float {
        val width=(minOf(a[0]+a[2],b[0]+b[2])-maxOf(a[0],b[0])).coerceAtLeast(0f)
        val height=(minOf(a[1]+a[3],b[1]+b[3])-maxOf(a[1],b[1])).coerceAtLeast(0f)
        val intersection=width*height
        val union=a[2]*a[3]+b[2]*b[3]-intersection
        return if(union>0) intersection/union else 0f
    }
}
