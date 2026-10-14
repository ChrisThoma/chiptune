import SwiftUI

/// What the export section says under its button when the render wouldn't be
/// worth keeping. nil when there is nothing to warn about.
enum ExportNotesFooter {
    static func text(for song: Song) -> String? {
        guard !song.hasNotes else {
            // Muting everything is a legitimate mix, so the export still runs
            // — it just wouldn't have anything in it.
            return song.hasAudibleNotes
                ? nil
                : "Every track with notes is muted, so the export would be silent."
        }
        guard song.hasNotesAnywhere else { return "This song has no notes yet." }
        return "Its notes are in a pattern the arrangement doesn't play. Add that pattern to the arrangement to export it."
    }
}

extension ExportNotesFooter {
    /// What sits under the Export button for `format`. A WAV keeps the notes
    /// above. A MIDI file still carries a muted or 0% track's notes (at
    /// volume 0; "silent" to the user, who sets it as 0%), or, for such a
    /// drum track beside one that plays, an empty
    /// track (see `MidiExport.emptiedTracks`), so the "would be silent"
    /// warning is replaced by a line saying where those tracks went; the
    /// no-notes messages stay, since there is nothing to export either way.
    static func text(for song: Song, format: ExportOptions.Format) -> String? {
        switch format {
        case .wav:
            return text(for: song)
        case .midi:
            guard song.hasNotes else { return text(for: song) }
            var line = "The whole arrangement once — \(Format.clock(song.arrangementDuration)). Arpeggios come out as the note you wrote."
            // Worked out once: only a silent track with notes the
            // arrangement plays has anything in the file to speak of.
            let chain = song.chain
            let emptied = MidiExport.emptiedTracks(of: song, chain: chain)
            let silentWithNotes = song.tracks.indices.filter {
                MidiExport.isSilent(song.tracks[$0]) && MidiExport.reaches($0, of: song, chain: chain)
            }
            let emptiedCount = silentWithNotes.filter(emptied.contains).count
            let silencedCount = silentWithNotes.count - emptiedCount
            if silencedCount == 1 {
                line += " A muted or silent track keeps its notes in the file, turned all the way down."
            } else if silencedCount > 1 {
                line += " Muted or silent tracks keep their notes in the file, turned all the way down."
            }
            if emptiedCount == 1 {
                line += " A muted or silent drum track is left empty, because all drum tracks share one part in the file."
            } else if emptiedCount > 1 {
                line += " Muted or silent drum tracks are left empty, because all drum tracks share one part in the file."
            }
            return line
        }
    }
}

/// What sits under the WAV/MIDI picker. A MIDI file is the one a beginner
/// can be surprised by: it opens in another app with that app's sounds, not
/// the chip's. nil for a WAV, which is the sound itself.
enum ExportFormatFooter {
    static func text(for format: ExportOptions.Format) -> String? {
        switch format {
        case .wav: return nil
        case .midi:
            return "A MIDI file holds your notes, not the chip sounds. The app you open it in plays them with its own instruments."
        }
    }
}

/// Whether the repeats and ending controls can still be changed. They are
/// frozen for the length of a render: it keeps the settings it started with, so
/// an edit made mid-render would only make the readout disagree with the file.
/// Takes the same flag the progress bar and Cancel export are shown from.
enum ExportControls {
    static func settingsLocked(isExporting: Bool) -> Bool { isExporting }

    /// Whether the Export button comes back once the render it started has
    /// finished. A failed or canceled one frees it for another try. One that
    /// left a file keeps it: the panel is coming down for the share sheet,
    /// which reads that file as it comes up, and a second render started in
    /// the meantime would clear it first. The panel comes back fresh.
    static func freesExportButton(startedAttempt: Int?, completedAttempt: Int, producedFile: Bool) -> Bool {
        guard let startedAttempt, completedAttempt >= startedAttempt else { return false }
        return !producedFile
    }
}

/// Export options, and the progress of the render they kick off.
///
/// A sheet rather than more items in the ••• menu: the render can take real
/// time on a long arrangement, and it needs somewhere to show how far along it
/// is and a way to stop it.
struct ExportSheet: View {
    @Bindable var studio: Studio
    /// Presented as a popover over the ••• menu rather than as a sheet, which
    /// is what an iPad-shaped window does with it. Passed in rather than read
    /// from the environment: a popover's content is handed a compact size
    /// class whatever the window behind it is.
    var popover = false
    @Environment(\.dismiss) private var dismiss
    // Separate from `studio.isExporting`: SwiftUI can miss a render that starts
    // and finishes between update passes. The model's monotonic attempt token
    // cannot be coalesced away, so failures and cancellations reliably retry.
    @State private var startedAttempt: Int?

    private var settingsLocked: Bool {
        ExportControls.settingsLocked(isExporting: studio.isExporting)
    }

    private var format: ExportOptions.Format { studio.exportOptions.format }

