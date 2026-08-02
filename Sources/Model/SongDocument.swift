import Foundation
import UniformTypeIdentifiers

/// Reading and writing `.chipsong` files — the format songs are shared in.
///
/// The on-disk library format is already this JSON, so sharing is a matter of
/// handing over the bytes. Importing is the interesting direction: the file
/// came from wherever the user got it, and nothing about it can be assumed.
enum SongDocument {

    static let fileExtension = "chipsong"

    /// Declared in `project.yml` as an exported type conforming to `public.json`.
    static var contentType: UTType {
        UTType(exportedAs: "dev.individuation.chiptune.song", conformingTo: .json)
    }

    enum ImportError: LocalizedError {
        case unreadable
        case notASong

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file couldn't be opened."
            case .notASong:
                return "That doesn't look like a Chiptune song."
            }
        }
    }

    // MARK: Export

    /// Writes `song` to a temp file named after it, ready to hand to a share
    /// sheet. Same per-song directory trick the WAV export uses, so two songs
    /// with the same name don't overwrite each other.
    static func write(_ song: Song) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(song)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(song.id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("\(safeName(song)).\(fileExtension)")
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func safeName(_ song: Song) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        // Stripping a character out of the middle of a name leaves the spaces
        // that were around it, so "My Song / v2" would become "My Song  v2".
        let stripped = song.name.components(separatedBy: allowed.inverted).joined()
        let collapsed = stripped
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return collapsed.isEmpty ? "chiptune" : collapsed
    }

    // MARK: Import

    /// Decodes a song from raw file contents.
    ///
    /// Always normalises. This is the only path by which values the UI cannot
    /// produce reach the synth — an arpeggio offset big enough to make a voice's
    /// phase increment infinite, a NaN tempo that traps on conversion to a
    /// sample count — so it is also the only place they can be stopped.
    static func decode(_ data: Data) throws -> Song {
        guard var song = try? JSONDecoder().decode(Song.self, from: data) else {
            throw ImportError.notASong
        }
        song.normalize()
        return song
    }

    /// Reads a song from a URL that may live outside the app's sandbox — a file
    /// picked in Files, or one another app handed over.
    static func read(contentsOf url: URL) throws -> Song {
        // Documents from outside the sandbox need this bracket, and the
        // matching `stopAccessing` only when `start` actually granted access.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        return try decode(data)
    }

    /// Prepares a decoded song to join the library.
    ///
    /// A song shared between two people who both started from the same file
    /// carries the same id, and saving it as-is would silently overwrite the
    /// copy already there. So a collision gets a new identity and a name that
    /// says where it came from.
    static func resolvingCollision(_ song: Song, against existing: [UUID]) -> Song {
        var song = song
        guard existing.contains(song.id) else { return song }
        song.id = UUID()
        song.name = "\(song.name) (imported)"
        return song
    }
}
