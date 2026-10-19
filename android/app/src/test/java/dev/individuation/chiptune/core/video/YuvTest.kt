package dev.individuation.chiptune.core.video

import java.nio.ByteBuffer
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
}
