package dev.individuation.chiptune.ui.layout

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.audio.WavExport
import dev.individuation.chiptune.core.audio.withInstrument
import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Instrument
import dev.individuation.chiptune.core.model.InstrumentPreset
import dev.individuation.chiptune.core.model.Pattern
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.model.SongClock
import dev.individuation.chiptune.core.model.SongSection
import dev.individuation.chiptune.core.model.Track
import java.time.ZoneOffset
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Port of `ExportFooterTests.swift` (both classes). */
class ExportFooterTest {
    private val unarranged =
        "Its notes are in a pattern the arrangement doesn't play. Add that pattern to the arrangement to export it."

    private fun songWithUnarrangedNotes() = TestSongs.empty().let { song ->
        val second = Pattern(name = "B", trackCount = song.tracks.size).withNote(0, 0, 60)
        song.copy(patterns = song.patterns + second)
    }

    @Test fun aSongWithNoNotesAtAllSaysSo() =
        assertEquals("This song has no notes yet.", ExportNotesFooter.text(TestSongs.empty()))

    @Test fun notesOutsideTheArrangementPointAtTheArrangement() =
        assertEquals(unarranged, ExportNotesFooter.text(songWithUnarrangedNotes()))

    @Test fun aSongWithNotesHasNoFooter() = assertNull(ExportNotesFooter.text(TestSongs.golden()))

    @Test fun everyTrackWithNotesMutedWarnsAboutSilence() {
        val song = TestSongs.golden().let { s -> s.copy(tracks = s.tracks.map { it.copy(muted = true) }) }
        assertEquals("Every track with notes is muted, so the export would be silent.", ExportNotesFooter.text(song))
    }

    @Test fun aMutedSongWithNoNotesStillSaysItHasNoNotes() {
        val song = TestSongs.empty().let { s -> s.copy(tracks = s.tracks.map { it.copy(muted = true) }) }
        assertEquals("This song has no notes yet.", ExportNotesFooter.text(song))
    }

    @Test fun aMutedSongWhoseNotesAreUnarrangedStillPointsAtTheArrangement() {
        val song = songWithUnarrangedNotes().let { s -> s.copy(tracks = s.tracks.map { it.copy(muted = true) }) }
        assertEquals(unarranged, ExportNotesFooter.text(song))
    }

    // MARK: MIDI

    private val midi = ExportOptions.Format.MIDI
    private val mutedGolden = TestSongs.golden().let { s -> s.copy(tracks = s.tracks.map { it.copy(muted = true) }) }

    @Test fun wavFormatFooterIsTheExistingOne() {
        assertEquals(ExportNotesFooter.text(mutedGolden), ExportNotesFooter.text(mutedGolden, ExportOptions.Format.WAV))
        assertNull(ExportNotesFooter.text(TestSongs.golden(), ExportOptions.Format.WAV))
    }

    @Test fun midiFooterGivesTheLengthAndTheArpeggioNote() {
        val song = TestSongs.golden()
        assertEquals(
            "The whole arrangement once \u2014 ${Format.clock(song.arrangementDuration)}. Arpeggios come out as the note you wrote.",
            ExportNotesFooter.text(song, midi),
        )
    }

    @Test fun midiFooterSaysAMutedTrackIsInTheFileAtVolumeZero() {
        val song = TestSongs.golden().let { s -> s.copy(tracks = s.tracks.mapIndexed { i, t -> if (i == 0) t.copy(muted = true) else t }) }
        assertEquals(
            "The whole arrangement once \u2014 ${Format.clock(song.arrangementDuration)}. " +
                "Arpeggios come out as the note you wrote. A muted or 0% track is in the file at volume 0.",
            ExportNotesFooter.text(song, midi),
        )
    }

