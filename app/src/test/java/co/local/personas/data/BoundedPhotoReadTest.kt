package co.local.personas.data

import java.io.ByteArrayInputStream
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Test

class BoundedPhotoReadTest {
    @Test fun knownOversizeDoesNotReadTheProvider() {
        val input=object:ByteArrayInputStream(ByteArray(128)) {
            override fun read(b:ByteArray,off:Int,len:Int):Int=error("Must not read an oversized snapshot")
        }
        assertNull(readBoundedPhoto(input,64,lengthHint=128))
    }
    @Test fun streamingDigestMatchesThePreviousFullBufferDigest() {
        val bytes=ByteArray(200_003) {(it*31).toByte()}
        val prefix="pipeline-v4".toByteArray()
        val digest=MessageDigest.getInstance("SHA-256").also {it.update(prefix)}
        assertArrayEquals(bytes,readBoundedPhoto(ByteArrayInputStream(bytes),300_000,bytes.size.toLong(),digest))
        val previous=MessageDigest.getInstance("SHA-256").also {it.update(prefix);it.update(bytes)}.digest()
        assertArrayEquals(previous,digest.digest())
    }
    @Test fun incorrectSmallLengthDoesNotTruncateContent() {
        val bytes=ByteArray(150_000) {it.toByte()}
        assertArrayEquals(bytes,readBoundedPhoto(ByteArrayInputStream(bytes),200_000,lengthHint=1))
    }
    @Test fun unknownSizeStillEnforcesTheSnapshotLimit() {
        assertNull(readBoundedPhoto(ByteArrayInputStream(ByteArray(65)),64))
        assertArrayEquals(ByteArray(64),readBoundedPhoto(ByteArrayInputStream(ByteArray(64)),64))
    }
    @Test(expected=CancellationException::class) fun cancellationStopsBeforeReading() {
        readBoundedPhoto(ByteArrayInputStream(ByteArray(16)),64,checkActive={throw CancellationException()})
    }
    @Test fun rejectedHeaderDoesNotConsumeTheRestOfTheFile() {
        val input=ByteArrayInputStream(ByteArray(200_000))
        assertNull(readBoundedPhoto(input,300_000,acceptHeader={false}))
        assertTrue(input.available()>100_000)
    }
}
