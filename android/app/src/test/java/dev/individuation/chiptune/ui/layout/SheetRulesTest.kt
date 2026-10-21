package dev.individuation.chiptune.ui.layout

import dev.individuation.chiptune.core.TestSongs
import dev.individuation.chiptune.core.audio.ExportOptions
import dev.individuation.chiptune.core.video.VideoExport
import dev.individuation.chiptune.core.video.VideoTimeline
import dev.individuation.chiptune.core.model.Chip
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
                "Arpeggios come out as the note you wrote. A muted or silent track keeps its notes in the file, turned all the way down.",
            ExportNotesFooter.text(song, midi),
        )
    }

    @Test fun midiFooterSaysMutedTracksAreInTheFileAtVolumeZero() {
        val song = TestSongs.golden().let { s -> s.copy(tracks = s.tracks.mapIndexed { i, t -> if (i == 0 || i == 2) t.copy(muted = true) else t }) }
        assertEquals(
            "The whole arrangement once \u2014 ${Format.clock(song.arrangementDuration)}. " +
                "Arpeggios come out as the note you wrote. Muted or silent tracks keep their notes in the file, turned all the way down.",
            ExportNotesFooter.text(song, midi),
        )
    }

    /** The MIDI file still has the notes, so the WAV's "would be silent" warning would be wrong for it. */
    @Test fun midiFooterDoesNotWarnAboutSilenceWhenEverythingIsMuted() {
        val text = ExportNotesFooter.text(mutedGolden, midi)!!
        assertFalse(text.contains("would be silent"))
        assertTrue(text.endsWith("Muted or silent tracks keep their notes in the file, turned all the way down."))
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
        assertEquals(lead(song) + " Muted or silent tracks keep their notes in the file, turned all the way down.", ExportNotesFooter.text(song, midi))
    }

    @Test fun midiFooterSaysAMutedDrumBesideAPlayingOneIsLeftEmpty() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(2))
        assertEquals(
            lead(song) + " A muted or silent drum track is left empty, because all drum tracks share one part in the file.",
            ExportNotesFooter.text(song, midi),
        )
    }

    @Test fun midiFooterSaysSoOfEveryEmptiedDrumTrack() {
        val song = song(listOf(ChannelKind.NOISE, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(0, 2))
        assertEquals(
            lead(song) + " Muted or silent drum tracks are left empty, because all drum tracks share one part in the file.",
            ExportNotesFooter.text(song, midi),
        )
    }

    @Test fun midiFooterGivesBothWhenBothHappen() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1, 3))
        assertEquals(
            lead(song) + " A muted or silent track keeps its notes in the file, turned all the way down." +
                " A muted or silent drum track is left empty, because all drum tracks share one part in the file.",
            ExportNotesFooter.text(song, midi),
        )
    }

    /** The unmuted drum track plays nothing, so the muted one is silenced
     * with the channel's volume rather than left empty. */
    @Test fun midiFooterLeavesNoDrumEmptyBesideADrumTrackWithNoNotes() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(2)).let { s ->
            s.copy(patterns = listOf(s.patterns[0].copy(rows = s.patterns[0].rows.mapIndexed { i, row -> if (i == 1) Pattern.EMPTY_ROW else row })))
        }
        assertEquals(lead(song) + " A muted or silent track keeps its notes in the file, turned all the way down.", ExportNotesFooter.text(song, midi))
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
            lead(song) + " A muted or silent drum track is left empty, because all drum tracks share one part in the file.",
            ExportNotesFooter.text(song, midi),
        )
    }

    // 0% volume: written like a muted track, so counted with them.

    @Test fun midiFooterCountsATrackAtZeroVolumeAsInTheFileAtVolumeZero() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE), muted = emptySet())
            .withInstrument(1) { it.copy(volume = 0.0) }
        assertEquals(lead(song) + " A muted or silent track keeps its notes in the file, turned all the way down.", ExportNotesFooter.text(song, midi))
    }

    @Test fun midiFooterCountsMutedAndZeroVolumeTracksTogether() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.TRIANGLE, ChannelKind.PULSE2), muted = setOf(2))
            .withInstrument(1) { it.copy(volume = 0.0) }
        assertEquals(lead(song) + " Muted or silent tracks keep their notes in the file, turned all the way down.", ExportNotesFooter.text(song, midi))
    }

    @Test fun midiFooterSaysAZeroVolumeDrumBesideAPlayingOneIsLeftEmpty() {
        val song = song(listOf(ChannelKind.PULSE1, ChannelKind.NOISE, ChannelKind.NOISE), muted = emptySet())
            .withInstrument(2) { it.copy(volume = 0.0) }
        assertEquals(
            lead(song) + " A muted or silent drum track is left empty, because all drum tracks share one part in the file.",
            ExportNotesFooter.text(song, midi),
        )
    }

    /** A drum track at 0% doesn't play, so the muted one beside it is at
     * volume 0 rather than left empty, and so is the 0% one. */
    @Test fun midiFooterLeavesNoDrumEmptyBesideAZeroVolumeDrum() {
        val song = song(listOf(ChannelKind.NOISE, ChannelKind.NOISE), muted = setOf(1))
            .withInstrument(0) { it.copy(volume = 0.0) }
        assertEquals(lead(song) + " Muted or silent tracks keep their notes in the file, turned all the way down.", ExportNotesFooter.text(song, midi))
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

/** What sits under the WAV/MIDI picker. Port of `ExportFormatFooterTests`. */
class ExportFormatFooterTest {
    /** A beginner doesn't know a MIDI file has no sounds in it. */
    @Test fun midiSaysTheFileHoldsNotesNotSounds() {
        assertEquals(
            "A MIDI file holds your notes, not the chip sounds. The app you open it in plays them with its own instruments.",
            ExportFormatFooter.text(ExportOptions.Format.MIDI),
        )
    }

    /** A WAV is the sound itself; its repeats and ending say the rest. */
    @Test fun wavHasNoFormatFooter() {
        assertNull(ExportFormatFooter.text(ExportOptions.Format.WAV))
    }
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
            "The whole arrangement, 1 time: 0:01.8.",
            ExportCopy.repeatsFooter(song, ExportOptions(loopCount = 1)),
        )
        assertEquals(
            "The whole arrangement, 4 times: 0:07.3.",
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

    /** A WAV and a video both play the arrangement more than once; a MIDI
     * file is the arrangement once. */
    @Test fun repeatsShowForWavAndVideoOnly() {
        assertTrue(ExportCopy.hasRepeats(ExportOptions.Format.WAV))
        assertTrue(ExportCopy.hasRepeats(ExportOptions.Format.VIDEO))
        assertFalse(ExportCopy.hasRepeats(ExportOptions.Format.MIDI))
    }

    /** A video always rings out, so only a WAV has an ending to choose. */
    @Test fun onlyAWavHasAnEnding() {
        assertTrue(ExportCopy.hasEnding(ExportOptions.Format.WAV))
        assertFalse(ExportCopy.hasEnding(ExportOptions.Format.VIDEO))
        assertFalse(ExportCopy.hasEnding(ExportOptions.Format.MIDI))
    }

    @Test fun onlyAVideoHasAStyle() {
        assertTrue(ExportCopy.hasStyle(ExportOptions.Format.VIDEO))
        assertFalse(ExportCopy.hasStyle(ExportOptions.Format.WAV))
        assertFalse(ExportCopy.hasStyle(ExportOptions.Format.MIDI))
    }

    @Test fun styleSegmentsAreLabelledGridAndCartridge() {
        assertEquals("Grid", ExportOptions.VideoStyle.GRID.label)
        assertEquals("Cartridge", ExportOptions.VideoStyle.COVER.label)
        // Just the name: the "Style" heading above the group says the rest once.
        assertEquals("Grid", ExportCopy.styleSegment(ExportOptions.VideoStyle.GRID))
        assertEquals("Cartridge", ExportCopy.styleSegment(ExportOptions.VideoStyle.COVER))
    }

    @Test fun anOverlongVideoBlocksTheExportButton() {
        val over = VideoExport.MAX_SECONDS + 1
        assertTrue(ExportCopy.blocksExport(ExportOptions.Format.VIDEO, over))
        assertFalse(ExportCopy.blocksExport(ExportOptions.Format.VIDEO, VideoExport.MAX_SECONDS))
        assertFalse(ExportCopy.blocksExport(ExportOptions.Format.WAV, over))
        assertFalse(ExportCopy.blocksExport(ExportOptions.Format.MIDI, over))
    }

    @Test fun videoSaysWhereItIsFor() {
        assertEquals("A tall video for Instagram, TikTok and YouTube.", ExportFormatFooter.text(ExportOptions.Format.VIDEO))
    }

    @Test fun eachStyleSaysWhatItLooksLike() {
        assertEquals(
            "The pattern grid scrolls along as the song plays, the way it looks in the editor.",
            ExportCopy.styleFooter(ExportOptions.VideoStyle.GRID),
        )
        assertEquals(
            "A game cartridge with the song's title and a bar for each track that jumps with its notes.",
            ExportCopy.styleFooter(ExportOptions.VideoStyle.COVER),
        )
    }

    @Test fun aVideoExportSaysHowFarAlongItIs() {
        assertEquals("Exporting\u2026 50%", ExportCopy.exporting(ExportOptions.Format.VIDEO, 0.5))
    }

    /** A video rings out whatever the stored ending says, so its length
     * includes the tail. */
    @Test fun aVideosLengthIncludesTheTail() {
        val song = TestSongs.empty(length = 64)
        val options = ExportOptions(
            loopCount = 2, tailMode = ExportOptions.TailMode.SEAMLESS_LOOP, format = ExportOptions.Format.VIDEO,
        )
        assertEquals(16.0 + WavExport.tailSeconds(song), ExportLength.seconds(song, options), 0.01)
        assertEquals(Format.clock(16.0 + WavExport.tailSeconds(song)), ExportCopy.duration(song, options))
        // Exactly the renderer's length, which counts whole samples a step.
        assertEquals(VideoTimeline(song, options).seconds, ExportLength.seconds(song, options), 0.0)
    }

    @Test fun aSeamlessWavHasNoTail() {
        val song = TestSongs.empty(length = 64)
        val options = ExportOptions(tailMode = ExportOptions.TailMode.SEAMLESS_LOOP)
        assertEquals(8.0, ExportLength.seconds(song, options), 0.0001)
    }

    @Test fun aVideoOverThreeMinutesWarnsItIsNotAShort() {
        assertEquals("Over 3:00, YouTube posts it as a regular video, not a Short.", ExportLength.warning(ExportOptions.Format.VIDEO, 181.0))
        assertNull(ExportLength.warning(ExportOptions.Format.VIDEO, 180.0))
    }

    @Test fun aWavOrMidiNeverWarnsAboutLength() {
        assertNull(ExportLength.warning(ExportOptions.Format.WAV, 400.0))
        assertNull(ExportLength.warning(ExportOptions.Format.MIDI, 400.0))
    }

    @Test fun aVideoOverTheCapSaysItIsTooLong() {
        assertEquals("Too long for a video. The limit is 10:00.", ExportLength.warning(ExportOptions.Format.VIDEO, 601.0))
        assertEquals("Over 3:00, YouTube posts it as a regular video, not a Short.", ExportLength.warning(ExportOptions.Format.VIDEO, 600.0))
    }

    @Test fun theRepeatsFooterCarriesTheLengthWarning() {
        val song = TestSongs.empty(tempo = 60.0, length = 64) // 16 s a pass
        // 192 s + tail. Repeats stop at 16, as the stepper and the renderer do.
        val video = ExportOptions(loopCount = 12, format = ExportOptions.Format.VIDEO)
        val line = ExportCopy.repeatsFooter(song, video)
        assertTrue(line, line.endsWith(". Then it rings out. Over 3:00, YouTube posts it as a regular video, not a Short."))
        assertEquals(
            "The whole arrangement, 2 times: ${ExportCopy.duration(song, ExportOptions(loopCount = 2))}.",
            ExportCopy.repeatsFooter(song, ExportOptions(loopCount = 2)),
        )
    }

    /** A video says it rings out after the passes; a WAV's ending has its
     * own section, so its readout stops at the length. */
    @Test fun aVideosRepeatsFooterSaysItRingsOut() {
        val song = TestSongs.golden()
        val video = ExportOptions(loopCount = 6, format = ExportOptions.Format.VIDEO)
        assertEquals(
            "The whole arrangement, 6 times: ${ExportCopy.duration(song, video)}. Then it rings out.",
            ExportCopy.repeatsFooter(song, video),
        )
    }

    /** Golden is 1.8 s a pass: a one-pass video of it is over before anyone
     * looks, so switching to Video starts at 6 passes, the fewest that make
     * 10 s before the tail. */
    @Test fun switchingToVideoRaisesOnePassToTenSeconds() {
        val song = TestSongs.golden()
        val switched = ExportCopy.withFormat(song, ExportOptions(), ExportOptions.Format.VIDEO)
        assertEquals(ExportOptions.Format.VIDEO, switched.format)
        assertEquals(6, switched.loopCount)
        assertTrue(song.arrangementDuration * 6 >= 10.0)
        assertTrue(song.arrangementDuration * 5 < 10.0)
    }

    @Test fun aLongEnoughSongStaysAtOnePass() {
        val song = TestSongs.empty(length = 64) // 8 s a pass
        assertEquals(2, ExportCopy.withFormat(song, ExportOptions(), ExportOptions.Format.VIDEO).loopCount)
        val long = TestSongs.empty(tempo = 60.0, length = 64) // 16 s a pass
        assertEquals(1, ExportCopy.withFormat(long, ExportOptions(), ExportOptions.Format.VIDEO).loopCount)
    }

    @Test fun aVeryShortSongStopsAtTheRepeatsLimit() {
        val song = TestSongs.empty(tempo = 300.0, length = 1)
        assertEquals(
            ExportOptions.MAX_LOOP_COUNT,
            ExportCopy.withFormat(song, ExportOptions(), ExportOptions.Format.VIDEO).loopCount,
        )
    }

    @Test fun aCountTheUserChangedIsKept() {
        val song = TestSongs.golden()
        val chosen = ExportOptions().withLoopCount(3)
        assertEquals(3, ExportCopy.withFormat(song, chosen, ExportOptions.Format.VIDEO).loopCount)
    }

    /** Stepping back to 1 is a choice too (iOS `loopCountChosen`): a user who
     * wants a one-pass video keeps it. */
    @Test fun aCountSteppedBackToOneIsKept() {
        val song = TestSongs.golden()
        val back = ExportOptions().withLoopCount(2).withLoopCount(1)
        assertTrue(back.loopCountChosen)
        assertEquals(1, ExportCopy.withFormat(song, back, ExportOptions.Format.VIDEO).loopCount)
    }

    @Test fun theStepperMarksTheCountChosenAndAFreshExportDoesNot() {
        assertFalse(ExportOptions().loopCountChosen)
        assertTrue(ExportOptions().withLoopCount(4).loopCountChosen)
        assertEquals(4, ExportOptions().withLoopCount(4).loopCount)
    }

    @Test fun otherFormatsLeaveTheCountAlone() {
        val song = TestSongs.golden()
        assertEquals(1, ExportCopy.withFormat(song, ExportOptions(), ExportOptions.Format.WAV).loopCount)
        assertEquals(1, ExportCopy.withFormat(song, ExportOptions(), ExportOptions.Format.MIDI).loopCount)
        val fromVideo = ExportOptions(loopCount = 6, format = ExportOptions.Format.VIDEO)
        assertEquals(ExportOptions.Format.WAV, ExportCopy.withFormat(song, fromVideo, ExportOptions.Format.WAV).format)
    }

    /** The song's name in quotes, not a raw file name with its extension. */
    @Test fun resultTitleNamesTheSong() {
        assertEquals("Exported \u201CGolden\u201D", ExportCopy.resultTitle("Golden.wav"))
        assertEquals("Exported \u201CMy.Song\u201D", ExportCopy.resultTitle("My.Song.mp4"))
    }
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

/** The sheet's Export button and the renderer agree on which videos are over
 * the cap. Port of iOS's `ExportCapAgreementTests`: the sheet once worked the
 * length out from the exact step length while the renderer counts whole
 * samples per step, so a song a hair under ten minutes on the sheet could be
 * refused after the tap. */
class ExportCapAgreementTest {

    /** [steps] steps in one pass at [tempo]: whole 64-step patterns, then one
     * shorter pattern for the rest. One track, no notes, so the tail is 1 s. */
    private fun song(tempo: Double, steps: Int): Song {
        val base = TestSongs.empty(name = "Cap", tempo = tempo, length = 64)
        val sections = ArrayList<SongSection>()
        var left = steps / 64
        while (left > 0) {
            val repeats = minOf(left, SongSection.MAX_REPEATS)
            sections.add(SongSection(patternID = base.patterns[0].id, repeats = repeats))
            left -= repeats
        }
        val patterns = base.patterns.toMutableList()
        val rest = steps % 64
        if (rest > 0) {
            val tail = Pattern(name = "B", length = rest, trackCount = base.tracks.size)
            patterns.add(tail)
            sections.add(SongSection(patternID = tail.id))
        }
        return base.copy(patterns = patterns, arrangement = sections)
    }

    private val video = ExportOptions(format = ExportOptions.Format.VIDEO)

    private fun sheetBlocks(song: Song): Boolean =
        ExportCopy.blocksExport(ExportOptions.Format.VIDEO, ExportLength.seconds(song, video))

    private fun rendererRefuses(song: Song): Boolean = VideoTimeline(song, video).seconds > VideoExport.MAX_SECONDS

    /** The case iOS's review found: 599.985 s by the exact step length,
     * 600.023 s by whole samples. */
    @Test fun a133BpmSongJustOverTheCapIsBlockedOnTheSheet() {
        val song = song(tempo = 133.0, steps = 5311)
        assertEquals(5311, song.arrangementSteps)
        assertTrue("the renderer refuses this one", rendererRefuses(song))
        assertTrue("so the sheet must not offer Export", sheetBlocks(song))
    }

    @Test fun theSheetAndTheRendererAgreeNearTheCap() {
        val disagreements = ArrayList<String>()
        var tempo = 60.0
        while (tempo <= 200.0) {
            // Steps that put one pass plus the 1 s tail near 600 s.
            val center = Math.round(599 * tempo * Chip.STEPS_PER_BEAT / 60).toInt()
            for (steps in center - 3..center + 3) {
                val song = song(tempo, steps)
                if (sheetBlocks(song) != rendererRefuses(song)) disagreements.add("$tempo BPM, $steps steps")
            }
            tempo += 1.0
        }
        assertEquals(emptyList<String>(), disagreements)
    }
}

/** What TalkBack hears while a render runs: the start, each quarter, and a cancel. */
class ExportAnnouncementTest {
    @Test fun theStartNamesAVideo() {
        assertEquals("Exporting video", ExportAnnouncement.started(ExportOptions.Format.VIDEO))
        assertEquals("Exporting", ExportAnnouncement.started(ExportOptions.Format.WAV))
        assertEquals("Exporting", ExportAnnouncement.started(ExportOptions.Format.MIDI))
    }

    @Test fun eachQuarterIsSaidOnceAsItIsCrossed() {
        assertNull(ExportAnnouncement.milestone(0.0, 0.24))
        assertEquals("25%", ExportAnnouncement.milestone(0.24, 0.25))
        assertNull("already said", ExportAnnouncement.milestone(0.25, 0.26))
        assertEquals("50%", ExportAnnouncement.milestone(0.49, 0.51))
        assertEquals("75%", ExportAnnouncement.milestone(0.74, 0.8))
        assertNull("the end is the result, not a milestone", ExportAnnouncement.milestone(0.8, 1.0))
    }

    /** Progress posted in a jump past two quarters says only the latest. */
    @Test fun aJumpSaysOnlyTheLastQuarterCrossed() {
        assertEquals("50%", ExportAnnouncement.milestone(0.2, 0.6))
    }

    @Test fun aCancelIsSaid() = assertEquals("Export canceled", ExportAnnouncement.CANCELED)

    /** Segment labels don't fit at the largest text ("Cartridge" wraps), so
     * from the accessibility sizes on, as iOS does, Format and Style are
     * menu rows, and Style's row names itself in place of the heading. */
    @Test fun pickersBecomeMenusAtAccessibilitySizes() {
        assertFalse(ExportControls.pickersAsMenus(1.0f))
        assertFalse(ExportControls.pickersAsMenus(1.3f))
        assertTrue(ExportControls.pickersAsMenus(1.5f))
        assertTrue(ExportControls.pickersAsMenus(2.0f))
        assertEquals("Style", ExportControls.styleHeader(menus = false))
        assertNull(ExportControls.styleHeader(menus = true))
    }

    /** A greyed-out Export button says why, so TalkBack users aren't left
     * guessing; it is only ever off for length when a video is too long. */
    @Test fun aBlockedExportButtonSaysWhy() {
        val over = VideoExport.MAX_SECONDS + 1
        assertEquals(
            "Too long for a video. The limit is 10:00.",
            ExportCopy.blockedReason(ExportOptions.Format.VIDEO, over),
        )
        assertNull(ExportCopy.blockedReason(ExportOptions.Format.VIDEO, VideoExport.MAX_SECONDS))
        assertNull(ExportCopy.blockedReason(ExportOptions.Format.WAV, over))
    }
}
