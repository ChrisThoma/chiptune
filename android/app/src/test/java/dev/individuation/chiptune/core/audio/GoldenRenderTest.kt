package dev.individuation.chiptune.core.audio

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.model.swiftRounded
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Port of `GoldenRenderTests.swift`: the fixed song rendered by iOS into
 * `Tests/Fixtures/golden-demo.wav`, re-rendered here through [WavExport] and
 * compared sample for sample. This is the cross-platform pin: the fixture was
 * written by the Swift synth, so a match here means the Kotlin port sounds the
 * same, not merely that it is stable.
 *
 * No regeneration path here: iOS owns the fixture. */
class GoldenRenderTest {

    @get:Rule val temp = TemporaryFolder()

    /** 132 BPM, 16 steps, one pass. */
    private val expectedSamples = swiftRounded(44100.0 * 60.0 / (132.0 * 4.0)).toInt() * 16

    private fun fixture(): ShortArray {
        val stream = javaClass.classLoader!!.getResourceAsStream("golden-demo.wav")
        assertNotNull("golden-demo.wav is missing from the test resources (../../Tests/Fixtures)", stream)
        return WavFile.pcm16(stream!!.use { it.readBytes() })
    }

    private fun renderGolden(): File {
        val file = WavExport.render(TestSongs.golden(), temp.root)
        assertNotNull("the golden song failed to render", file)
        return file!!
    }

    // MARK: The oracle - structure

    @Test fun goldenRenderHasTheDurationItsTempoImplies() {
        assertEquals(80176, expectedSamples) // the Swift test's own figure, restated
        assertEquals(expectedSamples, WavFile.pcm16(renderGolden()).size)
    }

    @Test fun goldenRenderHasAudioThroughoutAndNoClipping() {
        val samples = WavFile.samples(renderGolden())
        val quarter = samples.size / 4
        for (section in 0 until 4) {
            val from = section * quarter
            val until = (section + 1) * quarter
            val level = RenderHarness.rms(samples, from, until)
            assertTrue("quarter $section is too quiet to be the demo riff ($level)", level > 0.05)
            assertTrue("quarter $section is unexpectedly hot ($level)", level < 0.5)
            assertTrue("quarter $section clips", RenderHarness.peak(samples, from, until) <= 1.0)
        }
        assertFalse(samples.any { !it.isFinite() })
    }

    // MARK: The change detector, and the cross-platform pin

    @Test fun goldenRenderMatchesTheIosFixture() {
        val expected = fixture()
        val fresh = WavFile.pcm16(renderGolden())
        assertEquals("the render's length differs from the iOS fixture", expected.size, fresh.size)

        var worst = 0
        var worstIndex = -1
        var differing = 0
        for (i in fresh.indices) {
            val delta = kotlin.math.abs(fresh[i].toInt() - expected[i].toInt())
            if (delta != 0) differing += 1
            if (delta > worst) {
                worst = delta
                worstIndex = i
            }
        }
        println("GoldenRenderTest: max deviation $worst LSB at sample $worstIndex; " +
            "$differing of ${fresh.size} samples differ")
        assertTrue("the Kotlin synth's output differs from iOS: sample $worstIndex is off by $worst LSB " +
            "($differing samples differ)", worst <= 2)
    }

    /** Stricter than the 2 LSB contract above, and specific to the JVM: with
     * StrictMath the port reproduces the iOS fixture bit for bit, and that is
     * worth pinning. The 2 LSB slack would otherwise hide a whole class of
     * 1 LSB mistakes (rounding instead of truncating the PCM conversion,
     * scaling by 32768) that touch tens of thousands of samples. If a future
     * iOS regeneration lands within 2 LSB but not exactly, relax this one and
     * say why; the device check in the plan's Verification step uses 2 LSB. */
    @Test fun goldenRenderIsBitExactOnTheJvm() {
        val expected = fixture()
        val fresh = WavFile.pcm16(renderGolden())
        val differing = fresh.indices.count { fresh[it] != expected.getOrNull(it) }
        assertEquals("samples that differ from the iOS fixture at all", 0, differing)
    }

    /** The fixture header itself, so a misread of the fixture can't make the
     * comparison above vacuous. */
    @Test fun theFixtureIsSixteenBitMonoAtTheExportRate() {
        val bytes = javaClass.classLoader!!.getResourceAsStream("golden-demo.wav")!!.use { it.readBytes() }
        val fmt = WavFile.chunk(bytes, "fmt ")!!
        assertEquals(1, WavFile.le16(fmt, 2))
        assertEquals(44100, WavFile.le32(fmt, 4))
        assertEquals(16, WavFile.le16(fmt, 14))
        assertEquals(expectedSamples, fixture().size)
    }
}
