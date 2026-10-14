package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.model.ChannelKind
import dev.individuation.chiptune.core.model.Song
import dev.individuation.chiptune.core.store.InMemoryKeyValueStore
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** The pure policies the views lean on: `ScenePhasePolicyTests`,
 * `ConfirmationCopyTests`, `EditorPresentationTests`, `ExportFlowTests`,
 * `KeyboardShortcutsMenuVisibilityTests` and the review-prompt cases of
 * `LayoutTests`. */
class PolicyTest {

    // MARK: App phases (scene phases on iOS, lifecycle events here)

    @Test fun inactiveSavesButKeepsPlaying() {
        assertTrue(ScenePhasePolicy.savesNow(AppPhase.INACTIVE))
        assertFalse(ScenePhasePolicy.stopsEngine(AppPhase.INACTIVE))
    }

    @Test fun backgroundSavesAndStops() {
        assertTrue(ScenePhasePolicy.savesNow(AppPhase.BACKGROUND))
        assertTrue(ScenePhasePolicy.stopsEngine(AppPhase.BACKGROUND))
    }

    @Test fun activeDoesNeither() {
        assertFalse(ScenePhasePolicy.savesNow(AppPhase.ACTIVE))
        assertFalse(ScenePhasePolicy.stopsEngine(AppPhase.ACTIVE))
    }

    @Test fun lifecycleEventsMapToPhases() {
        assertEquals(AppPhase.ACTIVE, AppPhase.fromLifecycleEvent("ON_RESUME"))
        assertEquals(AppPhase.INACTIVE, AppPhase.fromLifecycleEvent("ON_PAUSE"))
        assertEquals(AppPhase.BACKGROUND, AppPhase.fromLifecycleEvent("ON_STOP"))
        assertEquals(null, AppPhase.fromLifecycleEvent("ON_CREATE"))
    }

    // MARK: Review prompt

    @Test fun reviewRequestOnlyFiresForACompletedShare() {
        assertTrue(ReviewPromptPolicy.shouldRequest(true, ShareOutcome.COMPLETED))
        assertFalse(ReviewPromptPolicy.shouldRequest(true, ShareOutcome.CANCELED))
        assertFalse(ReviewPromptPolicy.shouldRequest(true, ShareOutcome.FAILED))
        assertFalse(ReviewPromptPolicy.shouldRequest(false, ShareOutcome.COMPLETED))
    }

    @Test fun cancelingOrFailingAShareLeavesTheMilestoneUnadvanced() {
        val canceled = ReviewPromptPolicy.afterShareDismiss(true, ShareOutcome.CANCELED, 5, 0)
        assertFalse(canceled.shouldRequestReview)
        assertEquals(0, canceled.lastRequestExportCount)
        val failed = ReviewPromptPolicy.afterShareDismiss(true, ShareOutcome.FAILED, 5, 0)
        assertFalse(failed.shouldRequestReview)
        assertEquals(0, failed.lastRequestExportCount)
        val completed = ReviewPromptPolicy.afterShareDismiss(true, ShareOutcome.COMPLETED, 5, 0)
        assertTrue(completed.shouldRequestReview)
        assertEquals(5, completed.lastRequestExportCount)
        val ineligible = ReviewPromptPolicy.afterShareDismiss(false, ShareOutcome.COMPLETED, 5, 2)
        assertFalse(ineligible.shouldRequestReview)
        assertEquals(2, ineligible.lastRequestExportCount)
    }

    @Test fun reviewRequestRetriesAtALaterExportMilestone() {
        assertFalse(ReviewPromptPolicy.isDue(2, 0))
        assertTrue(ReviewPromptPolicy.isDue(3, 0))
        assertFalse(ReviewPromptPolicy.isDue(12, 3))
        assertTrue(ReviewPromptPolicy.isDue(13, 3))
        assertFalse("a count that went backwards is not due", ReviewPromptPolicy.isDue(4, 13))
    }

