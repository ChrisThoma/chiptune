import XCTest
@testable import Chiptune

/// Asserts two songs are the same edit, ignoring `modified`.
///
/// Every round trip through the store or a `.chipsong` stamps `modified`, so a
/// straight `XCTAssertEqual` on two songs that *are* the same song fails on the
/// one field that is expected to differ. Three suites had grown their own copy
/// of this, and they had already drifted apart — one had lost the `message`
/// parameter.
///
/// `file`/`line` default to the call site so a failure points at the assertion
/// that failed rather than at this function.
func assertSameSong(_ a: Song, _ b: Song, _ message: String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
    var a = a, b = b
    let epoch = Date(timeIntervalSince1970: 0)
    a.modified = epoch
    b.modified = epoch
    XCTAssertEqual(a, b, message, file: file, line: line)
}
