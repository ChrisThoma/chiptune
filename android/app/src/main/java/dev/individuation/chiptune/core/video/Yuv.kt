package dev.individuation.chiptune.core.video

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

    /** Writes [argb] (row-major, [width] x [height]) into the three planes. */
    fun fromArgb(argb: IntArray, width: Int, height: Int, y: Plane, u: Plane, v: Plane) {
        val yBuf = y.buffer
        for (row in 0 until height) {
            var src = row * width
            var dst = y.offset + row * y.rowStride
            for (col in 0 until width) {
                val p = argb[src++]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                yBuf.put(dst, (((yR * r + yG * g + yB * b + ONE / 2) shr 16) + 16).toByte())
                dst += y.pixelStride
            }
        }

        val chromaWidth = (width + 1) / 2
        val chromaHeight = (height + 1) / 2
        val uBuf = u.buffer
        val vBuf = v.buffer
        // Four pixels' sum against coefficients scaled by 2^16: divide by 2^18.
        val shift = 18
        val half = 1 shl (shift - 1)
        for (cy in 0 until chromaHeight) {
            val top = 2 * cy
            val bottom = minOf(top + 1, height - 1)
            var uAt = u.offset + cy * u.rowStride
            var vAt = v.offset + cy * v.rowStride
            for (cx in 0 until chromaWidth) {
                val left = 2 * cx
                val right = minOf(left + 1, width - 1)
                val p0 = argb[top * width + left]
                val p1 = argb[top * width + right]
                val p2 = argb[bottom * width + left]
                val p3 = argb[bottom * width + right]
                val r = ((p0 shr 16) and 0xFF) + ((p1 shr 16) and 0xFF) + ((p2 shr 16) and 0xFF) + ((p3 shr 16) and 0xFF)
                val g = ((p0 shr 8) and 0xFF) + ((p1 shr 8) and 0xFF) + ((p2 shr 8) and 0xFF) + ((p3 shr 8) and 0xFF)
                val b = (p0 and 0xFF) + (p1 and 0xFF) + (p2 and 0xFF) + (p3 and 0xFF)
                // shr on a negative Int floors, so adding half rounds to nearest.
                val cb = ((cbR * r + cbG * g + cbB * b + half) shr shift) + 128
                val cr = ((crR * r + crG * g + crB * b + half) shr shift) + 128
                uBuf.put(uAt, cb.toByte())
                vBuf.put(vAt, cr.toByte())
                uAt += u.pixelStride
                vAt += v.pixelStride
            }
        }
    }
}
