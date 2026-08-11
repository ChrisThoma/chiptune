import SwiftUI

/// Which screen `AppStore/shoot.sh` asked the app to open on launch.
///
/// App Store screenshots have to show that the app is more than one screen —
/// four framings of the grid is the "minimum functionality" impression
/// `AppStore/REVIEW-NOTES.md` warns about — and the screens worth showing are
/// two or three taps in. Driving those taps from outside is brittle, so the
/// shoot passes an argument instead and the app opens the sheet itself.
///
/// Launch arguments of the form `-key YES` land in `UserDefaults` for the
/// launch that passed them and nowhere else, so nothing here persists and no
/// ordinary launch sees any of it. The bare `-key` form does *not* work: the
/// value is required, or the argument is ignored and every shot silently comes
/// out as the grid.
enum ScreenshotMode {
    case arrangement, instrument, library

    static var requested: ScreenshotMode? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "shotArrangement") { return .arrangement }
        if defaults.bool(forKey: "shotEditor") { return .instrument }
        if defaults.bool(forKey: "shotLibrary") { return .library }
        return nil
    }
}

enum SongLibraryPresentation {
    /// Opening a different song routes back to the editor. This also handles a
    /// document URL arriving while the library sheet is already presented.
    static func afterOpeningSong(isPresented: Bool,
                                 previousSongID: UUID,
                                 currentSongID: UUID) -> Bool {
        isPresented && previousSongID == currentSongID
    }
}

enum SongNameFieldAccessibility {
    static let label = "Song title"
}

struct ContentView: View {
    @Bindable var studio: Studio
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingSongs = false
    @State private var showingArrangement = false
    @State private var showingShare = false
    @State private var confirmingClearPattern = false
    @State private var showingExport = false
    @State private var showingInstrument = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        // The window decides the metrics, so the layout has to be read from
        // the actual size rather than the device: an iPad in a Split View
        // slice gets the phone layout, and a rotation swaps arrangements.
        GeometryReader { geo in
            let layout = ChipLayout.resolve(size: geo.size,
                                            horizontalSizeClass: horizontalSizeClass)
            VStack(spacing: 0) {
                titleBar
                TransportBar(studio: studio, showingArrangement: $showingArrangement)
                PatternBar(studio: studio)
                if layout.usesSideKeyboard {
                    wideEditor
                } else {
                    stackedEditor
                }
            }
            .environment(\.chipLayout, layout)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSongs) {
            SongListView(studio: studio)
        }
        .onChange(of: studio.song.id) { previousSongID, currentSongID in
            showingSongs = SongLibraryPresentation.afterOpeningSong(
                isPresented: showingSongs,
                previousSongID: previousSongID,
                currentSongID: currentSongID
            )
        }
        .sheet(isPresented: $showingArrangement) {
            ArrangementView(studio: studio)
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet(studio: studio)
        }
        .sheet(isPresented: $showingShare) {
            if let url = studio.exportURL {
                ShareSheet(items: [url])
            }
        }
        // Sharing the .chipsong is immediate — the file is just the song's
        // JSON — so it needs no render and no progress.
        .sheet(isPresented: Binding(get: { studio.shareURL != nil },
                                    set: { if !$0 { studio.shareURL = nil } })) {
            if let url = studio.shareURL {
                ShareSheet(items: [url])
            }
        }
        // Export renders off the main thread; the share sheet waits for the
        // URL to land rather than racing the render.
        .onChange(of: studio.exportURL) { _, url in
            guard url != nil else { return }
            // The options sheet gets out of the way before the share sheet
            // arrives; two sheets at once is a no-op on iOS.
            showingExport = false
            showingShare = true
        }
        .confirmationDialog("Clear pattern \(studio.pattern.name)?",
                            isPresented: $confirmingClearPattern,
                            titleVisibility: .visible) {
            Button("Clear pattern", role: .destructive) { studio.clearPattern() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every track's notes in this pattern are erased.")
        }
        // Three things that used to fail without saying so. The save one
        // matters most: there's no Save button to retry with, so a write that
        // fails quietly is work quietly lost.
        .errorAlert("Save failed", message: $studio.storageError)
        .errorAlert("Export failed", message: $studio.exportError)
        .errorAlert("Audio unavailable", message: $studio.audioError)
        .errorAlert("Import failed", message: $studio.importError)
        .errorAlert("Share failed", message: $studio.shareError)
        .sheet(isPresented: $showingInstrument) {
            InstrumentEditor(studio: studio, index: 0)
        }
        // Opens whichever screen the screenshot shoot asked for. Inert unless
        // launched with one of its arguments; see `ScreenshotMode`.
        .task {
            switch ScreenshotMode.requested {
            case .arrangement: showingArrangement = true
            case .instrument: showingInstrument = true
            case .library: showingSongs = true
            case .none: break
            }
        }
    }

