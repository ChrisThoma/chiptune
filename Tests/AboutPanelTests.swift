import XCTest
@testable import Chiptune

/// What the Mac's About box says beyond the name and version AppKit reads
/// from the bundle itself.
final class AboutPanelTests: XCTestCase {

    private let date = ISO8601DateFormatter().date(from: "2026-11-26T12:00:00Z")!

    func testTheCreditsNameTheCommitAndTheBuildDate() {
        let stamp = BuildStamp(commit: "ec0d8e3", builtAt: date, version: "1.3.7")
        let credits = AboutPanel.creditsText(stamp)
        XCTAssertTrue(credits.contains("Commit ec0d8e3"), credits)
        XCTAssertTrue(credits.contains(stamp.builtLine!), credits)
    }

    /// A build from a source tarball has no commit; the line is left out
    /// rather than shown blank.
    func testAMissingCommitIsLeftOut() {
        let stamp = BuildStamp(commit: nil, builtAt: date, version: "1.3.7")
        XCTAssertFalse(AboutPanel.creditsText(stamp).contains("Commit"))
        XCTAssertEqual(AboutPanel.creditsText(BuildStamp(commit: nil, builtAt: nil, version: nil)), "")
    }

    func testTheVersionIsTheMarketingVersionAndTheBuildNumber() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.3.7", "CFBundleVersion": "26"]
        XCTAssertEqual(AboutPanel.versionText(info: info), "1.3.7 (26)")
        XCTAssertEqual(AboutPanel.versionText(info: ["CFBundleShortVersionString": "1.3.7"]), "1.3.7")
    }
}
