import Foundation

/// Links into the App Store for this app.
enum StoreLinks {
    static let appID = "6794059658"

    /// Opens the App Store app straight on the write-a-review sheet.
    static let writeReview = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")!
}
