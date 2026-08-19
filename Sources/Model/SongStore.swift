import Foundation

/// Saves songs as individual JSON files in the app's Documents directory, and
/// remembers which one was last open so a relaunch picks up where you left off.
struct SongStore {
    static let shared = SongStore()

    private let currentKey = "currentSongID"

    /// Where songs live and where "which song was open" is remembered. Both are
    /// injectable so a test can point at a temp directory and its own defaults
    /// suite rather than the real Documents folder — otherwise any test that
    /// saves a song leaks into every other test's `loadAll`.
    private let root: URL
    private let defaults: UserDefaults

    init(directory: URL, defaults: UserDefaults = .standard) {
        self.root = directory
        self.defaults = defaults
    }

    /// The app's store: `Documents/Songs` and the standard defaults.
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(directory: docs.appendingPathComponent("Songs", isDirectory: true))
    }

    /// Creates the directory lazily, so constructing a store never touches disk.
    private func ensuringDirectory() -> URL {
        if !FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private func url(for id: UUID) -> URL {
        ensuringDirectory().appendingPathComponent("\(id.uuidString).json")
    }

    /// - Parameter makeCurrent: also record this as the song to reopen on launch.
    ///
    /// Throws rather than failing quietly. Autosave is the app's entire
    /// persistence story — there is no Save button to try again with — so a
    /// write that fails and says nothing is the failure mode that loses work.
    func save(_ song: Song, makeCurrent: Bool = false) throws {
        var song = song
        song.modified = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(song)
        try data.write(to: url(for: song.id), options: .atomic)
        if makeCurrent {
            defaults.set(song.id.uuidString, forKey: currentKey)
        }
    }

    /// Throws for the same reason `save` does: a file that refuses to go means
    /// the song reappears in the library, and quietly keeping it is the failure
    /// mode that confuses. A file that is *already* gone is the outcome delete
    /// was after — deleted behind the app's back is still deleted — so that
    /// stays a no-op rather than becoming an alert.
    func delete(_ song: Song) throws {
        do {
            try FileManager.default.removeItem(at: url(for: song.id))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
        }
        if defaults.string(forKey: currentKey) == song.id.uuidString {
            defaults.removeObject(forKey: currentKey)
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
        if let raw = defaults.string(forKey: currentKey),
           let id = UUID(uuidString: raw),
           let song = load(id: id) {
            return song
        }
        return loadAll().first
    }

    /// Loads every saved song, newest first. Unreadable files are skipped
    /// rather than failing the whole load.
    func loadAll() -> [Song] {
        let files = (try? FileManager.default.contentsOfDirectory(at: ensuringDirectory(),
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