    @Test fun midiFooterSaysMutedTracksAreInTheFileAtVolumeZero() {
        val song = TestSongs.golden().let { s -> s.copy(tracks = s.tracks.mapIndexed { i, t -> if (i == 0 || i == 2) t.copy(muted = true) else t }) }
        assertEquals(
            "The whole arrangement once \u2014 ${Format.clock(song.arrangementDuration)}. " +
                "Arpeggios come out as the note you wrote. Muted or 0% tracks are in the file at volume 0.",
            ExportNotesFooter.text(song, midi),
        )
    }

    /** The MIDI file still has the notes, so the WAV's "would be silent" warning would be wrong for it. */
    @Test fun midiFooterDoesNotWarnAboutSilenceWhenEverythingIsMuted() {
        val text = ExportNotesFooter.text(mutedGolden, midi)!!
        assertFalse(text.contains("silent"))
        assertTrue(text.endsWith("Muted or 0% tracks are in the file at volume 0."))
    }

    /** Every track plays a note at step 0. */
    private fun song(kinds: List<ChannelKind>, muted: Set<Int>) = TestSongs.empty().let { base ->
        base.copy(
            tracks = kinds.mapIndexed { i, kind -> Track(kind = kind, muted = i in muted) },
            patterns = listOf(base.patterns[0].copy(rows = kinds.map { Pattern.EMPTY_ROW.toMutableList().also { it[0] = 60 } })),
        )
    }

    private fun lead(song: Song) =
        "The whole arrangement once \u2014 ${Format.clock(song.arrangementDuration)}. Arpeggios come out as the note you wrote."

