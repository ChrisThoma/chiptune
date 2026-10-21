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
        case .wav, .video:
            return text(for: song)
        case .midi:
            guard song.hasNotes else { return text(for: song) }
            var line = "The whole arrangement once: \(Format.clock(song.arrangementDuration)). Arpeggios come out as the note you wrote."
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
        case .video: return "A tall video for Instagram, TikTok and YouTube."
        case .midi:
            return "A MIDI file holds your notes, not the chip sounds. The app you open it in plays them with its own instruments."
        }
    }
}

/// What sits under the Grid/Cartridge picker, so the two names say what
/// each video looks like before one is rendered.
enum ExportStyleFooter {
    static func text(for style: ExportOptions.VideoStyle) -> String {
        switch style {
        case .grid: return "The pattern grid scrolls along as the song plays, the way it looks in the editor."
        case .cover: return "A game cartridge with the song's title and a bar for each track that jumps with its notes."
        }
    }
}

/// The line under the progress bar. "Exporting", not "Rendering", since it
/// covers both formats; only a WAV reports progress, so only a WAV gives a
/// percentage, where a MIDI one would sit at 0%.
enum ExportProgressText {
    static func text(format: ExportOptions.Format, progress: Double) -> String {
        switch format {
        case .wav, .video: return "Exporting… \(Int(progress * 100))%"
        case .midi: return "Exporting…"
        }
    }
}

/// How tall the iPad's export popover asks to be, by format. A MIDI export
/// has no repeats or ending, so the WAV height left a block of empty space
/// under its button. Measured on a 13-inch iPad at the default text size:
/// the WAV form runs to about 530pt, the MIDI one to about 280pt, with room
/// left in each for a footer a line or two longer. Width and Dynamic Type
/// scaling are `popoverSized`'s as before.
enum ExportPopoverSize {
    static func heights(for format: ExportOptions.Format) -> (min: CGFloat, ideal: CGFloat) {
        switch format {
        case .wav: return (min: 420, ideal: 560)
        case .video: return (min: 480, ideal: 620)
        case .midi: return (min: 300, ideal: 340)
        }
    }
}

/// The length readout under Repeats, and what to say when the file will run
/// past what a video can be.
enum ExportLength {
    /// The longest a YouTube Short can be. A longer video isn't cut off;
    /// YouTube posts it as a regular video instead.
    static let shortsLimitSeconds = 180.0

    /// Why the Export button is off for a video past `VideoExport.maxSeconds`:
    /// the footer's warning and the button's VoiceOver hint.
    static var tooLongForVideo: String {
        "Too long for a video. The limit is \(Format.clock(VideoExport.maxSeconds))."
    }

    /// Rough length of the file, so the repeat count means something. Reads
    /// the effective ending, so a video's length includes its tail.
    ///
    /// A video's is exact: it comes from the same `VideoTimeline` (normalized
    /// song, whole samples per step, truncated tail) that `VideoExport`
    /// checks against the cap, so the Export button is never offered for a
    /// video the renderer would then refuse as too long.
    static func seconds(song: Song, options: ExportOptions) -> Double {
        if options.format == .video { return VideoTimeline(song: song, options: options).seconds }
        var seconds = song.arrangementDuration * Double(options.loopCount)
        if options.effectiveTailMode == .ringOut { seconds += WavExport.tailSeconds(for: song) }
        return seconds
    }

    /// nil for anything but a video that runs long.
    static func warning(format: ExportOptions.Format, seconds: Double) -> String? {
        guard format == .video else { return nil }
        if seconds > VideoExport.maxSeconds {
            return tooLongForVideo
        }
        if seconds > shortsLimitSeconds {
            return "Over \(Format.clock(shortsLimitSeconds)), YouTube posts it as a regular video, not a Short."
        }
        return nil
    }
}

/// How many repeats a video starts at when the user hasn't picked a count.
enum ExportRepeats {
    /// The song a video should at least show, before its ring-out.
    static let videoBodySeconds = 10.0

