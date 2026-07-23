import SwiftUI

/// Sheet for shaping one channel's voice.
struct InstrumentEditor: View {
    @Bindable var studio: Studio
    let channel: Int
    @Environment(\.dismiss) private var dismiss

    private var kind: ChannelKind { studio.song.tracks[channel].kind }
    private var accent: Color { Theme.color(for: channel) }

    /// Preset arpeggio shapes; empty means the note plays straight.
    private let arps: [(name: String, offsets: [Int])] = [
        ("Off", []),
        ("Maj", [0, 4, 7]),
        ("Min", [0, 3, 7]),
        ("Oct", [0, 12]),
        ("5th", [0, 7]),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Level") {
                    slider(title: "Volume",
                           value: Binding(
                               get: { studio.song.tracks[channel].instrument.volume },
                               set: { studio.song.tracks[channel].instrument.volume = $0; studio.pushInstrument(channel) }),
                           range: 0...1,
                           display: { "\(Int($0 * 100))%" })

                    slider(title: "Decay",
                           value: Binding(
                               get: { studio.song.tracks[channel].instrument.decay },
                               set: { studio.song.tracks[channel].instrument.decay = $0; studio.pushInstrument(channel) }),
                           range: 0.03...4.0,
                           display: { $0 >= 3.99 ? "hold" : String(format: "%.2fs", $0) })
                }

                if kind.hasDuty {
                    Section("Pulse width") {
                        Picker("Duty", selection: Binding(
                            get: { studio.song.tracks[channel].instrument.duty },
                            set: { studio.song.tracks[channel].instrument.duty = $0; studio.pushInstrument(channel) })
                        ) {
                            ForEach(0..<Instrument.dutyLabels.count, id: \.self) { i in
                                Text(Instrument.dutyLabels[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Arpeggio") {
                    Picker("Shape", selection: Binding(
                        get: { studio.song.tracks[channel].instrument.arpeggio },
                        set: { studio.song.tracks[channel].instrument.arpeggio = $0; studio.pushInstrument(channel) })
                    ) {
                        ForEach(arps, id: \.name) { arp in
                            Text(arp.name).tag(arp.offsets)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Cycles through the chord tones fast enough to sound like one voice — the classic way to fake a chord on a single channel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Clear this track", role: .destructive) {
                        studio.clearTrack(channel)
                    }
                }
            }
            .navigationTitle(kind.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func slider(title: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double>,
                        display: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(display(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range).tint(accent)
        }
    }
}
