package dev.individuation.chiptune.core.video

import java.nio.ByteBuffer
import kotlin.random.Random
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** The ARGB to YUV 4:2:0 conversion the Android encoder feeds through
 * `MediaCodec.getInputImage`. Devices lay the planes out differently (I420,
 * NV12, NV21, padded rows), so the conversion takes each plane's offset,
 * row stride and pixel stride instead of assuming one packing. BT.709
 * limited range, to match the colour tags iOS writes. */
class YuvTest {

    private fun argb(r: Int, g: Int, b: Int): Int = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

    private fun u8(buffer: ByteBuffer, index: Int): Int = buffer.get(index).toInt() and 0xFF

    /** I420: Y, then U, then V, each tightly packed. */
    private fun planar(argb: IntArray, width: Int, height: Int): ByteBuffer {
        val cw = (width + 1) / 2
        val ch = (height + 1) / 2
        val buffer = ByteBuffer.allocate(width * height + 2 * cw * ch)
        Yuv.fromArgb(
            argb, width, height,
            Yuv.Plane(buffer, 0, width, 1),
            Yuv.Plane(buffer, width * height, cw, 1),
            Yuv.Plane(buffer, width * height + cw * ch, cw, 1),
        )
        return buffer
    }

    @Test fun knownColoursGiveTheirBt709Values() {
        val cases = listOf(
            argb(0, 0, 0) to Triple(16, 128, 128),
            argb(255, 255, 255) to Triple(235, 128, 128),
            argb(255, 0, 0) to Triple(63, 102, 240),
            argb(0, 255, 0) to Triple(173, 42, 26),
            argb(0, 0, 255) to Triple(32, 240, 118),
            // ChipColors.background, which fills most of every frame.
            argb(0x0D, 0x0D, 0x17) to Triple(28, 132, 128),
        )
        for ((pixel, yuv) in cases) {
            val out = planar(IntArray(4) { pixel }, 2, 2)
            assertEquals("Y of ${Integer.toHexString(pixel)}", yuv.first, u8(out, 0))
            assertEquals("Y of ${Integer.toHexString(pixel)}", yuv.first, u8(out, 3))
            assertEquals("U of ${Integer.toHexString(pixel)}", yuv.second, u8(out, 4))
            assertEquals("V of ${Integer.toHexString(pixel)}", yuv.third, u8(out, 5))
        }
    }

    /** Each chroma sample covers a 2x2 block: it is the block's average. */
    @Test fun chromaAveragesEachTwoByTwoBlock() {
        val red = argb(255, 0, 0)
        val blue = argb(0, 0, 255)
        // Left block all red, right block half red, half blue.
        val pixels = intArrayOf(
            red, red, red, blue,
            red, red, blue, red,
        )
        val out = planar(pixels, 4, 2)
        assertEquals(102, u8(out, 8))
        assertEquals(240, u8(out, 10))
        // Average of red and blue is (127.5, 0, 127.5).
        assertEquals(171, u8(out, 9))
        assertEquals(179, u8(out, 11))
        // Luma stays per pixel.
        assertEquals(63, u8(out, 2))
        assertEquals(32, u8(out, 3))
    }

    /** NV12: interleaved UV in one plane. Image hands this over as a U plane
     * and a V plane one byte apart, each with pixel stride 2. */
    @Test fun semiPlanarLayoutsInterleaveTheChroma() {
        val pixels = IntArray(16) { if (it % 4 < 2) argb(255, 0, 0) else argb(0, 0, 255) }
        val buffer = ByteBuffer.allocate(16 + 8)
        Yuv.fromArgb(
            pixels, 4, 4,
            Yuv.Plane(buffer, 0, 4, 1),
            Yuv.Plane(buffer, 16, 4, 2),
            Yuv.Plane(buffer, 17, 4, 2),
        )
        // Row 0 of chroma: (U,V) for the red block, then for the blue block.
        assertEquals(listOf(102, 240, 240, 118), (16 until 20).map { u8(buffer, it) })
        assertEquals(listOf(102, 240, 240, 118), (20 until 24).map { u8(buffer, it) })
    }

    /** NV21 is the same with V first. */
    @Test fun nv21PutsVFirst() {
        val pixels = IntArray(4) { argb(255, 0, 0) }
        val buffer = ByteBuffer.allocate(4 + 2)
        Yuv.fromArgb(
            pixels, 2, 2,
            Yuv.Plane(buffer, 0, 2, 1),
            Yuv.Plane(buffer, 5, 2, 2),
            Yuv.Plane(buffer, 4, 2, 2),
        )
        assertEquals(240, u8(buffer, 4))
        assertEquals(102, u8(buffer, 5))
    }

