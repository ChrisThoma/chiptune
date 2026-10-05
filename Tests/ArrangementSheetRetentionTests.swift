import SwiftUI
import UIKit
import XCTest
@testable import Chiptune

/// Opening and closing the ARR sheet kept ~0.15 MB alive every time, without
/// end. The sheet's own controller and graph went away; what stayed was the
/// rows' system `Stepper` — on iOS 26 a `UIStepper` drawing through its own
/// hosted SwiftUI graph, which UIKit never releases once it is torn down.
///
/// Presents the arrangement the way a phone does, dismisses it, and checks
/// that no view it put on screen is still alive.
@MainActor
final class ArrangementSheetRetentionTests: XCTestCase {

    private final class WeakView {
        weak var view: UIView?
        init(_ view: UIView) { self.view = view }
    }

    func testClosingTheArrangementLeavesNoViewsAlive() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        defer { studio.invalidateTimers() }
        studio.open(Song(name: "Blank"))
        studio.addPattern()
        studio.addSection(patternID: studio.song.patterns[0].id)   // three rows

        var presented: [WeakView] = []
        autoreleasepool {
            let window = UIWindow(windowScene: scene)
            let root = UIViewController()
            window.rootViewController = root
            window.isHidden = false

            let sheet = UIHostingController(rootView: ArrangementView(studio: studio))
            root.present(sheet, animated: false)
            spin(0.5)
            presented = allSubviews(of: sheet.view).map(WeakView.init)

            root.dismiss(animated: false)
            spin(0.5)
            window.isHidden = true
            window.rootViewController = nil
        }
        spin(0.5)

        XCTAssertFalse(presented.isEmpty, "the sheet never laid out")
        let alive = presented.compactMap(\.view).map { String(describing: type(of: $0)) }
        XCTAssertEqual(alive, [], "views outlived the dismissed arrangement")
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(allSubviews(of:))
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
