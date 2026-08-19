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

    /// Passes of the whole arrangement.
    var loopCount: Int = 1
    var tailMode: TailMode = .seamlessLoop

    static let maxLoopCount = 16

    var clamped: ExportOptions {
        var copy = self
        copy.loopCount = min(max(loopCount, 1), ExportOptions.maxLoopCount)
        return copy
    }
}

/// The outcome of an export. Cancelling is not failing: the UI must not show
/// an error for a file the user decided they didn't want.
enum ExportResult: Sendable {
    case success(URL)
    case cancelled
    case failed
}

/// Everything one export needs. Bundled into a struct so the injectable
/// renderer stays a one-argument function as it grows.
struct ExportRequest: Sendable {
    var song: Song
    var options: ExportOptions = ExportOptions()
    /// Called with 0...1 as the render proceeds, on the rendering thread.
    var progress: @Sendable (Double) -> Void = { _ in }
    /// Polled at chunk boundaries. Returning true abandons the render.
    var isCancelled: @Sendable () -> Bool = { false }
}

/// Renders a song offline and writes it out as a 16-bit mono WAV.
enum WavExport {
    static let sampleRate = 44100.0
    private static let chunk = 4096
    /// How long the last notes are given to decay past the end.
    private static let tailSeconds = 1.0

    /// Why a render stopped early. Thrown out of the streaming loops so a
    /// cancel or a failed write unwinds in one hop rather than threading an
    /// optional result out of a pointer closure.
    private enum RenderAbort: Error {
        case cancelled, failed
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
    static func render(_ request: ExportRequest) -> ExportResult {
        var song = request.song
        song.normalize()
        let options = request.options.clamped
        let folding = options.tailMode == .seamlessLoop

        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.setSongMode(true)
        core.start()

        let samplesPerStep = Chip.samplesPerStep(tempo: song.tempo, sampleRate: sampleRate)
        let onePass = samplesPerStep * max(song.arrangementSteps, 1)
        // The chain wraps on its own, so N passes are just a longer render.
        let bodySamples = onePass * options.loopCount
        let tail = Int(sampleRate * tailSeconds)

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
        let rawURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".raw")
        guard fm.createFile(atPath: rawURL.path, contents: nil),
              let raw = try? FileHandle(forWritingTo: rawURL) else { return .failed }
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
                if request.isCancelled() { throw RenderAbort.cancelled }
                let n = min(chunk, bodySamples - written)
                core.render(frames: n, into: base)
                let inHead = max(0, min(n, headLen - written))
                for i in 0..<inHead { head[written + i] = base[i] }
                if n > inHead {
                    for i in inHead..<n { bodyPeak = max(bodyPeak, abs(base[i])) }
                    let bytes = Data(bytes: base + inHead,
                                     count: (n - inHead) * MemoryLayout<Float>.size)
                    do { try raw.write(contentsOf: bytes) } catch { throw RenderAbort.failed }
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
                if request.isCancelled() { throw RenderAbort.cancelled }
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
                    do { try raw.write(contentsOf: bytes) } catch { throw RenderAbort.failed }
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
            return (error as? RenderAbort) == .cancelled ? .cancelled : .failed
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
                              isCancelled: request.isCancelled,
                              to: filename(for: song))
        if case .success = result { report(totalFrames) }
        return result
    }

    private static func filename(for song: Song) -> URL {
        let safe = song.name
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let base = safe.isEmpty ? "chiptune" : safe
        // A per-song directory keeps the shared file's display name clean while
        // stopping two same-named songs from overwriting each other's export.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(song.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(base).wav")
    }

    /// Streams the folded head plus the raw body file out as a WAV, converting
    /// to 16-bit in chunks so the whole song is never in memory twice.
    private static func writeWav(head: [Float], bodyURL: URL, bodySamples: Int,
                                 scale: Float,
                                 isCancelled: @Sendable () -> Bool,
                                 to url: URL) -> ExportResult {
        let totalSamples = head.count + bodySamples
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)

        // WAV's RIFF header caps a chunk at 32 bits; a render big enough to
        // overflow it can't be written as a valid WAV at all, so fail the
        // export instead of trapping the UInt32 conversion.
        let dataByteCount = totalSamples * 2
        guard dataByteCount <= Int(UInt32.max), 36 + dataByteCount <= Int(UInt32.max) else {
            return .failed
        }
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
        guard fm.createFile(atPath: url.path, contents: nil),
              let out = try? FileHandle(forWritingTo: url) else { return .failed }

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
                    if isCancelled() {
                        discard()
                        return .cancelled
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
            return .failed
        }
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
