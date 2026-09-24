import SwiftUI
import UIKit

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
    //
    // The pattern travels with the track for the same reason one dimension up:
    // in SONG mode the playhead moves `studio.selectedPattern` at every
    // arrangement boundary, so a live read would empty the track in whichever
    // pattern happened to be sounding at confirm time.
    private struct ClearTarget {
        let track: Int
        let pattern: Int
    }
    @State private var pendingClear: ClearTarget?
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
        ScrollViewReader { proxy in
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

                Section {
                    // Placeholder rather than a pre-filled value: an untouched
                    // track has no name, and showing "TRI" in the field would
                    // make clearing it look like it did something.
                    TextField(kind.fullName, text: trackName)
                        .accessibilityLabel("Track name")
                } header: {
                    Text("Name")
                } footer: {
                    // trackName's own setter already caps every keystroke at
                    // Track.maxNameLength (see below), so typing past the
                    // limit was silently swallowed with nothing on screen to
                    // explain why the field stopped changing. This mirrors
                    // PatternRenameSheet's counter so the cap is visible
                    // instead of feeling like a stuck keyboard.
                    Text("Up to \(Track.maxNameLength) characters — \(trackName.wrappedValue.count) of \(Track.maxNameLength) used.")
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
                    //
                    // The native switch alone only registers a ~0.3s held
                    // press here, not a normal quick tap — reproduced 5/5 on
                    // device, with every other control in this Form (sliders,
                    // segmented pickers) responding correctly to a quick tap
                    // using the same binding pattern. No stray gesture,
                    // background modifier, or custom ToggleStyle was found
                    // nearby to explain it, so this simultaneous tap gesture
                    // guarantees a quick tap flips the switch regardless of
                    // the underlying UIKit recognition issue.
                    Toggle("Hold", isOn: holdBinding)
                        .tint(accent)
                        .simultaneousGesture(
                            TapGesture().onEnded { holdBinding.wrappedValue.toggle() }
                        )

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
                    .id("duty")
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
                .id("arpeggio")

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
                        pendingClear = ClearTarget(track: index, pattern: studio.selectedPattern)
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
            .alert(
                pendingClear.map { "Clear this track in pattern \(studio.song.patterns[safe: $0.pattern]?.name ?? "")?" } ?? "",
                isPresented: Binding(get: { pendingClear != nil },
                                     set: { if !$0 { pendingClear = nil } })) {
                if let target = pendingClear {
                    Button("Clear track", role: .destructive) {
                        studio.clearTrack(target.track, in: target.pattern)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(ConfirmationCopy.clearTrack)
            }
            .alert(
                pendingDeleteIndex.map { "Delete \(studio.song.fullLabel(for: $0))?" } ?? "",
                isPresented: Binding(get: { pendingDeleteIndex != nil },
                                      set: { if !$0 { pendingDeleteIndex = nil } })) {
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
            // The screenshot shoot's phone frame lands on this sheet
            // already open (see `ScreenshotMode.instrument` in
            // `ContentView`), and the Name/Channel fields at the top of the
            // Form make for a dull shot — the sound controls further down are
            // the point. Scrolled only in that mode: an ordinary open should
            // land where the Form always has, at the top.
            .task {
                guard ScreenshotMode.requested == .instrument else { return }
                // The Form hasn't laid out its rows on the frame this task
                // starts in; scrolling immediately is a no-op. The shoot's
                // sheet shots already settle for several seconds before the
                // screenshot fires, so this wait is invisible to them.
                try? await Task.sleep(nanoseconds: 200_000_000)
                // Anchored a little below the top: the sheet's title bar
                // overlays the first few points of the Form, and `.top`
                // would tuck the section header underneath it.
                withAnimation(nil) {
                    proxy.scrollTo(kind.hasDuty ? "duty" : "arpeggio",
                                   anchor: UnitPoint(x: 0.5, y: 0.1))
                }
            }
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

    /// Same binding the Hold `Toggle` uses, hoisted so both the `Toggle`
    /// itself and its `simultaneousGesture` fallback read and write the exact
    /// same underlying value instead of two independently-constructed
    /// bindings that merely happen to agree.
    private var holdBinding: Binding<Bool> {
        instrument(\.sustain, default: false, kind: .sustain(index))
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