    /** Every noise track muted: none plays on the drum channel, so each is
     * silenced with the channel's volume like any other muted track. */
    @Test fun midiFooterCountsMutedDrumsAtVolumeZeroWhenNoDrumPlays() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1, 2))
        assertEquals(lead(song) + " Muted or 0% tracks are in the file at volume 0.", ExportNotesFooter.text(song, midi))
    }

    @Test fun midiFooterSaysAMutedDrumBesideAPlayingOneIsLeftEmpty() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(2))
        assertEquals(
            lead(song) + " A muted or 0% drum track is left empty, since it shares the drum channel with one that plays.",
            ExportNotesFooter.text(song, midi),
        )
    }

    @Test fun midiFooterSaysSoOfEveryEmptiedDrumTrack() {
        val song = song(listOf(ChannelKind.NOISE, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(0, 2))
        assertEquals(
            lead(song) + " Muted or 0% drum tracks are left empty, since they share the drum channel with one that plays.",
            ExportNotesFooter.text(song, midi),
        )
    }

    @Test fun midiFooterGivesBothWhenBothHappen() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1, 3))
        assertEquals(
            lead(song) + " A muted or 0% track is in the file at volume 0." +
                " A muted or 0% drum track is left empty, since it shares the drum channel with one that plays.",
            ExportNotesFooter.text(song, midi),
        )
    }

    /** The unmuted drum track plays nothing, so the muted one is silenced
     * with the channel's volume rather than left empty. */
    @Test fun midiFooterLeavesNoDrumEmptyBesideADrumTrackWithNoNotes() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(2)).let { s ->
            s.copy(patterns = listOf(s.patterns[0].copy(rows = s.patterns[0].rows.mapIndexed { i, row -> if (i == 1) Pattern.EMPTY_ROW else row })))
        }
        assertEquals(lead(song) + " A muted or 0% track is in the file at volume 0.", ExportNotesFooter.text(song, midi))
    }

    private fun Song.withRow(track: Int, row: List<Int>) =
        copy(patterns = patterns.mapIndexed { p, pattern ->
            if (p != 0) pattern else pattern.copy(rows = pattern.rows.mapIndexed { i, r -> if (i == track) row else r })
        })

    /** A muted track with nothing the arrangement plays has no notes in the
     * file to be at volume 0. */
    @Test fun midiFooterSkipsAMutedTrackWithNoNotesInTheArrangement() {
        var song = song(listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE, ChannelKind.PULSE2), muted = setOf(1, 2))
            .withRow(1, Pattern.EMPTY_ROW).withRow(2, Pattern.EMPTY_ROW)
        // Past the pattern's end, and in a pattern the arrangement skips.
        song = song.copy(patterns = listOf(song.patterns[0].withNote(1, song.patterns[0].length, 60)) +
            Pattern(name = "B", trackCount = 3).withNote(2, 0, 60))
        assertEquals(lead(song), ExportNotesFooter.text(song, midi))
    }

    /** Emptying a drum track that had no notes loses nothing worth a line. */
    @Test fun midiFooterSkipsAnEmptiedDrumTrackWithNoNotes() {
        val song = song(listOf(ChannelKind.NOISE, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1, 2))
            .withRow(2, Pattern.EMPTY_ROW)
        assertEquals(
            lead(song) + " A muted or 0% drum track is left empty, since it shares the drum channel with one that plays.",
            ExportNotesFooter.text(song, midi),
        )
    }

    // 0% volume: written like a muted track, so counted with them.

    @Test fun midiFooterCountsATrackAtZeroVolumeAsInTheFileAtVolumeZero() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE), muted = emptySet())
            .withInstrument(1) { it.copy(volume = 0.0) }
        assertEquals(lead(song) + " A muted or 0% track is in the file at volume 0.", ExportNotesFooter.text(song, midi))
    }

    @Test fun midiFooterCountsMutedAndZeroVolumeTracksTogether() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE, ChannelKind.PULSE2), muted = setOf(2))
            .withInstrument(1) { it.copy(volume = 0.0) }
        assertEquals(lead(song) + " Muted or 0% tracks are in the file at volume 0.", ExportNotesFooter.text(song, midi))
    }

    @Test fun midiFooterSaysAZeroVolumeDrumBesideAPlayingOneIsLeftEmpty() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.NOISE), muted = emptySet())
            .withInstrument(2) { it.copy(volume = 0.0) }
        assertEquals(
            lead(song) + " A muted or 0% drum track is left empty, since it shares the drum channel with one that plays.",
            ExportNotesFooter.text(song, midi),
        )
    }

    /** A drum track at 0% doesn't play, so the muted one beside it is at
     * volume 0 rather than left empty, and so is the 0% one. */
    @Test fun midiFooterLeavesNoDrumEmptyBesideAZeroVolumeDrum() {
        val song = song(listOf(ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1))
            .withInstrument(0) { it.copy(volume = 0.0) }
        assertEquals(lead(song) + " Muted or 0% tracks are in the file at volume 0.", ExportNotesFooter.text(song, midi))
    }

    @Test fun midiFooterKeepsTheNoNotesMessages() {
        assertEquals("This song has no notes yet.", ExportNotesFooter.text(TestSongs.empty(), midi))
        assertEquals(unarranged, ExportNotesFooter.text(songWithUnarrangedNotes(), midi))
    }

    @Test fun settingsAreLockedWhileARenderIsRunning() = assertTrue(ExportControls.settingsLocked(isExporting = true))

    @Test fun settingsAreEditableWhenNoRenderIsRunning() = assertFalse(ExportControls.settingsLocked(isExporting = false))

    // The Export button after a render.

    @Test fun theButtonComesBackWhenItsRenderLeftNoFile() =
        assertTrue(ExportControls.freesExportButton(startedAttempt = 1, completedAttempt = 1, producedFile = false))

    /** The panel is coming down for the result dialog, which offers that
     * file; a second render started meanwhile would clear it first. */
    @Test fun theButtonStaysLockedWhileASuccessTakesThePanelDown() =
        assertFalse(ExportControls.freesExportButton(startedAttempt = 1, completedAttempt = 1, producedFile = true))

    @Test fun theButtonStaysLockedWhileItsRenderRuns() =
        assertFalse(ExportControls.freesExportButton(startedAttempt = 2, completedAttempt = 1, producedFile = false))

    @Test fun aLaterCompletionAlsoFinishesTheStartedAttempt() =
        assertTrue(ExportControls.freesExportButton(startedAttempt = 1, completedAttempt = 2, producedFile = false))

    @Test fun nothingStartedHasNothingToFree() =
        assertFalse(ExportControls.freesExportButton(startedAttempt = null, completedAttempt = 1, producedFile = false))
}

