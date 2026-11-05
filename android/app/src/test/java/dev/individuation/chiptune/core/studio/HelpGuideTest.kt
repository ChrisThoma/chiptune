package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Chip
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The guide is prose about controls that live elsewhere, so nothing but these
 * tests notices when a label or a limit moves and the words stay behind. */
class HelpGuideTest {
    private fun terms(id: HelpGuide.SectionId) = HelpGuide.section(id)?.entries?.map { it.term }.orEmpty()

    private fun text(term: String, id: HelpGuide.SectionId) =
        HelpGuide.section(id)?.entries?.firstOrNull { it.term == term }?.text.orEmpty()

    private val allEntries get() = HelpGuide.sections.flatMap { it.entries }

    @Test fun everySectionAppearsOnceInOrderAndHasEntries() {
        assertEquals(HelpGuide.SectionId.entries.toList(), HelpGuide.sections.map { it.id })
        for (section in HelpGuide.sections) assertTrue(section.title, section.entries.isNotEmpty())
    }

    @Test fun entryKeysAreUniqueWithinASection() {
        for (section in HelpGuide.sections) {
            val keys = section.entries.map { it.key }
            assertEquals(section.title, keys.size, keys.toSet().size)
        }
    }

    @Test fun theTransportLabelsAreExplained() {
        for (label in listOf("PATT", "SONG", "ARR", "BPM")) {
            assertTrue(label, label in terms(HelpGuide.SectionId.PLAYING))
        }
    }

    @Test fun everyChannelNameIsExplained() {
        val joined = terms(HelpGuide.SectionId.TRACKS).joinToString(" ")
        for (kind in ChannelKind.entries) assertTrue(kind.shortName, kind.shortName in joined)
    }

    @Test fun tempoRangeMatchesTheEngine() {
        val range = "${Chip.TEMPO_MIN.toInt()} to ${Chip.TEMPO_MAX.toInt()}"
        assertTrue(range in text("BPM", HelpGuide.SectionId.PLAYING))
    }

    @Test fun patternLengthRangeMatchesTheModel() {
        val range = "${Chip.patternLengthRange.first} to ${Chip.patternLengthRange.last}"
        assertTrue(range in text("STEPS", HelpGuide.SectionId.PATTERNS))
    }

    @Test fun limitsMatchTheModel() {
        assertTrue("${Chip.MAX_PATTERNS}" in text("+", HelpGuide.SectionId.PATTERNS))
        assertTrue("${Chip.MAX_TRACKS}" in text("+", HelpGuide.SectionId.TRACKS))
    }

    @Test fun copyHasNoDashes() {
        assertTrue(allEntries.isNotEmpty())
        for (entry in allEntries) {
            assertFalse(entry.text, "\u2014" in entry.text)
            assertFalse(entry.text, " - " in entry.text)
        }
    }

    @Test fun everyEntryEndsAsASentence() {
        assertTrue(allEntries.isNotEmpty())
        for (entry in allEntries) assertTrue(entry.text, entry.text.endsWith("."))
    }

    @Test fun holdGesturesCantBeMistakenForTheHoldSwitch() {
        val all = HelpGuide.sections.flatMap { it.entries }
        assertTrue(all.any { it.term == "Hold a step" })
        assertTrue(all.any { it.term == "Hold a track" })
        assertEquals(1, all.count { it.term == "Hold" })
    }

    @Test fun trackIsDefinedBeforeTheChannels() {
        val tracks = HelpGuide.sections.first { it.id == HelpGuide.SectionId.TRACKS }
        assertEquals("Track", tracks.entries.first().term)
    }

    @Test fun presetNamesTheRowYouTap() {
        val sound = HelpGuide.sections.first { it.id == HelpGuide.SectionId.SOUND }
        assertTrue(sound.entries.first { it.term == "Preset" }.text.startsWith("Tap Sound"))
    }
}
