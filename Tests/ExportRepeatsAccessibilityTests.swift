import SwiftUI
import UIKit
import XCTest
@testable import Chiptune

/// The Export sheet's Repeats row, as VoiceOver meets it: one adjustable
/// element that says how many times the arrangement plays, and that reads as
/// dimmed while a render has the settings locked rather than as an adjustable
/// that silently does nothing.
@MainActor
final class ExportRepeatsAccessibilityTests: XCTestCase {

    func testRepeatsIsOneAdjustableElement() throws {
        let (studio, window) = try present()
        defer { window.isHidden = true; studio.invalidateTimers() }

        let repeats = repeatsElements(in: window)
        XCTAssertEqual(repeats.count, 1, "VoiceOver should meet Repeats once")
        let element = try XCTUnwrap(repeats.first)
        XCTAssertEqual(element.accessibilityValue, "1 time")
        XCTAssertTrue(element.accessibilityTraits.contains(.adjustable))
        XCTAssertFalse(element.accessibilityTraits.contains(.notEnabled))

        element.accessibilityIncrement()
        spin(0.3)
        XCTAssertEqual(repeatsElements(in: window).first?.accessibilityValue, "2 times")
    }

    func testRepeatsReadsAsDimmedWhileExporting() throws {
        let (studio, window) = try present()
        defer { window.isHidden = true; studio.invalidateTimers() }
        studio.isExporting = true
        spin(0.3)

        let element = try XCTUnwrap(repeatsElements(in: window).first)
        XCTAssertTrue(element.accessibilityTraits.contains(.notEnabled))
        element.accessibilityIncrement()
        spin(0.3)
        XCTAssertEqual(repeatsElements(in: window).first?.accessibilityValue, "1 time",
                       "a locked Repeats must not step")
    }

    private func present() throws -> (Studio, UIWindow) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let temp = makeTempStore()
        let studio = Studio(store: temp.store, autosaveEnabled: false)
        studio.open(TestSongs.golden())
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: ExportSheet(studio: studio))
        window.isHidden = false
        spin(0.5)
        return (studio, window)
    }

    /// Every accessibility element under `root` labelled "Repeats", walking
    /// views and the elements SwiftUI hands out for them alike.
    private func repeatsElements(in root: NSObject) -> [NSObject] {
        var seen = Set<ObjectIdentifier>()
        var found: [NSObject] = []
        func walk(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return }
            if object.isAccessibilityElement, object.accessibilityLabel == "Repeats" {
                found.append(object)
            }
            (object as? UIView)?.subviews.forEach(walk)
            (object.accessibilityElements as? [NSObject])?.forEach(walk)
            let count = object.accessibilityElementCount()
            if count != NSNotFound {
                for index in 0..<max(count, 0) {
                    if let child = object.accessibilityElement(at: index) as? NSObject { walk(child) }
                }
            }
        }
        walk(root)
        return found
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
