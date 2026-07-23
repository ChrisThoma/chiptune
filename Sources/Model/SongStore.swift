import Foundation

/// Saves songs as individual JSON files in the app's Documents directory.
struct SongStore {
    static let shared = SongStore()

    private var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Songs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    func save(_ song: Song) {
        var song = song
        song.modified = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(song) else { return }
        try? data.write(to: url(for: song.id), options: .atomic)
    }

    func delete(_ song: Song) {
        try? FileManager.default.removeItem(at: url(for: song.id))
    }

    /// Loads every saved song, newest first. Unreadable files are skipped
    /// rather than failing the whole load.
    func loadAll() -> [Song] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        var songs: [Song] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  var song = try? decoder.decode(Song.self, from: data) else { continue }
            song.normalize()
            songs.append(song)
        }
        return songs.sorted { $0.modified > $1.modified }
    }
}
