package dev.individuation.chiptune.core.studio

import dev.individuation.chiptune.core.audio.RenderHarness
import dev.individuation.chiptune.core.audio.withPattern
import dev.individuation.chiptune.core.model.Song
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** Port of `StudioArrangementPlaybackTests.swift`: editing the arrangement
 * while the song plays. Fixture: A x4, C x3, D x8. */
class StudioArrangementPlaybackTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio
    private val playback get() = SongPlayback(studio)

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Blank"))
        studio.addPattern()
        studio.addPattern()
        studio.selectPattern(0)
        studio.edit {
            it.withSection(0) { s -> s.copy(repeats = 4) }
                .withSection(1) { s -> s.copy(repeats = 3) }
                .withSection(2) { s -> s.copy(repeats = 8) }
        }
        studio.pushArrangement()
    }

    @After
    fun tearDown() = h.close()

    private fun soundC(): UUID {
        playback.start()
        assertEquals(listOf(0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2), studio.song.chain)
        playback.advance(4 * 16)
        assertEquals("precondition: C's first repeat", 4, studio.core.currentChainSlot)
        assertEquals(1, studio.core.currentPattern)
        return studio.song.patterns[1].id
    }

    private fun slotStart(pattern: UUID): Int? {
        val section = studio.song.arrangement.indexOfFirst { it.patternID == pattern }
        if (section < 0) return null
        return studio.song.chainStart(section)
    }

    @Test fun deletingAnEarlierSectionKeepsTheSoundingSectionPlaying() {
        val soundingID = soundC()
        studio.removeSection(setOf(0))
        assertEquals(listOf(1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2), studio.song.chain)
        assertEquals(0, slotStart(soundingID))
        assertEquals(0, studio.core.currentChainSlot)
        assertEquals(1, studio.core.currentPattern)
        assertEquals(1, studio.playingPattern)
    }

    @Test fun deletingAnEarlierSectionKeepsTheOffsetWithinTheRepeats() {
        val soundingID = soundC()
        playback.advance(16)
        assertEquals(5, studio.core.currentChainSlot)
        studio.removeSection(setOf(0))
        assertEquals(0, slotStart(soundingID))
        assertEquals(1, studio.core.currentChainSlot)
        assertEquals(1, studio.core.currentPattern)
        assertEquals(1, studio.playingPattern)
    }

    @Test fun movingASectionKeepsTheSoundingSectionPlaying() {
        val soundingID = soundC()
        studio.moveSection(setOf(2), 0)
        assertEquals(listOf(2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 1, 1, 1), studio.song.chain)
        assertEquals(12, slotStart(soundingID))
        assertEquals(12, studio.core.currentChainSlot)
        assertEquals(1, studio.core.currentPattern)
        assertEquals(1, studio.playingPattern)
    }

    @Test fun repointingAnotherSectionLeavesTheCursorAlone() {
        soundC()
        studio.setSection(studio.song.arrangement[0].id, patternID = studio.song.patterns[2].id)
        assertEquals(4, studio.core.currentChainSlot)
        assertEquals(1, studio.core.currentPattern)
        assertEquals(1, studio.playingPattern)
    }

    @Test fun appendingASectionLeavesTheCursorAlone() {
        soundC()
        studio.addSection(studio.song.patterns[0].id)
        assertEquals(4, studio.core.currentChainSlot)
        assertEquals(1, studio.core.currentPattern)
        assertEquals(1, studio.playingPattern)
    }

    @Test fun deletingTheSoundingPatternResumesFromTheArrangementHead() {
        playback.start()
        playback.advance(3)
        assertEquals(0, studio.core.currentPattern)
        studio.removeSection(setOf(1))
        val dID = studio.song.patterns[2].id

        studio.removePattern(0)
        RenderHarness.renderMono(studio.core, 64)

        val head = studio.song.chain.first()
        assertEquals(dID, studio.song.patterns[head].id)
        assertEquals(head, studio.core.currentPattern)
        assertEquals(0, studio.core.currentChainSlot)
        assertEquals(head, studio.playingPattern)
        assertEquals(0, studio.playingSection)
        assertEquals(head, studio.selectedPattern)
        assertTrue(studio.followsArrangement)
    }

    @Test fun deletingTheSoundingPatternKeepsAPinnedGridPinned() {
        playback.start()
        playback.advance(3)
        studio.removeSection(setOf(1))
        studio.selectPattern(1)
        val cID = studio.song.patterns[1].id

        studio.removePattern(0)

        assertEquals(cID, studio.song.patterns[studio.selectedPattern].id)
        assertFalse(studio.followsArrangement)
        assertEquals(studio.song.chain.first(), studio.core.currentPattern)
    }

    private fun deleteSoundingAWithAnUnarrangedMiddlePattern(): Pair<UUID, UUID> {
        studio.removeSection(setOf(1))
        val a = studio.song.patterns[0].id
        val d = studio.song.patterns[2].id
        playback.start()
        playback.advance(3)
        assertEquals(0, studio.core.currentPattern)
        studio.removePattern(0)
        assertEquals("precondition: D took over", d, studio.song.patterns[studio.core.currentPattern].id)
        return a to d
    }

    private fun assertCoreFollowsTheArrangement(message: String) {
        val core = studio.core
        val chain = studio.song.chain
        val slot = core.currentChainSlot
        assertTrue("$message: slot in range", slot in chain.indices)
        assertEquals("$message: the core runs its slot's pattern", chain.getOrNull(slot) ?: -1, core.currentPattern)
        assertEquals("$message: the dot names what sounds", core.currentPattern, studio.playingPattern)
        assertTrue("$message: the dot is in the arrangement", studio.playingPattern in chain)
    }

    @Test fun undoingTheDeleteKeepsTheSoundingPatternPlaying() {
        val (_, d) = deleteSoundingAWithAnUnarrangedMiddlePattern()
        studio.undo()
        assertCoreFollowsTheArrangement("after undo")
        assertEquals(d, studio.song.patterns[studio.playingPattern].id)
        assertEquals("from D's first slot", 4, studio.core.currentChainSlot)
    }

    private fun playUntilASoundsAgain() {
        for (i in 0 until 400) {
            if (studio.core.currentChainSlot == 0 && studio.core.currentPattern == 0) break
            playback.advance(1)
        }
        assertEquals("precondition: A sounds again", 0, studio.core.currentPattern)
    }

    @Test fun deletingTheSoundingPatternAgainAfterAnUndoFollowsTheArrangement() {
        val (a, d) = deleteSoundingAWithAnUnarrangedMiddlePattern()
        studio.undo()
        playUntilASoundsAgain()
        assertEquals("precondition: the grid is on A", a, studio.song.patterns[studio.selectedPattern].id)

        studio.removePattern(0)

        assertCoreFollowsTheArrangement("after the second delete")
        assertEquals(d, studio.song.patterns[studio.selectedPattern].id)
        assertTrue(studio.followsArrangement)
    }

    @Test fun redoingTheDeleteWhileItsPatternSoundsResumesInTheArrangement() {
        deleteSoundingAWithAnUnarrangedMiddlePattern()
        studio.undo()
        playUntilASoundsAgain()
        studio.redo()
        assertCoreFollowsTheArrangement("after redo")
    }

    @Test fun undoingASectionDeleteKeepsTheSoundingSectionPlaying() {
        val soundingID = soundC()
        studio.removeSection(setOf(0))
        assertEquals(0, studio.core.currentChainSlot)

        studio.undo()

        assertCoreFollowsTheArrangement("after undo")
        assertEquals(soundingID, studio.song.patterns[studio.playingPattern].id)
        assertEquals(4, studio.core.currentChainSlot)

        studio.redo()

        assertCoreFollowsTheArrangement("after redo")
        assertEquals(0, studio.core.currentChainSlot)
    }
}

