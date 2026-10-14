import Foundation
import XCTest

/// Finds a file from `Tests/Fixtures`. Resources are flattened into the test
/// bundle's root by XcodeGen; the `#filePath` fallback reads the checkout's
/// copy, as `SharedFixtureTests` does.
enum FixtureFiles {
    /// The fixture folder in the checkout, which is where regenerated
    /// fixtures are written.
    static var repoDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    static func url(_ fileName: String) throws -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        if let bundled = Bundle(for: BundleToken.self).url(forResource: base, withExtension: ext) {
            return bundled
        }
        let repo = repoDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: repo.path) { return repo }
        throw XCTSkip("\(fileName) is missing from both the test bundle and the checkout")
    }

    private final class BundleToken {}
}
