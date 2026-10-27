package co.local.personas.data

import org.junit.Assert.*
import org.junit.Test

class AnalysisCacheTest {
    private fun photo(faces: Int=1)=DetectedPhoto(List(faces) {FloatArray(15)})

    @Test fun recentEntriesSurviveEvictionAndPendingEmbeddingsReserveMemory() {
        val a=photo();val b=photo();val c=photo()
        val cache=AnalysisCache(maxBytes=a.reservedBytes*2,maxEntries=3)
        cache.put("a",a);cache.put("b",b)
        assertSame(a,cache["a"])
        cache.put("c",c)
        assertNull(cache["b"]);assertSame(a,cache["a"]);assertSame(c,cache["c"])
        val reserved=cache.reservedBytes
        a.embeddings[0]=FloatArray(128) {it.toFloat()}
        assertEquals(reserved,cache.reservedBytes)
    }
    @Test fun partialEntryKeepsAllFacesAndExactAlreadyComputedVector() {
        val entry=photo(3)
        val vector=FloatArray(128) {Float.fromBits(0x3f000001+it)}
        entry.embeddings[0]=vector
        val cache=AnalysisCache();cache.put("pixels-and-pipeline",entry)
        val loaded=cache["pixels-and-pipeline"]!!
        assertEquals(3,loaded.rows.size)
        assertArrayEquals(vector.map(Float::toRawBits).toIntArray(),loaded.embeddings[0]!!.map(Float::toRawBits).toIntArray())
        assertNull(loaded.embeddings[1]);assertNull(loaded.embeddings[2])
    }
    @Test fun faceFreeEntryCanBeReusedAndClearRemovesAllDerivedData() {
        val cache=AnalysisCache();val empty=photo(0)
        cache.put("empty",empty);cache.put("faces",photo())
        assertSame(empty,cache["empty"])
        cache.clear()
        assertNull(cache["empty"]);assertNull(cache["faces"])
        assertEquals(0,cache.size);assertEquals(0L,cache.reservedBytes)
    }
    @Test fun oversizedEntriesAndDisabledCacheDoNotRetainVectors() {
        val cache=AnalysisCache(maxBytes=200,maxEntries=1)
        cache.put("big",photo());assertEquals(0,cache.size)
        cache.put("small",photo(0));assertEquals(1,cache.size)
        val disabled=AnalysisCache(maxEntries=0)
        disabled.put("a",photo(0));assertEquals(0,disabled.size)
    }
    @Test fun replacementAndEntryLimitKeepAccountingCorrect() {
        val cache=AnalysisCache(maxEntries=1)
        cache.put("a",photo(3));val replacement=photo(0);cache.put("a",replacement)
        assertEquals(replacement.reservedBytes,cache.reservedBytes)
        cache.put("b",photo())
        assertNull(cache["a"]);assertNotNull(cache["b"]);assertEquals(1,cache.size)
    }
}
