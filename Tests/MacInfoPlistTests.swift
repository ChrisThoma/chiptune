#if os(macOS)
import XCTest
@testable import Chiptune

/// The Mac app's Info.plist keys the App Store and Finder read. The hosted
/// tests run inside the app, so its plist is `Bundle.main`'s.
final class MacInfoPlistTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    func testTheAppIsFiledUnderMusic() {
        XCTAssertEqual(info["LSApplicationCategoryType"] as? String, "public.app-category.music")
    }

    func testTheAboutBoxHasACopyrightLine() {
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""
        XCTAssertTrue(copyright.hasPrefix("Copyright ©"), copyright)
    }

    func testTheMinimumSystemVersionIsSet() {
        XCTAssertEqual(info["LSMinimumSystemVersion"] as? String, "14.0")
    }

    func testTheAppHasAnIconAndAPrivacyManifest() {
        XCTAssertEqual(info["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    /// Finder hands a .chipsong to this app, which is what a double-click
    /// and a drop on the Dock icon both need.
    func testTheAppOpensSongFiles() {
        let types = info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        let content = types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        XCTAssertTrue(content.contains("dev.individuation.chiptune.song"))
    }
}
#endif
