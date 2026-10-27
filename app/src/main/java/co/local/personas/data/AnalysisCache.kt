package co.local.personas.data

/** Complete detections, with explicitly uncomputed embeddings after an early match. */
class DetectedPhoto(val rows: List<FloatArray>) {
    val embeddings: Array<FloatArray?> = arrayOfNulls(rows.size)
    // Reserve the eventual embeddings too, so completing an entry cannot exceed the budget.
    val reservedBytes: Long = 128L + rows.size * 640L
}

/** Worker-confined, bounded session memory. No URI, bitmap or disk persistence. */
class AnalysisCache(private val maxBytes: Long=20L*1024*1024,private val maxEntries: Int=1024) {
    private val entries=LinkedHashMap<String,DetectedPhoto>(16,0.75f,true)
    var reservedBytes: Long=0; private set
    val size: Int get()=entries.size
    init {require(maxBytes>=0 && maxEntries>=0)}
    operator fun get(key: String): DetectedPhoto? = entries[key]
    fun put(key: String,photo: DetectedPhoto) {
        entries.remove(key)?.let {reservedBytes-=it.reservedBytes}
        if(photo.reservedBytes>maxBytes || maxEntries==0) return
        entries[key]=photo;reservedBytes+=photo.reservedBytes
        val iterator=entries.entries.iterator()
        while(reservedBytes>maxBytes || entries.size>maxEntries) {
            reservedBytes-=iterator.next().value.reservedBytes;iterator.remove()
        }
    }
    fun clear() {entries.clear();reservedBytes=0}
}
