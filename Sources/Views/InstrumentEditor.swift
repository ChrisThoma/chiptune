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

/// One track's voice: waveform, level, pulse width and arpeggio.
///
/// Presented over the grid on a phone and on a portrait iPad, and docked into
/// the side column on a landscape one — see `ChipLayout.docksInstrumentEditor`.
/// The controls are the same either way; only the chrome around them differs,
/// because a docked panel has nothing to dismiss and no title bar to put a
/// Done button in.
struct InstrumentEditor: View {
    @Bindable var studio: Studio
    let index: Int
    /// Living in the side column rather than arriving over the grid.
    var docked = false
    /// Presented as a popover rather than a sheet, which needs a stated size —
    /// see `ChipLayout.presentsInstrumentAsPopover` for why this is passed in
    /// rather than read from the environment.
    var popover = false
    @Environment(\.dismiss) private var dismiss
    // Snapshot which track a dialog targets at the moment it's raised, rather
    // than reading `index` (or `studio.selectedTrack`) again when it resolves:
    // in the docked layout this view stays alive while the grid's header
    // buttons keep changing `studio.selectedTrack` underneath it, so a live
    // read at confirm-time could act on whatever track got selected while the
    // dialog was still up, not the one the user opened it for.
    @State private var pendingClearIndex: Int?
    @State private var pendingDeleteIndex: Int?

    private var kind: ChannelKind { studio.song.tracks[safe: index]?.kind ?? .pulse1 }
    private var accent: Color { Theme.color(for: kind) }
    private var held: Bool { studio.song.tracks[safe: index]?.instrument.sustain ?? false }

    /// "Custom" once the sound has been edited away from every preset, which is
    /// the honest answer — the sliders below are the truth, not the menu.
    private var presetName: String {
        guard let instrument = studio.song.tracks[safe: index]?.instrument else { return "Custom" }
        return InstrumentPreset.matching(instrument, kind: kind)?.name ?? "Custom"
    }

    /// Replaces the whole instrument, and deliberately leaves the track's name
    /// alone — picking "Snare" shouldn't rename a track someone called Drums.
    private func apply(_ preset: InstrumentPreset) {
        guard studio.song.tracks.indices.contains(index) else { return }
        studio.checkpoint()
        studio.song.tracks[index].instrument = preset.instrument
        studio.pushInstrument(index)
    }

    /// Preset arpeggio shapes; empty offsets mean the note plays straight.
    /// `spoken` rides along because VoiceOver should say "Major", not "Maj" —
    /// deriving it from the button label meant a relabel silently broke the
    /// spoken name.
    private struct ArpShape: Identifiable {
        let label: String
        let spoken: String
        let offsets: [Int]
        var id: [Int] { offsets }
    }

    private let arps: [ArpShape] = [
        ArpShape(label: "Off", spoken: "Off", offsets: []),
        ArpShape(label: "Maj", spoken: "Major", offsets: [0, 4, 7]),
        ArpShape(label: "Min", spoken: "Minor", offsets: [0, 3, 7]),
        ArpShape(label: "Oct", spoken: "Octave", offsets: [0, 12]),
        ArpShape(label: "5th", spoken: "Fifth", offsets: [0, 7]),
    ]

    var body: some View {
        if docked {
            dockedPanel
        } else {
            presentedPanel
        }
    }

    /// The track can vanish while this is up — deleted from here, or removed
    /// elsewhere while it was open. Rendering the form against a dead index
    /// would trap in the bindings below, so a presented editor closes itself
    /// and a docked one waits for the selection to land somewhere real.
    private var trackExists: Bool { studio.song.tracks.indices.contains(index) }