    /** Encoders often pad each row to an alignment. The padding is left
     * alone and every row starts at its stride. */
    @Test fun paddedRowStridesAreHonoured() {
        val pad = 0x7F.toByte()
        val pixels = IntArray(8) { argb(255, 255, 255) }
        val yStride = 8
        val cStride = 4
        val buffer = ByteBuffer.allocate(yStride * 2 + cStride * 2)
        for (i in 0 until buffer.capacity()) buffer.put(i, pad)
        Yuv.fromArgb(
            pixels, 4, 2,
            Yuv.Plane(buffer, 0, yStride, 1),
            Yuv.Plane(buffer, yStride * 2, cStride, 1),
            Yuv.Plane(buffer, yStride * 2 + cStride, cStride, 1),
        )
        for (row in 0 until 2) {
            for (x in 0 until 4) assertEquals("y $row,$x", 235, u8(buffer, row * yStride + x))
            for (x in 4 until 8) assertEquals("padding $row,$x", 0x7F, u8(buffer, row * yStride + x))
        }
        assertEquals(listOf(128, 128, 0x7F, 0x7F), (16 until 20).map { u8(buffer, it) })
        assertEquals(listOf(128, 128, 0x7F, 0x7F), (20 until 24).map { u8(buffer, it) })
    }

    /** A plane's buffer may start partway through (Image's planes share one
     * allocation): offsets are absolute, and the buffer's position is not
     * moved. */
    @Test fun theBufferPositionIsLeftAlone() {
        val buffer = ByteBuffer.allocate(6)
        buffer.position(3)
        Yuv.fromArgb(
            IntArray(4) { argb(0, 0, 0) }, 2, 2,
            Yuv.Plane(buffer, 0, 2, 1),
            Yuv.Plane(buffer, 4, 1, 1),
            Yuv.Plane(buffer, 5, 1, 1),
        )
        assertEquals(3, buffer.position())
        assertEquals(16, u8(buffer, 0))
    }

    // MARK: Pinned against the original per-pixel converter

    /** The first, one-sample-at-a-time conversion, kept here verbatim so the
     * faster one can be held to exactly its output. */
    private fun reference(argb: IntArray, width: Int, height: Int, y: Yuv.Plane, u: Yuv.Plane, v: Yuv.Plane) {
        fun fixed(value: Double) = Math.round(value * 65536).toInt()
        val kr = 0.2126
        val kb = 0.0722
        val kg = 1 - kr - kb
        val ys = 219.0 / 255.0
        val cs = 224.0 / 255.0
        val yR = fixed(kr * ys)
        val yG = fixed(kg * ys)
        val yB = fixed(kb * ys)
        val cbR = fixed(-kr / (2 * (1 - kb)) * cs)
        val cbG = fixed(-kg / (2 * (1 - kb)) * cs)
        val cbB = -(cbR + cbG)
        val crG = fixed(-kg / (2 * (1 - kr)) * cs)
        val crB = fixed(-kb / (2 * (1 - kr)) * cs)
        val crR = -(crG + crB)
        for (row in 0 until height) {
            for (col in 0 until width) {
                val p = argb[row * width + col]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                y.buffer.put(y.offset + row * y.rowStride + col * y.pixelStride,
                    (((yR * r + yG * g + yB * b + 32768) shr 16) + 16).toByte())
            }
        }
        for (cy in 0 until (height + 1) / 2) {
            val top = 2 * cy
            val bottom = minOf(top + 1, height - 1)
            for (cx in 0 until (width + 1) / 2) {
                val left = 2 * cx
                val right = minOf(left + 1, width - 1)
                val px = intArrayOf(argb[top * width + left], argb[top * width + right],
                    argb[bottom * width + left], argb[bottom * width + right])
                val r = px.sumOf { (it shr 16) and 0xFF }
                val g = px.sumOf { (it shr 8) and 0xFF }
                val b = px.sumOf { it and 0xFF }
                u.buffer.put(u.offset + cy * u.rowStride + cx * u.pixelStride,
                    (((cbR * r + cbG * g + cbB * b + (1 shl 17)) shr 18) + 128).toByte())
                v.buffer.put(v.offset + cy * v.rowStride + cx * v.pixelStride,
                    (((crR * r + crG * g + crB * b + (1 shl 17)) shr 18) + 128).toByte())
            }
        }
    }

    /** One plane layout over a [size]-byte buffer, prefilled with a pattern
     * so untouched padding shows up in a comparison. */
    private class Layout(
        val name: String,
        val size: Int,
        val y: (ByteBuffer) -> Yuv.Plane,
        val u: (ByteBuffer) -> Yuv.Plane,
        val v: (ByteBuffer) -> Yuv.Plane,
    )

