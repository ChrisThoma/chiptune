import SwiftUI

extension View {
    /// The iOS form look on the Mac too. A Mac `Form` defaults to two
    /// columns, labels right-aligned on the left, which put section headers
    /// and footers out of line with the controls and ran the docked sound
    /// controls past the column's edge. Nothing on iOS, where grouped is
    /// already the default.
    @ViewBuilder
    func chipFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    /// A menu whose label draws itself, as on iOS. A Mac `Menu` otherwise
    /// wraps the label in a bordered pop-up button with a chevron beside it.
    @ViewBuilder
    func chipMenuStyle() -> some View {
        #if os(macOS)
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        #else
        self
        #endif
    }

    /// A Mac sheet takes its content's ideal size, and a List or ScrollView
    /// has none, so the Songs sheet opened as a title bar with nothing under
    /// it. iOS sheets get the screen (or a detent) and ignore this.
    @ViewBuilder
    func macSheetSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: width * 0.8, idealWidth: width, maxWidth: .infinity,
              minHeight: height * 0.7, idealHeight: height, maxHeight: .infinity)
        #else
        self
        #endif
    }
}
