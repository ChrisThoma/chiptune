import CoreGraphics

/// How the landscape side column makes room for the software keyboard while
/// the docked instrument editor's Name field is being typed into.
///
/// The editor root ignores the keyboard safe area on purpose (see
/// `ChipLayout.measurementIgnoresSafeArea`), so nothing under it is lifted by
/// UIKit. In the side column that left the docked editor, which sits under
/// the piano, entirely behind the keyboard: the user typed blind. This says
/// how far the column's bottom has to come up, and whether the piano has to
/// step aside so the editor's Form has room to show the field at all.
struct DockedKeyboardAvoidance: Equatable {
    /// Points of the column hidden by the keyboard, to pad off its bottom.
    var bottomInset: CGFloat
    /// The piano is hidden so the editor can move up above the keyboard.
    var hidesKeys: Bool

    static let none = DockedKeyboardAvoidance(bottomInset: 0, hidesKeys: false)

    /// Least height the Form needs to show the Name section above the
    /// keyboard with its header and a little context.
    static let minimumEditorHeight: CGFloat = 160

    /// - Parameters:
    ///   - nameEditing: the docked Name field holds focus. A keyboard raised
    ///     for any other field (the song title) leaves the column alone.
    ///   - column: the side column's frame, in the same space as `keyboardTop`.
    ///   - keyboardTop: the top of the keyboard, or the bottom of the safe
    ///     area when there is none.
    ///   - keysHeight: the piano block above the editor.
    static func resolve(nameEditing: Bool, column: CGRect,
                        keyboardTop: CGFloat, keysHeight: CGFloat) -> DockedKeyboardAvoidance {
        guard nameEditing else { return .none }
        let covered = min(max(0, column.maxY - keyboardTop), column.height)
        guard covered > 0 else { return .none }
        let left = column.height - covered
        return DockedKeyboardAvoidance(
            bottomInset: covered,
            hidesKeys: left - keysHeight < minimumEditorHeight)
    }
}
