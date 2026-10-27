package co.local.personas.data

import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer

class HeifOrientationTest {
    private fun box(kind: String,vararg chunks: ByteArray): ByteArray {
        val body=chunks.fold(byteArrayOf()) {a,b ->a+b}
        return ByteBuffer.allocate(body.size+8).putInt(body.size+8).put(kind.toByteArray()).put(body).array()
    }
    private val full=ByteArray(4)
    private fun fixture(primary: Int=1,wideAssociations: Boolean=false,vararg properties: ByteArray): ByteArray {
        val associations=byteArrayOf(0x81.toByte(),0x82.toByte())
        val ipma=box("ipma",byteArrayOf(0,0,0,if(wideAssociations) 1 else 0),byteArrayOf(0,0,0,2),
            byteArrayOf(0,1,2)+associations,byteArrayOf(0,2,2)+associations)
        return box("ftyp","heic".toByteArray(),ByteArray(4))+box("meta",full,
            box("pitm",full,byteArrayOf(0,primary.toByte())),
            box("iprp",box("ipco",*properties),ipma))+box("mdat",byteArrayOf(10,20,30,40))
    }

    @Test fun onlyPrimaryAssociationsAreDetachedAndEncodedContentIsUnchanged() {
        val source=fixture(properties=arrayOf(box("irot",byteArrayOf(3)),box("imir",byteArrayOf(0))))
        val original=source.copyOf()
        val result=HeifOrientation.detach(source)
        assertArrayEquals(original,source)
        assertEquals(listOf(HeifOrientation.Transform(3),HeifOrientation.Transform(mirrorAxis=0)),result.transforms)
        val changed=source.indices.filter {source[it]!=result.bytes[it]}
        assertEquals(2,changed.size)
        changed.forEach {assertEquals(0,result.bytes[it].toInt())}
        assertEquals(source.size,result.bytes.size)
        // The second item's associations still reference the same properties.
        assertEquals(2,result.bytes.count {it==0x81.toByte() || it==0x82.toByte()})
    }

    @Test fun noTransformOrUnassociatedTransformDoesNotCopyTheEncodedImage() {
        val noTransform=fixture(properties=arrayOf(box("ispe",full),box("pixi",full)))
        assertSame(noTransform,HeifOrientation.detach(noTransform).bytes)
        val differentPrimary=fixture(primary=3,properties=arrayOf(box("irot",byteArrayOf(1)),box("imir",byteArrayOf(1))))
        assertSame(differentPrimary,HeifOrientation.detach(differentPrimary).bytes)
    }

    @Test fun corruptLengthsTruncationAndUnsupportedAssociationWidthsAreRejected() {
        val valid=fixture(properties=arrayOf(box("irot",byteArrayOf(1)),box("imir",byteArrayOf(1))))
        for(length in listOf(1,7,15,valid.size-1)) {
            assertThrows(IllegalArgumentException::class.java) {HeifOrientation.detach(valid.copyOf(length))}
        }
        val oversized=valid.copyOf().also {ByteBuffer.wrap(it).putInt(Int.MAX_VALUE)}
        assertThrows(IllegalArgumentException::class.java) {HeifOrientation.detach(oversized)}
        val wide=fixture(wideAssociations=true,properties=arrayOf(box("irot",byteArrayOf(1)),box("imir",byteArrayOf(1))))
        assertThrows(IllegalArgumentException::class.java) {HeifOrientation.detach(wide)}
        val reserved=fixture(properties=arrayOf(box("irot",byteArrayOf(4)),box("imir",byteArrayOf(1))))
        assertThrows(IllegalArgumentException::class.java) {HeifOrientation.detach(reserved)}
    }
}
