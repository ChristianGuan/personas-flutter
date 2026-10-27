package co.local.personas.domain

import org.junit.Assert.*
import org.junit.Test

class FaceDetectionsTest {
    private fun box(x: Float,y: Float,score: Float=0.9f)=FloatArray(15).apply {this[0]=x;this[1]=y;this[2]=80f;this[3]=80f;this[14]=score}
    @Test fun retainsEveryDistinctFaceBeyondThree() {
        val faces=(0 until 9).map {box((it%3)*100f,(it/3)*100f)}
        assertEquals(9,FaceDetections.merge(faces).size)
    }
    @Test fun mergesDuplicateScalesWithoutDroppingOtherPeople() {
        val a=box(0f,0f,0.9f);val duplicate=box(2f,1f,0.95f);val b=box(100f,0f)
        val merged=FaceDetections.merge(listOf(a,b,duplicate))
        assertEquals(2,merged.size)
        assertTrue(merged.any {it===duplicate})
        assertTrue(merged.any {it===b})
    }
}
