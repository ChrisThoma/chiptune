import XCTest
import AVFoundation
@testable import Chiptune

/// The live-audio contract: however many frames Core Audio asks for, every one
/// of them is real rendered audio — byte-identical to what the synth would
/// have produced rendering the same stretch in a single call.
final class AudioCallbackTests: XCTestCase {

    /// A song with notes on every channel so the render is audibly nonzero
    /// well past any internal buffer size.
    private func makeSong() -> Song {
        var song = Song(name: "CallbackTest")
        song.tempo = 240
        // Long decays so sound persists across the whole window under test.
        for i in song.tracks.indices { song.tracks[i].instrument.sustain = true }
        song.patterns[0].rows[0][0] = 60
        song.patterns[0].rows[1][4] = 64
        song.patterns[0].rows[2][8] = 48
        song.patterns[0].rows[3][12] = 60
        return song
    }

    /// The synth is deterministic (the noise channel is a seeded LFSR), so two
    /// cores loaded and started identically must produce identical streams.
    private func makeStartedCore(song: Song) -> ChipCore {
        let core = ChipCore(sampleRate: 44100)
        core.load(song: song)
        core.start()
        return core
    }

    func testCallbackFillMatchesStraightRenderBeyondScratchSize() {
        let song = makeSong()
        let scratchLen = 4096
        // Deliberately larger than the scratch, and not a multiple of it.
        let frames = 10_000

        // Ground truth: an identical core rendering the same stretch in one call.
        var reference = [Float](repeating: 0, count: frames)
        reference.withUnsafeMutableBufferPointer { buf in
            makeStartedCore(song: song).render(frames: frames, into: buf.baseAddress!)
        }

        // The reference must actually contain audio past the scratch boundary,
        // otherwise this test could pass against a callback that silences
        // everything beyond one scratch's worth.
        let energyPastScratch = reference[scratchLen...].contains { abs($0) > 0.001 }
        XCTAssertTrue(energyPastScratch,
                      "test song must produce audio beyond \(scratchLen) frames for this test to mean anything")

        // Drive the fill the way the source node does: a deinterleaved stereo
        // buffer list, pre-poisoned so untouched frames are detectable.
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        pcm.frameLength = AVAudioFrameCount(frames)
        for ch in 0..<2 {
            let data = pcm.floatChannelData![ch]
            for i in 0..<frames { data[i] = .nan }
        }

        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: scratchLen)
        scratch.initialize(repeating: 0, count: scratchLen)
        defer { scratch.deallocate() }

        AudioEngine.fill(pcm.mutableAudioBufferList, frames: frames,
                         from: makeStartedCore(song: song),
                         scratch: scratch, scratchLen: scratchLen)

        for ch in 0..<2 {
            let data = pcm.floatChannelData![ch]
            for i in 0..<frames {
                XCTAssertFalse(data[i].isNaN,
                               "channel \(ch) frame \(i) was never written")
                XCTAssertEqual(data[i], reference[i],
                               "channel \(ch) frame \(i) differs from a straight render")
                if data[i] != reference[i] || data[i].isNaN { return }
            }
        }
    }

    func testCallbackFillHandlesRequestSmallerThanScratch() {
        let song = makeSong()
        let frames = 512

        var reference = [Float](repeating: 0, count: frames)
        reference.withUnsafeMutableBufferPointer { buf in
            makeStartedCore(song: song).render(frames: frames, into: buf.baseAddress!)
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        pcm.frameLength = AVAudioFrameCount(frames)
        for ch in 0..<2 {
            let data = pcm.floatChannelData![ch]
            for i in 0..<frames { data[i] = .nan }
        }

        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 4096)
        scratch.initialize(repeating: 0, count: 4096)
        defer { scratch.deallocate() }

        AudioEngine.fill(pcm.mutableAudioBufferList, frames: frames,
                         from: makeStartedCore(song: song),
                         scratch: scratch, scratchLen: 4096)

        for ch in 0..<2 {
            let data = pcm.floatChannelData![ch]
            for i in 0..<frames where data[i] != reference[i] {
                XCTFail("channel \(ch) frame \(i) differs from a straight render")
                return
            }
        }
    }
}
