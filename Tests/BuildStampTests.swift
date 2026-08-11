import XCTest
@testable import Chiptune

/// The row's content rules, and two assertions about the bundle this suite is
/// hosted in — which is the app itself, so it's the shipping plist being read.
final class BuildStampTests: XCTestCase {

    private let noon = ISO8601DateFormatter().date(from: "2026-08-11T12:00:00Z")!

    private func stamp(commit: String? = "c9d96bc",
                       builtAt: Date? = nil,
                       version: String? = "1.1") -> BuildStamp {
        BuildStamp(commit: commit, builtAt: builtAt ?? noon, version: version)
    }

    func testTheRowLeadsWithTheBuildAndEndsWithTheRelease() {
        // The commit is the subject: it's what says which code this is. The
        // release number is a separate fact and sits on its own line.
        let lines = stamp().lines
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("Built "), lines[0])
        XCTAssertEqual(lines[1], "c9d96bc")
        XCTAssertEqual(lines[2], "Version 1.1")
    }

    func testTheUploadCounterNeverAppears() {
        // CFBundleVersion exists so App Store Connect can tell two uploads
        // apart. It means nothing on a device, and mixing it in is what made
        // the first attempt at this row read like bookkeeping.
        //
        // Asserted against the real bundle, because that's where the counter
        // actually exists to leak from — it's "3" right now, and it would
        // surface as a parenthesised "(3)". Nothing else in the row can
        // produce a bracket, so this stays true as the numbers change.
        let shipping = BuildStamp()
        XCTAssertFalse(shipping.lines.contains { $0.contains("(") },
                       shipping.lines.joined(separator: " | "))
        XCTAssertFalse(shipping.copyText.contains("("), shipping.copyText)
    }

    func testTheBuildDateIsWrittenForReadingRatherThanParsing() {
        // Formatted for the reader, not echoed in the ISO form the plist
        // carries — the line exists to be glanced at.
        let line = stamp().builtLine
        XCTAssertNotNil(line)
        XCTAssertFalse(line!.contains("T"), line!)
        XCTAssertFalse(line!.contains("Z"), line!)
        XCTAssertTrue(line!.contains("2026"), line!)
    }

    func testCopyingGivesTheReleaseAndTheCommit() {
        // What a bug report needs. The date is derivable from the commit and
        // is only on screen to save a lookup.
        XCTAssertEqual(stamp().copyText, "1.1 · c9d96bc")
    }

    func testAMissingPieceLeavesItsLineOutRatherThanShowingAPlaceholder() {
        // Building outside a git checkout is legitimate — a source tarball,
        // or a machine without git. A dash where a hash should be tells the
        // reader nothing they can act on.
        let noCommit = stamp(commit: nil)
        XCTAssertEqual(noCommit.lines.count, 2)
        XCTAssertTrue(noCommit.lines[0].hasPrefix("Built "), noCommit.lines[0])
        XCTAssertEqual(noCommit.lines[1], "Version 1.1")
        XCTAssertEqual(noCommit.copyText, "1.1")

        let noDate = BuildStamp(commit: "c9d96bc", builtAt: nil, version: "1.1")
        XCTAssertEqual(noDate.lines, ["c9d96bc", "Version 1.1"])

        XCTAssertEqual(BuildStamp(commit: nil, builtAt: nil, version: nil).lines, [])
    }

    func testEmptyAndUnexpandedValuesAreNotData() {
        // A key present but blank is the same failure as one that's absent.
        XCTAssertNil(BuildStamp(commit: "   ", builtAt: noon, version: "1.1").commit)
        // `$(MARKETING_VERSION)` reaching the screen is what this arrangement
        // fails as when the plist isn't expanded — the version keys really are
        // written as substitutions, so it's a live outcome, not a hypothetical.
        XCTAssertNil(BuildStamp(commit: nil, builtAt: noon, version: "$(MARKETING_VERSION)").version)
    }

    func testWhitespaceAroundAValueIsTrimmedRatherThanRejected() {
        XCTAssertEqual(BuildStamp(commit: " c9d96bc\n", builtAt: noon, version: " 1.1 ").copyText,
                       "1.1 · c9d96bc")
    }

    /// The stamp has to survive the build, which is the part a unit test can
    /// check: the phase writes into the built plist after the plist is
    /// processed and before the bundle is signed, and any slip in that
    /// ordering shows up here as a missing key.
    func testTheShippingBundleCarriesACommitAndABuildDate() {
        // `Bundle.main` and not `Bundle(for:)` — this bundle is hosted inside
        // the app, so main is the app while `Bundle(for:)` would be the test
        // bundle and its own generated plist.
        let build = BuildStamp()

        XCTAssertNotNil(build.commit,
                        "No ChiptuneGitCommit in the built Info.plist — the stamping build "
                        + "phase didn't run, or ran before the plist was processed.")
        // The shape, not a value: the value changes with every commit, and
        // pinning it would make this a step in committing rather than a check.
        XCTAssertNotNil(build.commit?.range(of: #"^[0-9a-f]{7,40}$"#, options: .regularExpression),
                        "\(build.commit ?? "nil") doesn't look like a commit hash.")

        XCTAssertNotNil(build.builtAt, "No parseable ChiptuneBuildDate in the built Info.plist.")
    }

    func testTheShippingBundleKnowsItsRelease() {
        // Guards the generated plist's version substitution, which silently
        // shipped 1.0 as recently as this morning. Asserts it resolved to
        // something, not to which number, so a release bump doesn't edit this.
        XCTAssertNotNil(BuildStamp().version)
    }
}
