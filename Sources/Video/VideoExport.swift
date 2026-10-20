import AVFoundation
import CoreVideo

/// Renders a song as a 1080×1920, 30 fps H.264/AAC mp4 for Reels, TikTok and
/// Shorts.
///
/// Audio first, then pictures: the soundtrack is rendered by `WavExport` to a
/// scratch WAV (the first 30% of the progress bar), then every frame is drawn
/// by `VideoFrameRenderer` and written alongside that audio by one
/// `AVAssetWriter` (the rest). Frame `f` shows sample `f × 1470` of the same
/// render, through `VideoTimeline`, so the picture cannot drift from the
/// sound.
///
/// Nothing half-made is left behind. The WAV and the mp4 being written both
/// live in `scratchDirectory`, outside the per-song export folder so neither
/// clobbers the user's last WAV nor gets swept by `ExportFiles.pruneStale`,
/// and both are deleted however the export ends. The finished mp4 is moved
/// over the song's previous video only once it's complete, so a failure or a
/// cancel keeps the old one.
enum VideoExport {
    /// TikTok's upload limit, the longest of the three. WAV's own limit is
    /// about 13 hours, which says nothing useful about a video.
    static let maxSeconds = 600.0

    static var scratchDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("video-scratch", isDirectory: true)
    }

    /// The share of the progress bar the soundtrack takes. Drawing and
    /// encoding the frames is most of the work.
    private static let audioShare = 0.3

    /// Test seams into the middle of a render. The app never passes any.
    struct Hooks {
        /// Draws frame `f` in place of `VideoFrameRenderer`, for a test that
        /// needs a picture it knows exactly.
        var draw: ((Int, CGContext) -> Void)?
        /// Runs once the writer has finished the file, before it is moved
        /// over the song's previous video.
        var finishedWriting: () -> Void = {}
    }

    /// Async only where AVFoundation is waited on: loading the soundtrack's
    /// track and finishing the file. Those used to block on a semaphore, and
    /// AVFoundation calls its completion handlers back at default QoS, below
    /// the user-initiated render waiting on them: a priority inversion the
    /// waiting thread could do nothing about. Awaited, nothing is parked.
    /// The rest of the render is the same synchronous loop.
    static func render(_ request: ExportRequest, hooks: Hooks = Hooks()) async -> ExportResult {
        var song = request.song
        song.normalize()
        var options = request.options.clamped
        options.format = .video
        let timeline = VideoTimeline(song: song, options: options)
        // Checked from the timeline before anything is rendered: finding out
        // after minutes of drawing frames would waste them on a predictable
        // refusal.
        guard timeline.seconds <= maxSeconds else { return .tooLong }

        let fm = FileManager.default
        do {
            // A render killed mid-way (a crash, the app terminated in the
            // background) never reached its cleanup. Only one export runs at
            // a time — `Studio.export` refuses a second while `isExporting` —
            // so whatever is in here belongs to a dead one.
            if fm.fileExists(atPath: scratchDirectory.path) {
                try fm.removeItem(at: scratchDirectory)
            }
            try fm.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        } catch {
            return .failed(error)
        }
        let stem = UUID().uuidString
        let soundtrack = scratchDirectory.appendingPathComponent(stem + ".wav")
        let partial = scratchDirectory.appendingPathComponent(stem + ".mp4")
        defer {
            try? fm.removeItem(at: soundtrack)
            try? fm.removeItem(at: partial)
        }

        var audioRequest = request
        audioRequest.song = song
        audioRequest.options = options
        audioRequest.progress = { request.progress($0 * audioShare) }
        let audio = WavExport.render(audioRequest, to: soundtrack)
        guard case .success = audio else { return audio }

        let renderer = VideoFrameRenderer(song: song, options: options, timeline: timeline)
        let draw = hooks.draw ?? { renderer.draw(frame: $0, in: $1) }
        let encoded = await encode(timeline: timeline, draw: draw, soundtrack: soundtrack,
                                   to: partial, request: request)
        guard case .success = encoded else { return encoded }
        hooks.finishedWriting()
        // Finishing the file takes a moment, and a cancel tapped during it
        // is still a cancel: the previous video stays and nothing is shared.
        guard !request.isCanceled() else { return .canceled }

        let destination = ExportFiles.url(for: song, format: .video)
        do {
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: partial)
            } else {
                try fm.moveItem(at: partial, to: destination)
            }
        } catch {
            return .failed(error)
        }
        request.progress(1)
        return .success(destination)
    }

    // MARK: Encoding

    private static let width = Int(VideoLayout.size.width)
    private static let height = Int(VideoLayout.size.height)

    /// H.264 at 8 Mbit/s, tagged explicitly so players don't guess at the
    /// Theme colours.
    ///
    /// The frames are drawn in sRGB, so the stream says sRGB's transfer
    /// function. Tagged BT.709 (as it was), an Apple player decoded the
    /// sRGB-encoded values with 709's curve and showed every mid-grey
    /// lighter: the cartridge's #BDBAB3 plastic came back as #C5C2BC. A
    /// player that ignores the tag shows the values as drawn either way.
    /// The primaries and matrix stay 709, which sRGB shares. A system whose
    /// writer won't take the sRGB tag gets the 709 one rather than no video.
    private static func videoSettings(for writer: AVAssetWriter) -> [String: Any] {
        func settings(transfer: String) -> [String: Any] {
            [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: transfer,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoExpectedSourceFrameRateKey: VideoTimeline.fps,
                    AVVideoMaxKeyFrameIntervalKey: VideoTimeline.fps * 2,
                ],
            ]
        }
        let srgb = settings(transfer: kCVImageBufferTransferFunction_sRGB as String)
        return writer.canApply(outputSettings: srgb, forMediaType: .video)
            ? srgb
            : settings(transfer: AVVideoTransferFunction_ITU_R_709_2)
    }

    /// Writes every frame and the soundtrack into `url`. The two inputs are
    /// fed from one loop, each whenever the writer is ready for it, so the
    /// writer's interleaving never waits on a stream that isn't being fed.
    private static func encode(timeline: VideoTimeline, draw: (Int, CGContext) -> Void,
                               soundtrack: URL, to url: URL, request: ExportRequest) async -> ExportResult {
        let writer: AVAssetWriter
        let reader: AVAssetReader
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            reader = try AVAssetReader(asset: AVURLAsset(url: soundtrack))
        } catch {
            return .failed(error)
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(for: writer))
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: WavExport.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
        ])
        audioInput.expectsMediaDataInRealTime = false

        guard let audioTrack = try? await reader.asset.loadTracks(withMediaType: .audio).first else {
            return .failed(CocoaError(.fileReadCorruptFile))
        }
        let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard writer.canAdd(videoInput), writer.canAdd(audioInput), reader.canAdd(audioOutput) else {
            return .failed(CocoaError(.fileWriteUnknown))
        }
        writer.add(videoInput)
        writer.add(audioInput)
        reader.add(audioOutput)

        guard writer.startWriting() else { return .failed(writer.error ?? CocoaError(.fileWriteUnknown)) }
        guard reader.startReading() else {
            writer.cancelWriting()
            return .failed(reader.error ?? CocoaError(.fileReadUnknown))
        }
        writer.startSession(atSourceTime: .zero)

        func abandon() {
            reader.cancelReading()
            writer.cancelWriting()
        }

        let totalFrames = timeline.totalFrames
        var frame = 0
        var audioDone = false
        var reported = audioShare
        while frame < totalFrames || !audioDone {
            // Each pass drains its own autoreleased objects — the pixel
            // buffer, the audio sample buffer, whatever AVFoundation hands
            // back — rather than letting a ten-minute render pile them up
            // until the loop ends. nil carries on; a result ends the render.
            let outcome: ExportResult? = autoreleasepool {
                if request.isCanceled() {
                    abandon()
                    return .canceled
                }
                var moved = false
                if frame < totalFrames, videoInput.isReadyForMoreMediaData {
                    guard let buffer = drawFrame(frame, draw: draw, pool: adaptor.pixelBufferPool),
                          adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame),
                                                                              timescale: CMTimeScale(VideoTimeline.fps))) else {
                        let error = writer.error ?? CocoaError(.fileWriteUnknown)
                        abandon()
                        return .failed(error)
                    }
                    frame += 1
                    if frame == totalFrames { videoInput.markAsFinished() }
                    moved = true
                    // At most a hundred hops to the main actor, as the WAV
                    // render does.
                    let fraction = audioShare + (1 - audioShare) * Double(frame) / Double(totalFrames)
                    if fraction - reported >= 0.01, fraction < 1 {
                        reported = fraction
                        request.progress(fraction)
                    }
                }
                if !audioDone, audioInput.isReadyForMoreMediaData {
                    if let sample = audioOutput.copyNextSampleBuffer() {
                        guard audioInput.append(sample) else {
                            let error = writer.error ?? CocoaError(.fileWriteUnknown)
                            abandon()
                            return .failed(error)
                        }
                    } else {
                        if reader.status == .failed {
                            let error = reader.error ?? CocoaError(.fileReadUnknown)
                            abandon()
                            return .failed(error)
                        }
                        audioInput.markAsFinished()
                        audioDone = true
                    }
                    moved = true
                }
                if writer.status == .failed {
                    let error = writer.error ?? CocoaError(.fileWriteUnknown)
                    abandon()
                    return .failed(error)
                }
                // Neither input wants anything yet: the encoders are busy.
                if !moved { usleep(1000) }
                return nil
            }
            if let outcome { return outcome }
        }

        // The last frame stays up to the end of the audio, so the file is as
        // long as its soundtrack rather than rounded up to a whole frame.
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(timeline.totalSamples),
                                               timescale: CMTimeScale(WavExport.sampleRate)))
        await writer.finishWriting()
        guard writer.status == .completed else {
            return .failed(writer.error ?? CocoaError(.fileWriteUnknown))
        }
        return .success(url)
    }

    private static func drawFrame(_ frame: Int, draw: (Int, CGContext) -> Void,
                                  pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var made: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made) == kCVReturnSuccess,
              let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: Palette.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // UIKit's orientation: y runs down from the top, as VideoLayout's does.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(frame, context)
        return buffer
    }
}
