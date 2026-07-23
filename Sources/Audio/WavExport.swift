import Foundation

/// Renders a song offline and writes it out as a 16-bit mono WAV.
enum WavExport {
    static let sampleRate = 44100.0

    /// - Parameter repeats: how many times the pattern loops in the file.
    /// - Returns: the URL of the written file, or nil if writing failed.
    static func render(song: Song, repeats: Int = 4) -> URL? {
        var song = song
        song.normalize()

        let core = ChipCore(sampleRate: sampleRate)
        core.load(song: song)
        core.start()

        let samplesPerStep = Int((sampleRate * 60.0 / (song.tempo * 4.0)).rounded())
        let loopSamples = samplesPerStep * song.length * max(repeats, 1)
        // Extra second so the final note's decay isn't clipped off.
        let tail = Int(sampleRate)
        let total = loopSamples + tail

        var floats = [Float](repeating: 0, count: total)
        floats.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            // Render in chunks; the tail runs with the sequencer stopped so
            // nothing new is triggered while the envelopes ring out.
            let chunk = 4096
            var written = 0
            while written < loopSamples {
                let n = min(chunk, loopSamples - written)
                core.render(frames: n, into: base + written)
                written += n
            }
            core.playing = false
            while written < total {
                let n = min(chunk, total - written)
                core.render(frames: n, into: base + written)
                written += n
            }
        }

        return writeWav(samples: floats, to: filename(for: song))
    }

    private static func filename(for song: Song) -> URL {
        let safe = song.name
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let base = safe.isEmpty ? "chiptune" : safe
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(base).wav")
    }

    private static func writeWav(samples: [Float], to url: URL) -> URL? {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)

        var data = Data()
        func append<T>(_ value: T) {
            var v = value
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))

        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))            // PCM chunk size
        append(UInt16(1))             // PCM format
        append(channels)
        append(UInt32(sampleRate))
        append(byteRate)
        append(blockAlign)
        append(bitsPerSample)

        data.append(contentsOf: Array("data".utf8))
        append(dataSize)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            append(Int16(clamped * 32767.0))
        }

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            print("WAV export failed: \(error)")
            return nil
        }
    }
}
