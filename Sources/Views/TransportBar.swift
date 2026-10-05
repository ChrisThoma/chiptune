import SwiftUI
import UIKit

/// The spoken name for the tempo alert's field. It opens holding the current
/// tempo, so its "BPM" placeholder never shows and VoiceOver read a bare
/// number with nothing saying what it was. "BPM" matches the stepper the
/// alert opens from.
enum TempoFieldAccessibility {
    static let label = "BPM"

    static func apply(to field: UITextField) {
        field.accessibilityLabel = label
    }
}

/// Play/stop, tempo, and the pattern/song mode switch.
struct TransportBar: View {
    @Bindable var studio: Studio
    @Binding var showingArrangement: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.chipLayout) private var layout
    // Dynamic Type still has to scale the tray up: this scales as a ratio
    // against a fixed 1pt base, then multiplies the layout's own tray height
    // by it, rather than baking a phone-only literal into the ScaledMetric
    // the way `Theme.trayHeight` used to.
    @ScaledMetric(relativeTo: .body) private var trayHeightScale: CGFloat = 1
    private var trayHeight: CGFloat { layout.trayHeight * trayHeightScale }
    @State private var editingTempo = false
    @State private var tempoText = ""

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                // Every width in the row is fixed but the spacer's, so it
                // can't compress: drawn wider than the window, it widened the
                // whole stacked editor and pushed the grid and keys off the
                // right edge (a 375pt SE at extra-extra-extra-large, a 320pt
                // Slide Over window at any size). When it doesn't fit, drop
                // BPM to a row of its own, and stack all three only when play
                // and the mode tray don't fit side by side either. The order
                // matches `ChipLayout.transportForm`, which is the same sums.
                ViewThatFits(in: .horizontal) {
                    row
                    twoRows
                    stacked
                }
            }
        }
        .padding(.horizontal, ChipLayout.chromeRowPadding)
        .padding(.bottom, 8)
        .reportsPresentation(.tempoAlert, isPresented: editingTempo, studio: studio)
        .background {
            AlertTextFieldBridge(isPresented: editingTempo,
                                 configure: TempoFieldAccessibility.apply)
        }
        .alert("Tempo", isPresented: $editingTempo) {
            TextField("BPM", text: $tempoText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                if let bpm = Double(tempoText.trimmingCharacters(in: .whitespaces)) {
                    studio.setTempo(bpm)
                }
            }
        } message: {
            Text("40 to 300 BPM")
        }
    }

    /// Play, the mode tray and BPM side by side, BPM pushed to the far end.
    private var row: some View {
        HStack(spacing: ChipLayout.chromeRowSpacing) {
            playButton
            modeTray(stretched: false)
            Spacer(minLength: ChipLayout.transportTrayGap)
            tempoStepper(stretched: false)
        }
    }

    /// Play and the mode tray at their row widths, then BPM full width under
    /// them: a row of chrome less than `stacked`, which the grid gets back.
    private var twoRows: some View {
        VStack(spacing: 8) {
            HStack(spacing: ChipLayout.chromeRowSpacing) {
                playButton
                modeTray(stretched: false)
                Spacer(minLength: 0)
            }
            tempoStepper(stretched: true)
        }
    }

    /// Play on a row of its own, then the mode tray and BPM full width under it.
    private var stacked: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                playButton
                Spacer(minLength: 0)
            }
            modeTray(stretched: true).frame(maxWidth: .infinity)
            tempoStepper(stretched: true)
        }
    }

    /// The only saturated fill in the chrome, and the biggest target, so the
    /// eye lands here first.
    private var playButton: some View {
        Button {
            Haptics.transport()
            studio.togglePlay()
        } label: {
            Image(systemName: studio.isPlaying ? "stop.fill" : "play.fill")
                .symbolFont(18)
                .foregroundStyle(Theme.onLight)
                .frame(width: ChipLayout.playButtonWidth, height: trayHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.trayRadius)
                        .fill(studio.isPlaying ? Theme.accentRed : Theme.accentGreen)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // Matches the fill's own corners so the glow doesn't spill past it.
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Theme.trayRadius))
        .accessibilityLabel(studio.isPlaying ? "Stop" : "Play")
    }

    /// `stretched` drops the fixed segment widths so the tray fills the
    /// stacked layout's full row.
    private func modeTray(stretched: Bool) -> some View {
        HStack(spacing: 0) {
            modeToggle(stretched: stretched)
            TrayDivider()
            Button { showingArrangement = true } label: {
                Text("ARR")
                    .chipFont(11, weight: .semibold)
                    .foregroundStyle(Theme.text)
                    .frame(width: stretched ? nil : layout.arrButtonWidth,
                           height: trayHeight)
                    .frame(maxWidth: stretched ? .infinity : nil)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Arrangement")
            // Anchored to the ARR button so the play order sits beside the
            // transport that plays it and the grid stays visible behind;
            // a phone gets the sheet it has always had.
            .popover(isPresented: $showingArrangement,
                     attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                // `isRegularWidth` comes from the presenting side: a popover's
                // content is handed a compact size class whatever the window
                // is, so the view inside can't ask for itself.
                ArrangementView(studio: studio, regularWidth: layout.isRegularWidth)
                    .presentationCompactAdaptation(.sheet)
            }
        }
        .chipTray()
    }

    /// The value is a button as well as a readout — nudging from 120 to 174
    /// four BPM at a time is nobody's idea of a good afternoon.
    private func tempoStepper(stretched: Bool) -> some View {
        ChipStepper(label: "BPM",
                    value: Int(studio.song.tempo),
                    range: Int(Chip.tempoRange.lowerBound)...Int(Chip.tempoRange.upperBound),
                    onChange: { studio.setTempo(studio.song.tempo + Double($0) * 4) },
                    onTapValue: {
                        tempoText = String(Int(studio.song.tempo))
                        editingTempo = true
                    })
            .frame(maxWidth: stretched ? .infinity : nil)
            .chipTray()
    }

    /// PATT loops the pattern you're editing so you can work on it; SONG plays
    /// the arrangement from the top.
    private func modeToggle(stretched: Bool) -> some View {
        HStack(spacing: 0) {
            segment("PATT", on: !studio.songMode, stretched: stretched) { studio.setSongMode(false) }
            segment("SONG", on: studio.songMode, stretched: stretched) { studio.setSongMode(true) }
        }
        .frame(maxWidth: stretched ? .infinity : nil)
    }

    private func segment(_ title: String, on: Bool, stretched: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .chipFont(11, weight: on ? .bold : .semibold)
                .foregroundStyle(on ? Theme.onLight : Theme.dim)
                .frame(width: stretched ? nil : layout.patternSegmentWidth,
                       height: trayHeight)
                .frame(maxWidth: stretched ? .infinity : nil)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Theme.innerRadius)
                        .fill(on ? Theme.text : Color.clear)
                        .padding(4)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(title == "PATT" ? "Pattern" : "Song")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
