package dev.individuation.chiptune.core.model

import dev.individuation.chiptune.core.text.Graphemes
import dev.individuation.chiptune.core.text.SwiftText
import java.util.UUID

/** Reading and writing `.chipsong` files — the pure parts of
 * `SongDocument.swift`. File I/O and sharing live in the platform layer. */
object SongDocument {

    const val FILE_EXTENSION = "chipsong"

    /** Longest file-name base: 255 bytes minus room for the extension. */
    const val MAX_FILE_NAME_BYTES = 200

    /** Decodes a song from raw file contents, always normalized.
     * @throws SongDecodeException for anything that isn't a song. */
    fun decode(bytes: ByteArray): Song = SongCodec.decode(bytes)

    /** The song as `.chipsong` JSON text (UTF-8 when written to a file). */
    fun encode(song: Song): String = SongCodec.encode(song)

    fun encodeToBytes(song: Song): ByteArray = encode(song).toByteArray(Charsets.UTF_8)

    /** "My Song.chipsong". */
    fun fileName(song: Song): String = "${safeName(song)}.$FILE_EXTENSION"

    /** The one file-name base both the song-file and WAV exports use: letters,
     * marks and numbers in any script, space, hyphen and underscore; runs of
     * spaces collapsed; at most [MAX_FILE_NAME_BYTES] UTF-8 bytes. */
    fun safeName(song: Song): String {
        val stripped = StringBuilder()
        var i = 0
        val name = song.name
        while (i < name.length) {
            val cp = name.codePointAt(i)
            if (isAllowed(cp)) stripped.appendCodePoint(cp)
            i += Character.charCount(cp)
        }
        val collapsed = SwiftText.trimWhitespaces(stripped.split(' ').filter { it.isNotEmpty() }.joinToString(" "))
        val base = truncatedForFileName(collapsed)
        return base.ifEmpty { "chiptune" }
    }

    /** `CharacterSet.alphanumerics` (Unicode L*, M*, N*) plus " -_". */
    private fun isAllowed(cp: Int): Boolean {
        if (cp == ' '.code || cp == '-'.code || cp == '_'.code) return true
        return when (Character.getType(cp).toByte()) {
            Character.UPPERCASE_LETTER, Character.LOWERCASE_LETTER, Character.TITLECASE_LETTER,
            Character.MODIFIER_LETTER, Character.OTHER_LETTER,
            Character.NON_SPACING_MARK, Character.COMBINING_SPACING_MARK, Character.ENCLOSING_MARK,
            Character.DECIMAL_DIGIT_NUMBER, Character.LETTER_NUMBER, Character.OTHER_NUMBER,
            -> true
            else -> false
        }
    }

    /** Cuts [base] to at most [MAX_FILE_NAME_BYTES] UTF-8 bytes on a
     * character boundary, then drops any space the cut left at the end. */
    fun truncatedForFileName(base: String): String {
        if (base.toByteArray(Charsets.UTF_8).size <= MAX_FILE_NAME_BYTES) return base
        val out = StringBuilder()
        var bytes = 0
        for (ch in Graphemes.split(base)) {
            val n = ch.toByteArray(Charsets.UTF_8).size
            if (bytes + n > MAX_FILE_NAME_BYTES) break
            out.append(ch)
            bytes += n
        }
        return SwiftText.trimWhitespaces(out.toString())
    }

    /** A song whose id is already in the library gets a new identity and a
     * name that says where it came from, rather than overwriting the copy there. */
    fun resolvingCollision(song: Song, existing: Collection<UUID>): Song {
        if (song.id !in existing) return song
        return song.copy(id = UUID.randomUUID(), name = "${song.name} (imported)")
    }
}
