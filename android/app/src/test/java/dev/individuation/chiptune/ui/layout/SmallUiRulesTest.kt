package dev.individuation.chiptune.ui.layout

import dev.individuation.chiptune.core.model.PatternNameCheck
import dev.individuation.chiptune.core.studio.StudioHarness
import dev.individuation.chiptune.core.TestSongs
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `ScreenshotModeTests.swift`. iOS reads launch arguments out of
 * UserDefaults; here they are debug-only intent extras, passed as booleans
 * (`--ez shotPlaying true`) or strings (`--es shotPlaying YES`). */
class ScreenshotModeTest {
    @Test fun noArgumentRequestsNoMode() = assertNull(ScreenshotMode.requested(emptyMap()))

    @Test fun playingKeyMapsToPlayingCase() =
        assertEquals(ScreenshotMode.PLAYING, ScreenshotMode.requested(mapOf("shotPlaying" to true)))

    @Test fun patternKeyMapsToPatternCase() =
        assertEquals(ScreenshotMode.PATTERN, ScreenshotMode.requested(mapOf("shotPatternB" to true)))

    @Test fun falseValueSelectsNoMode() = assertNull(ScreenshotMode.requested(mapOf("shotPlaying" to false)))

    @Test fun noStringValueSelectsNoMode() = assertNull(ScreenshotMode.requested(mapOf("shotPatternB" to "NO")))

    @Test fun yesStringValueSelectsItsMode() =
        assertEquals(ScreenshotMode.PLAYING, ScreenshotMode.requested(mapOf("shotPlaying" to "YES")))

    @Test fun eachExistingKeyStillMapsToItsCase() {
        for (mode in ScreenshotMode.entries) assertEquals(mode, ScreenshotMode.requested(mapOf(mode.key to true)))
    }

    /** The shoot's keys are its command-line interface. */
    @Test fun keysAreTheShootsArguments() {
        assertEquals(
            listOf("shotArrangement", "shotEditor", "shotLibrary", "shotExport", "shotPlaying", "shotPatternB"),
            ScreenshotMode.entries.map { it.key },
        )
    }

    /** iOS takes `allCases.first`, so with several set the declaration order
     * decides: arrangement > editor > library > export > playing > pattern. */
    @Test fun severalKeysResolveInDeclarationOrder() {
        val all = ScreenshotMode.entries.associate { it.key to (true as Any?) }
        assertEquals(ScreenshotMode.ARRANGEMENT, ScreenshotMode.requested(all))
        assertEquals(ScreenshotMode.EXPORT, ScreenshotMode.requested(mapOf("shotPatternB" to true, "shotExport" to "YES", "shotPlaying" to true)))
    }
}

/** Ports of `FormatClockTests.swift` and `FormatPercentTests.swift`. */
class FormatTest {
    @Test fun shortDurationsShowTenths() {
        assertEquals("0:01.8", Format.clock(1.8))
        assertEquals("0:00.5", Format.clock(0.5))
        assertEquals("0:09.9", Format.clock(9.94))
    }

    @Test fun tenthsRoundRatherThanTruncate() {
        assertEquals("0:01.9", Format.clock(1.86))
        assertEquals("0:03.6", Format.clock(3.6))
    }

    @Test fun tenSecondsAndUpRoundToWholeSeconds() {
        assertEquals("0:10", Format.clock(10.0))
        assertEquals("0:13", Format.clock(12.6))
        assertEquals("1:07", Format.clock(67.2))
    }

    @Test fun roundingUpToTenDropsTheTenths() = assertEquals("0:10", Format.clock(9.96))

    @Test fun roundingCarriesIntoTheMinute() = assertEquals("1:00", Format.clock(59.6))

    @Test fun zeroIsWhole() = assertEquals("0:00", Format.clock(0.0))

    @Test fun percentRoundsRatherThanTruncates() {
        assertEquals("57%", Format.percent(0.57))
        assertEquals("29%", Format.percent(0.29))
        assertEquals("57%", Format.percent(0.567))
        assertEquals("56%", Format.percent(0.564))
    }

