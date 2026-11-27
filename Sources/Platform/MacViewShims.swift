#if os(macOS)
import SwiftUI

/// No-op stand-ins for the iOS-only modifiers the shared views use, so their
/// call sites stay free of #if and the iOS build reads exactly as before.
/// Each is something the Mac has no counterpart for: there is no navigation
/// bar to shrink the title of, and no on-screen keyboard to pick or to
/// capitalize for.
enum MacTitleDisplayMode { case automatic, inline, large }
enum MacAutocapitalization { case never, words, sentences, characters }
enum MacKeyboardType { case `default`, numberPad, decimalPad, asciiCapable }
/// iPadOS's pointer effects. Mac controls don't light up under the pointer,
/// so these are no-ops rather than an imitation.
enum MacHoverEffect { case automatic, highlight, lift }
enum MacHoverShapeKind { case hoverEffect }

/// iOS's edit mode, which the Arrangement's Edit pill is written against
/// (`ArrangementEditToggle`). The Mac List has no edit mode to hand it to;
/// the Arrangement reads the studio's flag instead.
enum EditMode: Hashable { case inactive, transient, active }

extension View {
    func navigationBarTitleDisplayMode(_ mode: MacTitleDisplayMode) -> some View { self }
    func textInputAutocapitalization(_ mode: MacAutocapitalization?) -> some View { self }
    func keyboardType(_ type: MacKeyboardType) -> some View { self }
    func hoverEffect(_ effect: MacHoverEffect) -> some View { self }
    func hoverEffectDisabled(_ disabled: Bool = true) -> some View { self }
    func contentShape<S: Shape>(_ kind: MacHoverShapeKind, _ shape: S) -> some View { self }
}
#endif
