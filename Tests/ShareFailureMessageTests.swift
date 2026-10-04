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