    private var repeatsSection: some View {
        Section {
            HStack {
                // The stepper carries both for VoiceOver, as one
                // adjustable "Repeats" element.
                Text("Repeats")
                    .accessibilityHidden(true)
                Spacer()
                Text("\(studio.exportOptions.loopCount)×")
                    .chipFont(15, weight: .bold)
                    .foregroundStyle(Theme.dim)
                    .accessibilityHidden(true)
                // Not the system Stepper; see PlainStepper.
                PlainStepper(value: $studio.exportOptions.loopCount,
                             range: 1...ExportOptions.maxLoopCount,
                             isEnabled: !settingsLocked,
                             accessibilityLabel: "Repeats",
                             accessibilityValue: Format.count(studio.exportOptions.loopCount, "time"))
            }
            // The stepper's own disabled styling is barely visible
            // against this row, so dim the whole row explicitly.
            .opacity(settingsLocked ? 0.4 : 1)
        } footer: {
            Text("The whole arrangement, \(Format.count(studio.exportOptions.loopCount, "time")) — \(duration).")
        }
    }

    private var endingSection: some View {
        Section {
            Picker("Ending", selection: $studio.exportOptions.tailMode) {
                Text("Seamless loop").tag(ExportOptions.TailMode.seamlessLoop)
                Text("Ring out").tag(ExportOptions.TailMode.ringOut)
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityHidden(true)
            .disabled(settingsLocked)
        } header: {
            Text("Ending")
        } footer: {
            Text(studio.exportOptions.tailMode == .seamlessLoop
                 ? "The last notes ring on into the start, so the file loops with no gap. Best for dropping into something else."
                 : "The last notes fade out past the end and the file finishes in silence. Best when the file is the finished thing.")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $studio.exportOptions.format) {
                        ForEach(ExportOptions.Format.allCases, id: \.self) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityLabel("Format")
                    // Like the repeats: the render keeps the format it started
                    // with, so a mid-render switch would only mislabel the file.
                    .disabled(settingsLocked)
                } footer: {
                    if let text = ExportFormatFooter.text(for: format) {
                        Text(text)
                    }
                }

                // A MIDI file is the arrangement once, so neither control
                // applies to it.
                if format == .wav {
                    repeatsSection
                    endingSection
                }

                Section {
                    if studio.isExporting {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: studio.exportProgress)
                                .tint(Theme.accentGreen)
                            Text("Rendering… \(Int(studio.exportProgress * 100))%")
                                .chipFont(11)
                                .foregroundStyle(Theme.dim)
                        }
                        Button("Cancel export", role: .destructive) {
                            studio.cancelExport()
                        }
                    } else {
                        Button {
                            guard startedAttempt == nil else { return }
                            startedAttempt = studio.export()
                        } label: {
                            Label("Export \(format.label)", systemImage: "square.and.arrow.up")
                        }
                        .disabled(startedAttempt != nil || !studio.song.hasNotes)
                    }
                } footer: {
                    if let text = ExportNotesFooter.text(for: studio.song, format: format) {
                        Text(text)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            // Carries the Ending picker's VoiceOver adjustable. Deliberately
            // not attached inside the Form: a `.background` on the Picker, or
            // on the Section/header around it, gets duplicated onto every
            // List row the `.inline` style and the Form generate — landing
            // VoiceOver on several identical "Ending" elements instead of
            // one. Attached to the whole Form instead, where it exists
            // exactly once.
            .overlay(alignment: .topLeading) {
                // Only while the Ending picker exists: a MIDI export has no
                // ending, and a hidden adjustable would still be announced.
                if format == .wav {
                    accessibilitySelector(
                        label: "Ending",
                        value: studio.exportOptions.tailMode == .seamlessLoop ? "Seamless loop" : "Ring out",
                        adjust: { direction in
                            guard !settingsLocked else { return }
                            studio.exportOptions.tailMode = studio.exportOptions.tailMode.adjusted(direction)
                        })
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(settingsLocked)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        studio.cancelExport()
                        dismiss()
                    }
                }
            }
            .tint(Theme.text)
        }
        .onChange(of: studio.completedExportAttempt) { _, completedAttempt in
            guard ExportControls.freesExportButton(startedAttempt: startedAttempt,
                                                   completedAttempt: completedAttempt,
                                                   producedFile: studio.exportURL != nil) else { return }
            startedAttempt = nil
        }
        .errorAlert("Export failed", message: $studio.exportError)
        .popoverSized(popover)
        .preferredColorScheme(.dark)
    }

    /// Rough length of the file, so the repeat count means something.
    private var duration: String {
        var seconds = studio.song.arrangementDuration * Double(studio.exportOptions.loopCount)
        if studio.exportOptions.tailMode == .ringOut { seconds += WavExport.tailSeconds(for: studio.song) }
        return Format.clock(seconds)
    }
}
