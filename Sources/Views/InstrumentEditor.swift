import SwiftUI

/// Sheet for shaping one track's voice.
struct InstrumentEditor: View {
    @Bindable var studio: Studio
    let index: Int
    @Environment(\.dismiss) private var dismiss

    private var kind: ChannelKind { studio.song.tracks[safe: index]?.kind ?? .pulse1 }
    private var accent: Color { Theme.color(for: kind) }

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
                Section("Channel") {
                    Picker("Waveform", selection: Binding(
                        get: { kind },
                        set: { studio.setKind($0, for: index) })
                    ) {
                        ForEach(ChannelKind.allCases, id: \.self) { k in
                            Text(k.name).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Switching waveform keeps this track's notes and loads the new channel's default sound.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Level") {
                    slider(title: "Volume",
                           value: Binding(
                               get: { studio.song.tracks[index].instrument.volume },
                               set: { studio.song.tracks[index].instrument.volume = $0; studio.pushInstrument(index) }),
                           range: 0...1,
                           display: { "\(Int($0 * 100))%" })

                    slider(title: "Decay",
                           value: Binding(
                               get: { studio.song.tracks[index].instrument.decay },
                               set: { studio.song.tracks[index].instrument.decay = $0; studio.pushInstrument(index) }),
                           range: 0.03...4.0,
                           display: { $0 >= 3.99 ? "hold" : String(format: "%.2fs", $0) })
                }

                if kind.hasDuty {
                    Section("Pulse width") {
                        Picker("Duty", selection: Binding(
                            get: { studio.song.tracks[index].instrument.duty },
                            set: { studio.song.tracks[index].instrument.duty = $0; studio.pushInstrument(index) })
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
                        get: { studio.song.tracks[index].instrument.arpeggio },
                        set: { studio.song.tracks[index].instrument.arpeggio = $0; studio.pushInstrument(index) })
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
                    Button {
                        studio.duplicateTrack(at: index)
                        dismiss()
                    } label: {
                        Label("Duplicate track", systemImage: "plus.square.on.square")
                    }
                    .disabled(!studio.song.canAddTrack)

                    // Notes live in patterns, so this only empties the one on
                    // screen — the other patterns keep their part.
                    Button("Clear this track in pattern \(studio.pattern.name)", role: .destructive) {
                        studio.clearTrack(index)
                    }

                    Button("Delete track", role: .destructive) {
                        studio.removeTrack(at: index)
                        dismiss()
                    }
                    .disabled(studio.song.tracks.count <= 1)
                } footer: {
                    if !studio.song.canAddTrack {
                        Text("A song can hold up to \(Chip.maxTracks) tracks.")
                    }
                }
            }
            .navigationTitle(studio.song.fullLabel(for: index))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
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
