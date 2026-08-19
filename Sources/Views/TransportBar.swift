import SwiftUI

/// Play/stop, tempo, and the pattern/song mode switch.
struct TransportBar: View {
    @Bindable var studio: Studio
    @Binding var showingArrangement: Bool
    @State private var editingTempo = false
    @State private var tempoText = ""

    var body: some View {
        HStack(spacing: 8) {
            // The only saturated fill in the chrome, and the biggest target, so
            // the eye lands here first.
            Button {
                studio.togglePlay()
            } label: {
                Image(systemName: studio.isPlaying ? "stop.fill" : "play.fill")
                    .symbolFont(18)
                    .foregroundStyle(Theme.onLight)
                    .frame(width: 56, height: Theme.trayHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.trayRadius)
                            .fill(studio.isPlaying ? Theme.accentRed : Theme.accentGreen)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(studio.isPlaying ? "Stop" : "Play")

            // What plays: the mode you're in and the arrangement behind it.
            HStack(spacing: 0) {
                modeToggle

                TrayDivider()

                Button {
                    showingArrangement = true
                } label: {
                    Text("ARR")
                        .chipFont(11, weight: .semibold)
                        .foregroundStyle(Theme.text)
                        .frame(width: 48, height: Theme.trayHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Arrangement")
            }
            .chipTray()

            Spacer(minLength: 12)

            // Trails the row so it lines up with STEPS below — the two steppers
            // read as a pair rather than as more transport buttons.
            //
            // The value is a button as well as a readout — nudging from 120 to
            // 174 four BPM at a time is nobody's idea of a good afternoon.
            ChipStepper(label: "BPM",
                        value: Int(studio.song.tempo),
                        range: Int(Chip.tempoRange.lowerBound)...Int(Chip.tempoRange.upperBound),
                        onChange: { studio.setTempo(studio.song.tempo + Double($0) * 4) },
                        onTapValue: {
                            tempoText = String(Int(studio.song.tempo))
                            editingTempo = true
                        })
                .chipTray()
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

    /// PATT loops the pattern you're editing so you can work on it; SONG plays
    /// the arrangement from the top.
    private var modeToggle: some View {
        HStack(spacing: 0) {
            segment("PATT", on: !studio.songMode) { studio.setSongMode(false) }
            segment("SONG", on: studio.songMode) { studio.setSongMode(true) }
        }
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .chipFont(11, weight: on ? .bold : .semibold)
                .foregroundStyle(on ? Theme.onLight : Theme.dim)
                .frame(width: 52, height: Theme.trayHeight)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Theme.innerRadius)
                        .fill(on ? Theme.text : Color.clear)
                        .padding(4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
