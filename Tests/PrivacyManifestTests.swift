import XCTest
@testable import Chiptune

/// App Store Connect rejects a build that calls a required-reason API its
/// privacy manifest doesn't declare. The hosted tests run inside the app, so
/// the manifest shipped in its bundle is `Bundle.main`'s.
final class PrivacyManifestTests: XCTestCase {
    private func declaredReasons() throws -> [String: [String]] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "PrivacyInfo.xcprivacy is not in the app bundle")
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil)
                                  as? [String: Any])
        let types = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons: [String: [String]] = [:]
        for entry in types {
            let category = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String)
            reasons[category] = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        }
        return reasons
    }

    /// SongStore remembers which song was open last.
    func testDeclaresUserDefaults() throws {
        XCTAssertEqual(try declaredReasons()["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
    }

    /// SongStore reads each song file's modification date to tell a replaced
    /// unreadable file from one already reported. The files are the app's
    /// own, inside its container: C617.1.
    func testDeclaresFileTimestampsForFilesInTheContainer() throws {
        XCTAssertEqual(try declaredReasons()["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"])
    }

    /// The disk-full message only reads the error a failed write returns; the
    /// app never asks how much space is free, so no DiskSpace entry.
    func testDeclaresNothingTheAppDoesNotUse() throws {
        XCTAssertEqual(Set(try declaredReasons().keys), [
            "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPICategoryFileTimestamp",
        ])
    }
}
