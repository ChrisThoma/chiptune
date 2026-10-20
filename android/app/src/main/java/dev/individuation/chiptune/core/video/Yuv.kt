package dev.individuation.chiptune.core.video

import java.nio.Buffer
import java.nio.ByteBuffer
import kotlin.math.roundToInt

/**
 * ARGB pixels to YUV 4:2:0, for the H.264 encoder's input image.
 *
 * `MediaCodec.getInputImage` hands back three planes whose layout depends on
 * the device: tightly packed I420, semi-planar NV12 or NV21 (U and V one byte
 * apart, each with a pixel stride of 2), and rows padded to an alignment. So
 * each plane is described by where its first sample is, how far apart its
 * rows are and how far apart its samples are, and nothing is assumed beyond
 * that.
 *
 * BT.709, limited range (Y 16-235, chroma 16-240), which the encoder is told
 * and which matches the colour tags the iOS writer puts on its file. Each
 * chroma sample is the average of its 2x2 block. Fixed point, rounded to
 * nearest, with each chroma row's coefficients summing to zero so greys come
 * out at exactly 128.
 */
object Yuv {

    /** Where one plane's samples go. [offset] is absolute in [buffer] and the
     * buffer's position is never moved. */
    class Plane(val buffer: ByteBuffer, val offset: Int, val rowStride: Int, val pixelStride: Int)

    /** How a pixel's channels sit in its Int. [ARGB] is `Bitmap.getPixels`;
     * [ABGR] is a little-endian RGBA_8888 bitmap's memory read straight into
     * ints (`Bitmap.copyPixelsToBuffer`), which skips getPixels' per-pixel
     * unpacking. Alpha is ignored either way. */
    enum class Order { ARGB, ABGR }

    private const val KR = 0.2126
    private const val KB = 0.0722
    private const val KG = 1 - KR - KB
    private const val ONE = 1 shl 16
    private const val Y_SCALE = 219.0 / 255.0
    private const val C_SCALE = 224.0 / 255.0

    private fun fixed(value: Double): Int = (value * ONE).roundToInt()

    private val yR = fixed(KR * Y_SCALE)
    private val yG = fixed(KG * Y_SCALE)
    private val yB = fixed(KB * Y_SCALE)

    private val cbR = fixed(-KR / (2 * (1 - KB)) * C_SCALE)
    private val cbG = fixed(-KG / (2 * (1 - KB)) * C_SCALE)
    private val cbB = -(cbR + cbG)

    private val crG = fixed(-KG / (2 * (1 - KR)) * C_SCALE)
    private val crB = fixed(-KB / (2 * (1 - KR)) * C_SCALE)
    private val crR = -(crG + crB)

    /**
     * Writes [argb] (row-major, [width] x [height], channels in [order]) into
     * the three planes.
     *
     * [chromaRows] limits the work to those chroma rows and the one or two
     * pixel rows each covers, so a frame can be split into bands that run on
     * separate threads: bands touch disjoint bytes. Each row is built in a
     * ByteArray and copied in with one bulk put, since a put per sample into
     * a direct buffer is most of the cost. A strided plane's row is read,
     * filled in and written back, so whatever lies between its samples (the
     * other chroma plane of an NV12 or NV21 image) is kept.
     */
    fun fromArgb(
        argb: IntArray,
        width: Int,
        height: Int,
        y: Plane,
        u: Plane,
        v: Plane,
        order: Order = Order.ARGB,
        chromaRows: IntRange = 0 until (height + 1) / 2,
    ) {
        val chromaWidth = (width + 1) / 2
        val chromaHeight = (height + 1) / 2
        val first = maxOf(chromaRows.first, 0)
        val last = minOf(chromaRows.last, chromaHeight - 1)
        if (first > last || width <= 0) return
        val rShift = if (order == Order.ARGB) 16 else 0
        val bShift = if (order == Order.ARGB) 0 else 16

        // Duplicates, so the callers' positions never move and each band has
        // its own to move.
        val yOut = y.buffer.duplicate()
        val uOut = u.buffer.duplicate()
        val vOut = v.buffer.duplicate()
        val yRow = ByteArray(width)
        val uRow = ByteArray(chromaWidth)
        val vRow = ByteArray(chromaWidth)
        val scratch = ByteArray(
            maxOf(span(width, y.pixelStride), span(chromaWidth, u.pixelStride), span(chromaWidth, v.pixelStride)),
        )

        // Four pixels' sum against coefficients scaled by 2^16: divide by 2^18.
        val shift = 18
        val half = 1 shl (shift - 1)
        val pairs = width / 2

        for (cy in first..last) {
            val top = 2 * cy
            val bottom = minOf(top + 1, height - 1)
            for (row in top..bottom) {
                val src = row * width
                for (col in 0 until width) {
                    val p = argb[src + col]
                    val r = (p shr rShift) and 0xFF
                    val g = (p shr 8) and 0xFF
                    val b = (p shr bShift) and 0xFF
                    yRow[col] = (((yR * r + yG * g + yB * b + ONE / 2) shr 16) + 16).toByte()
                }
                writeRow(yOut, y.offset + row * y.rowStride, y.pixelStride, yRow, width, scratch)
            }

            val upper = top * width
            val lower = bottom * width
            for (cx in 0 until chromaWidth) {
                val left = 2 * cx
                val right = if (cx < pairs) left + 1 else left
                val p0 = argb[upper + left]
                val p1 = argb[upper + right]
                val p2 = argb[lower + left]
                val p3 = argb[lower + right]
                val r = ((p0 shr rShift) and 0xFF) + ((p1 shr rShift) and 0xFF) +
                    ((p2 shr rShift) and 0xFF) + ((p3 shr rShift) and 0xFF)
                val g = ((p0 shr 8) and 0xFF) + ((p1 shr 8) and 0xFF) +
                    ((p2 shr 8) and 0xFF) + ((p3 shr 8) and 0xFF)
                val b = ((p0 shr bShift) and 0xFF) + ((p1 shr bShift) and 0xFF) +
                    ((p2 shr bShift) and 0xFF) + ((p3 shr bShift) and 0xFF)
                // shr on a negative Int floors, so adding half rounds to nearest.
                uRow[cx] = (((cbR * r + cbG * g + cbB * b + half) shr shift) + 128).toByte()
                vRow[cx] = (((crR * r + crG * g + crB * b + half) shr shift) + 128).toByte()
            }
            // U, then V read back after U is in, so planes that interleave
            // keep both.
            writeRow(uOut, u.offset + cy * u.rowStride, u.pixelStride, uRow, chromaWidth, scratch)
            writeRow(vOut, v.offset + cy * v.rowStride, v.pixelStride, vRow, chromaWidth, scratch)
        }
    }

    /** Bytes from a row's first sample to its last. */
    private fun span(count: Int, pixelStride: Int): Int = (count - 1) * pixelStride + 1

    /** Puts [count] samples from [values] at [at], [pixelStride] apart. */
    private fun writeRow(out: ByteBuffer, at: Int, pixelStride: Int, values: ByteArray, count: Int, scratch: ByteArray) {
        // Through Buffer: ByteBuffer's own position(Int) is only there from
        // API 28, and minSdk is 26.
        (out as Buffer).position(at)
        if (pixelStride == 1) {
            out.put(values, 0, count)
            return
        }
        val length = span(count, pixelStride)
        out.get(scratch, 0, length)
        for (i in 0 until count) scratch[i * pixelStride] = values[i]
        (out as Buffer).position(at)
        out.put(scratch, 0, length)
    }
}