/** The export sheet's readouts, word for word from `ExportSheet.swift`. */
class ExportCopyTest {
    @Test fun repeatsReadoutUsesTheTimesSign() = assertEquals("3\u00d7", ExportCopy.loopCount(3))

    /** Each format segment carries the picker's name, as iOS's segments sit
     * in a tab group labelled "Format", so the label costs no stop of its own. */
    @Test fun eachFormatSegmentIsLabelledWithThePicker() {
        assertEquals("Format, WAV", ExportCopy.formatSegment(ExportOptions.Format.WAV))
        assertEquals("Format, MIDI", ExportCopy.formatSegment(ExportOptions.Format.MIDI))
    }

    @Test fun repeatsFooterNamesTheCountAndOnePassLength() {
        // Golden: 16 steps at 132 BPM, 4 steps a beat = 1.818 s a pass.
        val song = TestSongs.golden()
        assertEquals(
            "The whole arrangement, 1 time \u2014 0:01.8.",
            ExportCopy.repeatsFooter(song, ExportOptions(loopCount = 1)),
        )
        assertEquals(
            "The whole arrangement, 4 times \u2014 0:07.3.",
            ExportCopy.repeatsFooter(song, ExportOptions(loopCount = 4)),
        )
    }

    @Test fun ringOutAddsTheTailToTheDuration() {
        val song = TestSongs.empty(length = 64) // 64 steps at 120 = 8 s a pass
        val ring = ExportOptions(loopCount = 2, tailMode = ExportOptions.TailMode.RING_OUT)
        val expected = Format.clock(16.0 + WavExport.tailSeconds(song))
        assertEquals(expected, ExportCopy.duration(song, ring))
        assertEquals("0:16", ExportCopy.duration(song, ring.copy(tailMode = ExportOptions.TailMode.SEAMLESS_LOOP)))
    }

    @Test fun endingLabelsAndFooters() {
        assertEquals("Seamless loop", ExportCopy.endingLabel(ExportOptions.TailMode.SEAMLESS_LOOP))
        assertEquals("Ring out", ExportCopy.endingLabel(ExportOptions.TailMode.RING_OUT))
        assertEquals(
            "The last notes ring on into the start, so the file loops with no gap. Best for dropping into something else.",
            ExportCopy.endingFooter(ExportOptions.TailMode.SEAMLESS_LOOP),
        )
        assertEquals(
            "The last notes fade out past the end and the file finishes in silence. Best when the file is the finished thing.",
            ExportCopy.endingFooter(ExportOptions.TailMode.RING_OUT),
        )
    }

    @Test fun aWavExportSaysHowFarAlongItIs() {
        assertEquals("Exporting\u2026 42%", ExportCopy.exporting(ExportOptions.Format.WAV, 0.42))
    }

    @Test fun exportingTruncatesThePercentLikeSwiftsInt() {
        assertEquals("Exporting\u2026 0%", ExportCopy.exporting(ExportOptions.Format.WAV, 0.0))
        assertEquals("Exporting\u2026 99%", ExportCopy.exporting(ExportOptions.Format.WAV, 0.999))
        assertEquals("Exporting\u2026 100%", ExportCopy.exporting(ExportOptions.Format.WAV, 1.0))
    }

    /** A MIDI export never reports progress, so a percentage would sit at 0%. */
    @Test fun aMidiExportGivesNoPercentage() {
        assertEquals("Exporting\u2026", ExportCopy.exporting(ExportOptions.Format.MIDI, 0.0))
    }

