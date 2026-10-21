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

/// Every surface that edits or exports the open song. A different song
/// opening (an import by URL, say) must close all of them, or they would keep
/// editing and exporting a song the title bar no longer names.
struct PresentedSurfaces: Equatable {
    var songs = false
    var arrangement = false
    var export = false
    var instrumentEditor = false
    /// A finished export's share sheet, offering a file rendered from the
    /// song that was open.
    var exportShare = false
    /// The song file's share sheet (••• Share song file).
    var songFileShare = false

    func afterOpeningSong(previousSongID: UUID, currentSongID: UUID) -> PresentedSurfaces {
        previousSongID == currentSongID ? self : PresentedSurfaces()
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
        /// The export is over, so its options go back to the defaults and
        /// the next opening starts at WAV, 1x, Seamless loop.
        var endsFlow = false
    }

    static func afterRender(url: URL?, exportPresented: Bool) -> Step {
        guard url != nil else { return Step() }
        // With no panel up there is no disappearance to wait for — a queued
        // share would sit there unspent — so that case goes straight out.
        guard exportPresented else { return Step(shareNow: true) }
        return Step(closeExport: true, shareWhenExportCloses: true)
    }

    /// The panel had to close for the share sheet to come up, but backing out
    /// of that sheet without sharing usually means trying another ending or
    /// repeat count, so it returns. A completed share is the end of the job,
    /// and a failed one is already putting up its own alert.
    ///
    /// Only for the song the file came from. A .chipsong opened from another
    /// app while the sheet is up swaps the song underneath it, and the panel
    /// coming back then would offer to export a song nobody asked to, with
    /// the old one's options.
    static func reopensExportAfterShare(outcome: ReviewPromptPolicy.ShareOutcome,
                                        sharedSongID: UUID?, currentSongID: UUID) -> Bool {
        outcome == .canceled && sharedSongID == currentSongID
    }

    /// Whatever doesn't bring the panel back ends the export. One that does
    /// is the same export, and the panel shows what was picked in it.
    ///
    /// Except a share Photos turned down: its alert offers to share the
    /// same video again after Settings, and backing out of that retried
    /// share brings the panel back, so the options are kept until the retry
    /// is either used or dropped (`endsFlowAfterPhotosAlert`,
    /// `endsFlowAfterPhotosRetry`).
    static func endsFlowAfterShare(outcome: ReviewPromptPolicy.ShareOutcome,
                                   sharedSongID: UUID?, currentSongID: UUID,
                                   photosRetryOffered: Bool = false) -> Bool {
        if photosRetryOffered { return false }
        return !reopensExportAfterShare(outcome: outcome, sharedSongID: sharedSongID, currentSongID: currentSongID)
    }

    /// The Photos alert was answered. OK drops the retry, and the export
    /// ends with it; Open Settings keeps both until the user is back.
    static func endsFlowAfterPhotosAlert(openedSettings: Bool) -> Bool {
        !openedSettings
    }

    /// Back from Settings. A reshare carries the export on; a retry that
    /// can no longer be offered (another song, the file gone) ends it.
    static func endsFlowAfterPhotosRetry(reshares: Bool) -> Bool {
        !reshares
    }

    /// The file a just-finished render left to share, read off the studio's
    /// attempt counter rather than its URL. Exporting the same song in the
    /// same format again writes the same path, and a MIDI file can be written
    /// before SwiftUI's next pass, so the URL's clear-then-set can fold into
    /// no change at all and the second export would end with nothing on
    /// screen. The counter moves for every finished render; one that left no
    /// file (canceled, failed) and a counter that hasn't moved forward ask for
    /// nothing.
    static func finishedExport(previousAttempt: Int, completedAttempt: Int, url: URL?) -> URL? {
        guard completedAttempt > previousAttempt else { return nil }
        return url
    }

