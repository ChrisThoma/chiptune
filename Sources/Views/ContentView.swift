import SwiftUI
import StoreKit
import UIKit

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

enum ReviewPromptPolicy {
    static let firstRequestExportCount = 3
    static let retryInterval = 10

    static func isDue(successfulExports: Int, lastRequestExportCount: Int) -> Bool {
        guard successfulExports >= firstRequestExportCount else { return false }
        guard lastRequestExportCount > 0 else { return true }
        guard successfulExports >= lastRequestExportCount else { return false }
        return successfulExports - lastRequestExportCount >= retryInterval
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
    @State private var confirmingClearPattern = false
    @State private var showingExport = false
    @State private var reviewAfterSharing = false
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
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .hardwareKeys(studio: studio)
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
            ArrangementView(studio: studio, regularWidth: horizontalSizeClass == .regular)
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet(studio: studio)
        }
        .sheet(isPresented: $showingShare, onDismiss: requestReviewIfDue) {
            if let url = studio.exportURL {
                ShareSheet(items: [url])
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
            Text(ConfirmationCopy.clearPattern)
        }
        // Three things that used to fail without saying so. The save one
        // matters most: there's no Save button to retry with, so a write that
        // fails quietly is work quietly lost.
        .errorAlert("Save failed", message: $studio.storageError)
        .errorAlert("Export failed", message: $studio.exportError)
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
            case .instrument, .none: break
            }
        }
    }

    /// Asking after the share sheet closes avoids competing presentations and
    /// ties the prompt to a moment when the app has demonstrably been useful.
    private func requestReviewIfDue() {
        guard reviewAfterSharing else { return }
        reviewAfterSharing = false
        // StoreKit decides whether a request is actually shown. Record the
        // milestone rather than latching forever, so a suppressed request can
        // be tried again after the app has delivered more value.
        lastReviewRequestExportCount = successfulExportCount
        requestReview()
    }

    /// Song name, transport and patterns. Capped and centred rather than
    /// stretched: BPM and STEPS trail their rows so the two steppers read as a
    /// column, and across 1200pt of window that puts the tempo at the far end
    /// of the room from the play button that uses it. The cap is per-layout,
    /// so a phone row is untouched.
    private func chrome(_ layout: ChipLayout) -> some View {
        VStack(spacing: 0) {
            titleBar
            TransportBar(studio: studio, showingArrangement: $showingArrangement)
            PatternBar(studio: studio)
        }
        .frame(maxWidth: layout.chromeMaxWidth)
        .frame(maxWidth: .infinity)
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
                GridView(studio: studio)
                    .frame(height: max(360, availableHeight * 0.55))
                Rectangle()
                    .fill(Theme.grid.opacity(0.5))
                    .frame(height: 1)
                    .padding(.top, 10)
                    .padding(.horizontal, 14)
                KeyboardView(studio: studio)
                    .padding(.top, 10)
            }
        }
        .environment(\.chipLayout, stackedLayout)
    }

    /// iPad in landscape. Stacking here would leave the grid a squat band with
    /// three or four steps visible and a keyboard stretched a metre wide, so
    /// the keys move into a column of their own and the grid takes the height
    /// back — which is the whole reason to run natively on the thing.
    private func wideEditor(_ layout: ChipLayout) -> some View {
        HStack(spacing: 0) {
            // The chrome rides above the grid rather than the whole window, so
            // the transport and the pattern strip stay over the thing they act
            // on instead of spanning the keyboard column too.
            VStack(spacing: 0) {
                chrome(layout)
                GridView(studio: studio)
            }

            Rectangle()
                .fill(Theme.grid.opacity(0.5))
                .frame(width: 1)
                .padding(.vertical, 12)

            instrumentPanel
                .frame(width: ChipLayout.sideKeyboardWidth)
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
            KeyboardView(studio: studio)

            Rectangle()
                .fill(Theme.grid.opacity(0.5))
                .frame(height: 1)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            InstrumentEditor(studio: studio, index: studio.selectedTrack, docked: true)
        }
    }

    /// Narrower than the 44pt targets either side of them — two more of those
    /// would squeeze the song name to nothing. Still comfortably tappable, and
    /// dimmed rather than hidden when there's nothing to undo, so the row
    /// doesn't reflow as you edit.
    private func historyButton(_ symbol: String, label: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolFont(15, weight: .semibold)
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
                    .symbolFont(19)
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
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
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
                Divider()
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
                    .symbolFont(19)
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
