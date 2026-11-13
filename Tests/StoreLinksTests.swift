import XCTest
@testable import Chiptune

/// The song menu's Rate Chiptune row opens the App Store's write-a-review page
/// for this app, not the listing's top.
final class StoreLinksTests: XCTestCase {
    func testRateOpensTheWriteReviewPage() {
        XCTAssertEqual(StoreLinks.writeReview.absoluteString,
                       "https://apps.apple.com/app/id6794059658?action=write-review")
    }
}