    /// The panel closing with no share owed was closed by hand (Close, a
    /// swipe, Escape, another song opening), which ends the export. Closing
    /// for the share sheet doesn't: a canceled share brings the panel back.
    static func afterExportClosed(pendingShare: Bool) -> Step {
        Step(shareNow: pendingShare, endsFlow: !pendingShare)
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

/// How the export's share sheet ended, once both halves of the news are in.
///
/// The sheet reports its end twice, in no fixed order: SwiftUI's `onDismiss`
/// when it has gone, and `UIActivityViewController`'s completion handler with
/// what the activity did. After the Photos permission prompt (a first Save
/// Video, Allow) the dismissal comes first, so deciding on it alone treated
/// a saved video as a canceled share: the Export panel came back and the
/// review milestone went uncounted. Each callback hands its half over here,
/// and whichever arrives second gets the outcome to act on — once.
struct ShareSheetEnding: Equatable {
    private var outcome: ReviewPromptPolicy.ShareOutcome?
    private var dismissed = false
    private var decided = false

    /// The sheet has gone. The outcome, if the activity already reported it.
    mutating func sheetDismissed() -> ReviewPromptPolicy.ShareOutcome? {
        dismissed = true
        return decide()
    }

    /// The activity reported. A canceled activity can leave the sheet up for
    /// another try, so a later report replaces an earlier one until the
    /// sheet goes. The outcome, if the sheet has already gone.
    mutating func activityFinished(_ outcome: ReviewPromptPolicy.ShareOutcome) -> ReviewPromptPolicy.ShareOutcome? {
        if !decided { self.outcome = outcome }
        return decide()
    }

    /// The app took the sheet down itself (a different song opened under
    /// it). `UIActivityViewController` may then never call its completion,
    /// so this can't wait for it: an outcome already reported stands, and
    /// with none it's a cancel. Whatever arrives later decides nothing.
    mutating func sheetClosedByApp() -> ReviewPromptPolicy.ShareOutcome? {
        if !decided, outcome == nil { outcome = .canceled }
        dismissed = true
        return decide()
    }

    private mutating func decide() -> ReviewPromptPolicy.ShareOutcome? {
        guard !decided, dismissed, let outcome else { return nil }
        decided = true
        return outcome
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
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var showingImporter = false
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
    /// The export share sheet's dismissal and its completion handler, put
    /// together: whichever lands second decides what happens next. Started
    /// fresh each time the sheet is (re-)presented, so a previous share's
    /// outcome never carries over. `UIActivityViewController` calls its
    /// handler on every way out, a plain close included (as canceled).
    @State private var shareEnding = ShareSheetEnding()
    /// The song the export share sheet's file was rendered from, so a
    /// canceled share brings the Export panel back only if that song is
    /// still the one open. See `ExportFlow.reopensExportAfterShare`.
    @State private var sharedSongID: UUID?
    /// Save Video was turned down by Photos: the alert with Open Settings is
    /// up for this video.
    @State private var photosDenied: PhotosRetry?
    /// Open Settings was tapped for this video, so coming back offers it
    /// again. See `PhotosRetry`.
    @State private var pendingPhotosRetry: PhotosRetry?
    /// A `.chipsong` is hovering over the editor, waiting to be dropped.
    @State private var songDropTargeted = false
    @FocusState private var nameFocused: Bool
    /// The docked instrument editor's Name field holds focus, and with it
    /// what the side column needs to keep that field above the keyboard.
    /// See `DockedKeyboardAvoidance`.
    @State private var dockedNameEditing = false
    @State private var dockedColumnFrame: CGRect = .zero
    @State private var dockedKeysHeight: CGFloat = 0
    /// Top of the on-screen keyboard in global space, or the bottom of the
    /// safe area while there is none.
    @State private var keyboardTop: CGFloat = .greatestFiniteMagnitude

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
                // Kept apart from `editor`, so crossing into or out of it
                // still rebuilds the editor. Both are rare mid-task: a text
                // size change, or a Stage Manager window dragged short.
                if dynamicTypeSize.isAccessibilitySize || layout.scrollsEditor {
                    scrollingEditor(layout, availableHeight: geo.size.height)
                } else {
                    editor(layout)
                }
            }
            .environment(\.chipLayout, layout)
            // Dropping a song file on the editor opens it, the same as
            // picking it in the importer, and a file that isn't a song gets
            // the same "Import failed" alert. Deferred one runloop tick, the
            // same as the library's drop: an alert raised inside the drop's
            // own transaction can be lost.
            .dropDestination(for: SongDrop.self) { drops, _ in
                guard let drop = drops.first else { return false }
                DispatchQueue.main.async {
                    studio.importDropped(drop)
                }
                return true
            } isTargeted: { songDropTargeted = $0 }
            .overlay {
                SongDropBorder(isTargeted: songDropTargeted)
            }
        }
        // The window, not the window less the on-screen keyboard; see
        // `ChipLayout.measurementIgnoresSafeArea`.
        .ignoresSafeArea(ChipLayout.measurementIgnoresSafeArea)
        // Outside the keyboard-ignoring region, so this one still sees the
        // keyboard: its frame ends at the keyboard's top edge (or at the
        // bottom of the safe area when there is none), which is what the
        // docked editor's column has to stay above.
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).maxY
                } action: { keyboardTop = $0 }
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
            confirmClearPattern: { confirmClearPattern() },
            canChangeSong: EditorPresentation.canChangeSong(songBoundPresented: songBoundPresented),
            canChangeSongNow: { EditorPresentation.canChangeSong(songBoundPresented: songBoundPresented) }))
        .sheet(isPresented: $showingSongs) {
            SongListView(studio: studio)
        }
        .onChange(of: studio.song.id) { previousSongID, currentSongID in
            showingSongs = SongLibraryPresentation.afterOpeningSong(
                isPresented: showingSongs,
                previousSongID: previousSongID,
                currentSongID: currentSongID
            )
            let after = PresentedSurfaces(songs: showingSongs,
                                          arrangement: showingArrangement,
                                          export: showingExport,
                                          exportShare: showingShare,
                                          songFileShare: studio.shareURL != nil)
                .afterOpeningSong(previousSongID: previousSongID,
                                  currentSongID: currentSongID)
            if showingExport && !after.export { studio.cancelExport() }
            showingArrangement = after.arrangement
            showingExport = after.export
            // A share sheet still offering the previous song's file goes too.
            // The activity may never report after a dismissal it didn't
            // make, so the ending is settled here (a cancel, unless it had
            // already said otherwise) rather than left waiting. `afterShare`
            // sees a different song open and neither reopens the Export
            // panel nor keeps the choices.
            if showingShare && !after.exportShare {
                showingShare = false
                if let outcome = shareEnding.sheetClosedByApp() { afterShare(outcome) }
            }
            if !after.songFileShare { studio.shareURL = nil }
            // The export options belong to the song that was open. With the
            // share sheet up there is no panel to close, so nothing else
            // would put them back to the defaults until that share ends.
            if previousSongID != currentSongID { studio.endExportFlow() }
        }
        // Arrangement and Export are no longer presented here: each hangs off
        // the control that opens it — ARR in the transport, the ••• menu — so
        // at regular width it arrives as a popover beside its button with the
        // grid still visible, and adapts back to a sheet on a phone.
        .sheet(isPresented: $showingShare, onDismiss: {
            if let outcome = shareEnding.sheetDismissed() { afterShare(outcome) }
        }) {
            if let url = studio.exportURL {
                ShareSheet(items: [url], onComplete: { completed, error in
                    if let error {
                        switch ShareFailureMessage.sheetFailure(file: WriteFailureMessage.fileNoun(for: url),
                                                                error: error) {
                        case .photosDenied:
                            photosDenied = PhotosRetry(url: url, songID: sharedSongID ?? studio.song.id)
                        case .message(let text):
                            studio.shareError = text
                        }
                    }
                    let outcome: ReviewPromptPolicy.ShareOutcome = completed ? .completed : (error != nil ? .failed : .canceled)
                    if let decided = shareEnding.activityFinished(outcome) { afterShare(decided) }
                })
            }
        }
        .songShareSheet(for: studio)
        // Export renders off the main thread; the share sheet waits for the
        // render to finish rather than racing it. Watched through the attempt
        // counter, not the URL: see `ExportFlow.finishedExport`.
        .onChange(of: studio.completedExportAttempt) { previous, completed in
            guard let url = ExportFlow.finishedExport(previousAttempt: previous,
                                                      completedAttempt: completed,
                                                      url: studio.exportURL) else { return }
            Haptics.exportSucceeded()
            successfulExportCount += 1
            reviewAfterSharing = ReviewPromptPolicy.isDue(
                successfulExports: successfulExportCount,
                lastRequestExportCount: lastReviewRequestExportCount
            )
            shareEnding = ShareSheetEnding()
            sharedSongID = studio.song.id
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
        .alert(PhotosDeniedAlert.title,
               isPresented: Binding(get: { photosDenied != nil },
                                    set: { if !$0 { photosDenied = nil } }),
               presenting: photosDenied) { retry in
            Button(PhotosDeniedAlert.openSettings) {
                pendingPhotosRetry = retry
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settings)
                }
            }
            Button("OK", role: .cancel) {
                if ExportFlow.endsFlowAfterPhotosAlert(openedSettings: false) { studio.endExportFlow() }
            }
        } message: { _ in
            Text(PhotosDeniedAlert.message)
        }
        // Back from Settings after the Photos alert: the same video, offered
        // again, without another render.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let retry = pendingPhotosRetry else { return }
            pendingPhotosRetry = nil
            let reshares = retry.reshares(exportURL: studio.exportURL,
                                          currentSongID: studio.song.id,
                                          fileExists: FileManager.default.fileExists(atPath: retry.url.path),
                                          anyPresented: anyPresented)
            if ExportFlow.endsFlowAfterPhotosRetry(reshares: reshares) { studio.endExportFlow() }
            guard reshares else { return }
            shareEnding = ShareSheetEnding()
            sharedSongID = retry.songID
            showingShare = true
        }
        .errorAlert(UnreadableSongs.title, message: $studio.unreadableSongsNotice)
        .songFileImporter(isPresented: $showingImporter, studio: studio)
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
            || showingKeyboardHelp || songBoundPresented || studio.shareURL != nil
    }

    /// The presenters that hold state read from the current song: this
    /// view's clear-pattern confirmation plus the ones the pattern bar,
    /// transport and track headers report into the studio.
    private var songBoundPresented: Bool {
        pendingClearPatternIndex != nil || studio.songBoundPresenters.isPresented
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
    /// review prompt reads. The instrument editor is grid-owned state, so its
    /// track header watches the same request and closes it there.
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
        if step.endsFlow { studio.endExportFlow() }
        guard step.shareNow else { return }
        showingShare = true
    }

    /// The share sheet has gone and its activity has said how it went (see
    /// `ShareSheetEnding`). Asking for a review only now avoids competing
    /// presentations and ties the prompt to a moment when the app has
    /// demonstrably been useful.
    private func afterShare(_ outcome: ReviewPromptPolicy.ShareOutcome) {
        // A canceled or failed share doesn't spend the milestone: only a
        // completed share advances `lastReviewRequestExportCount`, so the
        // user keeps their eligibility for the next share that actually goes
        // somewhere.
        let result = ReviewPromptPolicy.afterShareDismiss(
            eligible: reviewAfterSharing,
            outcome: outcome,
            successfulExports: successfulExportCount,
            lastRequestExportCount: lastReviewRequestExportCount)
        reviewAfterSharing = false
        if ExportFlow.reopensExportAfterShare(outcome: outcome, sharedSongID: sharedSongID,
                                              currentSongID: studio.song.id) {
            showingExport = true
        }
        if ExportFlow.endsFlowAfterShare(outcome: outcome, sharedSongID: sharedSongID,
                                         currentSongID: studio.song.id,
                                         photosRetryOffered: photosDenied != nil || pendingPhotosRetry != nil) {
            studio.endExportFlow()
        }
        sharedSongID = nil
        lastReviewRequestExportCount = result.lastRequestExportCount
        guard result.shouldRequestReview else { return }
        // StoreKit decides whether a request is actually shown.
        requestReview()
    }

    /// Song name, transport and patterns. As wide as the grid under them, so
    /// Songs lines up with the step numbers and BPM and STEPS with the last
    /// column; any cap is the editor's as a whole (see `EditorColumn`).
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
    }

    /// The editor in both of its arrangements.
    ///
    /// Phone, and any iPad window taller than it is wide: the keys sit under
    /// the grid across the full width.
    ///
    /// iPad in landscape: stacking would leave the grid a squat band with
    /// three or four steps visible and a keyboard stretched a meter wide, so
    /// the keys move into a column of their own and the grid takes the height
    /// back — which is the whole reason to run natively on the thing. The
    /// chrome rides above the grid rather than the whole window, so the
    /// transport and the pattern strip stay over the thing they act on
    /// instead of spanning the keyboard column too.
    ///
    /// One tree for both, with only the container's axis switching (see
    /// `ChipLayout.editorAxis`). Two branches gave the chrome, grid and keys
    /// a different identity in each, so a rotation, or a Stage Manager window
    /// crossing the split threshold, rebuilt all of it: an export rendering
    /// behind the ••• popover was canceled, and the tempo alert, the pattern
    /// rename and the popovers this view owns lost their state.
    private func editor(_ layout: ChipLayout) -> some View {
        let side = layout.editorAxis == .horizontal
        let arrangement = side
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
        return arrangement {
            VStack(spacing: 0) {
                chrome(layout)
                editorGrid
            }

            // The grid used to run straight into the keys; this is the
            // breathing room between the two, whichever way they meet.
            Rectangle()
                .fill(Theme.grid.opacity(0.5))
                .frame(width: side ? 1 : nil, height: side ? nil : 1)
                .padding(.top, side ? 12 : 10)
                .padding(.bottom, side ? 12 : 0)
                .padding(.horizontal, side ? 0 : 14)

            keyPanel(layout)
                .frame(width: side ? layout.sideColumnWidth : nil)
        }
        // Nothing sits under the grid in the side arrangement, so without
        // this the last step row runs beneath the home indicator.
        .padding(.bottom, side ? 8 : 0)
        .modifier(EditorColumn(layout: layout))
    }

    /// The keys, and in the side column the selected track's sound under
    /// them.
    ///
    /// The keyboard alone left most of that column empty, and the one thing
    /// worth putting beside a keyboard is the voice it plays. Docking the
    /// instrument controls there also takes the editor off the sheet path,
    /// which on an iPad covered the grid every time you nudged a decay — and
    /// nudging a decay is something you do against the part you just wrote.
    ///
    /// Keys sit above the controls rather than below: they're what your hands
    /// go to, and the bottom edge of a 13-inch iPad is a long way from where
    /// the hands holding it are.
    ///
    /// The root ignores the keyboard safe area, so while the docked Name field
    /// is typed into the column pads its own bottom up to the keyboard and,
    /// when that leaves the editor no room under the piano, folds the piano
    /// away until the rename ends (see `DockedKeyboardAvoidance`). The piano
    /// is collapsed rather than removed so its state survives, and the column
    /// keeps its width, so the grid beside it never moves.
    private func keyPanel(_ layout: ChipLayout) -> some View {
        let avoidance = layout.docksInstrumentEditor
            ? DockedKeyboardAvoidance.resolve(nameEditing: dockedNameEditing,
                                              column: dockedColumnFrame,
                                              keyboardTop: keyboardTop,
                                              keysHeight: dockedKeysHeight)
            : .none
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                editorKeyboard
                    .padding(.top, layout.docksInstrumentEditor ? 0 : 10)

                if layout.docksInstrumentEditor {
                    Rectangle()
                        .fill(Theme.grid.opacity(0.5))
                        .frame(height: 1)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // Read only while no rename is under way. Folding the piano
                // changes this height, and feeding that back into the
                // decision that folded it made the layout oscillate forever.
                if height > 0, !dockedNameEditing { dockedKeysHeight = height }
            }
            .frame(height: avoidance.hidesKeys ? 0 : nil, alignment: .top)
            .clipped()
            .opacity(avoidance.hidesKeys ? 0 : 1)
            .allowsHitTesting(!avoidance.hidesKeys)
            .accessibilityHidden(avoidance.hidesKeys)

            if layout.docksInstrumentEditor {
                InstrumentEditor(studio: studio, index: studio.selectedTrack, docked: true,
                                 onNameFocusChange: { dockedNameEditing = $0 },
                                 keyboardInset: avoidance.bottomInset)
            }
        }
        .padding(.bottom, avoidance.bottomInset)
        .animation(.easeOut(duration: 0.2), value: avoidance)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            dockedColumnFrame = frame
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

    /// Accessibility text makes the chrome several rows tall, and a short
    /// Stage Manager window leaves the fixed editor's chrome and keys no room
    /// for a grid (see `ChipLayout.scrollsEditor`). Either way, give the whole
    /// editor a vertical escape hatch instead of squeezing the grid and piano
    /// into whatever sliver remains below it.
    private func scrollingEditor(_ layout: ChipLayout,
                                 availableHeight: CGFloat) -> some View {
        // A landscape iPad normally docks the instrument editor beside the
        // grid. This layout deliberately stacks instead, so its
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
            .modifier(EditorColumn(layout: stackedLayout))
        }
        .environment(\.chipLayout, stackedLayout)
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
        .buttonStyle(PressDimStyle())
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
            .buttonStyle(PressDimStyle())
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
                // A song title is a name: autocorrect turned "Zq" into "Zach"
                // as the keyboard went away.
                .autocorrectionDisabled()
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
                    showingImporter = true
                } label: {
                    Label("Import song…", systemImage: "square.and.arrow.down")
                }
                Button {
                    studio.duplicateSong()
                } label: {
                    Label("Duplicate song", systemImage: "plus.square.on.square")
                }
                Divider()
                // Export first: it's what most people tap the menu open for, and
                // the song-file share below it is the less common ask. The
                // sheet it opens chooses WAV or MIDI.
                Button {
                    openExport()
                } label: {
                    Label(studio.isExporting ? "Exporting…" : "Export…",
                          systemImage: "arrow.up.doc")
                }
                .disabled(studio.isExporting)
                Button {
                    studio.share(studio.song)
                } label: {
                    Label("Share song file", systemImage: "square.and.arrow.up")
                }
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

/// The column the editor draws in: the whole window on a phone, a portrait
/// iPad and beside the side keyboard, centered past
/// `ChipLayout.stackedEditorMaxWidth` otherwise. Applied to the chrome, grid
/// and keys together so they keep one leading and one trailing edge.
private struct EditorColumn: ViewModifier {
    let layout: ChipLayout

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: layout.editorMaxWidth)
            .frame(maxWidth: .infinity)
    }
}
