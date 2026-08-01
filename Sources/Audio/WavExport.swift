import Foundation

/// Renders a song offline and writes it out as a 16-bit mono WAV.
enum WavExport {
    static let sampleRate = 44100.0
    private static let chunk = 4096

    /// Renders the whole arrangement exactly once, as a seamless loop: the file is
    /// precisely one pass long and its final notes ring on into its own start, so
    /// playing it on repeat is indistinguishable from the sequencer running on.
    ///
    /// The render is memory-bounded: a max-length arrangement at low BPM runs to
    /// hundreds of MB of floats, so everything past the first second streams
    /// through a raw temp file instead of living in one giant buffer. Only the
    /// opening stretch stays resident, because the tail folds over it.
    ///
    /// - Returns: the URL of the written file, or nil if writing failed.
    static func render(song: Song) -> URL? {
        var song = song
        song.normalize()

        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.setSongMode(true)
        core.start()

        let samplesPerStep = Int((sampleRate * 60.0 / (song.tempo * 4.0)).rounded())
        let loopSamples = samplesPerStep * max(song.arrangementSteps, 1)
        // Rendered past the end so the final note's decay isn't clipped off, then
        // folded back over the start rather than left as trailing silence.
        let tail = Int(sampleRate)

        let fm = FileManager.default
        let rawURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".raw")
        guard fm.createFile(atPath: rawURL.path, contents: nil),
              let raw = try? FileHandle(forWritingTo: rawURL) else { return nil }
        defer { try? fm.removeItem(at: rawURL) }

        // The stretch the tail folds over. Kept in memory; everything after it
        // goes straight to the raw file. Wraps in case a very short song runs
        // shorter than the tail itself.
        let headLen = min(tail, loopSamples)
        var head = [Float](repeating: 0, count: headLen)
        var bodyPeak: Float = 0

        var scratch = [Float](repeating: 0, count: chunk)
        var renderOK = true
        scratch.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { renderOK = false; return }
            var written = 0
            while written < loopSamples {
                let n = min(chunk, loopSamples - written)
                core.render(frames: n, into: base)
                let inHead = max(0, min(n, headLen - written))
                for i in 0..<inHead { head[written + i] = base[i] }
                if n > inHead {
                    for i in inHead..<n { bodyPeak = max(bodyPeak, abs(base[i])) }
                    let bytes = Data(bytes: base + inHead,
                                     count: (n - inHead) * MemoryLayout<Float>.size)
                    do { try raw.write(contentsOf: bytes) } catch {
                        renderOK = false
                        return
                    }
                }
                written += n
            }
        }
        try? raw.close()
        guard renderOK else { return nil }

        // The tail runs with the sequencer stopped so nothing new is triggered
        // while the envelopes ring out. A second of mono floats is small enough
        // to hold whole.
        core.finish()
        var tailBuf = [Float](repeating: 0, count: tail)
        tailBuf.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            var done = 0
            while done < tail {
                let n = min(chunk, tail - done)
                core.render(frames: n, into: base + done)
                done += n
            }
        }

        // Fold the tail over the start. Played on repeat, the file's last notes
        // ring on into the beginning exactly as they would have if the sequencer
        // had kept running — a seamless loop with no trailing dead air.
        for i in 0..<tail {
            head[i % headLen] += tailBuf[i]
        }

        // Summing the overlap can push it past full scale. Scale the whole file
        // rather than letting the write clamp it: clamping would distort only the
        // overlap, which is precisely the seam the fold exists to hide.
        var peak = bodyPeak
        for s in head { peak = max(peak, abs(s)) }
        let scale: Float = peak > 1 ? 1 / peak : 1

        return writeWav(head: head,
                        bodyURL: rawURL,
                        bodySamples: loopSamples - headLen,
                        scale: scale,
                        to: filename(for: song))
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
                                 scale: Float, to url: URL) -> URL? {
        let totalSamples = head.count + bodySamples
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(totalSamples * 2)

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
              let out = try? FileHandle(forWritingTo: url) else { return nil }

        do {
            try out.write(contentsOf: header)
            try out.write(contentsOf: pcm16(head, scale: scale))

            if bodySamples > 0 {
                let body = try FileHandle(forReadingFrom: bodyURL)
                defer { try? body.close() }
                var remaining = bodySamples
                while remaining > 0 {
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
            return url
        } catch {
            print("WAV export failed: \(error)")
            try? out.close()
            try? fm.removeItem(at: url)
            return nil
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
