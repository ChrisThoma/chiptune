package dev.individuation.chiptune.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `NoteNameTests.swift`. */
class NoteNameTest {
    @Test fun ordinaryPitchesLabelAsLetterAndOctave() {
        assertEquals("C4", NoteName.label(60))
        assertEquals("C#4", NoteName.label(61))
        assertEquals("C-1", NoteName.label(0))
        assertEquals("G9", NoteName.label(127))
    }

    @Test fun aNoteOffLabelsAsRest() = assertEquals("REST", NoteName.label(Chip.NOTE_OFF))

    @Test fun anEmptyNoteLabelsAsBlank() = assertEquals("", NoteName.label(Chip.EMPTY_NOTE))

    @Test fun frequencyIsEqualTemperedFromA440() {
        assertEquals(440.0, NoteName.frequency(69), 0.0)
        assertEquals(880.0, NoteName.frequency(81), 1e-9)
        assertEquals(261.6255653005986, NoteName.frequency(60), 1e-9)
    }
}

/** Port of `InstrumentPresetTests.swift` (the render test arrives in Phase 2). */
class InstrumentPresetTest {
    @Test fun everyKindHasPresets() {
        for (kind in ChannelKind.entries) assertFalse(kind.fullName, InstrumentPreset.presetsFor(kind).isEmpty())
    }

    @Test fun presetsAreListedUnderTheirOwnKind() {
        for (kind in ChannelKind.entries) {
            for (preset in InstrumentPreset.presetsFor(kind)) assertEquals(kind, preset.kind)
        }
    }

    @Test fun presetNamesAreUniqueWithinAKind() {
        for (kind in ChannelKind.entries) {
            val names = InstrumentPreset.presetsFor(kind).map { it.name }
            assertEquals(names.size, names.toSet().size)
        }
    }

    @Test fun everyPresetSurvivesNormalizationUnchanged() {
        for (preset in InstrumentPreset.ALL) assertEquals(preset.name, preset.instrument, preset.instrument.normalized())
    }

    @Test fun theDefaultInstrumentIsTheFirstPresetForItsKind() {
        for (kind in ChannelKind.entries) {
            assertEquals(InstrumentPreset.presetsFor(kind).first().instrument, Instrument.defaultFor(kind))
        }
    }

    @Test fun noPresetHoldsWithoutSayingSo() {
        for (preset in InstrumentPreset.ALL.filter { it.instrument.sustain }) {
            val n = preset.name.lowercase()
            assertTrue(preset.name, "hold" in n || "pad" in n || "drone" in n)
        }
    }

    @Test fun aPresetIsRecognizedAndAnEditedSoundIsNot() {
        val preset = InstrumentPreset.presetsFor(ChannelKind.TRIANGLE).first()
        assertEquals(preset.name, InstrumentPreset.matching(preset.instrument, ChannelKind.TRIANGLE)?.name)
        assertNull(InstrumentPreset.matching(preset.instrument.copy(volume = 0.13), ChannelKind.TRIANGLE))
    }

    @Test fun thePresetTableMatchesTheSwiftOne() {
        assertEquals(19, InstrumentPreset.ALL.size)
        assertEquals("0.Lead", InstrumentPreset.ALL[0].id)
        assertEquals(Instrument(duty = 2, volume = 0.7, decay = 0.5, arpeggio = listOf(0, 4, 7)),
            InstrumentPreset.ALL.first { it.name == "Chord" }.instrument)
        assertEquals(Instrument(duty = 2, volume = 0.9, decay = 1.5), Instrument.defaultFor(ChannelKind.TRIANGLE))
        assertEquals(Instrument(duty = 2, volume = 0.5, decay = 0.12), Instrument.defaultFor(ChannelKind.NOISE))
    }
}

/** Port of `NameCapTests.swift`. */
class NameCapTest {
    @Test fun clipsToTheCapLive() {
        assertEquals("abcdefghijklmnop", NameCap.clip("abcdefghijklmnopqrst", Track.MAX_NAME_LENGTH))
        assertEquals("abcdef", NameCap.clip("abcdefgh", PatternNameCheck.MAX_LENGTH))
    }

    @Test fun shortTextAndExactCapPassThrough() {
        assertEquals("abc", NameCap.clip("abc", 16))
        assertEquals("abcdefghijklmnop", NameCap.clip("abcdefghijklmnop", 16))
    }