/** Port of `StudioArrangementEditWhilePlayingTests.swift`. Fixture: patterns
 * A (16), B (32), C (8), D (16); arrangement A x2, B x2, C x1, D x2. */
class StudioArrangementEditWhilePlayingTest {

    private lateinit var h: StudioHarness
    private val studio get() = h.studio
    private val playback get() = SongPlayback(studio)
    private lateinit var ids: List<UUID>

    @Before
    fun setUp() {
        h = StudioHarness()
        studio.open(Song.create("Blank"))
        repeat(3) { studio.addPattern() }
        val lengths = listOf(16, 32, 8, 16)
        val repeats = listOf(2, 2, 1, 2)
        studio.edit { song ->
            var s = song
            for (i in 0 until 4) {
                s = s.withPattern(i) { p -> p.copy(length = lengths[i]) }.withSection(i) { x -> x.copy(repeats = repeats[i]) }
            }
            s
        }
        ids = studio.song.patterns.map { it.id }
        studio.selectPattern(0)
        studio.pushAll()
        studio.pushArrangement()
    }

    @After
    fun tearDown() = h.close()

    private fun play(toSlot: Int) {
        playback.start(armFollow = true)
        var guard = 0
        while (studio.core.currentChainSlot != toSlot && guard < 400) {
            playback.advance(1)
            guard += 1
        }
        playback.advance(2)
        assertEquals("precondition", toSlot, studio.core.currentChainSlot)
    }

    private fun index(n: Int): Int = studio.song.patternIndex(ids[n])!!

    private fun assertSounding(slot: Int, pattern: Int, section: Int, gridFollows: Boolean = true, message: String) {
        val core = studio.core
        assertEquals("$message: core slot", slot, core.currentChainSlot)
        assertEquals("$message: core pattern", index(pattern), core.currentPattern)
        assertEquals("$message: slot names that pattern", index(pattern), studio.song.chain.getOrNull(slot))
        assertEquals("$message: dot", index(pattern), studio.playingPattern)
        assertEquals("$message: marker", section, studio.playingSection)
        if (gridFollows) assertEquals("$message: grid", index(pattern), studio.selectedPattern)
        playback.advance(1)
        assertEquals("$message: dot after a step", index(pattern), studio.playingPattern)
        assertEquals("$message: marker after a step", section, studio.playingSection)
        if (gridFollows) assertEquals("$message: grid after a step", index(pattern), studio.selectedPattern)
    }

