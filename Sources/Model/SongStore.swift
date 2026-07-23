import Foundation

/// Saves songs as individual JSON files in the app's Documents directory, and
/// remembers which one was last open so a relaunch picks up where you left off.
struct SongStore {
    static let shared = SongStore()

    private let currentKey = "currentSongID"

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

    /// - Parameter makeCurrent: also record this as the song to reopen on launch.
    func save(_ song: Song, makeCurrent: Bool = false) {
        var song = song
        song.modified = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(song) else { return }
        try? data.write(to: url(for: song.id), options: .atomic)
        if makeCurrent {
            UserDefaults.standard.set(song.id.uuidString, forKey: currentKey)
        }
    }

    func delete(_ song: Song) {
        try? FileManager.default.removeItem(at: url(for: song.id))
        if UserDefaults.standard.string(forKey: currentKey) == song.id.uuidString {
            UserDefaults.standard.removeObject(forKey: currentKey)
        }
    }

    func load(id: UUID) -> Song? {
        guard let data = try? Data(contentsOf: url(for: id)),
              var song = try? JSONDecoder().decode(Song.self, from: data) else { return nil }
        song.normalize()
        return song
    }

    /// The song that was open when the app last ran, falling back to the most
    /// recently modified one if that file is gone.
    func loadLast() -> Song? {
        if let raw = UserDefaults.standard.string(forKey: currentKey),
           let id = UUID(uuidString: raw),
           let song = load(id: id) {
            return song
        }
        return loadAll().first
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
