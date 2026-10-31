package dev.individuation.chiptune.platform

import android.content.res.AssetManager

/** Reads the sample songs shipped as `*.chipsong` at the assets root (the
 * build points the assets at `Sources/Resources/Samples`, which iOS bundles
 * too). A file that can't be opened is left out; [SampleSongs] skips any
 * that won't decode. */
object BundledSamples {
    private const val EXTENSION = ".chipsong"

    fun read(assets: AssetManager): List<ByteArray> {
        val names = runCatching { assets.list("") }.getOrNull().orEmpty()
            .filter { it.endsWith(EXTENSION) }
            .sorted()
        return names.mapNotNull { name -> runCatching { assets.open(name).use { it.readBytes() } }.getOrNull() }
    }
}
