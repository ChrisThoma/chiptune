import SwiftUI
import UIKit

/// A real UIKit accessibility node for controls that iOS 17 bridges to an
/// empty tab group. Unlike a transparent SwiftUI view, this remains present in
/// the accessibility hierarchy while the segmented picker supplies the pixels
/// and direct-touch behavior above it.
private struct AccessibilityAdjustableControl: UIViewRepresentable {
    let label: String
    let value: String
    let adjust: (AccessibilityAdjustmentDirection) -> Void

    func makeUIView(context: Context) -> AdjustableView {
        AdjustableView()
    }

    func updateUIView(_ view: AdjustableView, context: Context) {
        view.accessibilityLabel = label
        view.accessibilityValue = value
        view.adjust = adjust
    }

    final class AdjustableView: UIView {
        var adjust: ((AccessibilityAdjustmentDirection) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityTraits = .adjustable
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func accessibilityIncrement() {
            adjust?(.increment)
        }

        override func accessibilityDecrement() {
            adjust?(.decrement)
        }
    }
}

/// Sheet for shaping one track's voice.
struct InstrumentEditor: View {
    @Bindable var studio: Studio
    let index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingClear = false
    @State private var confirmingDelete = false

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
            // The track can vanish while the sheet is up — deleted here, or
            // removed elsewhere while this was open. Rendering the form against
            // a dead index would trap in the bindings below.
            if studio.song.tracks.indices.contains(index) {
                editor
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var editor: some View {
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
                    .accessibilityHidden(true)
                    .background {
                        accessibilitySelector(label: "Channel",
                                              value: kind.fullName,
                                              adjust: adjustChannel)
                    }

                    Text("Switching waveform keeps this track's notes and loads the new channel's default sound.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Level") {
                    slider(title: "Volume",
                           value: instrument(\.volume, default: 0.5),
                           range: 0...1,
                           display: { "\(Int($0 * 100))%" })

                    slider(title: "Decay",
                           value: instrument(\.decay, default: 0.3),
                           range: 0.03...4.0,
                           display: { $0 >= 3.99 ? "hold" : String(format: "%.2fs", $0) })
                }

                if kind.hasDuty {
                    Section("Pulse width") {
                        Picker("Duty", selection: instrument(\.duty, default: 0)) {
                            ForEach(0..<Instrument.dutyLabels.count, id: \.self) { i in
                                Text(Instrument.dutyLabels[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityHidden(true)
                        .background {
                            accessibilitySelector(label: "Pulse width",
                                                  value: pulseWidthAccessibilityValue,
                                                  adjust: adjustPulseWidth)
                        }
                    }
                }

                Section("Arpeggio") {
                    Picker("Shape", selection: instrument(\.arpeggio, default: [])) {
                        ForEach(arps, id: \.name) { arp in
                            Text(arp.name).tag(arp.offsets)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHidden(true)
                    .background {
                        accessibilitySelector(label: "Arpeggio",
                                              value: arpeggioAccessibilityValue,
                                              adjust: adjustArpeggio)
                    }

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
                        confirmingClear = true
                    }

                    Button("Delete track", role: .destructive) {
                        confirmingDelete = true
                    }
                    .disabled(studio.song.tracks.count <= 1)
                } footer: {
                    if !studio.song.canAddTrack {
                        Text("A song can hold up to \(Chip.maxTracks) tracks.")
                    }
                }
            }
            // Without these the Form keeps its translucent system background
            // and the grid shows through the sheet. SongListView does the same.
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(studio.song.fullLabel(for: index))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.tint(accent)
                }
            }
            .confirmationDialog("Clear this track in pattern \(studio.pattern.name)?",
                                isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear track", role: .destructive) { studio.clearTrack(index) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its notes in the other patterns are left alone.")
            }
            .confirmationDialog("Delete \(studio.song.fullLabel(for: index))?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete track", role: .destructive) {
                    // Dismiss first and remove on the next main-actor turn, so
                    // SwiftUI never re-renders this sheet's bindings against
                    // the deleted index.
                    dismiss()
                    let i = index
                    DispatchQueue.main.async { studio.removeTrack(at: i) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its notes in every pattern go with it. This can't be undone.")
            }
    }

    /// Binding into the edited track's instrument that survives the track
    /// disappearing mid-render: reads fall back to a placeholder, writes on a
    /// stale index are dropped.
    private func instrument<T>(_ keyPath: WritableKeyPath<Instrument, T>,
                               default fallback: T) -> Binding<T> {
        Binding(
            get: { studio.song.tracks[safe: index]?.instrument[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard studio.song.tracks.indices.contains(index) else { return }
                // Before the write, so undo restores the sound as it was.
                // Coalesced: a slider drag is a stream of writes and should be
                // one undo, not one per pixel.
                studio.checkpoint(coalescing: true)
                studio.song.tracks[index].instrument[keyPath: keyPath] = newValue
                studio.pushInstrument(index)
            })
    }

    private var pulseWidthAccessibilityValue: String {
        let duty = studio.song.tracks[safe: index]?.instrument.duty ?? 0
        return Instrument.dutyLabels[safe: duty] ?? "Unknown"
    }

    private var arpeggioAccessibilityValue: String {
        let offsets = studio.song.tracks[safe: index]?.instrument.arpeggio ?? []
        switch arps.first(where: { $0.offsets == offsets })?.name {
        case "Maj": return "Major"
        case "Min": return "Minor"
        case "Oct": return "Octave"
        case "5th": return "Fifth"
        case let name?: return name
        case nil: return "Custom"
        }
    }

    private func adjustChannel(_ direction: AccessibilityAdjustmentDirection) {
        let kinds = ChannelKind.allCases
        guard let current = kinds.firstIndex(of: kind),
              let next = adjustedIndex(current, count: kinds.count, direction: direction),
              next != current else { return }
        studio.setKind(kinds[next], for: index)
    }

    private func adjustPulseWidth(_ direction: AccessibilityAdjustmentDirection) {
        let binding = instrument(\.duty, default: 0)
        guard let next = adjustedIndex(binding.wrappedValue,
                                       count: Instrument.dutyLabels.count,
                                       direction: direction),
              next != binding.wrappedValue else { return }
        binding.wrappedValue = next
    }

    private func adjustArpeggio(_ direction: AccessibilityAdjustmentDirection) {
        let binding = instrument(\.arpeggio, default: [])
        let current = arps.firstIndex(where: { $0.offsets == binding.wrappedValue }) ?? 0
        guard let next = adjustedIndex(current, count: arps.count, direction: direction),
              next != current else { return }
        binding.wrappedValue = arps[next].offsets
    }

    private func adjustedIndex(_ current: Int,
                               count: Int,
                               direction: AccessibilityAdjustmentDirection) -> Int? {
        switch direction {
        case .increment: return min(current + 1, count - 1)
        case .decrement: return max(current - 1, 0)
        @unknown default: return nil
        }
    }

    /// Segmented pickers are bridged to empty tab groups on iOS 17. A concrete
    /// UIKit view supplies the missing adjustable accessibility node.
    private func accessibilitySelector(
        label: String,
        value: String,
        adjust: @escaping (AccessibilityAdjustmentDirection) -> Void
    ) -> some View {
        AccessibilityAdjustableControl(label: label, value: value, adjust: adjust)
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
            Slider(value: value, in: range)
                .tint(accent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(display(value.wrappedValue))
                .accessibilityAdjustableAction { direction in
                    let step = (range.upperBound - range.lowerBound) / 10
                    switch direction {
                    case .increment:
                        value.wrappedValue = min(value.wrappedValue + step,
                                                 range.upperBound)
                    case .decrement:
                        value.wrappedValue = max(value.wrappedValue - step,
                                                 range.lowerBound)
                    @unknown default:
                        break
                    }
                }
        }
    }
}
