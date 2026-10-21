import Foundation

/// How the exported file should be shaped.
struct ExportOptions: Equatable, Sendable {
    enum TailMode: Equatable, Sendable {
        /// The file is exactly `loopCount` passes long and its final notes'
        /// ring-out is folded over its own start, so playing it on repeat is
        /// indistinguishable from the sequencer running on.
        case seamlessLoop
        /// The file runs `loopCount` passes and then keeps going in silence
        /// while the last notes decay, ending on nothing. What you want when
        /// the file is the finished thing rather than a loop to drop into
        /// something else.
        case ringOut
    }

    /// Which file the export writes. MIDI is the arrangement once, so
    /// `loopCount` and `tailMode` only shape a WAV. A video takes the repeats
    /// but always rings out (`effectiveTailMode`).
    enum Format: Equatable, Sendable, CaseIterable {
        case wav, midi, video

        /// What the sheet calls it: the picker's segment and the button's
        /// "Export WAV".
        var label: String {
            switch self {
            case .wav: return "WAV"
            case .midi: return "MIDI"
            case .video: return "Video"
            }
        }

        var fileExtension: String {
            switch self {
            case .wav: return "wav"
            case .midi: return "mid"
            case .video: return "mp4"
            }
        }

        /// What its file is called in an alert.
        var fileNoun: String {
            switch self {
            case .wav: return "WAV file"
            case .midi: return "MIDI file"
            case .video: return "video"
            }
        }

        /// The format a file of this extension was written as, ignoring
        /// case; nil for anything the exporters don't write.
        init?(fileExtension: String) {
            guard let format = Self.allCases.first(where: { $0.fileExtension == fileExtension.lowercased() }) else {
                return nil
            }
            self = format
        }
    }

    /// How a video draws the song. Both are 1080×1920 with the same audio;
    /// only the picture differs.
    enum VideoStyle: Equatable, Sendable, CaseIterable {
        /// The pattern grid scrolling past a fixed playing row, as in the app.
        case grid
        /// A game cartridge whose label carries the title and a bar per
        /// track that pulses on each note. Shown as "Cartridge".
        case cover

        var label: String {
            switch self {
            case .grid: return "Grid"
            case .cover: return "Cartridge"
            }
        }
    }

    var format: Format = .wav
    /// Passes of the whole arrangement.
    var loopCount: Int = 1
    var tailMode: TailMode = .seamlessLoop
    /// Only read by a video export; kept while another format is picked so
    /// switching back finds the style the user left.
    var videoStyle: VideoStyle = .grid

    /// The ending the render actually uses. A video always rings out: a
    /// seamless loop folds the last notes over the first, which is right on
    /// repeat but puts the song's closing notes under a picture of its
    /// opening. Everything that sizes or renders the audio reads this rather
    /// than `tailMode`, so the readout and the file agree.
    var effectiveTailMode: TailMode {
        format == .video ? .ringOut : tailMode
    }

    static let maxLoopCount = 16

    var clamped: ExportOptions {
        var copy = self
        copy.loopCount = min(max(loopCount, 1), ExportOptions.maxLoopCount)
        return copy
    }
}

/// The outcome of an export. Canceling is not failing: the UI must not show
/// an error for a file the user decided they didn't want.
enum ExportResult: Sendable {
    case success(URL)
    case canceled
    case tooLong
    /// Carries the write error so the alert can say whether it was a
    /// permission or a disk-space problem rather than guessing.
    case failed(Error)
}

/// Everything one export needs. Bundled into a struct so the injectable
/// renderer stays a one-argument function as it grows.
struct ExportRequest: Sendable {
    var song: Song
    var options: ExportOptions = ExportOptions()
    /// Called with 0...1 as the render proceeds, on the rendering thread.
    var progress: @Sendable (Double) -> Void = { _ in }
    /// Polled at chunk boundaries. Returning true abandons the render.
    var isCanceled: @Sendable () -> Bool = { false }
}

