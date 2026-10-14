import XCTest
@testable import Chiptune

final class TempoEntryTests: XCTestCase {
    func testWholeNumbersInRangeAreAccepted() {
        XCTAssertEqual(TempoEntry.bpm(from: "120"), 120)
        XCTAssertEqual(TempoEntry.bpm(from: " 40 "), 40)
        XCTAssertEqual(TempoEntry.bpm(from: "300"), 300)
    }

    /// 1280 used to be quietly turned into 300 by Set.
    func testOutOfRangeEntryIsRejectedRatherThanClamped() {
        XCTAssertNil(TempoEntry.bpm(from: "1280"))
        XCTAssertNil(TempoEntry.bpm(from: "39"))
        XCTAssertNil(TempoEntry.bpm(from: "301"))
        XCTAssertNil(TempoEntry.bpm(from: "0"))
    }

    func testBlankOrNonNumericEntryIsRejected() {
        XCTAssertNil(TempoEntry.bpm(from: ""))
        XCTAssertNil(TempoEntry.bpm(from: "  "))
        XCTAssertNil(TempoEntry.bpm(from: "abc"))
    }
}

/// `configure` runs again on every redraw of the transport while the tempo
/// alert is up. It must leave one edit handler on the field, not one more
/// each time.
final class TempoEntryConfigureTests: XCTestCase {

    private func editingChangedHandlers(_ field: UITextField) -> Int {
        var count = 0
        field.enumerateEventHandlers { _, _, event, _ in
            if event == .editingChanged { count += 1 }
        }
        return count
    }

    func testConfiguringTwiceLeavesOneEditHandler() {
        let field = UITextField()
        TempoEntry.configure(field) { _ in }
        TempoEntry.configure(field) { _ in }
        XCTAssertEqual(editingChangedHandlers(field), 1)
    }

    /// The handler left is the latest one, so an edit is reported once.
    func testAnEditIsReportedOnceToTheLatestHandler() {
        let field = UITextField()
        var first: [String] = [], second: [String] = []
        TempoEntry.configure(field) { first.append($0) }
        TempoEntry.configure(field) { second.append($0) }
        field.text = "140"
        field.sendActions(for: .editingChanged)
        XCTAssertEqual(first, [])
        XCTAssertEqual(second, ["140"])
    }
}
