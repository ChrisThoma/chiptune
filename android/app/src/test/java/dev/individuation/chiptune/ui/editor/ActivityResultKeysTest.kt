package dev.individuation.chiptune.ui.editor

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/** The registry keys a picker's result comes back under. The registry keeps a
 * pending result across process death and hands it to whoever next registers
 * that key, so a key must never repeat from one process to the next. */
class ActivityResultKeysTest {
    @Test fun eachRequestInAProcessGetsItsOwnKey() {
        val keys = ActivityResultKeys("run-a")
        val first = keys.next()
        val second = keys.next()
        assertNotEquals(first, second)
    }

    /** Save to device, the process dies, the user picks A.wav: the result
     * waits under the old process's first key. The new process's first
     * request must not register that key and receive A.wav's URI. */
    @Test fun aNewProcessNeverReusesAnEarlierProcesssKey() {
        val before = ActivityResultKeys("run-a")
        val after = ActivityResultKeys("run-b")
        val earlier = List(5) { before.next() }.toSet()
        val later = List(5) { after.next() }.toSet()
        assertEquals(emptySet<String>(), earlier intersect later)
    }

    @Test fun twoLaunchesGetDifferentProcessIds() {
        assertNotEquals(ActivityResultKeys.newProcessId(), ActivityResultKeys.newProcessId())
    }
}
