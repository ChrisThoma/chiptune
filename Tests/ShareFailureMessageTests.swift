import XCTest
import AVFoundation
@testable import Chiptune

final class ShareFailureMessageTests: XCTestCase {
    private func cocoa(_ code: Int, _ text: String = "raw system text in the folder “share-ABC”") -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: code,
                userInfo: [NSLocalizedDescriptionKey: text])
    }

    func testLongNameIsClippedWithEllipsisAndAppearsOnce() {
        let name = String(repeating: "N", count: 300)
        let msg = ShareFailureMessage.songFile(name: name, error: cocoa(CocoaError.fileWriteUnknown.rawValue))
        XCTAssertFalse(msg.contains(name))
        XCTAssertTrue(msg.contains("…"))
        XCTAssertLessThan(msg.count, 140)
    }

    func testShortNameIsUntouched() {
        let msg = ShareFailureMessage.songFile(name: "Neon Ascent", error: cocoa(CocoaError.fileWriteUnknown.rawValue))
        XCTAssertTrue(msg.contains("“Neon Ascent”"))
        XCTAssertFalse(msg.contains("…"))
    }

    func testRawSystemTextAndFolderNamesAreNotPasted() {
        let msg = ShareFailureMessage.songFile(name: "A", error: cocoa(CocoaError.fileWriteUnknown.rawValue))
        XCTAssertFalse(msg.contains("raw system text"))
        XCTAssertFalse(msg.contains("share-"))
        XCTAssertTrue(msg.lowercased().contains("try again"))
    }

    /// Retrying can't fix a permission problem, so only that cause leaves
    /// "Try again" off. Freeing space and retrying can help, as can retrying
    /// an unknown failure.
    func testOnlyAPermissionCauseLeavesOffTryAgain() {
        let perm = cocoa(CocoaError.fileWriteNoPermission.rawValue)
        let space = cocoa(CocoaError.fileWriteOutOfSpace.rawValue)
        let other = cocoa(CocoaError.fileWriteUnknown.rawValue)
        for build in [ShareFailureMessage.songFile, WriteFailureMessage.save, WriteFailureMessage.export] {
            XCTAssertFalse(build("A", perm).contains("Try again"), build("A", perm))
            XCTAssertTrue(build("A", space).hasSuffix(" Try again."), build("A", space))
            XCTAssertTrue(build("A", other).hasSuffix(" Try again."), build("A", other))
        }
    }

    func testPermissionAndSpaceErrorsGetOneShortClue() {
        let perm = ShareFailureMessage.songFile(name: "A", error: cocoa(CocoaError.fileWriteNoPermission.rawValue))
        let space = ShareFailureMessage.songFile(name: "A", error: cocoa(CocoaError.fileWriteOutOfSpace.rawValue))
        let other = ShareFailureMessage.songFile(name: "A", error: cocoa(CocoaError.fileWriteUnknown.rawValue))
        XCTAssertTrue(perm.lowercased().contains("permission"))
        XCTAssertTrue(space.lowercased().contains("space"))
        XCTAssertNotEqual(perm, space)
        XCTAssertNotEqual(perm, other)
    }

    func testBlankNameStillReadsAsASentence() {
        let msg = ShareFailureMessage.songFile(name: "", error: cocoa(CocoaError.fileWriteUnknown.rawValue))
        XCTAssertTrue(msg.contains("song"))
    }
}

/// The Save failed alert, built from the same pieces as Share failed above.
final class SaveFailureMessageTests: XCTestCase {
    private func cocoa(_ code: Int) -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: code,
                userInfo: [NSLocalizedDescriptionKey: "You don’t have permission to save the file “0C1D.json” in the folder “Songs”."])
    }

    func testRawSystemTextIsNotPastedAndTheReasonIsKept() {
        let msg = WriteFailureMessage.save(name: "Neon Ascent", error: cocoa(CocoaError.fileWriteNoPermission.rawValue))
        XCTAssertEqual(msg, "Couldn't save “Neon Ascent”. The app doesn't have permission to write the song file.")
    }

    func testSpaceAndOtherReasonsDiffer() {
        let space = WriteFailureMessage.save(name: "A", error: cocoa(CocoaError.fileWriteOutOfSpace.rawValue))
        let other = WriteFailureMessage.save(name: "A", error: cocoa(CocoaError.fileWriteUnknown.rawValue))
        XCTAssertTrue(space.contains("enough free space"))
        XCTAssertTrue(other.contains("couldn't be written"))
        XCTAssertFalse(other.contains(".json"))
    }

    func testLongNameIsClipped() {
        let name = String(repeating: "N", count: 300)
        let msg = WriteFailureMessage.save(name: name, error: cocoa(CocoaError.fileWriteUnknown.rawValue))
        XCTAssertFalse(msg.contains(name))
        XCTAssertTrue(msg.contains("…"))
        XCTAssertLessThan(msg.count, 140)
    }
}

