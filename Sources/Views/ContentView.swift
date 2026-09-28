import SwiftUI
import StoreKit
import UIKit
import GameController

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
enum ScreenshotMode: String, CaseIterable {
    // The raw values are the launch-argument keys shoot.sh passes; they are
    // its command-line interface and outlive any renaming of the cases.
    case arrangement = "shotArrangement"
    case instrument = "shotEditor"
    case library = "shotLibrary"
    case export = "shotExport"
    case playing = "shotPlaying"
    case pattern = "shotPatternB"

    static var requested: ScreenshotMode? {
        allCases.first { UserDefaults.standard.bool(forKey: $0.rawValue) }
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

enum KeyboardShortcutsMenuVisibility {
    /// The song menu's "Keyboard shortcuts" row means nothing on a phone that
    /// has never seen a keyboard, so it stays hidden until one has actually
    /// said something: connected right now (`keyboardConnected`, kept live
    /// from `GCKeyboard.coalesced` via the connect/disconnect notifications),
    /// or connected earlier this session and used, which
    /// `studio.hardwareKeyboardInUse` remembers even after it's unplugged.
    static func visible(keyboardConnected: Bool, hardwareKeyboardInUse: Bool) -> Bool {
        keyboardConnected || hardwareKeyboardInUse
    }
}

enum ReviewPromptPolicy {
    static let firstRequestExportCount = 3
    static let retryInterval = 10

    /// What became of the share sheet the review prompt is gated behind.
    /// Canceling and failing are both "not completed", but kept distinct so
    /// a failure can still surface through `shareError` without being
    /// conflated with a plain cancel.
    enum ShareOutcome { case completed, canceled, failed }

    static func isDue(successfulExports: Int, lastRequestExportCount: Int) -> Bool {
        guard successfulExports >= firstRequestExportCount else { return false }
        guard lastRequestExportCount > 0 else { return true }
        guard successfulExports >= lastRequestExportCount else { return false }
        return successfulExports - lastRequestExportCount >= retryInterval
    }

    /// A milestone being due only means it's worth asking *if the share the
    /// user was mid-way through actually went somewhere*. Canceling or
    /// failing a share is not a moment to interrupt with a review prompt.
    static func shouldRequest(eligible: Bool, outcome: ShareOutcome) -> Bool {
        eligible && outcome == .completed
    }

    /// The state transition after a share sheet dismisses: whether to
    /// actually fire StoreKit's request, and what `lastRequestExportCount`
    /// should become. A skipped request leaves the count untouched, so the
    /// user keeps their eligibility for the next share that actually
    /// completes rather than losing the milestone to a cancel.
    static func afterShareDismiss(eligible: Bool,
                                  outcome: ShareOutcome,
                                  successfulExports: Int,
                                  lastRequestExportCount: Int) -> (shouldRequestReview: Bool,
                                                                   lastRequestExportCount: Int) {
        guard shouldRequest(eligible: eligible, outcome: outcome) else {
            return (false, lastRequestExportCount)
        }
        return (true, successfulExports)
    }
}

/// Getting from a finished render to the share sheet.
///
/// The export panel and the share sheet are presented by different hosts — the
/// panel hangs off the ••• menu as a popover, the share sheet off the editor
/// root — and UIKit will not present the second while the first is still going
/// away. So the render says what is owed and the panel's disappearance is what
/// pays it, rather than both flags flipping in one transaction.
enum ExportFlow {
    struct Step: Equatable {
        /// Take the export panel down; the render it was watching is done.
        var closeExport = false
        /// Raise the share sheet once that panel has actually gone.
        var shareWhenExportCloses = false
        /// Nothing to wait for: raise it now.
        var shareNow = false
    }

    static func afterRender(url: URL?, exportPresented: Bool) -> Step {
        guard url != nil else { return Step() }
        // With no panel up there is no disappearance to wait for — a queued
        // share would sit there unspent — so that case goes straight out.
        guard exportPresented else { return Step(shareNow: true) }
        return Step(closeExport: true, shareWhenExportCloses: true)
    }

    static func afterExportClosed(pendingShare: Bool) -> Step {
        Step(shareNow: pendingShare)
    }

    /// The export panel can disappear without the Close button ever running —
    /// a swipe-to-dismiss on the sheet a compact window turns it into, or an
    /// outside tap on the popover a regular-width one keeps it as. Either way
    /// `onDisappear` is the one place that sees it happen. A render still
    /// going at that moment has to be canceled there too, or its eventual
    /// success or failure lands on a studio nothing is watching anymore.
    static func afterPanelDisappeared(isExporting: Bool) -> Bool {
        isExporting
    }
}

/// The border that says a dragged song will land here.
///
/// Nothing but the border: the editor and the library both already say what
/// they are, and a drop hint with words in it would cover the thing being
/// dropped onto.
struct SongDropBorder: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Theme.accentGreen, lineWidth: 2)
            .opacity(isTargeted ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isTargeted)
            // The highlight is feedback, never a target.
            .allowsHitTesting(false)
    }
}