    @Test fun countsGraphemeClustersLikeTheSavedName() {
        val flag = "\uD83C\uDDEF\uD83C\uDDF5"
        val clipped = NameCap.clip(flag.repeat(20), 16)
        assertEquals(flag.repeat(16), clipped)
    }

    @Test fun clippedTextMatchesTheSavedRule() {
        val typed = "abcdefghijklmnopqrst"
        val saved = Song.create("x").let { s ->
            s.copy(tracks = listOf(s.tracks[0].copy(name = typed))).normalized().tracks[0].name
        }
        assertEquals(saved, NameCap.clip(typed, Track.MAX_NAME_LENGTH))
    }

    @Test fun draftFollowsStoredNameOnlyWhenTheyDiffer() {
        assertNull(NameCap.draftUpdate("abc", "abc"))
        assertNull(NameCap.draftUpdate("   ", null))
        assertEquals("", NameCap.draftUpdate("abc", null))
        assertEquals("xyz", NameCap.draftUpdate("abc", "xyz"))
    }
}

/** Port of `TrackReorderTests.swift`. */
class TrackReorderTest {
    private val step = 82.0

    @Test fun aShortDragStaysPut() {
        assertEquals(1, TrackReorder.destination(1, 30.0, step, 4))
        assertEquals(1, TrackReorder.destination(1, -30.0, step, 4))
    }

    @Test fun crossingHalfAColumnReachesTheNeighbor() {
        assertEquals(2, TrackReorder.destination(1, 42.0, step, 4))
        assertEquals(0, TrackReorder.destination(1, -42.0, step, 4))
    }

    /** Swift's `.rounded()` is half away from zero, so exactly half a column
     * left counts as a whole one — `Math.round` would round -0.5 to 0. */
    @Test fun exactlyHalfAColumnRoundsAwayFromZero() {
        assertEquals(2, TrackReorder.destination(1, 41.0, step, 4))
        assertEquals(0, TrackReorder.destination(1, -41.0, step, 4))
    }

    @Test fun aLongDragCrossesSeveralColumns() = assertEquals(3, TrackReorder.destination(0, 250.0, step, 4))

    @Test fun draggingPastEitherEndStopsAtTheEnd() {
        assertEquals(3, TrackReorder.destination(2, 2000.0, step, 4))
        assertEquals(0, TrackReorder.destination(2, -2000.0, step, 4))
    }

    @Test fun aDegenerateColumnWidthStaysPut() = assertEquals(2, TrackReorder.destination(2, 50.0, 0.0, 4))

    @Test fun theColumnsBetweenSlideTowardTheGap() {
        assertEquals(-step, TrackReorder.offset(1, 0, 2, step), 0.0)
        assertEquals(-step, TrackReorder.offset(2, 0, 2, step), 0.0)
        assertEquals(0.0, TrackReorder.offset(3, 0, 2, step), 0.0)
    }

    @Test fun draggingLeftPushesTheColumnsBetweenRight() {
        assertEquals(0.0, TrackReorder.offset(0, 3, 1, step), 0.0)
        assertEquals(step, TrackReorder.offset(1, 3, 1, step), 0.0)
        assertEquals(step, TrackReorder.offset(2, 3, 1, step), 0.0)
    }

    @Test fun theDraggedColumnGetsNoSlide() = assertEquals(0.0, TrackReorder.offset(0, 0, 2, step), 0.0)

    @Test fun aSingleTrackCannotBeReordered() {
        val base = Song.create("Solo")
        val solo = base.copy(tracks = listOf(Track(kind = ChannelKind.PULSE1)),
            patterns = listOf(base.patterns[0].copy(rows = listOf(Pattern.EMPTY_ROW))))
        assertFalse(solo.canReorderTracks)
        assertTrue(solo.copy(tracks = solo.tracks + Track(kind = ChannelKind.NOISE)).canReorderTracks)
    }
}

/** Port of `ArrangementReorderTests.swift`, checked against a port of
 * `Array.move(fromOffsets:toOffset:)` for a single index. */
class ArrangementReorderTest {
    private fun <T> List<T>.moved(from: Int, to: Int): List<T> {
        val out = toMutableList()
        val item = out.removeAt(from)
        out.add(if (to > from) to - 1 else to, item)
        return out
    }

    @Test fun dragDownMovesPastTheTargetRow() {
        val d = ArrangementReorder.destination(draggedIndex = 0, overIndex = 2)
        assertEquals(listOf(1, 2, 0, 3), listOf(0, 1, 2, 3).moved(0, d))
    }

