package dev.individuation.chiptune.ui.layout

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/** `ui/layout` holds the views' pure rules, so it runs in plain JVM tests:
 * no Android or Compose imports. */
class UiLayoutPurityTest {
    private val dir = File("src/main/java/dev/individuation/chiptune/ui/layout")

    @Test fun layoutHelpersImportNoPlatformClasses() {
        val files = dir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()
        assertTrue("no sources under ${dir.absolutePath}", files.isNotEmpty())
        val offenders = files.flatMap { file ->
            file.readLines().filter { it.startsWith("import android") || it.startsWith("import androidx") }
                .map { "${file.name}: $it" }
        }
        assertTrue("platform imports in ui/layout: $offenders", offenders.isEmpty())
    }
}