/// The Export failed alert's reason. A failed `FileHandle` write reports the
/// POSIX cause underneath a generic Cocoa write error, so the reason looks one
/// level down before giving up on naming it.
final class WriteFailureReasonTests: XCTestCase {
    func testAnUnderlyingPosixCauseIsNamed() {
        let full = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                           userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        let denied = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                             userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])
        XCTAssertEqual(WriteFailureMessage.reason(for: full, file: "WAV file"),
                       "There isn't enough free space to write the WAV file.")
        XCTAssertEqual(WriteFailureMessage.reason(for: denied, file: "WAV file"),
                       "The app doesn't have permission to write the WAV file.")
    }

    func testExportWordsMatchSaveAndShare() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
        XCTAssertEqual(WriteFailureMessage.export(name: "Neon Ascent", error: denied),
                       "Couldn't export “Neon Ascent”. The app doesn't have permission to write the WAV file.")
    }

    func testExportWordsNameTheFileThatFailed() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue)
        XCTAssertEqual(WriteFailureMessage.export(name: "Neon Ascent", error: denied, file: "MIDI file"),
                       "Couldn't export “Neon Ascent”. The app doesn't have permission to write the MIDI file.")
        XCTAssertEqual(ExportOptions.Format.midi.fileNoun, "MIDI file")
        XCTAssertEqual(ExportOptions.Format.wav.fileNoun, "WAV file")
    }

    /// The share failure reads the noun off the file that was offered, since
    /// the sheet's format may have been switched since the export finished.
    func testShareFailureNamesTheFileByItsExtension() {
        let dir = URL(fileURLWithPath: "/tmp/x", isDirectory: true)
        XCTAssertEqual(WriteFailureMessage.fileNoun(forExtension: "mid"), "MIDI file")
        XCTAssertEqual(WriteFailureMessage.fileNoun(forExtension: "MID"), "MIDI file")
        XCTAssertEqual(WriteFailureMessage.fileNoun(forExtension: "wav"), "WAV file")
        XCTAssertEqual(WriteFailureMessage.fileNoun(for: dir.appendingPathComponent("a.mid")), "MIDI file")
        XCTAssertEqual(WriteFailureMessage.fileNoun(for: dir.appendingPathComponent("a.wav")), "WAV file")
    }

    /// The same rule as Android's, which shares song files through the same
    /// path: anything that isn't a WAV or MIDI export is a song file.
    func testAFileThatIsntAnExportIsASongFile() {
        XCTAssertEqual(WriteFailureMessage.fileNoun(forExtension: "chipsong"), "song file")
        XCTAssertEqual(WriteFailureMessage.fileNoun(forExtension: ""), "song file")
        XCTAssertEqual(WriteFailureMessage.fileNoun(forExtension: "txt"), "song file")
    }

    func testAnUnknownCauseSaysSoPlainly() {
        let unknown = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue)
        XCTAssertEqual(WriteFailureMessage.reason(for: unknown, file: "WAV file"),
                       "The WAV file couldn't be written.")
    }
}

/// Delete failed, Import failed and the share sheet's own Share failed: the
/// rest of the alerts that used to paste the system's text, which can name a
/// song's internal UUID file.
final class DeleteFailureMessageTests: XCTestCase {
    private let raw = "“0C1D-4E2F.json” couldn’t be removed because you don’t have permission to access it."

    func testPermissionNamesTheCauseWithoutTryAgain() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteNoPermission.rawValue,
                             userInfo: [NSLocalizedDescriptionKey: raw])
        XCTAssertEqual(DeleteFailureMessage.song(name: "Doomed", error: denied),
                       "Couldn't delete “Doomed”. The app doesn't have permission to change that file.")
    }

    func testAnUnknownCauseSaysTryAgainAndNothingRaw() {
        let unknown = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
                              userInfo: [NSLocalizedDescriptionKey: raw])
        XCTAssertEqual(DeleteFailureMessage.song(name: "Doomed", error: unknown),
                       "Couldn't delete “Doomed”. Try again.")
    }
}

final class ImportFailureMessageTests: XCTestCase {
    func testAFileThatIsNotASong() {
        XCTAssertEqual(ImportFailureMessage.file(error: SongDocument.ImportError.notASong),
                       "Couldn't import the file. It isn't a Chiptune song, or it's damaged.")
    }

    func testAFileThatCannotBeRead() {
        XCTAssertEqual(ImportFailureMessage.file(error: SongDocument.ImportError.unreadable),
                       "Couldn't import the file. Something went wrong reading it. Try again.")
        let other = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "raw picker text"])
        XCTAssertEqual(ImportFailureMessage.file(error: other),
                       "Couldn't import the file. Something went wrong reading it. Try again.")
    }

    func testAFileTheAppMayNotRead() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue)
        XCTAssertEqual(ImportFailureMessage.file(error: denied),
                       "Couldn't import the file. The app doesn't have permission to read it.")
    }

    func testASongThatCannotBeSavedReadsLikeSaveFailed() {
        let full = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue,
                           userInfo: [NSLocalizedDescriptionKey: "raw text naming 0C1D.json"])
        XCTAssertEqual(ImportFailureMessage.save(name: "Neon Ascent", error: full),
                       "Couldn't import “Neon Ascent”. There isn't enough free space to write the song file. Try again.")
    }
}

