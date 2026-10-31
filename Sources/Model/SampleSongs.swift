import Foundation

/// The example songs that ship in the app bundle and join the library: all of
/// them on a first launch, next to First Loop, and each one once into a
/// library that already exists.
///
/// Injectable so tests can seed from files of their own (or broken ones)
/// rather than whatever the real bundle holds.
struct SampleSongs {
    /// The bundled samples, in the order they're listed in the library. A new
    /// sample goes on the end; existing installs get it once on their next
    /// launch.
    static let fileNames = ["sample-sky-arcade", "sample-rainy-waltz", "sample-tower-climb"]
    static let fileExtension = "chipsong"

    let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    /// The samples `bundle` holds. A missing file is left out.
    init(bundle: Bundle) {
        urls = Self.fileNames.compactMap { bundle.url(forResource: $0, withExtension: Self.fileExtension) }
    }

    static var bundled: SampleSongs { SampleSongs(bundle: .main) }

    /// Decodes each sample through the import path, which normalizes it. A
    /// file that is missing or won't decode is skipped: a sample is a nicety,
    /// never a reason to alert or to stop the others.
    func load() -> [Song] {
        urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? SongDocument.decode(data)
        }
    }

    /// Saves each sample `store` hasn't been given before and returns how many
    /// were written.
    ///
    /// A sample is given only once: one the user deleted stays deleted. A file
    /// already in the library with a sample's id is the user's (perhaps edited)
    /// copy and is never overwritten. The samples are stamped a second apart,
    /// before `now`, so they list in `fileNames` order and anything saved
    /// after this (First Loop on a first launch) lists above them.
    @discardableResult
    func seed(into store: SongStore, now: Date = Date()) -> Int {
        let given = store.seededSampleIDs()
        var seeded = given
        var written = 0
        for (i, sample) in load().enumerated() where !seeded.contains(sample.id) {
            if store.exists(id: sample.id) {
                seeded.insert(sample.id)
                continue
            }
            // A write that fails is left unrecorded, so the next launch tries again.
            guard (try? store.save(sample, modified: now.addingTimeInterval(-Double(i + 1)))) != nil
            else { continue }
            seeded.insert(sample.id)
            written += 1
        }
        if seeded != given {
            store.setSeededSampleIDs(seeded)
        }
        return written
    }
}