    @Test fun theTrackerPersistsCountsAndSpendsOnlyCompletedShares() {
        val prefs = InMemoryKeyValueStore()
        val tracker = ReviewPromptTracker(prefs)
        assertFalse(tracker.exportSucceeded())
        assertFalse(tracker.exportSucceeded())
        assertTrue("third export is due", tracker.exportSucceeded())
        assertFalse("canceled share spends nothing", tracker.shareDismissed(ShareOutcome.CANCELED))
        assertEquals(0, prefs.getInt(ReviewPromptTracker.LAST_REQUEST_KEY))
        assertTrue(ReviewPromptTracker(prefs).exportSucceeded())
        assertEquals(4, prefs.getInt(ReviewPromptTracker.SUCCESSFUL_EXPORTS_KEY))
        val again = ReviewPromptTracker(prefs)
        assertTrue(again.exportSucceeded())
        assertTrue(again.shareDismissed(ShareOutcome.COMPLETED))
        assertEquals(5, prefs.getInt(ReviewPromptTracker.LAST_REQUEST_KEY))
        assertFalse(again.shareDismissed(ShareOutcome.COMPLETED))
        repeat(9) { assertFalse(again.exportSucceeded()) }
        assertTrue(again.exportSucceeded())
    }

    // MARK: Editor presentation

    @Test fun nothingPresentedAllowsSongCommands() {
        val p = SongBoundPresenters()
        assertFalse(p.isPresented)
        assertTrue(EditorPresentation.canChangeSong(p.isPresented))
    }

    @Test fun everySongBoundSurfaceBlocksSongCommands() {
        for (surface in SongBoundPresenters.Surface.entries) {
            val p = SongBoundPresenters().set(surface, true)
            assertTrue("$surface", p.isPresented)
            assertFalse("$surface", EditorPresentation.canChangeSong(p.isPresented))
        }
    }

    @Test fun oneSurfaceClosingDoesNotClearAnother() {
        var p = SongBoundPresenters()
        p = p.set(SongBoundPresenters.Surface.TEMPO_ALERT, true)
        p = p.set(SongBoundPresenters.Surface.TRACK_SOUND, true)
        p = p.set(SongBoundPresenters.Surface.TEMPO_ALERT, false)
        assertTrue(p.isPresented)
        p = p.set(SongBoundPresenters.Surface.TRACK_SOUND, false)
        assertFalse(p.isPresented)
    }

    @Test fun settingTwiceIsIdempotent() {
        var p = SongBoundPresenters()
        p = p.set(SongBoundPresenters.Surface.PATTERN_CLEAR, true)
        p = p.set(SongBoundPresenters.Surface.PATTERN_CLEAR, true)
        p = p.set(SongBoundPresenters.Surface.PATTERN_CLEAR, false)
        assertFalse(p.isPresented)
    }

    @Test fun commandEnabledNeedsAnEditorAndNothingSongBound() {
        assertTrue(EditorPresentation.commandEnabled(hasEditor = true, canChangeSong = true))
        assertFalse(EditorPresentation.commandEnabled(hasEditor = true, canChangeSong = false))
        assertFalse(EditorPresentation.commandEnabled(hasEditor = false, canChangeSong = true))
    }

    @Test fun canOpenOnlyWithNothingPresented() {
        assertTrue(EditorPresentation.canOpen(anyPresented = false))
        assertFalse(EditorPresentation.canOpen(anyPresented = true))
    }

    @Test fun libraryAndSurfacesCloseOnlyWhenTheSongChanges() {
        val a = UUID.randomUUID()
        val b = UUID.randomUUID()
        assertTrue(SongLibraryPresentation.afterOpeningSong(true, a, a))
        assertFalse(SongLibraryPresentation.afterOpeningSong(true, a, b))
        assertFalse(SongLibraryPresentation.afterOpeningSong(false, a, a))
        val all = PresentedSurfaces(songs = true, arrangement = true, export = true, instrumentEditor = true)
        assertEquals(all, all.afterOpeningSong(a, a))
        assertEquals(PresentedSurfaces(), all.afterOpeningSong(a, b))
    }

    // MARK: Export flow

    private val file = File("/tmp/song.wav")

    @Test fun noFileAsksForNothing() {
        assertEquals(ExportFlow.Step(), ExportFlow.afterRender(null, exportPresented = true))
    }

    @Test fun renderFromThePanelQueuesTheShareRatherThanPresentingIt() {
        val step = ExportFlow.afterRender(file, exportPresented = true)
        assertTrue(step.closeExport)
        assertTrue(step.shareWhenExportCloses)
        assertFalse(step.shareNow)
    }

    @Test fun renderWithNoPanelUpSharesImmediately() {
        val step = ExportFlow.afterRender(file, exportPresented = false)
        assertFalse(step.closeExport)
        assertFalse(step.shareWhenExportCloses)
        assertTrue(step.shareNow)
    }

    @Test fun panelClosingSpendsTheQueuedShare() {
        assertTrue(ExportFlow.afterExportClosed(pendingShare = true).shareNow)
        assertEquals(ExportFlow.Step(), ExportFlow.afterExportClosed(pendingShare = false))
    }