    @Test fun percentEndsAreExact() {
        assertEquals("0%", Format.percent(0.0))
        assertEquals("100%", Format.percent(1.0))
        assertEquals("50%", Format.percent(0.5))
    }

    @Test fun countsAndTempo() {
        assertEquals("1 pattern", Format.count(1, "pattern"))
        assertEquals("3 patterns", Format.count(3, "pattern"))
        assertEquals("132 BPM", Format.bpm(132.0))
    }
}

/** Port of `PlainStepperTests.swift`. */
class PlainStepperTest {
    @Test fun stepsWithinTheRange() {
        assertEquals(2, PlainStepperRules.stepped(1, 1, 1..16, isEnabled = true))
        assertEquals(4, PlainStepperRules.stepped(5, -1, 1..16, isEnabled = true))
    }

    @Test fun stopsAtEitherEnd() {
        assertEquals(1, PlainStepperRules.stepped(1, -1, 1..16, isEnabled = true))
        assertEquals(16, PlainStepperRules.stepped(16, 1, 1..16, isEnabled = true))
    }

    @Test fun aLockedStepperDoesNotStep() {
        assertEquals(3, PlainStepperRules.stepped(3, 1, 1..16, isEnabled = false))
        assertEquals(3, PlainStepperRules.stepped(3, -1, 1..16, isEnabled = false))
    }

    @Test fun actionsAreNamedAsTheSystemStepperNamesThem() {
        assertEquals("Increment", PlainStepperRules.INCREMENT_ACTION_NAME)
        assertEquals("Decrement", PlainStepperRules.DECREMENT_ACTION_NAME)
    }

    @Test fun actionsStepByOneInTheirDirection() {
        assertEquals(1, PlainStepperRules.delta(forIncrement = true))
        assertEquals(-1, PlainStepperRules.delta(forIncrement = false))
    }

    /** The dimmed ends follow the same bounds the steps stop at. */
    @Test fun endsDimAtTheirBoundsAndWhenLocked() {
        assertFalse(PlainStepperRules.canDecrease(1, 1..16, true))
        assertTrue(PlainStepperRules.canIncrease(1, 1..16, true))
        assertFalse(PlainStepperRules.canIncrease(16, 1..16, true))
        assertFalse(PlainStepperRules.canDecrease(5, 1..16, false))
    }
}

/** The rename sheet's decisions (`PatternRenameFooterTests.swift`'s Studio
 * case, plus the sheet's own live cap and its no-index footer). */
class PatternRenameFooterTest {
    @Test fun aSheetWithNoPatternStillCounts() {
        assertEquals("Up to 6 characters \u2014 2 of 6 used.", PatternRenameForm.footer("ab", listOf("A"), null))
    }

    @Test fun theFieldIsCappedAsYouType() {
        assertEquals("Chorus", PatternRenameForm.capped("ChorusBridge99"))
        assertEquals("Verse", PatternRenameForm.capped("Verse"))
    }

    @Test fun renameIsOfferedOnlyForAnAcceptableName() {
        val names = listOf("A", "B")
        assertTrue(PatternRenameForm.canRename("Zed", names, 1))
        assertFalse(PatternRenameForm.canRename("A", names, 1))
        assertFalse(PatternRenameForm.canRename("  ", names, 1))
        assertFalse(PatternRenameForm.canRename("Zed", names, null))
    }

    @Test fun studioDecisionMatchesTheSharedCheck() {
        val harness = StudioHarness()
        try {
            val studio = harness.studio
            studio.open(TestSongs.twoPatterns())
            val list = studio.song.patterns.map { it.name }
            for (name in listOf("", " ", list[0], list[1], "Zed", "toolongname")) {
                for (i in list.indices) {
                    assertEquals(PatternNameCheck.evaluate(name, list, i).acceptedName, studio.acceptablePatternName(name, i))
                    assertEquals(studio.acceptablePatternName(name, i) != null, PatternRenameForm.canRename(name, list, i))
                }
            }
        } finally {
            harness.close()
        }
    }
}