/// Picks the writer for the format the export sheet chose. Studio's default
/// renderer, so the sheet's WAV / MIDI choice reaches the file without Studio
/// knowing either format. Clears the song's stale exports once the new file
/// is written, so neither writer has to.
enum Export {
    static func render(_ request: ExportRequest) async -> ExportResult {
        let result: ExportResult
        switch request.options.format {
        case .wav: result = WavExport.render(request)
        case .midi: result = MidiExport.render(request)
        case .video: result = await VideoExport.render(request)
        }
        if case .success(let url) = result {
            ExportFiles.pruneStale(keeping: url)
        }
        return result
    }
}

/// Where exports are written, shared by the WAV and MIDI writers.
enum ExportFiles {

    static func url(for song: Song, format: ExportOptions.Format) -> URL {
        let base = SongDocument.safeName(song)
        // A per-song directory keeps the shared file's display name clean while
        // stopping two same-named songs from overwriting each other's export.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(song.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(base).\(format.fileExtension)")
    }

    /// Renaming a song leaves its old exports sitting in the same per-song
    /// temp directory as the new one — storage that accumulates silently since
    /// nothing else ever visits that directory. Any export, WAV, MIDI or
    /// video, under a name other than `url`'s goes, as does an older file of
    /// `url`'s own type; the other formats' files under the current name
    /// stay, since the song's WAV, MIDI file and video are each worth keeping
    /// while another is exported. Files the exporters don't write are left alone. Only run once
    /// the new file is safely written, so a later failure never costs the
    /// previous export. Best-effort: a cleanup failure doesn't fail the export
    /// that just succeeded.
    static func pruneStale(keeping url: URL) {
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension.lowercased()
        let base = url.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent != url.lastPathComponent {
            guard ExportOptions.Format(fileExtension: entry.pathExtension) != nil else { continue }
            let sameType = entry.pathExtension.lowercased() == ext
            if sameType || entry.deletingPathExtension().lastPathComponent != base {
                try? fm.removeItem(at: entry)
            }
        }
    }
}

extension ExportFiles {
    /// The scratch folders the WAV and video renders work in, by name under
    /// the temp folder.
    static var scratchFolderNames: [String] {
        [WavExport.scratchDirectory.lastPathComponent, VideoExport.scratchDirectory.lastPathComponent]
    }

    /// Run at launch, before anything can be rendering. `pruneStale` only
    /// tidies the folder of the song just exported, so every other song kept
    /// its last export (a video runs to about 60 MB a minute) until iOS got
    /// round to clearing tmp. This clears every song's exports, the folders
    /// they leave empty, and the scratch a killed render left behind. Only
    /// what the exporters write: a folder named for a song id, the files in
    /// it with an export's extension, the two scratch folders, and a stray
    /// `.raw` from builds before the WAV scratch folder. Everything else in
    /// tmp, the song-file share folders included, is left alone.
    /// Best-effort, like `pruneStale`.
    static func sweep(root: URL = FileManager.default.temporaryDirectory) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            let name = entry.lastPathComponent
            if scratchFolderNames.contains(name) {
                try? fm.removeItem(at: entry)
            } else if entry.pathExtension == "raw" {
                try? fm.removeItem(at: entry)
            } else if let id = UUID(uuidString: name) {
                removeExports(forSongID: id, root: root)
            }
        }
    }

    /// A deleted song's exports, and its folder once nothing else is in it.
    static func removeExports(forSongID id: UUID, root: URL = FileManager.default.temporaryDirectory) {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return
        }
        for entry in entries where ExportOptions.Format(fileExtension: entry.pathExtension) != nil {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDirectory else { continue }
            try? fm.removeItem(at: entry)
        }
        if (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
            try? fm.removeItem(at: dir)
        }
    }
}

/// Renders a song offline and writes it out as a 16-bit mono WAV.
enum WavExport {
    static let sampleRate = 44100.0
    private static let chunk = 4096

