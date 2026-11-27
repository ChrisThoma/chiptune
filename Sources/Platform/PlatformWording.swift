import Foundation

/// Help and footnote copy is written once, for a touch screen. With a pointer
/// a tap is a click and a long press is a right-click, so the Mac reads the
/// same strings through `adapt`, and iOS gets them untouched.
enum PlatformWording {
    static func adapt(_ text: String) -> String {
        #if os(macOS)
        forPointer(text)
        #else
        text
        #endif
    }

    /// Whole words only, so "tapping" or a word with "tap" inside it is left
    /// alone. "Hold" only where iOS means a long press on a note or a pattern
    /// chip ("Hold a note", "Hold one"); "hold a section for longer" is
    /// about repeats and stays.
    static func forPointer(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement,
                                                 options: .regularExpression)
        }
        return result
    }

    private static let replacements: [(String, String)] = [
        // The Mac window always docks the sound controls beside the grid, so
        // the iPad's opening tap and its "held sideways" aside don't apply.
        (#"Tap it again to open its sound controls\. On a large screen held sideways, they may already be open beside the grid\."#,
         "Its sound controls are beside the grid."),
        (#"\bHold (a note|one)\b"#, "Right-click $1"),
        (#"\bhold (a note|one)\b"#, "right-click $1"),
        (#"\bTap\b"#, "Click"),
        (#"\btap\b"#, "click"),
    ]
}