    /// Phone, and any iPad window taller than it is wide: the keys sit under
    /// the grid across the full width.
    private var stackedEditor: some View {
        VStack(spacing: 0) {
            GridView(studio: studio)
            // The grid used to run straight into the keys; this is the breathing
            // room between the two.
            Rectangle()
                .fill(Theme.grid.opacity(0.5))
                .frame(height: 1)
                .padding(.top, 10)
                .padding(.horizontal, 14)
            KeyboardView(studio: studio)
                .padding(.top, 10)
        }
    }

    /// iPad in landscape. Stacking here would leave the grid a squat band with
    /// three or four steps visible and a keyboard stretched a metre wide, so
    /// the keys move into a column of their own and the grid takes the height
    /// back — which is the whole reason to run natively on the thing.
    private var wideEditor: some View {
        HStack(spacing: 0) {
            GridView(studio: studio)

            Rectangle()
                .fill(Theme.grid.opacity(0.5))
                .frame(width: 1)
                .padding(.vertical, 12)

            // Centred in its column rather than pinned to the bottom: on a
            // 13-inch iPad the bottom edge is a long way from where the hands
            // holding it actually are.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                KeyboardView(studio: studio)
                Spacer(minLength: 0)
            }
            .frame(width: ChipLayout.sideKeyboardWidth)
        }
        // Nothing sits under the grid in this layout, so without this the last
        // step row runs beneath the home indicator.
        .padding(.bottom, 8)
    }

    /// Narrower than the 44pt targets either side of them — two more of those
    /// would squeeze the song name to nothing. Still comfortably tappable, and
    /// dimmed rather than hidden when there's nothing to undo, so the row
    /// doesn't reflow as you edit.
    private func historyButton(_ symbol: String, label: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Theme.text : Theme.dim.opacity(0.4))
                .frame(width: 34, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Commits whatever is in the name field and closes the undo run, for the
    /// controls that act on the song while the field still has focus. Calls
    /// through directly rather than relying on the focus change alone, which
    /// arrives a beat later than the action that triggered it.
    private func endRenaming() {
        guard nameFocused else { return }
        nameFocused = false
        studio.normalizeSongName()
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            // Browsing saved songs used to be buried two levels into the •••
            // menu, which made it feel like the app had no library at all.
            Button {
                // Before the save, or the library lists the name as it was
                // before whatever is still being typed in the field.
                endRenaming()
                studio.saveNow()
                showingSongs = true
            } label: {
                Image(systemName: "music.note.list")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Songs")

            // Bound through `setSongName` rather than at `song.name` directly,
            // so a rename is one undo step. Reading straight from the model
            // means an undo of that step shows up in the field immediately.
            TextField("Song name", text: Binding(get: { studio.song.name },
                                                 set: { studio.setSongName($0) }))
                .chipFont(16, weight: .bold)
                .foregroundStyle(Theme.text)
                .accessibilityLabel(SongNameFieldAccessibility.label)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { studio.normalizeSongName() }
                .onChange(of: nameFocused) { _, focused in
                    if !focused { studio.normalizeSongName() }
                }

            // Both close any open rename first, so undo lands on the step the
            // user can see rather than on one still being typed.
            historyButton("arrow.uturn.backward", label: "Undo",
                          enabled: studio.canUndo) { endRenaming(); studio.undo() }
            historyButton("arrow.uturn.forward", label: "Redo",
                          enabled: studio.canRedo) { endRenaming(); studio.redo() }

            Menu {
                Button {
                    studio.newSong()
                } label: {
                    Label("New song", systemImage: "doc.badge.plus")
                }
                Button {
                    studio.duplicateSong()
                } label: {
                    Label("Duplicate song", systemImage: "plus.square.on.square")
                }
                Divider()
                Button {
                    studio.share(studio.song)
                } label: {
                    Label("Share song file", systemImage: "square.and.arrow.up")
                }
                Button {
                    showingExport = true
                } label: {
                    Label(studio.isExporting ? "Exporting…" : "Export WAV",
                          systemImage: "square.and.arrow.up")
                }
                .disabled(studio.isExporting)
                Divider()
                Button(role: .destructive) {
                    confirmingClearPattern = true
                } label: {
                    Label("Clear pattern \(studio.pattern.name)", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Song menu")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

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
                    .font(.system(size: 18))
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
                        range: 40...300,
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

/// Where the pattern strip is scrolled to, and how much of it there is.
struct StripMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
}

private struct StripMetricsKey: PreferenceKey {
    static let defaultValue = StripMetrics()
    static func reduce(value: inout StripMetrics, nextValue: () -> StripMetrics) {
        value = nextValue()
    }
}

private struct StripViewportKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The patterns strip: pick which block the grid is editing, and set its length.
struct PatternBar: View {
    @Bindable var studio: Studio
    @State private var renaming: Int?
    @State private var renameText = ""
    /// Pattern indices queued behind a confirmation. Both erase work with no
    /// way back, so neither happens straight off a context-menu tap.
    @State private var clearing: Int?
    @State private var deleting: Int?
    @State private var strip = StripMetrics()
    @State private var stripViewport: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            // The tray sits *inside* here rather than around the whole row, so
            // it hugs the chips and grows with them instead of stretching an
            // empty panel across the row. `+` is pinned outside the scrolling
            // part so it can't be scrolled out of reach.
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    chips
                    scrollingChips
                }

                if studio.song.canAddPattern {
                    TrayDivider()
                    addButton
                }
            }
            .chipTray()

            // Now that the chip tray hugs its contents, STEPS would drift left
            // with it; this keeps it pinned under BPM so the two steppers line
            // up as a column down the right edge.
            Spacer(minLength: 12)

            // Deliberately a separate tray: STEPS belongs to the pattern, not to
            // the strip of chips beside it, and the gap is what says so.
            ChipStepper(label: "STEPS",
                        value: studio.patternLength,
                        range: 4...Chip.maxSteps,
                        onChange: { studio.setPatternLength(studio.patternLength + $0 * 4) })
                .chipTray()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .alert("Rename pattern", isPresented: Binding(get: { renaming != nil },
                                                      set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let index = renaming { studio.renamePattern(at: index, to: renameText) }
                renaming = nil
            }
            // Greyed out rather than silently ignored when the name is empty
            // or already another pattern's.
            .disabled(renaming.map { studio.acceptablePatternName(renameText, for: $0) == nil } ?? true)
        }
        .confirmationDialog("Clear pattern \(name(clearing))?",
                            isPresented: Binding(get: { clearing != nil },
                                                 set: { if !$0 { clearing = nil } }),
                            titleVisibility: .visible) {
            Button("Clear pattern", role: .destructive) {
                // Clears in place — jumping the editor to the cleared pattern
                // reads as "my work just vanished" when it's still in the one
                // you were editing.
                if let index = clearing { studio.clearPattern(at: index) }
                clearing = nil
            }
            Button("Cancel", role: .cancel) { clearing = nil }
        } message: {
            Text("Every track's notes in this pattern are erased.")
        }
        .confirmationDialog("Delete pattern \(name(deleting))?",
                            isPresented: Binding(get: { deleting != nil },
                                                 set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete pattern", role: .destructive) {
                if let index = deleting { studio.removePattern(at: index) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            // No "can't be undone" here: removePattern checkpoints, and a
            // false warning teaches people to distrust the real ones.
            Text("It's removed from the arrangement too. Undo brings it back.")
        }
    }

    private func name(_ index: Int?) -> String {
        index.flatMap { studio.song.patterns[safe: $0]?.name } ?? ""
    }

    private var chips: some View {
        HStack(spacing: 4) {
            ForEach(Array(studio.song.patterns.enumerated()), id: \.element.id) { index, pattern in
                chip(index: index, pattern: pattern)
            }
        }
        .padding(.horizontal, 4)
    }

    /// The overflow case. Fades whichever edge still has chips behind it, so a
    /// half-cut chip isn't the only clue that the strip scrolls.
    private var scrollingChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            chips
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: StripMetricsKey.self,
                            value: StripMetrics(offset: geo.frame(in: .named("patternStrip")).minX,
                                                content: geo.size.width))
                    }
                )
        }
        .coordinateSpace(name: "patternStrip")
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: StripViewportKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(StripMetricsKey.self) { strip = $0 }
        .onPreferenceChange(StripViewportKey.self) { stripViewport = $0 }
        .mask(edgeFade)
    }

    private var edgeFade: some View {
        // A point of slack keeps the fade from flickering on at the extremes.
        let leading = strip.offset < -1
        let trailing = strip.content + strip.offset > stripViewport + 1
        return LinearGradient(
            stops: [
                .init(color: leading ? .clear : .black, location: 0),
                .init(color: .black, location: leading ? 0.07 : 0),
                .init(color: .black, location: trailing ? 0.93 : 1),
                .init(color: trailing ? .clear : .black, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing)
    }

    private var addButton: some View {
        Button {
            studio.addPattern()
        } label: {
            Image(systemName: "plus")
                .chipFont(13)
                .foregroundStyle(Theme.text)
                // 36pt of fill, but the whole tray height stays tappable.
                .frame(width: 42, height: Theme.trayHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add pattern")
    }

    private func chip(index: Int, pattern: Pattern) -> some View {
        let selected = studio.selectedPattern == index
        let playing = studio.isPlaying && studio.playingPattern == index

        return Button {
            studio.selectPattern(index)
        } label: {
            HStack(spacing: 4) {
                if playing {
                    // A selected chip fills with near-white, where the usual
                    // bright green scores 1.1:1 and vanishes.
                    Circle()
                        .fill(selected ? Theme.onLightGreen : Theme.accentGreen)
                        .frame(width: 5, height: 5)
                }
                Text(pattern.name)
                    .chipFont(13, weight: selected ? .bold : .semibold)
                    .foregroundStyle(selected ? Theme.onLight : (pattern.isEmpty ? Theme.dim : Theme.text))
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 40)
            .frame(height: Theme.trayHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.innerRadius)
                    .fill(selected ? Theme.text : Theme.panelHigh)
                    .padding(.vertical, 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pattern \(pattern.name)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .contextMenu {
            Button {
                renameText = pattern.name
                renaming = index
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                studio.duplicatePattern(at: index)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(!studio.song.canAddPattern)
            Button(role: .destructive) {
                clearing = index
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            Button(role: .destructive) {
                deleting = index
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(studio.song.patterns.count <= 1)
        }
    }
}

/// −/value/+ control. The value is tappable when `onTapValue` is supplied.
///
/// Draws no background of its own so it can sit inside a shared `chipTray`
/// alongside other controls; standalone uses apply `.chipTray()` themselves.
struct ChipStepper: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void
    var onTapValue: (() -> Void)?

    var canDecrease: Bool { value > range.lowerBound }
    var canIncrease: Bool { value < range.upperBound }

    var body: some View {
        HStack(spacing: 0) {
            Button { onChange(-1) } label: {
                Image(systemName: "minus").chipFont(13)
                    .frame(width: 38, height: Theme.trayHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canDecrease ? Theme.text : Theme.dim.opacity(0.4))
            .accessibilityLabel("Decrease \(label)")
            .disabled(!canDecrease)

            Group {
                if let onTapValue {
                    Button(action: onTapValue) { readout }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(label) \(value), edit")
                } else {
                    readout.allowsHitTesting(false)
                }
            }

            Button { onChange(1) } label: {
                Image(systemName: "plus").chipFont(13)
                    .frame(width: 38, height: Theme.trayHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canIncrease ? Theme.text : Theme.dim.opacity(0.4))
            .accessibilityLabel("Increase \(label)")
            .disabled(!canIncrease)
        }
    }

    private var readout: some View {
        VStack(spacing: 0) {
            Text("\(value)").chipFont(15, weight: .bold).foregroundStyle(Theme.text)
            Text(label).chipFont(8).foregroundStyle(Theme.dim)
        }
        .frame(minWidth: 38)
        .frame(height: Theme.trayHeight)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Presents `message` as a one-button alert and clears it on dismissal, so
    /// the same failure happening twice shows twice.
    func errorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil },
                                          set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

/// Export options, and the progress of the render they kick off.
///
/// A sheet rather than more items in the ••• menu: the render can take real
/// time on a long arrangement, and it needs somewhere to show how far along it
/// is and a way to stop it.
struct ExportSheet: View {
    @Bindable var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportOptions()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $options.loopCount, in: 1...ExportOptions.maxLoopCount) {
                        HStack {
                            Text("Repeats")
                            Spacer()
                            Text("\(options.loopCount)×")
                                .chipFont(15, weight: .bold)
                                .foregroundStyle(Theme.dim)
                        }
                    }
                } footer: {
                    Text("The whole arrangement, \(options.loopCount) time\(options.loopCount == 1 ? "" : "s") — \(duration).")
                }

                Section {
                    Picker("Ending", selection: $options.tailMode) {
                        Text("Seamless loop").tag(ExportOptions.TailMode.seamlessLoop)
                        Text("Ring out").tag(ExportOptions.TailMode.ringOut)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Ending")
                } footer: {
                    Text(options.tailMode == .seamlessLoop
                         ? "The last notes ring on into the start, so the file loops with no gap. Best for dropping into something else."
                         : "The last notes fade out past the end and the file finishes in silence. Best when the file is the finished thing.")
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
                            studio.export(options: options)
                        } label: {
                            Label("Export WAV", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
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
        .preferredColorScheme(.dark)
    }

    /// Rough length of the file, so the repeat count means something.
    private var duration: String {
        var seconds = studio.song.arrangementDuration * Double(options.loopCount)
        if options.tailMode == .ringOut { seconds += 1 }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

/// UIActivityViewController wrapper for sharing the exported WAV.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // UIKit-presented, so it doesn't inherit the app's forced dark scheme
        // and would otherwise flash white on a light-mode device.
        controller.overrideUserInterfaceStyle = .dark
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
