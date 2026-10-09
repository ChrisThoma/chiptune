import XCTest
@testable import Chiptune

/// The `.chipsong` contract shared with the Android port.
///
/// `Tests/Fixtures/song-fixtures.json` lists every `song-*.chipsong` fixture
/// and what decoding it must give: either a rejection, or a handful of facts
/// about the normalized song. The Android suite reads the same manifest and
/// the same files, so both platforms are held to one contract. Where Swift's
/// behavior was uncertain (an Int written as `16.0`, a repeated key), the
/// fixture records what this decoder actually does, and Android follows it.
final class SharedFixtureTests: XCTestCase {

    /// Resources are flattened into the bundle root by XcodeGen; the
    /// `#filePath` fallback reads the repo copy, like `GoldenRenderTests`.
    private func fixtureURL(_ fileName: String) throws -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        if let bundled = Bundle(for: SharedFixtureTests.self).url(forResource: base, withExtension: ext) {
            return bundled
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fileName)")
        if FileManager.default.fileExists(atPath: repo.path) { return repo }
        throw XCTSkip("\(fileName) is missing from both the test bundle and the checkout")
    }

    private func manifest() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: try fixtureURL("song-fixtures.json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
    }

    func testTheManifestCoversEveryFixtureInTheCheckout() throws {
        let entries = try manifest()
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            throw XCTSkip("no checkout to compare against")
        }
        let songs = Set(files.filter { $0.hasPrefix("song-") && $0.hasSuffix(".chipsong") })
        XCTAssertEqual(songs, Set(entries.keys))
    }

    func testEveryFixtureDecodesOrIsRejectedAsTheManifestSays() throws {
        let entries = try manifest()
        XCTAssertGreaterThan(entries.count, 20)
        for (fileName, facts) in entries.sorted(by: { $0.key < $1.key }) {
            let data = try Data(contentsOf: try fixtureURL(fileName))
            let decodes = try XCTUnwrap(facts["decodes"] as? Bool, fileName)
            if !decodes {
                XCTAssertThrowsError(try SongDocument.decode(data), "\(fileName) should be rejected")
                continue
            }
            let song: Song
            do {
                song = try SongDocument.decode(data)
            } catch {
                XCTFail("\(fileName) should decode: \(error)")
                continue
            }
            check(song, against: facts, fileName)
        }
    }

    // MARK: Facts

    private func check(_ song: Song, against facts: [String: Any], _ file: String) {
        func eq<T: Equatable>(_ key: String, _ actual: T, _ expected: T?) {
            guard let expected else { return }
            XCTAssertEqual(actual, expected, "\(file): \(key)")
        }
        func near(_ key: String, _ actual: [Double], _ expected: [Double]?) {
            guard let expected else { return }
            XCTAssertEqual(actual.count, expected.count, "\(file): \(key) count")
            for (a, e) in zip(actual, expected) { XCTAssertEqual(a, e, accuracy: 1e-9, "\(file): \(key)") }
        }
        func doubles(_ key: String) -> [Double]? { (facts[key] as? [NSNumber])?.map(\.doubleValue) }
        func ints(_ key: String) -> [Int]? { (facts[key] as? [NSNumber])?.map(\.intValue) }

        eq("id", song.id.uuidString, facts["id"] as? String)
        eq("name", song.name, facts["name"] as? String)
        if let tempo = (facts["tempo"] as? NSNumber)?.doubleValue {
            XCTAssertEqual(song.tempo, tempo, accuracy: 1e-9, "\(file): tempo")
        }
        if let modified = (facts["modified"] as? NSNumber)?.doubleValue {
            XCTAssertEqual(song.modified.timeIntervalSinceReferenceDate, modified, accuracy: 1e-6,
                           "\(file): modified")
        }
        eq("trackCount", song.tracks.count, (facts["trackCount"] as? NSNumber)?.intValue)
        eq("patternCount", song.patterns.count, (facts["patternCount"] as? NSNumber)?.intValue)
        eq("sectionCount", song.arrangement.count, (facts["sectionCount"] as? NSNumber)?.intValue)
        eq("trackKinds", song.tracks.map(\.kind.rawValue), ints("trackKinds"))
        eq("trackSustain", song.tracks.map(\.instrument.sustain), (facts["trackSustain"] as? [Bool]))
        near("trackDecays", song.tracks.map(\.instrument.decay), doubles("trackDecays"))
        eq("trackDuties", song.tracks.map(\.instrument.duty), ints("trackDuties"))
        near("trackVolumes", song.tracks.map(\.instrument.volume), doubles("trackVolumes"))
        eq("trackMuted", song.tracks.map(\.muted), facts["trackMuted"] as? [Bool])
        if let names = facts["trackNames"] as? [Any] {
            let expected: [String?] = names.map { $0 as? String }
            XCTAssertEqual(song.tracks.map(\.name), expected, "\(file): trackNames")
        }
        if let arps = facts["trackArpeggios"] as? [[NSNumber]] {
            XCTAssertEqual(song.tracks.map(\.instrument.arpeggio), arps.map { $0.map(\.intValue) },
                           "\(file): trackArpeggios")
        }
        eq("patternNames", song.patterns.map(\.name), facts["patternNames"] as? [String])
        eq("patternLengths", song.patterns.map(\.length), ints("patternLengths"))
        eq("sectionRepeats", song.arrangement.map(\.repeats), ints("sectionRepeats"))
        eq("sectionPatternIndices", song.arrangement.map { song.patternIndex(id: $0.patternID) ?? -1 },
           ints("sectionPatternIndices"))
        for cell in (facts["cells"] as? [[NSNumber]]) ?? [] {
            let p = cell[0].intValue, r = cell[1].intValue, s = cell[2].intValue
            XCTAssertEqual(Int(song.patterns[p].rows[r][s]), cell[3].intValue,
                           "\(file): pattern \(p) row \(r) step \(s)")
        }
    }
}