    @Test fun exportIsOfferedOnlyWithNotesAndNoAttemptInFlight() {
        assertTrue(ExportCopy.canExport(hasNotes = true, attemptInFlight = false))
        assertFalse(ExportCopy.canExport(hasNotes = false, attemptInFlight = false))
        assertFalse(ExportCopy.canExport(hasNotes = true, attemptInFlight = true))
    }

    @Test fun formatChoiceAndButtonNameTheFormat() {
        assertEquals("WAV", ExportOptions.Format.WAV.label)
        assertEquals("MIDI", ExportOptions.Format.MIDI.label)
        assertEquals("Export WAV", ExportCopy.exportButton(ExportOptions.Format.WAV))
        assertEquals("Export MIDI", ExportCopy.exportButton(ExportOptions.Format.MIDI))
    }

    /** A MIDI file is the arrangement once, so neither control applies to it. */
    @Test fun onlyAWavHasRepeatsAndEnding() {
        assertTrue(ExportCopy.hasRepeatsAndEnding(ExportOptions.Format.WAV))
        assertFalse(ExportCopy.hasRepeatsAndEnding(ExportOptions.Format.MIDI))
    }

    @Test fun resultTitleNamesTheFile() = assertEquals("Exported Golden.wav", ExportCopy.resultTitle("Golden.wav"))
}

/** `ArrangementEditToggleTests.swift`, plus the sheet's copy. */
class ArrangementCopyTest {
    @Test fun toggleFlipsAndTheLabelFollowsTheMode() {
        assertTrue(ArrangementEditToggle.toggled(false))
        assertFalse(ArrangementEditToggle.toggled(true))
        assertEquals("Edit", ArrangementEditToggle.title(false))
        assertEquals("Done editing", ArrangementEditToggle.title(true))
    }

    @Test fun summaryCountsDistinctPatternsStepsAndClock() {
        // Two patterns, 16 + 8 steps, A twice: 40 steps at 120 = 5 s.
        val song = TestSongs.twoPatterns(lengths = 16 to 8, repeats = 2 to 1)
        assertEquals("2 patterns \u00b7 40 steps \u00b7 0:05.0 at 120 BPM", ArrangementCopy.summary(song))
        assertEquals("1 pattern \u00b7 16 steps \u00b7 0:02.0 at 120 BPM", ArrangementCopy.summary(TestSongs.empty()))
    }

    @Test fun capacityWarningNamesTheLimit() =
        assertEquals("More than 128 plays \u2014 sections past that won't sound.", ArrangementCopy.CAPACITY_WARNING)

    @Test fun helpIsWordForWord() = assertEquals(
        "Each section plays one pattern. Repeat it to hold a section for longer, and drag to reorder. " +
            "Switch the transport to SONG to hear the whole thing; PATT keeps looping just the pattern you're editing.",
        ArrangementCopy.HELP,
    )

    @Test fun sectionLabelNamesPositionAndPattern() {
        assertEquals("Section 1, pattern A", ArrangementCopy.sectionLabel(0, "A"))
        assertEquals("Section 3, pattern none", ArrangementCopy.sectionLabel(2, null))
    }

    @Test fun theLastSectionCannotBeDeleted() {
        assertFalse(ArrangementCopy.canDelete(1))
        assertTrue(ArrangementCopy.canDelete(2))
    }

    @Test fun capacityIsCrossedAtNineSectionsOfSixteen() {
        val song = TestSongs.empty()
        val id = song.patterns[0].id
        val eight = song.copy(arrangement = List(8) { SongSection(patternID = id, repeats = 16) })
        assertFalse(eight.exceedsChainCapacity)
        val nine = eight.copy(arrangement = eight.arrangement + SongSection(patternID = id, repeats = 1))
        assertTrue(nine.exceedsChainCapacity)
    }
}

