import Foundation

/// The parts of the Mac's About box that AppKit doesn't read from the bundle
/// on its own. Pure, so what it says is tested without a panel.
enum AboutPanel {
    /// The commit and the build date, one per line: the same facts the iOS
    /// ••• menu shows, and the reason to look is the same (a bug report).
    static func creditsText(_ stamp: BuildStamp) -> String {
        [stamp.commit.map { "Commit \($0)" }, stamp.builtLine]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    /// "1.3.7 (26)". AppKit's default shows the build number alone in the
    /// parentheses with "Version" in front; this keeps both in one place.
    static func versionText(info: [String: Any]) -> String {
        let marketing = info["CFBundleShortVersionString"] as? String ?? ""
        guard let build = info["CFBundleVersion"] as? String, !build.isEmpty else { return marketing }
        return "\(marketing) (\(build))"
    }
}

#if os(macOS)
import AppKit

extension AboutPanel {
    @MainActor
    static func show() {
        let credits = NSAttributedString(
            string: creditsText(BuildStamp()),
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                         .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            // The "(build)" AppKit adds is already in this line.
            .version: "",
            .applicationVersion: versionText(info: Bundle.main.infoDictionary ?? [:]),
        ])
        NSApp.activate()
    }
}
#endif