    /// The smallest count, up to `ExportOptions.maxLoopCount`, whose passes
    /// (before the tail) run at least `videoBodySeconds`. The starter song
    /// is 1.8 s, so it gets 6.
    static func forVideo(song: Song) -> Int {
        let pass = song.arrangementDuration
        guard pass > 0 else { return 1 }
        // A hair of slack so a pass that divides ten exactly isn't pushed
        // one count further by rounding.
        let needed = Int((videoBodySeconds / pass - 1e-9).rounded(.up))
        return min(max(needed, 1), ExportOptions.maxLoopCount)
    }
}

/// The readout under Repeats: the count and the file's length, then for a
/// video that it rings out and any length warning.
enum ExportLengthFooter {
    static func text(format: ExportOptions.Format, loopCount: Int, seconds: Double) -> String {
        var line = "The whole arrangement, \(Format.count(loopCount, "time")): \(Format.clock(seconds))."
        if format == .video { line += " Then it rings out." }
        guard let warning = ExportLength.warning(format: format, seconds: seconds) else { return line }
        return "\(line) \(warning)"
    }
}

/// What VoiceOver hears while a render runs. A video can take a minute, and
/// a bar that only moves on screen tells someone who can't see it nothing.
enum ExportAnnouncement {
    static let canceled = "Export canceled"

    /// Said as the render starts, and the progress row's label.
    static func started(format: ExportOptions.Format) -> String {
        format == .video ? "Exporting video" : "Exporting"
    }

    /// The quarters worth saying along the way. Not 100%: the end is the
    /// share sheet coming up.
    static let milestones = [0.25, 0.5, 0.75]

    /// The quarter crossed going from `old` to `new`, the latest one if the
    /// progress jumped past several. nil when none was crossed, including
    /// the reset to 0 when a render ends.
    static func milestone(from old: Double, to new: Double) -> String? {
        guard let crossed = milestones.last(where: { old < $0 && $0 <= new }) else { return nil }
        return Format.percent(crossed)
    }

    /// The progress row's value. A MIDI export reports no progress, so it
    /// has none.
    static func progressValue(format: ExportOptions.Format, progress: Double) -> String? {
        switch format {
        // Truncated like the line under the bar, so the two never disagree.
        case .wav, .video: return "\(Int(progress * 100))%"
        case .midi: return nil
        }
    }

    static func post(_ text: String) {
        var announcement = AttributedString(text)
        // Not cut off by the focus moving to Cancel export as it starts.
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }
}

/// Whether the repeats and ending controls can still be changed. They are
/// frozen for the length of a render: it keeps the settings it started with, so
/// an edit made mid-render would only make the readout disagree with the file.
/// Takes the same flag the progress bar and Cancel export are shown from.
enum ExportControls {
    static func settingsLocked(isExporting: Bool) -> Bool { isExporting }

    /// A MIDI file is the arrangement once, so repeats don't apply to it.
    static func showsRepeats(_ format: ExportOptions.Format) -> Bool {
        format == .wav || format == .video
    }

    /// Only a WAV has an ending to choose: a video always rings out.
    static func showsEnding(_ format: ExportOptions.Format) -> Bool { format == .wav }

    /// Only a video has a picture to style.
    static func showsStyle(_ format: ExportOptions.Format) -> Bool { format == .video }

    /// Whether the Export button is off because the file couldn't be made:
    /// a video past `VideoExport.maxSeconds` is refused before it renders.
    static func blocksExport(format: ExportOptions.Format, seconds: Double) -> Bool {
        format == .video && seconds > VideoExport.maxSeconds
    }