    @Test fun panelDisappearingMidRenderAsksForACancel() {
        assertTrue(ExportFlow.afterPanelDisappeared(isExporting = true))
        assertFalse(ExportFlow.afterPanelDisappeared(isExporting = false))
    }

    /** The same song in the same format writes the same path, and the
     * file's clear-then-set can fold into no change at all; the attempt
     * counter moves for every finished render. */
    @Test fun theSameFileTwiceInARowIsSharedTwice() {
        assertEquals(file, ExportFlow.finishedExport(previousAttempt = 0, completedAttempt = 1, file = file))
        assertEquals(file, ExportFlow.finishedExport(previousAttempt = 1, completedAttempt = 2, file = file))
    }

    @Test fun anAttemptThatLeftNoFileSharesNothing() {
        assertNull(ExportFlow.finishedExport(previousAttempt = 1, completedAttempt = 2, file = null))
    }

    @Test fun anAttemptThatHasNotAdvancedSharesNothing() {
        assertNull(ExportFlow.finishedExport(previousAttempt = 2, completedAttempt = 2, file = file))
        assertNull(ExportFlow.finishedExport(previousAttempt = 3, completedAttempt = 2, file = file))
    }

    // MARK: Keyboard shortcuts menu

    @Test fun keyboardShortcutsRowVisibility() {
        assertFalse(KeyboardShortcutsMenuVisibility.visible(keyboardConnected = false, hardwareKeyboardInUse = false))
        assertTrue(KeyboardShortcutsMenuVisibility.visible(keyboardConnected = true, hardwareKeyboardInUse = false))
        assertTrue(KeyboardShortcutsMenuVisibility.visible(keyboardConnected = false, hardwareKeyboardInUse = true))
        assertTrue(KeyboardShortcutsMenuVisibility.visible(keyboardConnected = true, hardwareKeyboardInUse = true))
    }
}

/** Port of `ConfirmationCopyTests.swift`. */
class ConfirmationCopyTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Confirm"))
    }

    @After
    fun tearDown() = h.close()

    @Test fun clearPatternCopyPromisesUndoBecauseClearingCheckpoints() {
        studio.setNote(0, 0, 60)
        studio.clearPattern()
        assertTrue(studio.canUndo)
        assertTrue(ConfirmationCopy.CLEAR_PATTERN.endsWith("Undo brings them back."))
    }

    @Test fun clearTrackCopyPromisesUndoBecauseClearingCheckpoints() {
        studio.setNote(0, 0, 60)
        studio.clearTrack(0)
        assertTrue(studio.canUndo)
        assertTrue(ConfirmationCopy.CLEAR_TRACK.endsWith("Undo brings them back."))
    }

    @Test fun deleteTrackCopyPromisesUndoInTheSameWordsAsDeletePattern() {
        studio.addTrack(ChannelKind.PULSE1)
        studio.removeTrack(1)
        assertTrue(studio.canUndo)
        assertTrue(ConfirmationCopy.DELETE_TRACK.endsWith("Undo brings it back."))
        assertTrue(ConfirmationCopy.DELETE_PATTERN.endsWith("Undo brings it back."))
    }

    @Test fun deleteTitlesNameWhatIsDeleted() {
        assertEquals("Delete track Bass?", ConfirmationCopy.deleteTrackTitle("Bass"))
        assertEquals("Delete pattern A?", ConfirmationCopy.deletePatternTitle("A"))
    }

    @Test fun theCopyIsWordForWord() {
        assertEquals("Every track's notes in this pattern are erased. Undo brings them back.", ConfirmationCopy.CLEAR_PATTERN)
        assertEquals("Its notes in the other patterns are left alone. Undo brings them back.", ConfirmationCopy.CLEAR_TRACK)
        assertEquals("Its notes in every pattern go with it. Undo brings it back.", ConfirmationCopy.DELETE_TRACK)
        assertEquals("It's removed from the arrangement too. Undo brings it back.", ConfirmationCopy.DELETE_PATTERN)
    }

    @Test fun songBoundPresentersAreReportedIntoTheStudio() {
        studio.setPresented(SongBoundPresenters.Surface.PATTERN_RENAME, true)
        assertTrue(studio.songBoundPresenters.isPresented)
        assertTrue(studio.state.value.songBoundPresenters.isPresented)
        studio.setPresented(SongBoundPresenters.Surface.PATTERN_RENAME, false)
        assertFalse(studio.songBoundPresenters.isPresented)
    }
}
