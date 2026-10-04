import XCTest
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
        let msg = ShareFailureMessage.songFile(name: "A", error: cocoa(CocoaError.fileWriteNoPermission.rawValue))
        XCTAssertFalse(msg.contains("raw system text"))
        XCTAssertFalse(msg.contains("share-"))
        XCTAssertTrue(msg.lowercased().contains("try again"))
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
        XCTAssertEqual(msg, "Couldn't save “Neon Ascent”. The app doesn't have permission to write the song file. Try again.")
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
                       "Couldn't export “Neon Ascent”. The app doesn't have permission to write the WAV file. Try again.")
    }

    func testAnUnknownCauseSaysSoPlainly() {
        let unknown = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue)
        XCTAssertEqual(WriteFailureMessage.reason(for: unknown, file: "WAV file"),
                       "The WAV file couldn't be written.")
    }
}