    private var presentedPanel: some View {
        NavigationStack {
            if trackExists {
                editor
                    .navigationTitle(studio.song.fullLabel(for: index))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }.tint(accent)
                        }
                    }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .compactSheetDetents(!popover)
        .popoverSized(popover)
        .preferredColorScheme(.dark)
    }


    /// No navigation bar: the column it sits in is already labelled by the
    /// track header the selection highlights, and a title bar here would read
    /// as a second window inside the editor.
    private var dockedPanel: some View {
        VStack(spacing: 0) {
            if trackExists {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .symbolFont(11, weight: .semibold)
                    Text(studio.song.fullLabel(for: index).uppercased())
                        .chipFont(11, weight: .bold)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sound settings for \(studio.song.fullLabel(for: index))")

                editor
            }
        }
    }

    private var editor: some View {
            Form {
                Section("Preset") {
                    Menu {
                        ForEach(InstrumentPreset.presets(for: kind)) { preset in
                            Button(preset.name) { apply(preset) }
                        }
                    } label: {
                        HStack {
                            Text("Sound")
                            Spacer()
                            Text(presetName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Sound preset")
                    .accessibilityValue(presetName)

                    Text("A starting point. Every control below stays yours to move.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Name") {
                    // Placeholder rather than a pre-filled value: an untouched
                    // track has no name, and showing "TRI" in the field would
                    // make clearing it look like it did something.
                    TextField(kind.fullName, text: trackName)
                        .accessibilityLabel("Track name")
                }

                Section("Channel") {
                    Picker("Waveform", selection: Binding(
                        get: { kind },
                        set: { studio.setKind($0, for: index) })
                    ) {
                        ForEach(ChannelKind.allCases, id: \.self) { k in
                            // Full names here — "PU1 PU2 TRI NOI" was the
                            // densest jargon in the app, in the one row with
                            // room to spell it out.
                            Text(k.fullName).minimumScaleFactor(0.7).tag(k)
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

                Section {
                    slider(title: "Volume",
                           value: instrument(\.volume, default: 0.5, kind: .volume(index)),
                           range: 0...1,
                           display: { "\(Int($0 * 100))%" })

                    // Hold used to be the far end of the decay slider, which
                    // meant the triangle shipped droning with nothing on screen
                    // saying so and no obvious way out.
                    Toggle("Hold", isOn: instrument(\.sustain, default: false, kind: .sustain(index)))
                        .tint(accent)

                    slider(title: "Decay",
                           value: instrument(\.decay, default: 0.3, kind: .decay(index)),
                           range: 0.03...4.0,
                           display: { String(format: "%.2fs", $0) })
                        .disabled(held)
                        .opacity(held ? 0.4 : 1)
                } header: {
                    Text("Level")
                } footer: {
                    Text(held
                         ? "The note sounds until the next one on this track, or an OFF."
                         : "The note fades out over the decay time.")
                }

                if kind.hasDuty {
                    Section("Pulse width") {
                        Picker("Duty", selection: instrument(\.duty, default: 0, kind: .duty(index))) {
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
                    Picker("Shape", selection: instrument(\.arpeggio, default: [], kind: .arpeggio(index))) {
                        ForEach(arps) { arp in
                            Text(arp.label).tag(arp.offsets)
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
                        pendingClearIndex = index
                    }

                    Button("Delete track", role: .destructive) {
                        pendingDeleteIndex = index
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
            .confirmationDialog("Clear this track in pattern \(studio.pattern.name)?",
                                isPresented: Binding(get: { pendingClearIndex != nil },
                                                      set: { if !$0 { pendingClearIndex = nil } }),
                                titleVisibility: .visible) {
                if let target = pendingClearIndex {
                    Button("Clear track", role: .destructive) { studio.clearTrack(target) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its notes in the other patterns are left alone.")
            }
            .confirmationDialog(
                pendingDeleteIndex.map { "Delete \(studio.song.fullLabel(for: $0))?" } ?? "",
                isPresented: Binding(get: { pendingDeleteIndex != nil },
                                      set: { if !$0 { pendingDeleteIndex = nil } }),
                titleVisibility: .visible) {
                if let target = pendingDeleteIndex {
                    Button("Delete track", role: .destructive) {
                        // Dismiss first and remove on the next main-actor turn, so
                        // SwiftUI never re-renders this sheet's bindings against
                        // the deleted index.
                        dismiss()
                        DispatchQueue.main.async { studio.removeTrack(at: target) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(ConfirmationCopy.deleteTrack)
            }
    }

    /// Binding into the edited track's instrument that survives the track
    /// disappearing mid-render: reads fall back to a placeholder, writes on a
    /// stale index are dropped.
    /// Separate from `instrument(_:default:)` because a name never reaches the
    /// DSP — there is nothing to push. Non-optional so `TextField` can bind to
    /// it; emptying the field clears the name back to nil.
    private var trackName: Binding<String> {
        Binding(
            get: { studio.song.tracks[safe: index]?.name ?? "" },
            set: { newValue in
                guard studio.song.tracks.indices.contains(index) else { return }
                // Coalesced: typing a name is a stream of writes and should be
                // one undo, not one per keystroke.
                studio.checkpoint(coalescing: true, kind: .trackName(index))
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                studio.song.tracks[index].name =
                    trimmed.isEmpty ? nil : String(newValue.prefix(Track.maxNameLength))
            })
    }

    private func instrument<T>(_ keyPath: WritableKeyPath<Instrument, T>,
                               default fallback: T,
                               kind: Studio.CheckpointKind) -> Binding<T> {
        Binding(
            get: { studio.song.tracks[safe: index]?.instrument[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard studio.song.tracks.indices.contains(index) else { return }
                // Before the write, so undo restores the sound as it was.
                // Coalesced: a slider drag is a stream of writes and should be
                // one undo, not one per pixel.
                studio.checkpoint(coalescing: true, kind: kind)
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
        return arps.first { $0.offsets == offsets }?.spoken ?? "Custom"
    }

    private func adjustChannel(_ direction: AccessibilityAdjustmentDirection) {
        let kinds = ChannelKind.allCases
        guard let current = kinds.firstIndex(of: kind),
              let next = adjustedIndex(current, count: kinds.count, direction: direction),
              next != current else { return }
        studio.setKind(kinds[next], for: index)
    }

    private func adjustPulseWidth(_ direction: AccessibilityAdjustmentDirection) {
        let binding = instrument(\.duty, default: 0, kind: .duty(index))
        guard let next = adjustedIndex(binding.wrappedValue,
                                       count: Instrument.dutyLabels.count,
                                       direction: direction),
              next != binding.wrappedValue else { return }
        binding.wrappedValue = next
    }

    private func adjustArpeggio(_ direction: AccessibilityAdjustmentDirection) {
        let binding = instrument(\.arpeggio, default: [], kind: .arpeggio(index))
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

private extension View {
    /// A popover takes its size from its content and has no detents, so it
    /// needs one stated. A sheet does not, and a minimum height taller than
    /// the medium detent would fight the detent it was given.
    @ViewBuilder
    func popoverSized(_ apply: Bool) -> some View {
        if apply {
            frame(minWidth: 380, idealWidth: 420, minHeight: 420, idealHeight: 520)
        } else {
            self
        }
    }
}
