import SwiftUI

/// Play/stop, tempo, and the pattern/song mode switch.
struct TransportBar: View {
    @Bindable var studio: Studio
    @Binding var showingArrangement: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var trayHeight = Theme.trayHeight
    @State private var editingTempo = false
    @State private var tempoText = ""

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        playButton
                        Spacer(minLength: 0)
                    }
                    modeTray.frame(maxWidth: .infinity)
                    tempoStepper
                }
            } else {
                HStack(spacing: 8) {
                    playButton
                    modeTray
                    Spacer(minLength: 12)
                    tempoStepper
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
                .frame(width: 56, height: trayHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.trayRadius)
                        .fill(studio.isPlaying ? Theme.accentRed : Theme.accentGreen)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(studio.isPlaying ? "Stop" : "Play")
    }

    private var modeTray: some View {
        HStack(spacing: 0) {
            modeToggle
            TrayDivider()
            Button { showingArrangement = true } label: {
                Text("ARR")
                    .chipFont(11, weight: .semibold)
                    .foregroundStyle(Theme.text)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 48,
                           height: trayHeight)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Arrangement")
        }
        .chipTray()
    }

    /// The value is a button as well as a readout — nudging from 120 to 174
    /// four BPM at a time is nobody's idea of a good afternoon.
    private var tempoStepper: some View {
        ChipStepper(label: "BPM",
                    value: Int(studio.song.tempo),
                    range: Int(Chip.tempoRange.lowerBound)...Int(Chip.tempoRange.upperBound),
                    onChange: { studio.setTempo(studio.song.tempo + Double($0) * 4) },
                    onTapValue: {
                        tempoText = String(Int(studio.song.tempo))
                        editingTempo = true
                    })
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            .chipTray()
    }

    /// PATT loops the pattern you're editing so you can work on it; SONG plays
    /// the arrangement from the top.
    private var modeToggle: some View {
        HStack(spacing: 0) {
            segment("PATT", on: !studio.songMode) { studio.setSongMode(false) }
            segment("SONG", on: studio.songMode) { studio.setSongMode(true) }
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .chipFont(11, weight: on ? .bold : .semibold)
                .foregroundStyle(on ? Theme.onLight : Theme.dim)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 52,
                       height: trayHeight)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Theme.innerRadius)
                        .fill(on ? Theme.text : Color.clear)
                        .padding(4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "PATT" ? "Pattern" : "Song")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