/** Port of `BuildStampTests.swift`'s content rules. */
class BuildStampTest {
    private val noon = Instant.parse("2026-08-11T12:00:00Z")

    private fun stamp(commit: String? = "c9d96bc", builtAt: Instant? = noon, version: String? = "1.1") =
        BuildStamp(commit, builtAt, version)

    @Test fun theRowLeadsWithTheBuildAndEndsWithTheRelease() {
        val lines = stamp().lines
        assertEquals(3, lines.size)
        assertTrue(lines[0], lines[0].startsWith("Built "))
        assertEquals("c9d96bc", lines[1])
        assertEquals("Version 1.1", lines[2])
    }

    @Test fun theBuildDateIsWrittenForReadingRatherThanParsing() {
        val line = stamp().builtLine!!
        assertFalse(line, line.contains("T"))
        assertFalse(line, line.contains("Z"))
        assertTrue(line, line.contains("2026"))
    }

    @Test fun copyingGivesTheReleaseAndTheCommit() = assertEquals("1.1 \u00b7 c9d96bc", stamp().copyText)

    @Test fun aMissingPieceLeavesItsLineOut() {
        val noCommit = stamp(commit = null)
        assertEquals(2, noCommit.lines.size)
        assertEquals("Version 1.1", noCommit.lines[1])
        assertEquals("1.1", noCommit.copyText)
        assertEquals(listOf("c9d96bc", "Version 1.1"), BuildStamp("c9d96bc", null, "1.1").lines)
        assertEquals(emptyList<String>(), BuildStamp(null, null, null).lines)
    }

    @Test fun emptyAndPlaceholderValuesAreNotData() {
        assertNull(BuildStamp("   ", noon, "1.1").commit)
        assertNull(BuildStamp(null, noon, "\$(MARKETING_VERSION)").version)
        // What the Gradle stamp writes outside a git checkout.
        assertNull(BuildStamp("nogit", noon, "1.0").commit)
    }

    @Test fun whitespaceAroundAValueIsTrimmed() =
        assertEquals("1.1 \u00b7 c9d96bc", BuildStamp(" c9d96bc\n", noon, " 1.1 ").copyText)

    /** The Gradle stamp writes the day as an ISO date; anything else is no date. */
    @Test fun theBuildDateParsesFromTheStampedField() {
        assertEquals(Instant.parse("2026-10-09T00:00:00Z"), BuildStamp.parseBuildDate("2026-10-09"))
        assertNull(BuildStamp.parseBuildDate(""))
        assertNull(BuildStamp.parseBuildDate("yesterday"))
    }
}

/** The VoiceOver words that became TalkBack's: `PatternChipAccessibilityTests`,
 * `TransportPlayShapeTests` and the grid cell's label and value. */
class AccessibilityRulesTest {
    @Test fun chipValueNamesPlayingAndEmpty() {
        assertNull(PatternChipAccessibility.value(playing = false, isEmpty = false))
        assertEquals("Playing", PatternChipAccessibility.value(playing = true, isEmpty = false))
        assertEquals("Empty", PatternChipAccessibility.value(playing = false, isEmpty = true))
        assertEquals("Playing, Empty", PatternChipAccessibility.value(playing = true, isEmpty = true))
    }

    @Test fun defaultSizeKeepsTheFixedPlayWidthAndGlyph() {
        assertEquals(ChipLayout.PLAY_BUTTON_WIDTH, TransportPlayShape.width(fillsRow = false)!!, 0.0)
        assertEquals(18.0, TransportPlayShape.glyphSize(1.0), 0.0)
    }

    @Test fun stackedPlayFillsItsRow() = assertNull(TransportPlayShape.width(fillsRow = true))