final class ShareSheetFailureMessageTests: XCTestCase {
    func testTheSheetsOwnFailureNamesTheFileAndNothingRaw() {
        XCTAssertEqual(ShareFailureMessage.sheet(file: "song file"), "Couldn't share the song file. Try again.")
        XCTAssertEqual(ShareFailureMessage.sheet(file: "WAV file"), "Couldn't share the WAV file. Try again.")
    }
}

/// Save Video with Photos access turned down. Retrying can't help until
/// access is given, so it gets an alert of its own with a way to Settings
/// rather than the plain "Share failed" one.
final class PhotosDeniedShareMessageTests: XCTestCase {

    /// Exactly what the share sheet reported on the simulator after Don't
    /// Allow: an "unknown" assets-library error wrapping Photos' own
    /// access-denied code.
    func testTheShareSheetsDeniedErrorIsPhotosDenied() {
        let denied = NSError(domain: "ALAssetsLibraryErrorDomain", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Unknown error",
            NSUnderlyingErrorKey: NSError(domain: "PHPhotosErrorDomain", code: 3311),
        ])
        XCTAssertEqual(ShareFailureMessage.sheetFailure(file: "video", error: denied), .photosDenied)
    }

    func testPhotosAndAssetsLibraryDeniedCodesArePhotosDenied() {
        XCTAssertEqual(ShareFailureMessage.sheetFailure(file: "video",
                                                        error: NSError(domain: "PHPhotosErrorDomain", code: 3311)),
                       .photosDenied)
        XCTAssertEqual(ShareFailureMessage.sheetFailure(file: "video",
                                                        error: NSError(domain: "ALAssetsLibraryErrorDomain", code: -3311)),
                       .photosDenied)
    }

    func testAnyOtherShareFailureStillSaysTryAgain() {
        let other = NSError(domain: "ALAssetsLibraryErrorDomain", code: -1)
        XCTAssertEqual(ShareFailureMessage.sheetFailure(file: "video", error: other),
                       .message("Couldn't share the video. Try again."))
    }

    func testThePhotosAlertSaysWhereToFixIt() {
        XCTAssertEqual(PhotosDeniedAlert.title, "Chiptune can't save to Photos")
        XCTAssertEqual(PhotosDeniedAlert.message, "Allow Chiptune to add videos to Photos in Settings, then try again.")
        XCTAssertEqual(PhotosDeniedAlert.openSettings, "Open Settings")
    }
}

/// Coming back from Settings after the Photos alert brings the share sheet
/// back with the video already rendered, rather than sending the user
/// through another render.
final class PhotosRetryTests: XCTestCase {
    private let song = UUID()
    private let url = URL(fileURLWithPath: "/tmp/x/Song.mp4")

    func testTheSameVideoIsOfferedAgain() {
        let retry = PhotosRetry(url: url, songID: song)
        XCTAssertTrue(retry.reshares(exportURL: url, currentSongID: song, fileExists: true, anyPresented: false))
    }

    func testNotWhenAnotherSongIsOpen() {
        let retry = PhotosRetry(url: url, songID: song)
        XCTAssertFalse(retry.reshares(exportURL: url, currentSongID: UUID(), fileExists: true, anyPresented: false))
    }

    func testNotWhenTheVideoIsGoneOrReplaced() {
        let retry = PhotosRetry(url: url, songID: song)
        XCTAssertFalse(retry.reshares(exportURL: url, currentSongID: song, fileExists: false, anyPresented: false))
        XCTAssertFalse(retry.reshares(exportURL: nil, currentSongID: song, fileExists: true, anyPresented: false))
        XCTAssertFalse(retry.reshares(exportURL: URL(fileURLWithPath: "/tmp/x/Other.mp4"),
                                      currentSongID: song, fileExists: true, anyPresented: false))
    }

    /// Something else came up in the meantime; a second presentation would
    /// be refused by UIKit and fire later on some unrelated dismissal.
    func testNotOverSomethingElse() {
        let retry = PhotosRetry(url: url, songID: song)
        XCTAssertFalse(retry.reshares(exportURL: url, currentSongID: song, fileExists: true, anyPresented: true))
    }
}

/// The video writer reports a full disk in its own domain, not as a Cocoa or
/// POSIX error.
final class VideoWriteFailureCauseTests: XCTestCase {
    func testAVFoundationsDiskFullIsASpaceProblem() {
        let full = NSError(domain: AVFoundationErrorDomain, code: AVError.diskFull.rawValue)
        XCTAssertEqual(WriteFailureMessage.cause(of: full), .space)
        XCTAssertEqual(WriteFailureMessage.export(name: "Clip", error: full, file: "video"),
                       "Couldn't export “Clip”. There isn't enough free space to write the video. Try again.")
    }
}