/** The library row and its dialogs (`SongListView.swift`). */
class SongListCopyTest {
    @Test fun rowDetailIsTempoPatternsAndAnAbbreviatedDate() {
        // 2001-01-01T00:00:00Z is `modified` 0; the 9th of October 2026 at noon UTC:
        val modified = SongClock.fromUnixMillis(1_791_547_200_000L)
        val song = TestSongs.twoPatterns().copy(tempo = 132.0, modified = modified)
        assertEquals("132 BPM \u00b7 2 patterns \u00b7 Oct 9, 2026", SongListCopy.detail(song, Locale.US, ZoneOffset.UTC))
        assertEquals(
            "120 BPM \u00b7 1 pattern \u00b7 Jan 1, 2001",
            SongListCopy.detail(TestSongs.empty().copy(modified = 0.0), Locale.US, ZoneOffset.UTC),
        )
    }

    @Test fun theDateFollowsTheReadersZone() {
        val song = TestSongs.empty().copy(modified = 0.0)
        assertTrue(SongListCopy.detail(song, Locale.US, ZoneOffset.ofHours(-5)).endsWith("Dec 31, 2000"))
    }

    @Test fun deleteTitleQuotesTheName() {
        assertEquals("Delete \u201cDemo\u201d?", SongListCopy.deleteTitle("Demo"))
        assertEquals("This can't be undone.", SongListCopy.DELETE_MESSAGE)
    }

    @Test fun renameIsOfferedForANewNonBlankUnusedName() {
        val a = TestSongs.empty(name = "Alpha")
        val b = TestSongs.empty(name = "Beta")
        val songs = listOf(a, b)
        assertTrue(SongListCopy.canRename("Gamma", songs, a.id))
        assertFalse(SongListCopy.canRename("   ", songs, a.id))
        assertFalse(SongListCopy.canRename("", songs, a.id))
        assertFalse(SongListCopy.canRename("Beta", songs, a.id))
        assertFalse(SongListCopy.canRename("  Beta ", songs, a.id))
        // Its own name is fine (the model treats it as a no-op).
        assertTrue(SongListCopy.canRename("Alpha", songs, a.id))
        // Case-sensitive, as the model is.
        assertTrue(SongListCopy.canRename("beta", songs, a.id))
    }
}

/** `InstrumentEditor.swift`'s readouts and adjustables. */
class InstrumentEditorCopyTest {
    @Test fun arpeggioShapesSpeakTheirFullNames() {
        assertEquals(listOf("Off", "Maj", "Min", "Oct", "5th"), InstrumentEditorCopy.ARPS.map { it.label })
        assertEquals(listOf("Off", "Major", "Minor", "Octave", "Fifth"), InstrumentEditorCopy.ARPS.map { it.spoken })
        assertEquals("Major", InstrumentEditorCopy.arpeggioValue(listOf(0, 4, 7)))
        assertEquals("Off", InstrumentEditorCopy.arpeggioValue(emptyList()))
        assertEquals("Custom", InstrumentEditorCopy.arpeggioValue(listOf(0, 5)))
        assertEquals(1, InstrumentEditorCopy.arpeggioIndex(listOf(0, 4, 7)))
        assertEquals(0, InstrumentEditorCopy.arpeggioIndex(listOf(0, 5)))
    }

    @Test fun presetNameIsCustomOnceEdited() {
        val lead = InstrumentPreset.presetsFor(ChannelKind.PULSE1)[0]
        assertEquals("Lead", InstrumentEditorCopy.presetName(lead.instrument, ChannelKind.PULSE1))
        assertEquals("Custom", InstrumentEditorCopy.presetName(lead.instrument.copy(volume = 0.1), ChannelKind.PULSE1))
        assertEquals("Custom", InstrumentEditorCopy.presetName(null, ChannelKind.PULSE1))
    }

