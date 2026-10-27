package co.local.personas.data

import java.security.MessageDigest

/** Fixed lowercase hex without a Formatter allocation for each digest byte. */
internal fun ByteArray.hexDigest(): String {
    val alphabet="0123456789abcdef"
    return String(CharArray(size*2) {index ->
        val value=this[index/2].toInt() and 255
        alphabet[if(index%2==0) value ushr 4 else value and 15]
    })
}
internal fun encodedInputKey(pipeline: String,encodedKey: String): String =
    MessageDigest.getInstance("SHA-256").digest("$pipeline/encoded/$encodedKey".toByteArray(Charsets.UTF_8)).hexDigest()