    /// What VoiceOver hears on an Export button that `blocksExport` turned
    /// off: the footer says why, but VoiceOver doesn't read it with the
    /// button. nil whenever the length isn't what's stopping it.
    static func disabledHint(format: ExportOptions.Format, seconds: Double) -> String? {
        blocksExport(format: format, seconds: seconds) ? ExportLength.tooLongForVideo : nil
    }

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Separate from `studio.isExporting`: SwiftUI can miss a render that starts
    // and finishes between update passes. The model's monotonic attempt token
    // cannot be coalesced away, so failures and cancellations reliably retry.
    @State private var startedAttempt: Int?
    /// VoiceOver moves to Cancel export as a render starts: the Export
    /// button it was on has just gone.
    @AccessibilityFocusState private var cancelFocused: Bool

    private var settingsLocked: Bool {
        ExportControls.settingsLocked(isExporting: studio.isExporting)
    }

    private var format: ExportOptions.Format { studio.exportOptions.format }

    // The stepper carries both for VoiceOver, as one adjustable "Repeats"
    // element.
    private var repeatsLabel: some View {
        Text("Repeats")
            .accessibilityHidden(true)
    }

    private var repeatsCount: some View {
        Text("\(studio.exportOptions.loopCount)×")
            .chipFont(15, weight: .bold)
            .foregroundStyle(Theme.dim)
            .accessibilityHidden(true)
    }

    // Not the system Stepper; see PlainStepper.
    private var repeatsStepper: some View {
        PlainStepper(value: Binding(get: { studio.exportOptions.loopCount },
                                    set: { studio.exportOptions.setLoopCount($0) }),
                     range: 1...ExportOptions.maxLoopCount,
                     isEnabled: !settingsLocked,
                     accessibilityLabel: "Repeats",
                     accessibilityValue: Format.count(studio.exportOptions.loopCount, "time"))
    }

    private var repeatsControls: some View {
        HStack {
            repeatsCount
            repeatsStepper
        }
        .fixedSize()
    }

