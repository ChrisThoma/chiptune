import XCTest
@testable import Chiptune

/// Help copy says "Tap" on a touch screen and "Click" with a pointer. The
/// strings are written once, for iOS; the Mac reads them through
/// `PlatformWording`.
final class PlatformWordingTests: XCTestCase {

    func testTapBecomesClick() {
        XCTAssertEqual(PlatformWording.forPointer("Tap a key to hear that note."),
                       "Click a key to hear that note.")
        XCTAssertEqual(PlatformWording.forPointer("Tap REST, then tap a step."),
                       "Click REST, then click a step.")
        XCTAssertEqual(PlatformWording.forPointer("Tap"), "Click")
    }

    /// iOS's long press is the Mac's right-click.
    func testHoldingANoteOrAPatternBecomesARightClick() {
        XCTAssertEqual(PlatformWording.forPointer("Hold a note"), "Right-click a note")
        XCTAssertEqual(PlatformWording.forPointer("Hold a note to pick one."),
                       "Right-click a note to pick one.")
        XCTAssertEqual(PlatformWording.forPointer("Tap one to edit it. Hold one to rename it."),
                       "Click one to edit it. Right-click one to rename it.")
    }

    /// Only whole words: "tapping", "Taproom", a tempo "tap" inside another
    /// word are left alone.
    func testOnlyWholeWordsChange() {
        XCTAssertEqual(PlatformWording.forPointer("tapping Taproom"), "tapping Taproom")
        XCTAssertEqual(PlatformWording.forPointer("to hold a section for longer"),
                       "to hold a section for longer")
    }

    func testEveryHelpEntryReadsForAPointer() {
        for section in HelpGuide.sections {
            for entry in section.entries {
                for text in [entry.term, entry.text] {
                    let mac = PlatformWording.forPointer(text)
                    XCTAssertNil(mac.range(of: #"\b[Tt]ap\b"#, options: .regularExpression), mac)
                }
            }
        }
    }

    /// The iOS build reads every string unchanged.
    func testThePlatformWordingIsThePointerOneOnlyOnTheMac() {
        let text = "Tap a key. Hold a note."
        #if os(macOS)
        XCTAssertEqual(PlatformWording.adapt(text), PlatformWording.forPointer(text))
        #else
        XCTAssertEqual(PlatformWording.adapt(text), text)
        #endif
    }
}
