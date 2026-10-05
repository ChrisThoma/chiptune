import SwiftUI
import UIKit
import XCTest

extension XCTestCase {
    /// Presents `content` as a sheet the way a phone does, dismisses it, and
    /// fails if any view it put on screen is still alive afterwards.
    ///
    /// On iOS 26 a dismissed sheet's own controller and graph go away, but
    /// some system controls inside it do not: the SwiftUI `Stepper` is a
    /// `UIStepper` drawing through a hosted graph of its own, which UIKit
    /// never releases, so each open and close kept one alive. Was written for
    /// ARR and is shared with every sheet that had one.
    @MainActor
    func assertClosingLeavesNoViewsAlive<Content: View>(
        _ content: @autoclosure () -> Content,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first, file: file, line: line)

        var presented: [WeakView] = []
        autoreleasepool {
            let window = UIWindow(windowScene: scene)
            let root = UIViewController()
            window.rootViewController = root
            window.isHidden = false

            let sheet = UIHostingController(rootView: content())
            root.present(sheet, animated: false)
            spinMainRunLoop(0.5)
            presented = allSubviews(of: sheet.view).map(WeakView.init)

            root.dismiss(animated: false)
            spinMainRunLoop(0.5)
            window.isHidden = true
            window.rootViewController = nil
        }
        spinMainRunLoop(0.5)

        XCTAssertFalse(presented.isEmpty, "the sheet never laid out", file: file, line: line)
        let alive = presented.compactMap(\.view).map { String(describing: type(of: $0)) }
        XCTAssertEqual(alive, [], "views outlived the dismissed sheet", file: file, line: line)
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(allSubviews(of:))
    }

    private func spinMainRunLoop(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

private final class WeakView {
    weak var view: UIView?
    init(_ view: UIView) { self.view = view }
}