    private var repeatsSection: some View {
        Section {
            // On one line while it fits; at the largest text sizes the label
            // takes a line of its own rather than hyphenating beside the
            // count and the stepper.
            ViewThatFits(in: .horizontal) {
                HStack {
                    repeatsLabel.fixedSize()
                    Spacer()
                    repeatsControls
                }
                VStack(alignment: .leading, spacing: 8) {
                    repeatsLabel
                    HStack {
                        repeatsCount
                        Spacer()
                        repeatsStepper
                    }
                }
            }
            // The stepper's own disabled styling is barely visible
            // against this row, so dim the whole row explicitly.
            .opacity(settingsLocked ? 0.4 : 1)
        } footer: {
            Text(lengthFooter)
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

    private var styleSection: some View {
        Section {
            stylePicker
                .disabled(settingsLocked)
                // Dimmed like the repeats row: the disabled picker barely
                // shows it.
                .opacity(settingsLocked ? 0.4 : 1)
        } header: {
            // The menu row at accessibility sizes carries its own "Style"
            // label, as Format's does, so the header would say it twice.
            // VoiceOver hears "Style" from the picker's own label, so the
            // header is for the eye only.
            if !dynamicTypeSize.isAccessibilitySize {
                Text("Style")
                    .accessibilityHidden(true)
            }
        } footer: {
            Text(ExportStyleFooter.text(for: studio.exportOptions.videoStyle))
        }
    }

    /// Same shape as the format picker: segmented, a menu at the
    /// accessibility text sizes.
    @ViewBuilder
    private var stylePicker: some View {
        let picker = Picker("Style", selection: $studio.exportOptions.videoStyle) {
            ForEach(ExportOptions.VideoStyle.allCases, id: \.self) { style in
                Text(style.label).tag(style)
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker
                .pickerStyle(.menu)
                .accessibilityLabel("Style")
        } else {
            picker
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Style")
        }
    }

    /// Segmented at ordinary text sizes. A segmented control's labels don't
    /// grow with Dynamic Type, so at the accessibility sizes it becomes a
    /// menu row, whose label and value do.
    @ViewBuilder
    private var formatPicker: some View {
        let selection = Binding(get: { studio.exportOptions.format },
                                set: { studio.exportOptions.selectFormat($0, for: studio.song) })
        let picker = Picker("Format", selection: selection) {
            ForEach(ExportOptions.Format.allCases, id: \.self) { format in
                Text(format.label).tag(format)
            }
        }
        if dynamicTypeSize.isAccessibilitySize {
            picker
                .pickerStyle(.menu)
                .accessibilityLabel("Format")
        } else {
            picker
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Format")
        }
    }

    /// The Export button's label. At the accessibility text sizes the icon
    /// goes, so "Export MIDI" fits on one line rather than wrapping after
    /// "Export".
    @ViewBuilder
    private var exportLabel: some View {
        let title = "Export \(format.label)"
        if dynamicTypeSize.isAccessibilitySize {
            Text(title)
        } else {
            Label(title, systemImage: "square.and.arrow.up")
        }
    }

    /// The bar and the line under it, read by VoiceOver as one element:
    /// "Exporting video, 42%".
    private var progressRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: studio.exportProgress)
                .tint(Theme.accentGreen)
            Text(ExportProgressText.text(format: format, progress: studio.exportProgress))
                .chipFont(11)
                .foregroundStyle(Theme.dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ExportAnnouncement.started(format: format))
        .accessibilityValue(ExportAnnouncement.progressValue(format: format, progress: studio.exportProgress) ?? "")
    }

    private var cancelButton: some View {
        Button("Cancel export", role: .destructive) {
            studio.cancelExport()
            ExportAnnouncement.post(ExportAnnouncement.canceled)
        }
        .accessibilityFocused($cancelFocused)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    formatPicker
                    // Like the repeats: the render keeps the format it started
                    // with, so a mid-render switch would only mislabel the file.
                    .disabled(settingsLocked)
                    // Dimmed like Repeats and Style: a disabled segmented
                    // control barely looks it.
                    .opacity(settingsLocked ? 0.4 : 1)
                } footer: {
                    if let text = ExportFormatFooter.text(for: format) {
                        Text(text)
                    }
                }

                // A MIDI file is the arrangement once, so neither control
                // applies to it.
                if ExportControls.showsRepeats(format) { repeatsSection }
                if ExportControls.showsEnding(format) { endingSection }
                if ExportControls.showsStyle(format) { styleSection }

                Section {
                    if studio.isExporting {
                        progressRow
                        cancelButton
                    } else {
                        Button {
                            guard startedAttempt == nil else { return }
                            startedAttempt = studio.export()
                        } label: {
                            exportLabel
                        }
                        .disabled(startedAttempt != nil || !studio.song.hasNotes
                                   || ExportControls.blocksExport(format: format, seconds: length))
                        .accessibilityHint(ExportControls.disabledHint(format: format, seconds: length) ?? "")
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
                if ExportControls.showsEnding(format) {
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
        .onChange(of: studio.isExporting) { _, exporting in
            guard exporting else { return }
            ExportAnnouncement.post(ExportAnnouncement.started(format: format))
            // A pass later, once Cancel export is in the tree to take it.
            DispatchQueue.main.async { cancelFocused = true }
        }
        .onChange(of: studio.exportProgress) { old, new in
            guard studio.isExporting,
                  let milestone = ExportAnnouncement.milestone(from: old, to: new) else { return }
            ExportAnnouncement.post(milestone)
        }
        .errorAlert("Export failed", message: $studio.exportError)
        .popoverSized(popover,
                      minHeight: ExportPopoverSize.heights(for: format).min,
                      idealHeight: ExportPopoverSize.heights(for: format).ideal)
        .preferredColorScheme(.dark)
    }

    private var length: Double {
        ExportLength.seconds(song: studio.song, options: studio.exportOptions)
    }

    /// The repeats readout, with a video's length warning after it.
    private var lengthFooter: String {
        ExportLengthFooter.text(format: format, loopCount: studio.exportOptions.loopCount, seconds: length)
    }
}