struct ContentView: View {
    @Bindable var studio: Studio
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.requestReview) private var requestReview
    @AppStorage("successfulExportCount") private var successfulExportCount = 0
    @AppStorage("lastReviewRequestExportCount") private var lastReviewRequestExportCount = 0
    @State private var showingSongs = false
    @State private var showingArrangement = false
    @State private var showingShare = false
    // Snapshot which pattern the clear dialog targets at the moment it's
    // raised. In SONG mode the playhead moves `studio.selectedPattern` at every
    // arrangement boundary while the dialog is up, so reading it again at
    // confirm time erased whichever pattern playback had reached, not the one
    // the title named. Same rule as `InstrumentEditor`'s track snapshot.
    @State private var pendingClearPatternIndex: Int?
    @State private var showingExport = false
    @State private var showingKeyboardHelp = false
    /// Kept live by `GCKeyboardDidConnect`/`DidDisconnect` below, rather than
    /// read once, because a keyboard can arrive or leave without the view
    /// re-appearing. See `KeyboardShortcutsMenuVisibility`.
    @State private var hardwareKeyboardConnected = GCKeyboard.coalesced != nil
    @State private var reviewAfterSharing = false
    /// A finished render owes the user a share sheet, held until the export
    /// panel has left the screen — `.popover` has no `onDismiss:`, so the
    /// content's `.onDisappear` is what spends this.
    @State private var shareWhenExportCloses = false
    /// What the WAV share sheet's completion handler reported. Reset to
    /// `.canceled` each time the sheet is (re-)presented, so a handler that
    /// never fires — the completion callback is documented as "may not be
    /// called" for some activities — defaults to "not completed" rather than
    /// stale-carrying the previous share's outcome.
    @State private var shareOutcome: ReviewPromptPolicy.ShareOutcome = .canceled
    /// A `.chipsong` is hovering over the editor, waiting to be dropped.
    @State private var songDropTargeted = false
    @FocusState private var nameFocused: Bool

    /// Fixed for the life of the process — the bundle can't change under a
    /// running app — so it's read once rather than per menu open.
    private let build = BuildStamp()

    var body: some View {
        // The window decides the metrics, so the layout has to be read from
        // the actual size rather than the device: an iPad in a Split View
        // slice gets the phone layout, and a rotation swaps arrangements.
        GeometryReader { geo in
            let layout = ChipLayout.resolve(size: geo.size,
                                            horizontalSizeClass: horizontalSizeClass)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityEditor(layout, availableHeight: geo.size.height)
                } else if layout.usesSideKeyboard {
                    wideEditor(layout)
                } else {
                    VStack(spacing: 0) {
                        chrome(layout)
                        stackedEditor
                    }
                }
            }
            .environment(\.chipLayout, layout)
            // Dropping a song file on the editor opens it, the same as
            // picking it in the importer.
            .dropDestination(for: SongFile.self) { files, _ in
                guard let file = files.first else { return false }
                return studio.importSong(decoded: file.song)
            } isTargeted: { songDropTargeted = $0 }
            .overlay {
                SongDropBorder(isTargeted: songDropTargeted)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .hardwareKeys(studio: studio)
        // What the Command chords in `EditorCommands` act on. A scene value
        // rather than a focused one: nothing in this editor is a focusable
        // control, so no view ever holds focus and a plain focused value would
        // stay nil for the whole session.
        .focusedSceneValue(\.editor, EditorActions(
            studio: studio,
            endRenaming: { endRenaming() },
            openSongs: { openSongs() },
            openArrangement: { openArrangement() },
            openExport: { openExport() },
            confirmClearPattern: { confirmClearPattern() }))
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
        // Arrangement and Export are no longer presented here: each hangs off
        // the control that opens it — ARR in the transport, the ••• menu — so
        // at regular width it arrives as a popover beside its button with the
        // grid still visible, and adapts back to a sheet on a phone.
        .sheet(isPresented: $showingShare, onDismiss: requestReviewIfDue) {
            if let url = studio.exportURL {
                ShareSheet(items: [url], onComplete: { completed, error in
                    if let error {
                        studio.shareError = "Couldn't share the exported file. \(error.localizedDescription)"
                    }
                    shareOutcome = completed ? .completed : (error != nil ? .failed : .canceled)
                })
            }
        }
        .songShareSheet(for: studio)
        // Export renders off the main thread; the share sheet waits for the
        // URL to land rather than racing the render.
        .onChange(of: studio.exportURL) { _, url in
            guard url != nil else { return }
            Haptics.exportSucceeded()
            successfulExportCount += 1
            reviewAfterSharing = ReviewPromptPolicy.isDue(
                successfulExports: successfulExportCount,
                lastRequestExportCount: lastReviewRequestExportCount
            )
            shareOutcome = .canceled
            // The options panel gets out of the way first, and the share sheet
            // waits for it to actually be gone — see `ExportFlow`.
            let step = ExportFlow.afterRender(url: url, exportPresented: showingExport)
            if step.closeExport { showingExport = false }
            shareWhenExportCloses = step.shareWhenExportCloses
            if step.shareNow { showingShare = true }
        }
        // The keyboard asked for whatever is up to close. A counter rather
        // than a flag, so a second Escape is a second request.
        .onChange(of: studio.dismissRequests) { _, _ in
            closePresentation()
        }
        .alert(
            pendingClearPatternIndex.map { "Clear pattern \(studio.song.patterns[safe: $0]?.name ?? "")?" } ?? "",
            isPresented: Binding(get: { pendingClearPatternIndex != nil },
                                 set: { if !$0 { pendingClearPatternIndex = nil } })) {
            if let target = pendingClearPatternIndex {
                Button("Clear pattern", role: .destructive) { studio.clearPattern(at: target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ConfirmationCopy.clearPattern)
        }
        // Three things that used to fail without saying so. The save one
        // matters most: there's no Save button to retry with, so a write that
        // fails quietly is work quietly lost.
        .errorAlert("Save failed", message: $studio.storageError)
        .errorAlert("Audio unavailable", message: $studio.audioError)
        .errorAlert("Import failed", message: $studio.importError)
        .errorAlert("Share failed", message: $studio.shareError)
        // Opens whichever screen the screenshot shoot asked for. Inert unless
        // launched with one of its arguments; see `ScreenshotMode`.
        //
        // The instrument editor isn't here: it's opened from the track header
        // instead, so a shot catches the presentation that window really uses
        // — a popover on a portrait iPad, a sheet on a phone, and nothing at
        // all where the panel is already docked beside the grid.
        .task {
            switch ScreenshotMode.requested {
            case .arrangement: showingArrangement = true
            case .library: showingSongs = true
            case .export: showingExport = true
            // The shot is taken several seconds after launch, so starting the
            // transport here — same call the PLAY button makes — leaves
            // plenty of time for the playhead row to be lit by the time the
            // screenshot fires.
            case .playing: studio.play()
            // Pattern B is the second pattern; `make_song.py` gives it 32
            // steps so this shot can show that patterns aren't all the same
            // length.
            case .pattern: studio.selectPattern(1)
            case .instrument, .none: break
            }
        }
        // Only signal that flips the "Keyboard shortcuts" row without a menu
        // re-open to trigger a re-read; see `hardwareKeyboardConnected`.
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)) { _ in
            hardwareKeyboardConnected = GCKeyboard.coalesced != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)) { _ in
            hardwareKeyboardConnected = GCKeyboard.coalesced != nil
        }
    }

    /// Everything this view knows to be on screen over the editor. The docked
    /// or popover instrument editor isn't here: it's owned by the grid, not by
    /// this view, and it resigns the keyboard the same way a sheet does.
    private var anyPresented: Bool {
        showingSongs || showingArrangement || showingExport || showingShare
            || showingKeyboardHelp || pendingClearPatternIndex != nil || studio.shareURL != nil
    }

    /// The four screens a command can open, each behind the same guard. A
    /// second presentation request while one is up is answered with silence by
    /// iOS, so the flag would stay set and the screen would appear later, on
    /// whatever dismissal happened next.
    private func openSongs() {
        guard EditorPresentation.canOpen(anyPresented: anyPresented) else { return }
        // Before the save, or the library lists the name as it was before
        // whatever is still being typed in the field.
        endRenaming()
        if studio.saveNow() {
            showingSongs = true
        }
    }

    private func openArrangement() {
        guard EditorPresentation.canOpen(anyPresented: anyPresented) else { return }
        showingArrangement = true
    }

    private func openExport() {
        guard EditorPresentation.canOpen(anyPresented: anyPresented) else { return }
        showingExport = true
    }

    private func confirmClearPattern() {
        guard EditorPresentation.canOpen(anyPresented: anyPresented) else { return }
        pendingClearPatternIndex = studio.selectedPattern
    }

    /// Escape, and Cmd+. with it, arriving from the key catcher — see
    /// `KeyAction.forPresentedKey` for why it can't come from a command or
    /// from a sheet's own Close button. Every screen this view presents,
    /// closed the way that button would — including the export, which has a
    /// render to call off.
    ///
    /// The share sheet is left alone: it's UIKit's, it has its own Cancel, and
    /// dismissing it from underneath would skip the completion handler the
    /// review prompt reads. The instrument editor is grid-owned state, so it
    /// isn't reachable from here either; its Done button stays the way out.
    private func closePresentation() {
        if showingExport {
            studio.cancelExport()
        }
        showingSongs = false
        showingArrangement = false
        showingExport = false
        showingKeyboardHelp = false
        pendingClearPatternIndex = nil
    }

    /// The export panel has left the screen. If it left behind a rendered
    /// file, this is the first moment UIKit will present anything else.
    private func shareAfterExport() {
        if ExportFlow.afterPanelDisappeared(isExporting: studio.isExporting) {
            studio.cancelExport()
        }
        let step = ExportFlow.afterExportClosed(pendingShare: shareWhenExportCloses)
        shareWhenExportCloses = false
        guard step.shareNow else { return }
        showingShare = true
    }

    /// Asking after the share sheet closes avoids competing presentations and
    /// ties the prompt to a moment when the app has demonstrably been useful.
    private func requestReviewIfDue() {
        // A canceled or failed share doesn't spend the milestone: only a
        // completed share advances `lastReviewRequestExportCount`, so the
        // user keeps their eligibility for the next share that actually goes
        // somewhere.
        let result = ReviewPromptPolicy.afterShareDismiss(
            eligible: reviewAfterSharing,
            outcome: shareOutcome,
            successfulExports: successfulExportCount,
            lastRequestExportCount: lastReviewRequestExportCount)
        reviewAfterSharing = false
        lastReviewRequestExportCount = result.lastRequestExportCount
        guard result.shouldRequestReview else { return }
        // StoreKit decides whether a request is actually shown.
        requestReview()
    }

    /// Song name, transport and patterns. Capped and centered rather than
    /// stretched: BPM and STEPS trail their rows so the two steppers read as a
    /// column, and across 1200pt of window that puts the tempo at the far end
    /// of the room from the play button that uses it. The cap is per-layout,
    /// so a phone row is untouched.
    private func chrome(_ layout: ChipLayout) -> some View {
        VStack(spacing: 0) {
            titleBar(layout)
            // Same reason the grid and the piano close the rename out: these
            // are buttons and steppers, so UIKit hands them no focus and the
            // name field above keeps the keyboard — and the hardware keys with
            // it — while the user is plainly working on something else. The
            // gesture is attached to each bar rather than the stack, or it
            // would fire on the tap that opens the name field.
            TransportBar(studio: studio, showingArrangement: $showingArrangement)
                .simultaneousGesture(TapGesture().onEnded { endRenaming() })
            PatternBar(studio: studio)
                .simultaneousGesture(TapGesture().onEnded { endRenaming() })
        }
        .frame(maxWidth: layout.chromeMaxWidth)
        .frame(maxWidth: .infinity)
    }

    /// Phone, and any iPad window taller than it is wide: the keys sit under
    /// the grid across the full width.
    private var stackedEditor: some View {
        VStack(spacing: 0) {
            editorGrid
            // The grid used to run straight into the keys; this is the breathing
            // room between the two.
            Rectangle()
                .fill(Theme.grid.opacity(0.5))
                .frame(height: 1)
                .padding(.top, 10)
                .padding(.horizontal, 14)
            editorKeyboard
                .padding(.top, 10)
        }
    }

    /// The grid and the piano, with the rename closed out first.
    ///
    /// A grid cell is a tap gesture on a shape and a piano key is a plain
    /// button, so neither is something UIKit will hand focus to: touching one
    /// while the song name field is being edited leaves that field first
    /// responder, and a hardware key then keeps typing into the title instead
    /// of the pattern. Nothing else takes the focus away — no other focusable
    /// control, no dismiss affordance — so the editor has to say so itself.
    ///
    /// Simultaneous rather than `onTapGesture`, or this would swallow the tap
    /// the cell or key is there to receive.
    private var editorGrid: some View {
        GridView(studio: studio)
            .simultaneousGesture(TapGesture().onEnded { endRenaming() })
    }

    private var editorKeyboard: some View {
        KeyboardView(studio: studio)
            .simultaneousGesture(TapGesture().onEnded { endRenaming() })
    }

    /// Accessibility text makes the chrome several rows tall. Give the whole
    /// editor a vertical escape hatch instead of squeezing the grid and piano
    /// into whatever sliver remains below it.
    private func accessibilityEditor(_ layout: ChipLayout,
                                     availableHeight: CGFloat) -> some View {
        // A landscape iPad normally docks the instrument editor beside the
        // grid. This accessibility layout deliberately stacks instead, so its
        // descendants must also stop believing that editor is still docked;
        // the selected track can then open it as a popover.
        let stackedLayout = layout.withoutDockedInstrumentEditor
        return ScrollView {
            VStack(spacing: 0) {
                chrome(layout)
                editorGrid
                    .frame(height: max(360, availableHeight * 0.55))
                Rectangle()
                    .fill(Theme.grid.opacity(0.5))
                    .frame(height: 1)
                    .padding(.top, 10)
                    .padding(.horizontal, 14)
                editorKeyboard
                    .padding(.top, 10)
            }
        }
        .environment(\.chipLayout, stackedLayout)
    }

    /// iPad in landscape. Stacking here would leave the grid a squat band with
    /// three or four steps visible and a keyboard stretched a meter wide, so
    /// the keys move into a column of their own and the grid takes the height
    /// back — which is the whole reason to run natively on the thing.
    private func wideEditor(_ layout: ChipLayout) -> some View {
        HStack(spacing: 0) {
            // The chrome rides above the grid rather than the whole window, so
            // the transport and the pattern strip stay over the thing they act
            // on instead of spanning the keyboard column too.
            VStack(spacing: 0) {
                chrome(layout)
                editorGrid
            }

            Rectangle()
                .fill(Theme.grid.opacity(0.5))
                .frame(width: 1)
                .padding(.vertical, 12)

            instrumentPanel
                .frame(width: layout.sideColumnWidth)
        }
        // Nothing sits under the grid in this layout, so without this the last
        // step row runs beneath the home indicator.
        .padding(.bottom, 8)
    }

    /// The side column: keys on top, the selected track's sound underneath.
    ///
    /// The keyboard alone left most of this column empty, and the one thing
    /// worth putting beside a keyboard is the voice it plays. Docking the
    /// instrument controls here also takes the editor off the sheet path,
    /// which on an iPad covered the grid every time you nudged a decay — and
    /// nudging a decay is something you do against the part you just wrote.
    ///
    /// Keys sit above the controls rather than below: they're what your hands
    /// go to, and the bottom edge of a 13-inch iPad is a long way from where
    /// the hands holding it are.
    private var instrumentPanel: some View {
        VStack(spacing: 0) {
            editorKeyboard

            Rectangle()
                .fill(Theme.grid.opacity(0.5))
                .frame(height: 1)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            InstrumentEditor(studio: studio, index: studio.selectedTrack, docked: true)
        }
    }

    /// Narrower than the 44pt targets either side of them on the phone — two
    /// more of those would squeeze the song name to nothing — but the pad has
    /// the room, so `layout.historyButtonWidth` gives it the full 44pt there.
    /// Still comfortably tappable at either size, and dimmed rather than
    /// hidden when there's nothing to undo, so the row doesn't reflow as you
    /// edit.
    private func historyButton(_ symbol: String, label: String, enabled: Bool,
                               width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolFont(15, weight: .semibold)
                .foregroundStyle(enabled ? Theme.text : Theme.dim.opacity(0.4))
                .frame(width: width, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .hoverEffect(.highlight)
        // A dimmed undo/redo shouldn't glow as if it were live.
        .hoverEffectDisabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Commits whatever is in the name field and closes the undo run, for the
    /// controls that act on the song while the field still has focus. Calls
    /// through directly rather than relying on the focus change alone, which
    /// arrives a beat later than the action that triggered it.
    ///
    /// The keyboard is taken back unconditionally, even when `nameFocused`
    /// already reads false: the flag is what SwiftUI intends, not what UIKit
    /// has done, and the two can disagree. When they do, this tap is the only
    /// signal that the user is finished with the field — returning early on
    /// the flag alone left a field that never actually resigned holding every
    /// hardware key for the rest of the session. Reclaiming when nothing
    /// borrowed the keyboard is a no-op.
    private func endRenaming() {
        if nameFocused {
            nameFocused = false
            studio.normalizeSongName()
        }
        HardwareKeyCapture.reclaim()
    }

    private func titleBar(_ layout: ChipLayout) -> some View {
        HStack(spacing: 8) {
            // Browsing saved songs used to be buried two levels into the •••
            // menu, which made it feel like the app had no library at all.
            Button {
                openSongs()
            } label: {
                Image(systemName: "music.note.list")
                    .symbolFont(layout.titleIconGlyphSize)
                    .foregroundStyle(Theme.text)
                    .frame(width: layout.titleIconTargetSize, height: layout.titleIconTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            .accessibilityLabel("Songs")

            // Bound through `setSongName` rather than at `song.name` directly,
            // so a rename is one undo step. Reading straight from the model
            // means an undo of that step shows up in the field immediately.
            TextField("Song name", text: Binding(get: { studio.song.name },
                                                 set: { studio.setSongName($0) }))
                .chipFont(16, weight: .bold)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
                .accessibilityLabel(SongNameFieldAccessibility.label)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { studio.normalizeSongName() }
                .onChange(of: nameFocused) { _, focused in
                    if !focused {
                        studio.normalizeSongName()
                        // Covers every path back out of the field (tapping
                        // away, endRenaming(), a rename alert taking focus),
                        // since updateUIView reaching KeyCatcher again isn't
                        // guaranteed to happen, and isn't guaranteed to see
                        // the field as resigned yet even when it does.
                        HardwareKeyCapture.reclaim()
                    }
                }

            // Both close any open rename first, so undo lands on the step the
            // user can see rather than on one still being typed.
            historyButton("arrow.uturn.backward", label: "Undo",
                          enabled: studio.canUndo,
                          width: layout.historyButtonWidth) { endRenaming(); studio.undo() }
            historyButton("arrow.uturn.forward", label: "Redo",
                          enabled: studio.canRedo,
                          width: layout.historyButtonWidth) { endRenaming(); studio.redo() }

            // Export hangs off the same button the menu does, one layer out:
            // both presentations are anchored to the ••• glyph, and keeping
            // them on separate views means neither modifier has to share a
            // presentation slot with the other.
            menuButton(layout)
                .popover(isPresented: $showingExport,
                         attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    ExportSheet(studio: studio, popover: layout.isRegularWidth)
                        .presentationCompactAdaptation(.sheet)
                        // A popover has no `onDismiss:`, and the share sheet
                        // can't be presented until this is off screen.
                        .onDisappear { shareAfterExport() }
                }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func menuButton(_ layout: ChipLayout) -> some View {
        Group {
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
                    openExport()
                } label: {
                    Label(studio.isExporting ? "Exporting…" : "Export WAV",
                          systemImage: "square.and.arrow.up")
                }
                .disabled(studio.isExporting)
                Divider()
                Button(role: .destructive) {
                    confirmClearPattern()
                } label: {
                    Label("Clear pattern \(studio.pattern.name)", systemImage: "trash")
                }
                Divider()
                // The Cmd-hold overlay lists the chords and can't list anything
                // else, so the keys that do the actual writing — space, the
                // arrows, the note row — are only discoverable here. Hidden
                // unless a keyboard has said something this session: see
                // `KeyboardShortcutsMenuVisibility`.
                if KeyboardShortcutsMenuVisibility.visible(keyboardConnected: hardwareKeyboardConnected,
                                                            hardwareKeyboardInUse: studio.hardwareKeyboardInUse) {
                    Button {
                        showingKeyboardHelp = true
                    } label: {
                        Label("Keyboard shortcuts", systemImage: "keyboard")
                    }
                }
                Link(destination: URL(string: "https://individuation.dev/contact/")!) {
                    Label("Contact support", systemImage: "envelope")
                }
                if !build.lines.isEmpty {
                    // Which build this is, last in the menu because it's read
                    // rarely and never while writing a part. Tapping copies
                    // the release and commit, since the reason to look is
                    // almost always a bug report.
                    Button {
                        UIPasteboard.general.string = build.copyText
                    } label: {
                        // A menu row takes a title and a subtitle, so the
                        // first line leads and the rest stack underneath it.
                        Text(build.lines[0])
                        Text(build.lines.dropFirst().joined(separator: "\n"))
                        Image(systemName: "info.circle")
                    }
                    .accessibilityHint("Copies the version and commit to the clipboard")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .symbolFont(layout.titleIconGlyphSize)
                    .foregroundStyle(Theme.text)
                    .frame(width: layout.titleIconTargetSize, height: layout.titleIconTargetSize)
                    .contentShape(Rectangle())
                    .hoverEffect(.highlight)
            }
            .accessibilityLabel("Song menu")
            // Anchored to the menu it was chosen from, so the list appears
            // where the finger already is; a phone gets it as a sheet.
            .popover(isPresented: $showingKeyboardHelp) {
                KeyboardHelpView()
            }
        }
    }
}
