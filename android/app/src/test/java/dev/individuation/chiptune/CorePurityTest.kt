package dev.individuation.chiptune

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/** `core` must stay platform-free so it runs in plain JVM tests. */
class CorePurityTest {
    private val coreDir = File("src/main/java/dev/individuation/chiptune/core")

    private fun coreFiles(): List<File> =
        coreDir.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    @Test
    fun coreDirectoryHasSources() {
        assertTrue("no .kt files under ${coreDir.absolutePath}", coreFiles().isNotEmpty())
    }

    @Test
    fun coreImportsNoAndroidClasses() {
        val offenders = coreFiles().flatMap { file ->
            file.readLines().filter { it.startsWith("import android") || it.startsWith("import androidx") }
                .map { "${file.name}: $it" }
        }
        assertTrue("platform imports in core: $offenders", offenders.isEmpty())
    }
}
