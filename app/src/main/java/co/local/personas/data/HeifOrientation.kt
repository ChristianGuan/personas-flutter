package co.local.personas.data

/**
 * Compatibility adapter for avif-coder 3.0.0: its HEIC orientation code treats RGBA
 * as RGB and corrupts/fails rotated images. Detach only the primary item's irot/imir
 * associations in a private copy; apply those transforms to the decoded bitmap.
 * Box sizes, payloads, other items, color, crop and original bytes stay intact.
 * Remove this adapter after upgrading to a codec with verified RGBA orientation.
 */
internal object HeifOrientation {
    data class Transform(val ccwQuarterTurns: Int=0,val mirrorAxis: Int?=null)
    data class Input(val bytes: ByteArray,val transforms: List<Transform>)
    private data class Box(val kind: String,val payload: Int,val end: Int)

    fun detach(bytes: ByteArray): Input {
        val reader=Reader(bytes)
        val meta=reader.boxes(0,bytes.size).singleOrNull {it.kind=="meta"}
            ?: return Input(bytes,emptyList())
        require(reader.number(meta.payload,4,meta.end)==0L) {"Unsupported HEIF meta version"}
        val children=reader.boxes(meta.payload+4,meta.end)
        val pitm=children.singleOrNull {it.kind=="pitm"} ?: return Input(bytes,emptyList())
        // The pinned native HEVC decoder accepts 16-bit IDs and 7-bit associations.
        require(reader.number(pitm.payload,4,pitm.end)==0L) {"Unsupported HEIF item IDs"}
        val primary=reader.number(pitm.payload+4,2,pitm.end)
        val iprp=children.singleOrNull {it.kind=="iprp"} ?: return Input(bytes,emptyList())
        val properties=reader.boxes(iprp.payload,iprp.end)
        val ipco=properties.singleOrNull {it.kind=="ipco"} ?: return Input(bytes,emptyList())
        val definitions=reader.boxes(ipco.payload,ipco.end)
        val transforms=mutableListOf<Transform>()
        val detachAt=mutableListOf<Int>()
        var seenPrimary=false
        for(ipma in properties.filter {it.kind=="ipma"}) {
            require(reader.number(ipma.payload,4,ipma.end)==0L) {"Unsupported HEIF associations"}
            val entries=reader.number(ipma.payload+4,4,ipma.end)
            var position=ipma.payload+8
            require(entries<=(ipma.end-position)/3) {"Invalid HEIF entry count"}
            repeat(entries.toInt()) {
                val item=reader.number(position,2,ipma.end);position+=2
                val count=reader.number(position++,1,ipma.end).toInt()
                require(count<=ipma.end-position) {"Truncated HEIF associations"}
                if(item==primary) {
                    require(!seenPrimary) {"Duplicate primary associations"};seenPrimary=true
                    repeat(count) {offset ->
                        val index=(bytes[position+offset].toInt() and 0x7f)
                        require(index<=definitions.size) {"Invalid HEIF property index"}
                        if(index>0) {
                            val property=definitions[index-1]
                            if(property.kind=="irot" || property.kind=="imir") {
                                require(property.end-property.payload==1) {"Invalid HEIF transform"}
                                val value=reader.number(property.payload,1,property.end).toInt()
                                val mask=if(property.kind=="irot") 3 else 1
                                require(value and mask==value) {"Invalid HEIF transform bits"}
                                transforms+=if(property.kind=="irot") Transform(ccwQuarterTurns=value)
                                    else Transform(mirrorAxis=value)
                                detachAt+=position+offset
                            }
                        }
                    }
                }
                position+=count
            }
            require(position==ipma.end) {"Invalid HEIF association size"}
        }
        if(detachAt.isEmpty()) return Input(bytes,emptyList())
        val copy=bytes.copyOf()
        // Property index zero means no property; also clear its essential flag.
        detachAt.forEach {copy[it]=0}
        return Input(copy,transforms)
    }

    private class Reader(val bytes: ByteArray) {
        fun number(at: Int,count: Int,end: Int): Long {
            require(at>=0 && count<=end-at && end<=bytes.size) {"Truncated HEIF box"}
            var value=0L
            repeat(count) {value=(value shl 8) or (bytes[at+it].toLong() and 255)}
            require(value>=0) {"HEIF box exceeds addressable size"}
            return value
        }
        fun boxes(start: Int,end: Int): List<Box> {
            var position=start
            val result=mutableListOf<Box>()
            while(position<end) {
                require(end-position>=8) {"Truncated HEIF box header"}
                var size=number(position,4,end)
                var header=8
                if(size==1L) {size=number(position+8,8,end);header=16}
                else if(size==0L) size=(end-position).toLong()
                require(size>=header && size<=end-position) {"Invalid HEIF box size"}
                result+=Box(String(bytes,position+4,4,Charsets.US_ASCII),position+header,position+size.toInt())
                require(result.size<=32768) {"Too many HEIF boxes"}
                position+=size.toInt()
            }
            return result
        }
    }
}
