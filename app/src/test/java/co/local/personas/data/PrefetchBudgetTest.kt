package co.local.personas.data

import org.junit.Assert.assertEquals
import org.junit.Test

class PrefetchBudgetTest {
    private val mib=1024L*1024
    @Test fun bitmapThresholdRespectsHeapAndMemoryPressure() {
        assertEquals((32*mib).toInt(),BatchPhotoSearch.recommendedPrefetchBitmapBytes(256*mib,false))
        assertEquals((32*mib).toInt(),BatchPhotoSearch.recommendedPrefetchBitmapBytes(1024*mib,false))
        assertEquals((16*mib).toInt(),BatchPhotoSearch.recommendedPrefetchBitmapBytes(128*mib,false))
        assertEquals((8*mib).toInt(),BatchPhotoSearch.recommendedPrefetchBitmapBytes(64*mib,false))
        assertEquals((16*mib).toInt(),BatchPhotoSearch.recommendedPrefetchBitmapBytes(256*mib,true))
        assertEquals(0,BatchPhotoSearch.recommendedPrefetchBitmapBytes(0,false))
    }
}
