package co.local.personas.domain

import org.junit.Assert.*
import org.junit.Test

class MatchingTest {
    @Test fun cosineIsScaleInvariant() { assertEquals(1f,Matching.cosine(floatArrayOf(1f,2f),floatArrayOf(3f,6f)),1e-6f) }
    @Test fun unrelatedFacesAreRejected() { assertFalse(Matching.matches(floatArrayOf(1f,0f),listOf(floatArrayOf(0f,1f)))) }
    @Test fun anyFaceInGroupCanMatch() { assertTrue(Matching.matches(floatArrayOf(1f,0f),listOf(floatArrayOf(0f,1f),floatArrayOf(2f,0f)))) }
    @Test fun noFacesMeansNoMatch() { assertFalse(Matching.matches(floatArrayOf(1f),emptyList())) }
    @Test fun oppositeFacesHaveNegativeSimilarity() { assertEquals(-1f,Matching.cosine(floatArrayOf(1f),floatArrayOf(-2f)),1e-6f) }
    @Test(expected=IllegalArgumentException::class) fun zeroEmbeddingIsInvalid() { Matching.normalize(floatArrayOf(0f,0f)) }
    @Test(expected=IllegalArgumentException::class) fun invalidNumbersAreRejected() { Matching.normalize(floatArrayOf(Float.NaN)) }
    @Test fun additionalReferenceRecoversChangedAppearanceWithoutAveraging() {
        val references=listOf(floatArrayOf(1f,0f,0f),floatArrayOf(0f,1f,0f))
        assertTrue(Matching.matchesAny(references,listOf(floatArrayOf(0f,1f,0f))))
        assertFalse(Matching.matchesAny(references,listOf(floatArrayOf(0f,0f,1f))))
    }
    @Test fun noReferencesOrNoFacesCannotMatch() {
        assertFalse(Matching.matchesAny(emptyList(),listOf(floatArrayOf(1f))))
        assertFalse(Matching.matchesAny(listOf(floatArrayOf(1f)),emptyList()))
    }
    @Test fun onlySelectedResultsCanBeSharedWithoutDuplicates() {
        assertEquals(listOf("b"),Matching.selectedForSharing(listOf("a","b","b"),setOf("b","outside")))
    }
    @Test fun borderlineCandidatesNeverBecomeAutomaticMatches() {
        assertEquals(MatchDecision.NONE,Matching.decision(0.36299f))
        assertEquals(MatchDecision.REVIEW,Matching.decision(0.363f))
        assertEquals(MatchDecision.REVIEW,Matching.decision(0.49999f))
        assertEquals(MatchDecision.MATCH,Matching.decision(0.50f))
        assertEquals(MatchDecision.NONE,Matching.prepare(emptyList()).decide(listOf(floatArrayOf(1f))))
    }
    @Test fun preparedComparisonsKeepTheExactCosineArithmetic() {
        val random=kotlin.random.Random(103)
        repeat(100) {
            val reference=Matching.normalize(FloatArray(128) {random.nextFloat()-0.5f})
            val face=Matching.normalize(FloatArray(128) {random.nextFloat()-0.5f})
            val prepared=Matching.prepare(listOf(reference))
            val old=Matching.cosine(reference,face)
            assertEquals(old,prepared.bestScore(Matching.normalize(face)),0f)
            assertEquals(Matching.decision(old),prepared.decide(listOf(face)))
        }
    }
}