    @Test fun dragUpMovesBeforeTheTargetRow() {
        val d = ArrangementReorder.destination(draggedIndex = 3, overIndex = 1)
        assertEquals(listOf(0, 3, 1, 2), listOf(0, 1, 2, 3).moved(3, d))
    }

    @Test fun dropOnItselfIsANoOp() {
        val d = ArrangementReorder.destination(draggedIndex = 2, overIndex = 2)
        assertEquals(listOf(0, 1, 2, 3), listOf(0, 1, 2, 3).moved(2, d))
    }
}

/** Port of `ArrangementRowLeadingTests.swift`. */
class ArrangementRowLeadingTest {
    @Test fun idleRowShowsItsOneBasedSectionNumber() =
        assertEquals(ArrangementRowLeading.Number("2"), ArrangementRowLeading.content(position = 1, playing = false))

    @Test fun playingRowShowsTheMarkerInTheNumberSlot() =
        assertEquals(ArrangementRowLeading.PlayingMarker, ArrangementRowLeading.content(position = 1, playing = true))
}

/** Port of `RepeatsAccessibilityTests.swift`. */
class RepeatsAccessibilityTest {
    @Test fun labelNamesTheOneBasedSection() {
        assertEquals("Section 1 repeats", RepeatsAccessibility.label(0))
        assertEquals("Section 3 repeats", RepeatsAccessibility.label(2))
    }

    @Test fun labelsDifferAcrossRows() = assertEquals(4, (0 until 4).map { RepeatsAccessibility.label(it) }.toSet().size)

    @Test fun valueIsGrammatical() {
        assertEquals("1 time", RepeatsAccessibility.value(1))
        assertEquals("2 times", RepeatsAccessibility.value(2))
        assertEquals("16 times", RepeatsAccessibility.value(16))
    }
}

/** The pure parts of `PatternRenameFooterTests.swift`. */
class PatternNameCheckTest {
    private val names = listOf("A", "B", "C")

    @Test fun duplicateOfAnotherPatternIsExplained() {
        assertEquals(PatternNameCheck.Duplicate, PatternNameCheck.evaluate("A", names, 1))
        assertEquals("Another pattern already uses this name.", PatternNameCheck.footer("A", names, 1))
    }

    @Test fun duplicateIgnoresSurroundingSpacesButNotCase() {
        assertEquals(PatternNameCheck.Duplicate, PatternNameCheck.evaluate(" A ", names, 1))
        assertEquals(PatternNameCheck.Accepted("a"), PatternNameCheck.evaluate("a", names, 1))
    }

    @Test fun blankKeepsTheCounterAndIsRefused() {
        assertEquals(PatternNameCheck.Blank, PatternNameCheck.evaluate("  ", names, 1))
        assertEquals("Up to 6 characters — 0 of 6 used.", PatternNameCheck.footer("", names, 1))
    }

    @Test fun uniqueAndOwnNameKeepTheCounter() {
        assertEquals(PatternNameCheck.Accepted("Zed"), PatternNameCheck.evaluate("Zed", names, 1))
        assertEquals("Up to 6 characters — 3 of 6 used.", PatternNameCheck.footer("Zed", names, 1))
        assertEquals(PatternNameCheck.Accepted("B"), PatternNameCheck.evaluate("B", names, 1))
        assertEquals("B", PatternNameCheck.evaluate("B", names, 1).acceptedName)
        assertNull(PatternNameCheck.Blank.acceptedName)
    }

    @Test fun longNamesAreCutToSixGraphemes() {
        assertEquals(PatternNameCheck.Accepted("toolon"), PatternNameCheck.evaluate("toolongname", names, 1))
    }
}

/** Chip limits and the step-length formula the core and the exporter share. */
class ChipTest {
    @Test fun clampNoteFoldsAnythingOutsideTheRangeIntoARest() {
        assertEquals(-2, Chip.clampNote(-2L))
        assertEquals(127, Chip.clampNote(127L))
        assertEquals(-1, Chip.clampNote(128L))
        assertEquals(-1, Chip.clampNote(-3L))
        assertEquals(-1, Chip.clampNote(200L))
        assertEquals(-1, Chip.clampNote(Long.MAX_VALUE))
    }