    @Test fun nameFooterCountsGraphemes() {
        assertEquals("Up to 16 characters \u2014 0 of 16 used.", InstrumentEditorCopy.nameFooter(""))
        assertEquals("Up to 16 characters \u2014 4 of 16 used.", InstrumentEditorCopy.nameFooter("Bass"))
        assertEquals("Up to 16 characters \u2014 1 of 16 used.", InstrumentEditorCopy.nameFooter("\uD83D\uDC4D\uD83C\uDFFD"))
    }

    @Test fun decayReadsInSecondsWithTwoPlaces() {
        assertEquals("0.35s", InstrumentEditorCopy.decay(0.35))
        assertEquals("4.00s", InstrumentEditorCopy.decay(4.0))
        assertEquals("0.03s", InstrumentEditorCopy.decay(0.03))
    }

    @Test fun levelFooterFollowsHold() {
        assertEquals("The note sounds until the next one on this track, or a rest.", InstrumentEditorCopy.levelFooter(true))
        assertEquals("The note fades out over the decay time.", InstrumentEditorCopy.levelFooter(false))
    }

    @Test fun pulseWidthValueIsTheLabel() {
        assertEquals("50%", InstrumentEditorCopy.pulseWidthValue(2))
        assertEquals("Unknown", InstrumentEditorCopy.pulseWidthValue(9))
    }

    @Test fun adjustedIndexHoldsAtTheEnds() {
        assertEquals(1, InstrumentEditorCopy.adjustedIndex(0, 4, AdjustmentDirection.INCREMENT))
        assertEquals(3, InstrumentEditorCopy.adjustedIndex(3, 4, AdjustmentDirection.INCREMENT))
        assertEquals(0, InstrumentEditorCopy.adjustedIndex(0, 4, AdjustmentDirection.DECREMENT))
        assertEquals(2, InstrumentEditorCopy.adjustedIndex(3, 4, AdjustmentDirection.DECREMENT))
    }

    @Test fun slidersStepATenthOfTheirRangeAndClamp() {
        assertEquals(0.6, InstrumentEditorCopy.sliderStep(0.5, 0.0..1.0, AdjustmentDirection.INCREMENT), 1e-9)
        assertEquals(1.0, InstrumentEditorCopy.sliderStep(0.95, 0.0..1.0, AdjustmentDirection.INCREMENT), 1e-9)
        assertEquals(0.03, InstrumentEditorCopy.sliderStep(0.2, 0.03..4.0, AdjustmentDirection.DECREMENT), 1e-9)
        assertEquals(0.427, InstrumentEditorCopy.sliderStep(0.03, 0.03..4.0, AdjustmentDirection.INCREMENT), 1e-9)
    }

    @Test fun actionCopy() {
        assertEquals("Clear this track in pattern B", InstrumentEditorCopy.clearTrackButton("B"))
        assertEquals("Clear this track in pattern B?", InstrumentEditorCopy.clearTrackTitle("B"))
        assertEquals("A song can hold up to 8 tracks.", InstrumentEditorCopy.TRACK_LIMIT_FOOTER)
        assertEquals("Sound settings for Pulse 1", InstrumentEditorCopy.dockedHeading("Pulse 1"))
    }

    @Test fun captionsAreWordForWord() {
        assertEquals("A starting point. Every control below stays yours to move.", InstrumentEditorCopy.PRESET_CAPTION)
        assertEquals(
            "Switching waveform keeps this track's notes and loads the new channel's default sound.",
            InstrumentEditorCopy.CHANNEL_CAPTION,
        )
        assertEquals(
            "Cycles through the chord tones fast enough to sound like one voice \u2014 the classic way to fake a chord on a single channel.",
            InstrumentEditorCopy.ARPEGGIO_CAPTION,
        )
    }

    @Test fun defaultInstrumentsMatchTheirKindsFirstPreset() =
        assertEquals("Bass", InstrumentEditorCopy.presetName(Instrument.defaultFor(ChannelKind.TRIANGLE), ChannelKind.TRIANGLE))
}