    private fun layouts(width: Int, height: Int): List<Layout> {
        val cw = (width + 1) / 2
        val ch = (height + 1) / 2
        val ys = width + 6
        val cs = 2 * cw + 4
        return listOf(
            Layout("I420", width * height + 2 * cw * ch,
                { Yuv.Plane(it, 0, width, 1) },
                { Yuv.Plane(it, width * height, cw, 1) },
                { Yuv.Plane(it, width * height + cw * ch, cw, 1) }),
            Layout("NV12 padded", ys * height + cs * ch,
                { Yuv.Plane(it, 0, ys, 1) },
                { Yuv.Plane(it, ys * height, cs, 2) },
                { Yuv.Plane(it, ys * height + 1, cs, 2) }),
            Layout("NV21", width * height + 2 * cw * ch,
                { Yuv.Plane(it, 0, width, 1) },
                { Yuv.Plane(it, width * height + 1, 2 * cw, 2) },
                { Yuv.Plane(it, width * height, 2 * cw, 2) }),
        )
    }

    private fun filled(size: Int, direct: Boolean): ByteBuffer {
        val buffer = if (direct) ByteBuffer.allocateDirect(size) else ByteBuffer.allocate(size)
        for (i in 0 until size) buffer.put(i, (i * 7 + 3).toByte())
        return buffer
    }

    private fun bytes(buffer: ByteBuffer): ByteArray = ByteArray(buffer.capacity()) { buffer.get(it) }

    /** The same pixel, in the int a little-endian RGBA_8888 bitmap's memory
     * reads as (`Bitmap.copyPixelsToBuffer` into an IntBuffer): 0xAABBGGRR. */
    private fun abgr(argb: Int): Int =
        (argb and 0xFF00FF00.toInt()) or ((argb shr 16) and 0xFF) or ((argb and 0xFF) shl 16)

    private val sizes = listOf(2 to 2, 4 to 4, 5 to 3, 16 to 9, 33 to 17)

    @Test fun matchesTheOriginalConverterForEveryLayout() {
        val random = Random(7)
        for ((w, h) in sizes) for (layout in layouts(w, h)) for (direct in listOf(false, true)) {
            val pixels = IntArray(w * h) { random.nextInt() or (0xFF shl 24) }
            val expected = filled(layout.size, direct)
            reference(pixels, w, h, layout.y(expected), layout.u(expected), layout.v(expected))
            val actual = filled(layout.size, direct)
            Yuv.fromArgb(pixels, w, h, layout.y(actual), layout.u(actual), layout.v(actual))
            assertArrayEquals("${layout.name} ${w}x$h direct=$direct", bytes(expected), bytes(actual))
        }
    }

    /** A bitmap's memory read straight into ints, with no unpacking pass,
     * comes out as 0xAABBGGRR; converting from that gives the same bytes. */
    @Test fun abgrPixelsGiveTheSameYuvAsArgb() {
        val random = Random(11)
        for ((w, h) in sizes) for (layout in layouts(w, h)) {
            val pixels = IntArray(w * h) { random.nextInt() or (0xFF shl 24) }
            val expected = filled(layout.size, direct = true)
            reference(pixels, w, h, layout.y(expected), layout.u(expected), layout.v(expected))
            val actual = filled(layout.size, direct = true)
            Yuv.fromArgb(IntArray(w * h) { abgr(pixels[it]) }, w, h,
                layout.y(actual), layout.u(actual), layout.v(actual), order = Yuv.Order.ABGR)
            assertArrayEquals("${layout.name} ${w}x$h", bytes(expected), bytes(actual))
        }
    }

    /** The frame can be split into bands of chroma rows (two pixel rows
     * each) and converted piece by piece, in any order, to the same bytes,
     * so the bands can run on separate threads. */
    @Test fun bandsOfChromaRowsAddUpToTheWholeFrame() {
        val random = Random(13)
        for ((w, h) in sizes) for (layout in layouts(w, h)) {
            val pixels = IntArray(w * h) { random.nextInt() or (0xFF shl 24) }
            val expected = filled(layout.size, direct = true)
            reference(pixels, w, h, layout.y(expected), layout.u(expected), layout.v(expected))
            val actual = filled(layout.size, direct = true)
            val chromaRows = (h + 1) / 2
            val cut = chromaRows / 2
            for (band in listOf(cut until chromaRows, 0 until cut)) {
                Yuv.fromArgb(pixels, w, h, layout.y(actual), layout.u(actual), layout.v(actual), chromaRows = band)
            }
            assertArrayEquals("${layout.name} ${w}x$h", bytes(expected), bytes(actual))
        }
    }
}