    @Test fun samplesPerStepMatchesSwift() {
        // 44100*60/(132*4) = 5011.36… → 5011
        assertEquals(5011, Chip.samplesPerStep(132.0, 44100.0))
        assertEquals(5513, Chip.samplesPerStep(120.0, 44100.0)) // 5512.5 rounds away from zero
        assertEquals(Chip.samplesPerStep(40.0, 44100.0), Chip.samplesPerStep(1.0, 44100.0))
        assertEquals(Chip.samplesPerStep(300.0, 44100.0), Chip.samplesPerStep(9999.0, 44100.0))
    }

    @Test fun swiftRoundingIsHalfAwayFromZero() {
        assertEquals(1.0, swiftRounded(0.5), 0.0)
        assertEquals(-1.0, swiftRounded(-0.5), 0.0)
        assertEquals(2.0, swiftRounded(1.5), 0.0)
        assertEquals(3.0, swiftRounded(2.5), 0.0)
        assertEquals(-3.0, swiftRounded(-2.5), 0.0)
        assertEquals(0.0, swiftRounded(0.49999999999999994), 0.0)
    }
}

/** The arrangement expansion the audio thread walks. */
class SongChainTest {
    private fun song(repeats: List<Int>, dangling: Int? = null): Song {
        val base = Song.create("Chain")
        val b = Pattern(name = "B", length = 8, trackCount = base.tracks.size)
        val ids = listOf(base.patterns[0].id, b.id)
        val sections = repeats.mapIndexed { i, r ->
            SongSection(patternID = if (i == dangling) java.util.UUID.randomUUID() else ids[i % 2], repeats = r)
        }
        return base.copy(patterns = listOf(base.patterns[0], b), arrangement = sections)
    }

    @Test fun chainExpandsRepeatsInOrder() {
        assertEquals(listOf(0, 0, 1, 0), song(listOf(2, 1, 1)).chain)
    }

    @Test fun chainSkipsDanglingSectionsAndFallsBackToTheFirstPattern() {
        assertEquals(listOf(0, 0), song(listOf(2, 3), dangling = 1).chain)
        assertEquals(listOf(0), song(listOf(3), dangling = 0).chain)
    }

    @Test fun chainIsCappedAndTheCapIsReported() {
        val s = song(List(9) { 16 })
        assertEquals(Chip.MAX_CHAIN, s.chain.size)
        assertEquals(144, s.plannedPlaythroughs)
        assertTrue(s.exceedsChainCapacity)
        assertFalse(song(listOf(16)).exceedsChainCapacity)
    }

    @Test fun sectionIndexAndChainStartAreInverses() {
        val s = song(listOf(2, 3, 1), dangling = 1)
        assertEquals(0, s.sectionIndex(0))
        assertEquals(0, s.sectionIndex(1))
        assertEquals(2, s.sectionIndex(2))
        assertNull(s.sectionIndex(3))
        assertNull(s.sectionIndex(-1))
        assertEquals(0, s.chainStart(0))
        assertNull(s.chainStart(1))
        assertEquals(2, s.chainStart(2))
        assertNull(s.chainStart(3))
    }

    @Test fun arrangementStepsAndDuration() {
        val s = song(listOf(2, 1)).copy(tempo = 120.0)
        assertEquals(16 * 2 + 8, s.arrangementSteps)
        assertEquals(40 * 60.0 / (120.0 * 4), s.arrangementDuration, 1e-12)
    }

    @Test fun nextPatternNameIsTheFirstUnusedLetter() {
        val s = song(listOf(1))
        assertEquals("C", s.nextPatternName())
        assertEquals("A", s.copy(patterns = listOf(s.patterns[1])).nextPatternName())
        assertTrue(s.canAddPattern)
        assertNotNull(s.patternIndex(s.patterns[1].id))
    }

    @Test fun maxAudibleDecayIgnoresMutedHeldAndSilentTracks() {
        var s = Song.create("Decay").withNote(0, 0, 0, 60).withNote(0, 1, 0, 60).withNote(0, 2, 0, 60)
        // Defaults: PU1 0.35, PU2 0.5, TRI 1.5, NOI 0.12 (no notes).
        assertEquals(1.5, s.maxAudibleDecay!!, 0.0)
        s = s.copy(tracks = s.tracks.mapIndexed { i, t ->
            when (i) {
                2 -> t.copy(muted = true)
                1 -> t.copy(instrument = t.instrument.copy(sustain = true))
                else -> t
            }
        })
        assertEquals(0.35, s.maxAudibleDecay!!, 0.0)
        assertNull(Song.create("Empty").maxAudibleDecay)
    }
}
