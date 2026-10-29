package co.local.personas.domain

import kotlin.math.sqrt

enum class MatchDecision { MATCH, REVIEW, NONE }

/** References normalized once per batch; candidates supplied here are comparison vectors. */
class PreparedReferences internal constructor(private val references: List<FloatArray>) {
    fun bestScore(candidate: FloatArray): Float = references.maxOfOrNull {Matching.dot(it,candidate)} ?: -1f
    fun decide(faces: List<FloatArray>): MatchDecision = Matching.decision(faces.maxOfOrNull {bestScore(Matching.normalize(it))} ?: -1f)
}

object Matching {
    // Calibrated on separate AT&T subjects with 1/2/4 references; see ADR 007.
    const val THRESHOLD = 0.50f
    const val REVIEW_THRESHOLD = 0.363f
    fun decision(score: Float): MatchDecision = when {
        score>=THRESHOLD -> MatchDecision.MATCH
        score>=REVIEW_THRESHOLD -> MatchDecision.REVIEW
        else -> MatchDecision.NONE
    }
    fun prepare(references: List<FloatArray>) = PreparedReferences(references.map(::normalize))
    /** Fuse two views of the SAME aligned face, never different people/references. */
    fun mergeViews(original: FloatArray, reflected: FloatArray): FloatArray {
        require(original.size == reflected.size)
        val a = normalize(original)
        val b = normalize(reflected)
        val merged = FloatArray(a.size) { a[it] + b[it] }
        // A contradictory/degenerate second view must not invalidate a usable face.
        return if (merged.sumOf { it.toDouble() * it } <= 1e-24) a else normalize(merged)
    }
    fun normalize(vector: FloatArray): FloatArray {
        require(vector.isNotEmpty() && vector.all { it.isFinite() })
        val norm = sqrt(vector.sumOf { it.toDouble() * it })
        require(norm > 1e-12) { "Embedding sin señal" }
        return FloatArray(vector.size) { (vector[it] / norm).toFloat() }
    }
    internal fun dot(x: FloatArray,y: FloatArray): Float {
        require(x.size==y.size)
        return x.indices.sumOf {x[it].toDouble()*y[it]}.toFloat().coerceIn(-1f,1f)
    }
    fun cosine(a: FloatArray, b: FloatArray): Float = dot(normalize(a),normalize(b))
    fun matches(reference: FloatArray, faces: List<FloatArray>, threshold: Float = THRESHOLD) =
        faces.any { cosine(reference, it) >= threshold }
    fun matchesAny(references: List<FloatArray>, faces: List<FloatArray>, threshold: Float = THRESHOLD): Boolean =
        references.any { matches(it, faces, threshold) }
    fun selectedForSharing(results: List<String>, selected: Set<String>) = results.distinct().filter { it in selected }
}
