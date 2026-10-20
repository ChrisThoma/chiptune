import XCTest
@testable import Chiptune

/// Save Video in the share sheet writes to the photo library, and without
/// this key iOS kills the app the moment it asks. The hosted tests run
/// inside the app, so its own Info.plist is `Bundle.main`'s.
final class PhotoLibraryUsageTests: XCTestCase {
    func testTheAppSaysWhyItAddsToPhotos() {
        let reason = Bundle.main.infoDictionary?["NSPhotoLibraryAddUsageDescription"] as? String
        XCTAssertFalse((reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "NSPhotoLibraryAddUsageDescription is missing or blank")
    }
}
