package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.model.Chip
import dev.individuation.chiptune.core.model.Song
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Port of `HardwareKeyTests.swift`: the pure key mapping and the cursor.
 * Command maps to Ctrl or Meta on Android; UIKit's key repeater is replaced by
 * Android's own auto-repeat, so only the policy of what repeats is kept. */
class HardwareKeyTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Blank"))
    }

    @After
    fun tearDown() = h.close()

    // MARK: The note row

    @Test fun theNoteRowIsAPianoStartingAtC() {
        assertEquals(60, NoteKeys.note('a', 5))
        assertEquals(61, NoteKeys.note('w', 5))
        assertEquals(62, NoteKeys.note('s', 5))
        assertEquals(72, NoteKeys.note('k', 5))
    }

    @Test fun theNoteRowIsCaseInsensitive() {
        assertEquals(NoteKeys.note('a', 5), NoteKeys.note('A', 5))
    }

    @Test fun keysOutsideTheRowWriteNothing() {
        for (c in listOf('q', 'r', 'i', 'o', 'p', 'l', '1', ' ', '\u00F1')) {
            assertNull("$c is not part of the layout", NoteKeys.note(c, 5))
        }
    }

    @Test fun keysPastTheTopOfMidiAreDroppedRatherThanClamped() {
        assertEquals(120, NoteKeys.note('a', 10))
        assertNull(NoteKeys.note('k', 10))
    }

    // MARK: What a press means

    private fun action(
        key: Key = Key.OTHER,
        characters: String = "",
        modifiers: KeyModifiers = KeyModifiers(),
        octave: Int = 5,
    ): KeyAction? = KeyAction.forKey(key, characters, modifiers, octave)

    @Test fun theTransportAndCursorKeys() {
        assertEquals(KeyAction.TogglePlay, action(Key.SPACE))
        assertEquals(KeyAction.Move(0, -1), action(Key.UP))
        assertEquals(KeyAction.Move(0, 1), action(Key.DOWN))
        assertEquals(KeyAction.Move(-1, 0), action(Key.LEFT))
        assertEquals(KeyAction.Move(1, 0), action(Key.RIGHT))
    }

    @Test fun bothDeleteKeysClear() {
        assertEquals(KeyAction.Clear, action(Key.BACKSPACE))
        assertEquals(KeyAction.Clear, action(Key.FORWARD_DELETE))
    }

    @Test fun returnWritesTheSelectedNote() {
        assertEquals(KeyAction.TypeSelected, action(Key.ENTER))
        assertEquals(KeyAction.TypeSelected, action(Key.NUMPAD_ENTER))
    }

    @Test fun lettersWriteNotesAtTheCurrentOctave() {
        assertEquals(KeyAction.Type(60), action(characters = "a", octave = 5))
        assertEquals(KeyAction.Type(72), action(characters = "a", octave = 6))
        assertEquals(KeyAction.Octave(-1), action(characters = "z"))
        assertEquals(KeyAction.Octave(1), action(characters = "x"))
    }

    @Test fun modifiedPressesAreLeftToTheSystem() {
        assertNull(action(characters = "a", modifiers = KeyModifiers(ctrl = true)))
        assertNull(action(characters = "a", modifiers = KeyModifiers(meta = true)))
        assertNull(action(Key.SPACE, modifiers = KeyModifiers(ctrl = true)))
        assertNull(action(characters = "a", modifiers = KeyModifiers(alt = true)))
        assertEquals(KeyAction.Type(60), action(characters = "A", modifiers = KeyModifiers(shift = true)))
    }

    @Test fun keysTheEditorDoesntClaimArePassedOn() {
        assertNull(action(characters = "q"))
        assertNull(action(Key.TAB))
        assertNull(action(Key.ESCAPE))
    }

    // MARK: Escape, while something is presented

    @Test fun escapeAndCtrlPeriodDismissWhateverIsPresented() {
        assertEquals(KeyAction.Dismiss, KeyAction.forPresentedKey(Key.ESCAPE, KeyModifiers()))
        assertEquals(KeyAction.Dismiss, KeyAction.forPresentedKey(Key.PERIOD, KeyModifiers(ctrl = true)))
        assertEquals(KeyAction.Dismiss, KeyAction.forPresentedKey(Key.PERIOD, KeyModifiers(meta = true)))
    }

    @Test fun nothingElseIsClaimedWhileSomethingIsPresented() {
        assertNull(KeyAction.forPresentedKey(Key.SPACE, KeyModifiers()))
        assertNull(KeyAction.forPresentedKey(Key.OTHER, KeyModifiers()))
        assertNull(KeyAction.forPresentedKey(Key.DOWN, KeyModifiers()))
        assertNull(KeyAction.forPresentedKey(Key.BACKSPACE, KeyModifiers()))
        assertNull(KeyAction.forPresentedKey(Key.OTHER, KeyModifiers(ctrl = true)))
        assertNull("a bare period is a period", KeyAction.forPresentedKey(Key.PERIOD, KeyModifiers()))
    }

    @Test fun escapeDoesNothingWithNothingPresented() {
        assertNull(action(Key.ESCAPE))
        assertNull(action(Key.PERIOD, modifiers = KeyModifiers(ctrl = true)))
    }

    @Test fun dismissRaisesARequestForTheEditorToAnswer() {
        val before = studio.dismissRequests
        studio.apply(KeyAction.Dismiss)
        assertEquals(before + 1, studio.dismissRequests)
        studio.apply(KeyAction.Dismiss)
        assertEquals(before + 2, studio.dismissRequests)
        assertEquals(before + 2, studio.state.value.dismissRequests)
    }

    // MARK: Holding a key

    @Test fun onlyTheArrowsRepeat() {
        assertTrue(KeyRepeat.repeats(KeyAction.Move(0, 1)))
        assertTrue(KeyRepeat.repeats(KeyAction.Move(-1, 0)))
        for (a in listOf(KeyAction.TogglePlay, KeyAction.Type(60), KeyAction.TypeSelected, KeyAction.ToggleNoteOff,
            KeyAction.Clear, KeyAction.Octave(1), KeyAction.Dismiss)) {
            assertFalse("$a must not repeat", KeyRepeat.repeats(a))
        }
    }

    // MARK: The cursor

    @Test fun arrowsStopAtTheEdgesRatherThanWrapping() {
        studio.selectedTrack = 0
        studio.selectedStep = 0
        studio.moveCursor(track = -1, step = -1)
        assertEquals(0, studio.selectedTrack)
        assertEquals(0, studio.selectedStep)
        studio.selectedTrack = studio.song.tracks.size - 1
        studio.selectedStep = studio.patternLength - 1
        studio.moveCursor(track = 1, step = 1)
        assertEquals(studio.song.tracks.size - 1, studio.selectedTrack)
        assertEquals(studio.patternLength - 1, studio.selectedStep)
    }

    @Test fun typingAdvancesTheCursorAndWrapsAtTheEndOfThePattern() {
        studio.selectedStep = 0
        studio.typeNote(60)
        assertEquals(1, studio.selectedStep)
        studio.selectedStep = studio.patternLength - 1
        studio.typeNote(62)
        assertEquals(0, studio.selectedStep)
    }

    @Test fun typingWritesTheNoteAndPointsTheOnScreenKeyboardAtIt() {
        studio.selectedTrack = 1
        studio.selectedStep = 4
        studio.typeNote(67)
        assertEquals(67, studio.note(1, 4))
        assertEquals(67, studio.selectedNote)
    }

    @Test fun typingAuditionsTheNoteOnTheCursorTrack() {
        studio.selectedTrack = 1
        studio.typeNote(67)
        assertTrue("the output was started to play it", h.audio.isRunning)
    }

    @Test fun deleteEmptiesTheCellAndCarriesOnDownTheTrack() {
        studio.selectedStep = 2
        studio.typeNote(60)
        studio.selectedStep = 2
        studio.clearAtCursor()
        assertEquals(Chip.EMPTY_NOTE, studio.note(0, 2))
        assertEquals(3, studio.selectedStep)
    }

    @Test fun typingIsUndoable() {
        studio.selectedStep = 0
        studio.typeNote(60)
        assertTrue(studio.canUndo)
        studio.undo()
        assertEquals(Chip.EMPTY_NOTE, studio.note(0, 0))
    }

    @Test fun aShortenedPatternPullsTheCursorBackInside() {
        studio.setPatternLength(64)
        studio.selectedStep = 60
        studio.setPatternLength(16)
        studio.typeNote(60)
        assertTrue(studio.selectedStep < studio.patternLength)
        assertEquals(60, studio.note(0, 15))
    }

    @Test fun shorteningThePatternPullsTheCursorBackInsideImmediately() {
        studio.setPatternLength(64)
        studio.selectedStep = 60
        studio.setPatternLength(16)
        assertTrue(studio.selectedStep < studio.patternLength)
    }

    @Test fun aDeletedTrackPullsTheCursorBackInside() {
        studio.selectedTrack = studio.song.tracks.size - 1
        studio.removeTrack(studio.song.tracks.size - 1)
        studio.typeNote(60)
        assertTrue(studio.selectedTrack < studio.song.tracks.size)
    }

    @Test fun theCursorStaysHiddenUntilAKeyIsPressed() {
        assertFalse(studio.hardwareKeyboardInUse)
        studio.placeCursor(2, 5)
        assertEquals(0, studio.selectedStep)
        studio.moveCursor(step = 1)
        assertTrue(studio.hardwareKeyboardInUse)
        studio.placeCursor(2, 5)
        assertEquals(2, studio.selectedTrack)
        assertEquals(5, studio.selectedStep)
    }

    @Test fun leftAndRightAskTheGridToShowTheCursorColumn() {
        val start = studio.revealRequest.generation
        studio.apply(KeyAction.Move(1, 0))
        assertEquals(RevealRequest(start + 1, RevealRequest.Reason.CURSOR), studio.revealRequest)
        studio.apply(KeyAction.Move(-1, 0))
        assertEquals(RevealRequest(start + 2, RevealRequest.Reason.CURSOR), studio.revealRequest)
    }

    @Test fun upDownAndTapsRequestNoReveal() {
        val start = studio.revealRequest
        studio.apply(KeyAction.Move(0, 1))
        studio.apply(KeyAction.Move(0, -1))
        studio.placeCursor(2, 3)
        studio.selectedTrack = 1
        assertEquals(start, studio.revealRequest)
    }

    @Test fun theOctaveIsSharedAndStaysInTheKeyboardsRange() {
        studio.octave = 5
        studio.shiftOctave(1)
        assertEquals(6, studio.octave)
        studio.octave = 8
        studio.shiftOctave(1)
        assertEquals(8, studio.octave)
        studio.octave = 0
        studio.shiftOctave(-1)
        assertEquals(0, studio.octave)
        assertEquals(0..8, Studio.OCTAVE_RANGE)
    }

    @Test fun backslashArmsAndDisarmsNoteOff() {
        assertEquals(KeyAction.ToggleNoteOff, KeyAction.forKey(Key.BACKSLASH, "\\", KeyModifiers(), 5))
        studio.selectedNote = 62
        studio.apply(KeyAction.ToggleNoteOff)
        assertEquals(Chip.NOTE_OFF, studio.selectedNote)
        assertTrue(studio.hardwareKeyboardInUse)
        studio.apply(KeyAction.ToggleNoteOff)
        assertEquals(62, studio.selectedNote)
    }

    @Test fun backslashIsNotReadAsANote() {
        assertNull(NoteKeys.note('\\', 5))
    }

    @Test fun applyRunsEveryAction() {
        studio.apply(KeyAction.Octave(1))
        assertEquals(6, studio.octave)
        studio.apply(KeyAction.Type(72))
        assertEquals(72, studio.note(0, 0))
        studio.selectedNote = 64
        studio.apply(KeyAction.TypeSelected)
        assertEquals(64, studio.note(0, 1))
        studio.selectedStep = 0
        studio.apply(KeyAction.Clear)
        assertEquals(Chip.EMPTY_NOTE, studio.note(0, 0))
        studio.apply(KeyAction.TogglePlay)
        assertTrue(studio.isPlaying)
        studio.apply(KeyAction.TogglePlay)
        assertFalse(studio.isPlaying)
    }
}
