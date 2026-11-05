import XCTest
@testable import Chiptune

/// The guide is prose about controls that live elsewhere, so nothing but these
/// tests notices when a label or a limit moves and the words stay behind.
final class HelpGuideTests: XCTestCase {

    private func terms(_ id: HelpGuide.SectionID) -> [String] {
        HelpGuide.section(id)?.entries.map(\.term) ?? []
    }

    private func text(_ term: String, in id: HelpGuide.SectionID) -> String {
        HelpGuide.section(id)?.entries.first { $0.term == term }?.text ?? ""
    }

    private var allEntries: [HelpGuide.Entry] { HelpGuide.sections.flatMap(\.entries) }

    func testEverySectionAppearsOnceInOrderAndHasEntries() {
        XCTAssertEqual(HelpGuide.sections.map(\.id), HelpGuide.SectionID.allCases)
        for section in HelpGuide.sections {
            XCTAssertFalse(section.entries.isEmpty, section.title)
        }
    }

    func testEntryIDsAreUniqueWithinASection() {
        for section in HelpGuide.sections {
            let ids = section.entries.map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, section.title)
        }
    }

    func testTheTransportLabelsAreExplained() {
        for label in ["PATT", "SONG", "ARR", "BPM"] {
            XCTAssertTrue(terms(.playing).contains(label), label)
        }
    }

    func testEveryChannelNameIsExplained() {
        let joined = terms(.tracks).joined(separator: " ")
        for kind in ChannelKind.allCases {
            XCTAssertTrue(joined.contains(kind.name), kind.name)
        }
    }

    func testTempoRangeMatchesTheEngine() {
        let low = Int(Chip.tempoRange.lowerBound)
        let high = Int(Chip.tempoRange.upperBound)
        XCTAssertTrue(text("BPM", in: .playing).contains("\(low) to \(high)"))
    }

    func testPatternLengthRangeMatchesTheModel() {
        let range = Chip.patternLengthRange
        XCTAssertTrue(text("STEPS", in: .patterns)
            .contains("\(range.lowerBound) to \(range.upperBound)"))
    }

    func testLimitsMatchTheModel() {
        XCTAssertTrue(text("+", in: .patterns).contains("\(Chip.maxPatterns)"))
        XCTAssertTrue(text("+", in: .tracks).contains("\(Chip.maxTracks)"))
    }

    func testCopyHasNoDashes() {
        for entry in allEntries {
            XCTAssertFalse(entry.text.contains("—"), entry.text)
            XCTAssertFalse(entry.text.contains(" - "), entry.text)
        }
    }

    func testEveryEntryEndsAsASentence() {
        for entry in allEntries {
            XCTAssertTrue(entry.text.hasSuffix("."), entry.text)
        }
    }

    func testHoldGesturesCantBeMistakenForTheHoldSwitch() {
        XCTAssertTrue(terms(.notes).contains("Hold a step"))
        XCTAssertTrue(terms(.tracks).contains("Hold a track"))
        XCTAssertEqual(allEntries.filter { $0.term == "Hold" }.count, 1)
        XCTAssertFalse(text("Hold", in: .sound).isEmpty)
    }

    func testTrackIsDefinedBeforeTheChannels() {
        XCTAssertEqual(terms(.tracks).first, "Track")
    }

    func testPresetNamesTheRowYouTap() {
        XCTAssertTrue(text("Preset", in: .sound).hasPrefix("Tap \(ControlLabel.presetRow) "))
    }

    func testDecaySaysHoldTurnsItOff() {
        XCTAssertTrue(text(ControlLabel.decay, in: .sound)
            .contains("off while \(ControlLabel.holdSwitch) is on"))
    }

    func testChannelSaysTheSoundResets() {
        XCTAssertTrue(text("Channel", in: .sound).contains("resets"))
    }

    func testMuteSaysItReachesExports() {
        XCTAssertTrue(text("Mute", in: .tracks).contains("exports"))
    }

    /// These read the same constants the controls draw.
    func testTheGuideQuotesTheLabelsOnTheControls() {
        XCTAssertTrue(terms(.playing).contains(ControlLabel.patt))
        XCTAssertTrue(terms(.playing).contains(ControlLabel.song))
        XCTAssertTrue(terms(.playing).contains(ControlLabel.arrangement))
        XCTAssertTrue(terms(.notes).contains(ControlLabel.rest))
        XCTAssertTrue(terms(.sound).contains(ControlLabel.volume))
        XCTAssertTrue(terms(.sound).contains(ControlLabel.holdSwitch))
        XCTAssertTrue(terms(.sound).contains(ControlLabel.decay))
        XCTAssertTrue(text(ControlLabel.song, in: .arrangement).contains("tap \(ControlLabel.song) "))
        XCTAssertTrue(text(ControlLabel.song, in: .arrangement).contains(ControlLabel.patt))
        XCTAssertTrue(text("Hold a track", in: .tracks).hasSuffix("tap \(ControlLabel.reorderDone)."))
        XCTAssertTrue(text("Preset", in: .sound).contains(ControlLabel.volume))
    }

    func testTracksSaysTheGesturesLiveOnTheName() {
        XCTAssertTrue(text("Tap", in: .tracks).hasPrefix("Tap a track's name"))
        XCTAssertTrue(text("Hold a track", in: .tracks).contains("hold a name"))
    }
}