    /// Where the raw float stream lives while a render runs. Its own folder,
    /// apart from `VideoExport.scratchDirectory`, so the video's sweep and
    /// this one never take each other's files: the video's soundtrack is
    /// rendered by this code into that folder.
    static var scratchDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wav-scratch", isDirectory: true)
    }

    /// A render killed mid-way (the app force-quit, or terminated in the
    /// background) never reached its cleanup, and a ten-minute song's raw
    /// stream is about 100 MB. Only one export runs at a time —
    /// `Studio.export` refuses a second while `isExporting` — so whatever is
    /// in the scratch folder belongs to a dead render. Builds before the
    /// folder wrote the stream to the top of the temp folder, so a `.raw`
    /// there is swept too.
    ///
    /// Removing and recreating the folder throws, rather than shrugging, so a
    /// read-only temp folder fails here with the permission error the alert
    /// names, as the raw file's own write used to.
    private static func resetScratch() throws {
        let fm = FileManager.default
        let top = fm.temporaryDirectory
        for entry in (try? fm.contentsOfDirectory(at: top, includingPropertiesForKeys: nil)) ?? []
        where entry.pathExtension == "raw" {
            try? fm.removeItem(at: entry)
        }
        if fm.fileExists(atPath: scratchDirectory.path) {
            try fm.removeItem(at: scratchDirectory)
        }
        try fm.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
    }
    /// How long the last notes are given to decay past the end.
    ///
    /// The envelope hits -60dB at `decay` seconds and is culled to exact zero
    /// at 4/3 × decay; 1.5× covers that with room to spare. Floor of 1.0 keeps
    /// today's behavior for short decays; ceiling of 6.0 is 1.5 × the decay
    /// slider's max (4.0s).
    static func tailSeconds(for song: Song) -> Double {
        min(max(1.5 * (song.maxAudibleDecay ?? 0), 1.0), 6.0)
    }

    /// Why a render stopped early. Thrown out of the streaming loops so a
    /// cancel unwinds in one hop rather than threading an optional result out
    /// of a pointer closure. A failed write throws its own error instead, so
    /// the alert can name the cause.
    private enum RenderAbort: Error {
        case canceled, failed
    }

    /// The simple entry point: one pass, seamless loop, no progress, no cancel.
    /// The app itself now exports through `Studio.export(options:)`; this
    /// overload survives as the tests' one-line way to render a song.
    static func render(song: Song) -> URL? {
        guard case .success(let url) = render(ExportRequest(song: song)) else { return nil }
        return url
    }

    /// Renders `request` and writes the WAV.
    ///
    /// The render is memory-bounded: a max-length arrangement at low BPM runs to
    /// hundreds of MB of floats, so everything past the first second streams
    /// through a raw temp file instead of living in one giant buffer. Only the
    /// opening stretch stays resident, and only when the tail folds over it.
    ///
    /// `destination` defaults to the song's WAV export. The video export
    /// passes a scratch file instead, so rendering its soundtrack never
    /// replaces the WAV the user last exported.
    static func render(_ request: ExportRequest, to destination: URL? = nil) -> ExportResult {
        var song = request.song
        song.normalize()
        let options = request.options.clamped
        let folding = options.effectiveTailMode == .seamlessLoop

        let samplesPerStep = Chip.samplesPerStep(tempo: song.tempo, sampleRate: sampleRate)
        let onePass = samplesPerStep * max(song.arrangementSteps, 1)
        // The chain wraps on its own, so N passes are just a longer render.
        let bodySamples = onePass * options.loopCount
        let tail = Int(sampleRate * tailSeconds(for: song))

        // Reject an invalid RIFF size before rendering. The scratch stream is
        // 32-bit float — twice the eventual WAV's size — so discovering this
        // after the render can burn minutes and many gigabytes only to report
        // a predictable format limit.
        let outputSamples = bodySamples + (folding ? 0 : tail)
        guard fitsInWav(sampleCount: outputSamples) else { return .tooLong }

        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.setSongMode(true)
        core.start()

        // Progress covers the body and the tail, which is the whole render.
        let totalFrames = bodySamples + tail
        var reported = -1.0
        func report(_ done: Int) {
            let fraction = min(Double(done) / Double(max(totalFrames, 1)), 1.0)
            // At most a hundred hops to the main actor, rather than one per
            // 4096 samples.
            guard fraction - reported >= 0.01 || fraction >= 1.0 else { return }
            reported = fraction
            request.progress(fraction)
        }

        let fm = FileManager.default
        let rawURL = scratchDirectory.appendingPathComponent(UUID().uuidString + ".raw")
        // `Data().write` rather than `createFile`, which only returns false:
        // the thrown error is what tells a read-only folder from a full disk.
        let raw: FileHandle
        do {
            try resetScratch()
            try Data().write(to: rawURL)
            raw = try FileHandle(forWritingTo: rawURL)
        } catch {
            return .failed(error)
        }
        defer { try? fm.removeItem(at: rawURL) }

        // The stretch the tail folds over. Kept in memory; everything after it
        // goes straight to the raw file. Wraps in case a very short song runs
        // shorter than the tail itself. Ring-out folds nothing, so it keeps
        // nothing resident.
        let headLen = folding ? min(tail, bodySamples) : 0
        var head = [Float](repeating: 0, count: headLen)
        var bodyPeak: Float = 0

        var scratch = [Float](repeating: 0, count: chunk)

        func renderBody(into base: UnsafeMutablePointer<Float>) throws {
            var written = 0
            while written < bodySamples {
                if request.isCanceled() { throw RenderAbort.canceled }
                let n = min(chunk, bodySamples - written)
                core.render(frames: n, into: base)
                let inHead = max(0, min(n, headLen - written))
                for i in 0..<inHead { head[written + i] = base[i] }
                if n > inHead {
                    for i in inHead..<n { bodyPeak = max(bodyPeak, abs(base[i])) }
                    let bytes = Data(bytes: base + inHead,
                                     count: (n - inHead) * MemoryLayout<Float>.size)
                    try raw.write(contentsOf: bytes)
                }
                written += n
                report(written)
            }
        }

        // The tail runs with the sequencer stopped so nothing new is
        // triggered while the envelopes ring out.
        func renderTail(into base: UnsafeMutablePointer<Float>) throws {
            var done = 0
            while done < tail {
                if request.isCanceled() { throw RenderAbort.canceled }
                let n = min(chunk, tail - done)
                core.render(frames: n, into: base)
                if folding {
                    // Fold over the start: played on repeat, the file's last
                    // notes ring on into its beginning exactly as they would
                    // have if the sequencer had kept running — a seamless loop
                    // with no trailing dead air.
                    if headLen > 0 {
                        for i in 0..<n { head[(done + i) % headLen] += base[i] }
                    }
                } else {
                    for i in 0..<n { bodyPeak = max(bodyPeak, abs(base[i])) }
                    let bytes = Data(bytes: base, count: n * MemoryLayout<Float>.size)
                    try raw.write(contentsOf: bytes)
                }
                done += n
                report(bodySamples + done)
            }
        }

        do {
            try scratch.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { throw RenderAbort.failed }
                try renderBody(into: base)
                core.finish()
                try renderTail(into: base)
            }
            try? raw.close()
        } catch {
            try? raw.close()
            return (error as? RenderAbort) == .canceled ? .canceled : .failed(error)
        }

        // Summing the overlap can push it past full scale. Scale the whole file
        // rather than letting the write clamp it: clamping would distort only the
        // overlap, which is precisely the seam the fold exists to hide.
        var peak = bodyPeak
        for s in head { peak = max(peak, abs(s)) }
        let scale: Float = peak > 1 ? 1 / peak : 1

        // Ring-out keeps the tail as trailing audio; the seamless loop folded
        // it into the head and the file stops at the end of the last pass.
        let streamed = (bodySamples - headLen) + (folding ? 0 : tail)
        let result = writeWav(head: head,
                              bodyURL: rawURL,
                              bodySamples: streamed,
                              scale: scale,
                              isCanceled: request.isCanceled,
                              to: destination ?? filename(for: song))
        if case .success = result {
            report(totalFrames)
        }
        return result
    }

    static func filename(for song: Song) -> URL {
        ExportFiles.url(for: song, format: .wav)
    }

    /// Streams the folded head plus the raw body file out as a WAV, converting
    /// to 16-bit in chunks so the whole song is never in memory twice.
    private static func writeWav(head: [Float], bodyURL: URL, bodySamples: Int,
                                 scale: Float,
                                 isCanceled: @Sendable () -> Bool,
                                 to url: URL) -> ExportResult {
        let totalSamples = head.count + bodySamples
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        // WAV's RIFF header caps a chunk at 32 bits; a render big enough to
        // overflow it can't be written as a valid WAV at all, so fail the
        // export instead of trapping the UInt32 conversion.
        guard fitsInWav(sampleCount: totalSamples) else {
            return .tooLong
        }
        let dataByteCount = totalSamples * 2
        let dataSize = UInt32(dataByteCount)

        var header = Data()
        func append<T>(_ value: T) {
            var v = value
            withUnsafeBytes(of: &v) { header.append(contentsOf: $0) }
        }

        header.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        header.append(contentsOf: Array("WAVE".utf8))

        header.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))            // PCM chunk size
        append(UInt16(1))             // PCM format
        append(channels)
        append(UInt32(sampleRate))
        append(byteRate)
        append(blockAlign)
        append(bitsPerSample)

        header.append(contentsOf: Array("data".utf8))
        append(dataSize)

        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let out: FileHandle
        do {
            try Data().write(to: url)
            out = try FileHandle(forWritingTo: url)
        } catch {
            return .failed(error)
        }

        /// A half-written WAV left on disk is worse than no file — it would
        /// show up in the share sheet and play as noise.
        func discard() {
            try? out.close()
            try? fm.removeItem(at: url)
        }

        do {
            try out.write(contentsOf: header)
            try out.write(contentsOf: pcm16(head, scale: scale))

            if bodySamples > 0 {
                let body = try FileHandle(forReadingFrom: bodyURL)
                defer { try? body.close() }
                var remaining = bodySamples
                while remaining > 0 {
                    if isCanceled() {
                        discard()
                        return .canceled
                    }
                    let n = min(1 << 16, remaining)
                    guard let bytes = try body.read(upToCount: n * MemoryLayout<Float>.size),
                          !bytes.isEmpty, bytes.count % MemoryLayout<Float>.size == 0 else {
                        // A short raw file means the render was cut off; a
                        // truncated WAV with a full-length header is worse
                        // than no file.
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    let count = bytes.count / MemoryLayout<Float>.size
                    var floats = [Float](repeating: 0, count: count)
                    floats.withUnsafeMutableBytes { _ = bytes.copyBytes(to: $0) }
                    try out.write(contentsOf: pcm16(floats, scale: scale))
                    remaining -= count
                }
            }
            try out.close()
            return .success(url)
        } catch {
            discard()
            return .failed(error)
        }
    }

    /// RIFF stores its whole chunk size, including the 36 bytes around sample
    /// data, in one UInt32. Division avoids overflowing while checking.
    private static func fitsInWav(sampleCount: Int) -> Bool {
        sampleCount >= 0 && sampleCount <= (Int(UInt32.max) - 36) / 2
    }

    private static func pcm16(_ samples: [Float], scale: Float) -> Data {
        var ints = [Int16](repeating: 0, count: samples.count)
        for i in samples.indices {
            let clamped = max(-1.0, min(1.0, samples[i] * scale))
            ints[i] = Int16(clamped * 32767.0)
        }
        return ints.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
