package co.local.personas.data

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.security.MessageDigest

/** Length is only an allocation/fallback hint, never a content/cache identity. */
internal fun readBoundedPhoto(
    input: InputStream,
    limit: Int,
    lengthHint: Long = -1,
    digest: MessageDigest? = null,
    checkActive: () -> Unit = {},
    acceptHeader: ((ByteArray) -> Boolean)? = null,
): ByteArray? {
    require(limit > 0)
    if (lengthHint > limit) return null
    val capacity = if (lengthHint in 1..limit.toLong()) lengthHint.toInt() else minOf(64 * 1024, limit)
    val output = ByteArrayOutputStream(capacity)
    val block = ByteArray(64 * 1024)
    var headerChecked = acceptHeader == null
    while (true) {
        checkActive()
        val count = input.read(block)
        if (count < 0) return output.toByteArray()
        if (count > limit - output.size()) return null
        output.write(block, 0, count)
        digest?.update(block, 0, count)
        if (!headerChecked && output.size() >= 64) {
            if (!acceptHeader!!(output.toByteArray())) return null
            headerChecked = true
        }
    }
}