    @Test fun deletingTheSoundingSectionHandsOverToTheNextSection() {
        play(3)
        studio.removeSection(setOf(1))
        assertEquals(5, studio.song.chain.size)
        assertSounding(2, 2, 1, message = "after delete")
        assertTrue(studio.followsArrangement)
    }

    @Test fun deletingTheSoundingSectionThenUndoAndRedo() {
        play(3)
        studio.removeSection(setOf(1))
        studio.undo()
        assertSounding(4, 2, 2, gridFollows = false, message = "after undo")
        studio.redo()
        assertSounding(2, 2, 1, gridFollows = false, message = "after redo")
    }

    @Test fun deletingTheSoundingSectionKeepsAPinnedGridPinned() {
        play(3)
        studio.selectPattern(0)
        studio.removeSection(setOf(1))
        assertSounding(2, 2, 1, gridFollows = false, message = "pinned delete")
        assertEquals(index(0), studio.selectedPattern)
        assertFalse(studio.followsArrangement)
        studio.undo()
        assertSounding(4, 2, 2, gridFollows = false, message = "pinned undo")
        assertTrue(studio.selectedPattern in studio.song.chain)
        studio.redo()
        assertSounding(2, 2, 1, gridFollows = false, message = "pinned redo")
        assertTrue(studio.selectedPattern in studio.song.chain)
    }

    @Test fun deletingTheSoundingLastSectionWrapsToTheHead() {
        play(5)
        studio.removeSection(setOf(3))
        assertSounding(0, 0, 0, message = "wrap to head")
    }

    @Test fun deletingTheSoundingSectionWhoseOtherSectionSharesItsPattern() {
        studio.addSection(ids[1])
        play(3)
        studio.removeSection(setOf(1))
        assertSounding(2, 2, 1, message = "next section, not a twin")
    }

    @Test fun deletingAnEarlierSectionKeepsTheSoundingSection() {
        play(4)
        studio.removeSection(setOf(0))
        assertSounding(2, 2, 1, message = "after delete")
    }

    @Test fun deletingAnEarlierSectionThenUndoAndRedo() {
        play(4)
        studio.removeSection(setOf(0))
        studio.undo()
        assertSounding(4, 2, 2, gridFollows = false, message = "after undo")
        studio.redo()
        assertSounding(2, 2, 1, gridFollows = false, message = "after redo")
    }

    @Test fun deletingAnEarlierSectionKeepsTheRepeatPositionOfTheSoundingOne() {
        play(3)
        studio.removeSection(setOf(0))
        assertSounding(1, 1, 0, message = "second pass kept")
    }

    @Test fun raisingAnEarlierSectionsRepeatsKeepsTheSoundingSection() {
        play(3)
        val a = studio.song.arrangement[0].id
        studio.setSection(a, repeats = 3)
        studio.setSection(a, repeats = 4)
        assertSounding(5, 1, 1, message = "after raise")
        studio.undo()
        assertSounding(3, 1, 1, message = "after undo")
        studio.redo()
        assertSounding(5, 1, 1, gridFollows = false, message = "after redo")
    }

    @Test fun loweringTheSoundingSectionsRepeatsClampsTheRepeatPosition() {
        play(3)
        studio.setSection(studio.song.arrangement[1].id, repeats = 1)
        assertSounding(2, 1, 1, message = "clamped to the only pass")
    }

    @Test fun raisingTheSoundingSectionsRepeatsKeepsItsPass() {
        play(3)
        studio.setSection(studio.song.arrangement[1].id, repeats = 4)
        assertSounding(3, 1, 1, message = "same pass of more")
    }

    @Test fun raisingRepeatsKeepsAPinnedGridPinned() {
        play(3)
        studio.selectPattern(3)
        studio.setSection(studio.song.arrangement[0].id, repeats = 4)
        assertSounding(5, 1, 1, gridFollows = false, message = "pinned raise")
        assertEquals(index(3), studio.selectedPattern)
    }

    @Test fun movingASectionKeepsTheSoundingSectionAndUndoRedo() {
        play(4)
        studio.moveSection(setOf(3), 0)
        assertSounding(6, 2, 3, message = "after move")
        studio.undo()
        assertSounding(4, 2, 2, gridFollows = false, message = "after undo")
        studio.redo()
        assertSounding(6, 2, 3, gridFollows = false, message = "after redo")
    }

    @Test fun repointingTheSoundingSectionMovesTheCoreToItsNewPattern() {
        play(3)
        studio.setSection(studio.song.arrangement[1].id, patternID = ids[2])
        assertSounding(3, 2, 1, message = "after repoint")
        studio.undo()
        assertSounding(3, 1, 1, gridFollows = false, message = "after undo")
        studio.redo()
        assertSounding(3, 2, 1, gridFollows = false, message = "after redo")
    }

    @Test fun appendingASectionLeavesPlaybackAlone() {
        play(3)
        studio.addSection(ids[0])
        assertSounding(3, 1, 1, message = "after append")
        studio.undo()
        assertSounding(3, 1, 1, gridFollows = false, message = "after undo")
    }
}