    @Test fun playGlyphGrowsWithTheText() = assertEquals(18 * 2.3, TransportPlayShape.glyphSize(2.3), 0.001)

    @Test fun cellsSpeakTrackStepAndNote() {
        assertEquals("Triangle B step 4", CellAccessibility.label("Triangle B", 3))
        assertEquals("C4", CellAccessibility.value(60))
        assertEquals("REST", CellAccessibility.value(-2))
        assertEquals("Empty", CellAccessibility.value(-1))
    }

    /** Chip menu entries and the matching TalkBack actions share one rule. */
    @Test fun patternChipActionsFollowTheMenuRules() {
        assertEquals(listOf("Rename", "Duplicate", "Clear", "Delete"), PatternChipActions.available(canAddPattern = true, patternCount = 2))
        assertEquals(listOf("Rename", "Clear"), PatternChipActions.available(canAddPattern = false, patternCount = 1))
    }
}

/** Large text: iOS's accessibility Dynamic Type sizes are `fontScale >= 1.5`. */
class TextScaleTest {
    @Test fun accessibilitySizesStartAtOneAndAHalf() {
        assertFalse(TextScale.isAccessibilitySize(1.0f))
        assertFalse(TextScale.isAccessibilitySize(1.3f))
        assertTrue(TextScale.isAccessibilitySize(1.5f))
        assertTrue(TextScale.isAccessibilitySize(2.0f))
    }

    @Test fun gridAndKeyTextIsCappedAtOneAndAHalf() {
        assertEquals(1.0f, TextScale.capped(1.0f), 0f)
        assertEquals(1.3f, TextScale.capped(1.3f), 0f)
        assertEquals(1.5f, TextScale.capped(2.0f), 0f)
    }

    @Test fun theEditorScrollsAtAccessibilitySizesOrWhenTheLayoutSaysSo() {
        assertFalse(EditorChrome.scrollsEditor(ChipLayout.PHONE, 1.3f))
        assertTrue(EditorChrome.scrollsEditor(ChipLayout.PHONE, 1.5f))
        assertTrue(EditorChrome.scrollsEditor(ChipLayout.PHONE.copy(scrollsEditor = true), 1.0f))
    }

    @Test fun transportAndPatternBarStackAtAccessibilitySizes() {
        assertEquals(TransportForm.STACKED, EditorChrome.transportForm(ChipLayout.PHONE, 440.0, 1.5f))
        assertEquals(TransportForm.ROW, EditorChrome.transportForm(ChipLayout.PHONE, 411.0, 1.0f))
        assertEquals(TransportForm.TWO_ROWS, EditorChrome.transportForm(ChipLayout.PHONE, 320.0, 1.0f))
        assertTrue(EditorChrome.patternBarStacks(1.5f))
        assertFalse(EditorChrome.patternBarStacks(1.3f))
    }

    /** The scrolling editor's grid gets a floor of its own. */
    @Test fun theScrollingGridHasAFloor() {
        assertEquals(360.0, EditorChrome.scrollingGridHeight(500.0), 0.0)
        assertEquals(550.0, EditorChrome.scrollingGridHeight(1000.0), 0.0)
    }

    @Test fun regularStartsAtSixHundredDp() {
        assertEquals(SizeClass.COMPACT, SizeClass.forWindowWidth(599.0))
        assertEquals(SizeClass.REGULAR, SizeClass.forWindowWidth(600.0))
    }
}

/** The tempo dialog reads its field the way Swift's `Double(String)` does. */
class TempoInputTest {
    @Test fun aNumberIsATempo() {
        assertEquals(132.0, TempoInput.parse("132")!!, 0.0)
        assertEquals(132.5, TempoInput.parse(" 132.5 ")!!, 0.0)
    }

    @Test fun anythingElseIsNot() {
        assertNull(TempoInput.parse(""))
        assertNull(TempoInput.parse("fast"))
        assertNull(TempoInput.parse("120d"))
        assertNull(TempoInput.parse("12 0"))
    }
}
