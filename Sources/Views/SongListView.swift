import SwiftUI
import UIKit

/// The rename alert's text field is native UIKit, not SwiftUI, and its
/// background flips between OS versions: white on iOS 17's alert, dark on
/// iOS 26's. SwiftUI never tells us which one we got, so the ink is decided
/// from the field's own container's real background at apply time instead of
/// a fixed color.
enum SongRenameAlertStyle {
    /// The ink to use over a given background: whichever of the two theme
    /// inks actually contrasts more with it, by WCAG contrast ratio -- not a
    /// fixed luminance cut, which stops being the true crossover once the two
    /// candidate inks aren't pure black and white.
    static func textColor(over background: UIColor) -> UIColor {
        let onLight = UIColor(Theme.onLight)
        let text = UIColor(Theme.text)
        return contrastRatio(onLight, background) >= contrastRatio(text, background) ? onLight : text
    }

    /// The WCAG contrast ratio between two colors: (Lmax + 0.05) / (Lmin + 0.05).
    static func contrastRatio(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let luminanceA = relativeLuminance(of: a)
        let luminanceB = relativeLuminance(of: b)
        return (max(luminanceA, luminanceB) + 0.05) / (min(luminanceA, luminanceB) + 0.05)
    }

    /// The first opaque-enough background found walking up from `view`'s own
    /// superview, or nil if none of its ancestors have one.
    static func containerBackground(of view: UIView) -> UIColor? {
        var candidate = view.superview
        while let view = candidate {
            if let background = view.backgroundColor, background.cgColor.alpha > 0.5 {
                return background
            }
            candidate = view.superview
        }
        return nil
    }

    /// Colors `field`'s text from its real container's background, falling
    /// back to the system label color when no ancestor has one to read.
    static func apply(to field: UITextField) {
        field.textColor = containerBackground(of: field).map(textColor(over:)) ?? .label
    }

    static func relativeLuminance(of color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

extension SongNameFieldAccessibility {
    static func apply(to textField: UITextField) {
        textField.accessibilityLabel = label
    }
}

/// SwiftUI drops modifiers from alert TextFields on iOS 17. This inert bridge
/// labels the UITextField SwiftUI creates, leaving the alert itself and
/// all of its binding/action behavior native to SwiftUI.
private struct SongRenameAlertAccessibilityBridge: UIViewRepresentable {
    let isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.generation += 1
        guard isPresented else { return }
        context.coordinator.applyLabel(from: view,
                                       generation: context.coordinator.generation)
    }

    final class Coordinator {
        var generation = 0

        func applyLabel(from view: UIView, generation expectedGeneration: Int,
                        attemptsRemaining: Int = 100) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self, weak view] in
                guard let self, let view,
                      self.generation == expectedGeneration else { return }
                var presented = view.window?.rootViewController
                while let next = presented?.presentedViewController { presented = next }
                if let field = (presented as? UIAlertController)?.textFields?.first {
                    SongNameFieldAccessibility.apply(to: field)
                    SongRenameAlertStyle.apply(to: field)
                } else if attemptsRemaining > 1 {
                    self.applyLabel(from: view, generation: expectedGeneration,
                                    attemptsRemaining: attemptsRemaining - 1)
                }
            }
        }
    }
}

/// Browse, open, duplicate and delete saved songs. Everything is autosaved, so
/// this is the whole library rather than a list of things you remembered to save.
struct SongListView: View {
    @Bindable var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []
    /// Song queued for deletion, held while the confirmation is up.
    @State private var pendingDelete: Song?
    @State private var renaming: Song?
    @State private var renameText = ""
    @State private var showingImporter = false
    /// A save failure raised by an action taken here, moved out of the studio
    /// so only this sheet's alert presents it. See `claimStorageError()`.
    @State private var saveError: String?
    /// An import failure, claimed the same way and for the same reason.
    @State private var importFailure: String?
    /// A share failure, claimed the same way and for the same reason.
    @State private var shareFailure: String?
    /// A `.chipsong` is hovering over the library, waiting to be dropped.
    @State private var dropTargeted = false

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label("No songs yet", systemImage: "waveform")
                            .foregroundStyle(Theme.text)
                    } description: {
                        Text("Start writing and this one shows up here — songs save themselves as you go.")
                            .foregroundStyle(Theme.dim)
                    }
                } else {
                    List {
                        ForEach(songs) { song in
                            row(song)
                                .listRowBackground(Theme.background)
                        }
                        // Deliberately not `.onDelete`: swipe-to-delete removes
                        // the song the moment the swipe completes, and a song
                        // is not recoverable. The swipe now only asks.
                        .onDelete { offsets in
                            pendingDelete = offsets.first.map { songs[$0] }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .listRowSeparatorTint(Theme.grid)
                }
            }
            // Dropping a song file here imports it, the same as the Import
            // item in the Add menu. Attached out here rather than to the
            // `List` so an empty library — the one most likely to be dropped
            // on — is a target too.
            .dropDestination(for: SongFile.self) { files, _ in
                guard let file = files.first else { return false }
                // Deferred one runloop tick for the same reason the file
                // importer defers: importing (and dismissing) inside the
                // drop's own transaction can make SwiftUI drop the error
                // alert's presentation.
                DispatchQueue.main.async {
                    if studio.importSong(decoded: file.song) {
                        reload()
                        dismiss()
                    } else {
                        claimImportError()
                    }
                }
                return true
            } isTargeted: { dropTargeted = $0 }
            .overlay {
                SongDropBorder(isTargeted: dropTargeted)
            }
            // A song row is a name and a date; across the full width of an
            // iPad form sheet that leaves a long empty gutter after each one,
            // so the list is capped and centered and the background keeps the
            // rest.
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Songs")
            .navigationBarTitleDisplayMode(.inline)
            // `.cancellationAction`/`.confirmationAction` get bridged to legacy
            // UIBarButtonItems that drop the accessibility metadata attached
            // here; the topBar placements stay SwiftUI-native and keep it.
            .toolbar {
                ToolbarItem(id: "SongListView.CloseButton", placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .accessibilityLabel("Close")
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("SongListView.CloseButton")
                }
                ToolbarItem(id: "SongListView.AddMenu", placement: .topBarTrailing) {
                    Menu {
                        Button {
                            studio.newSong()
                            dismiss()
                        } label: {
                            Label("New song", systemImage: "doc.badge.plus")
                        }
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import song…", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add")
                    }
                    .accessibilityLabel("Add")
                    .accessibilityIdentifier("SongListView.AddMenu")
                }
            }
            .tint(Theme.text)
        }
        .preferredColorScheme(.dark)
        .onAppear { reload() }
        // On iOS 26 iPhone and on every iPad this presents as a popover, and
        // UIKit drops `.cancel`-role actions from a popover, so a
        // confirmationDialog here would leave no way out but tapping
        // outside. `.alert` always presents modally and keeps both buttons.
        .alert("Delete “\(pendingDelete?.name ?? "")”?",
               isPresented: Binding(isPresenting: $pendingDelete)) {
            Button("Delete song", role: .destructive) {
                if let song = pendingDelete { studio.delete(song) }
                claimStorageError()
                pendingDelete = nil
                reload()
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
        .songFileImporter(isPresented: $showingImporter, studio: studio) { imported in
            if imported {
                dismiss()
            } else {
                claimImportError()
            }
        }
        // Deferred one runloop tick, the same as the file importer and the
        // drop destination above: presenting this alert in the same
        // transaction as the share sheet's own dismissal can make SwiftUI
        // drop the alert's presentation.
        .songShareSheet(for: studio, onFailure: { message in
            DispatchQueue.main.async { shareFailure = message }
        })
        .background {
            SongRenameAlertAccessibilityBridge(isPresented: renaming != nil)
        }
        .alert("Rename song", isPresented: Binding(isPresenting: $renaming)) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let song = renaming { studio.rename(song, to: renameText) }
                claimStorageError()
                renaming = nil
                reload()
            }
            // A blank name, or one that collides with a different existing
            // song's name, is rejected by the model; gray the button out
            // instead of letting it dismiss and silently do nothing.
            .disabled({
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return true }
                return songs.contains { $0.id != renaming?.id && $0.name == trimmed }
            }())
        }
        // Failures raised in here get their own presenters, bound to local
        // state rather than to the studio; see `claimStorageError()`.
        .errorAlert("Save failed", message: $saveError)
        .errorAlert("Import failed", message: $importFailure)
        .errorAlert("Share failed", message: $shareFailure)
    }

    /// Moves a storage failure off the studio and onto this sheet's alert.
    ///
    /// The library is itself a sheet, so the presenter on ContentView is
    /// underneath it and SwiftUI won't surface it — see
    /// `songShareSheet(for:)`'s doc comment for the same reasoning. Worse,
    /// leaving the message on the studio means two live presenters bound to
    /// the same property try to present at once, and the editor's, whose view
    /// controller is already presenting this sheet, tears the sheet down
    /// instead. Claiming the message leaves exactly one presenter for it.
    private func claimStorageError() {
        guard let error = studio.storageError else { return }
        studio.storageError = nil
        saveError = error
    }

    /// The same claim for an import failure, which has the same two-presenter
    /// problem.
    private func claimImportError() {
        guard let error = studio.importError else { return }
        studio.importError = nil
        importFailure = error
    }

    /// The same claim for a share failure, which has the same two-presenter
    /// problem.
    private func claimShareError() {
        guard let error = studio.shareError else { return }
        studio.shareError = nil
        shareFailure = error
    }

    private func reload() {
        songs = studio.store.loadAll()
    }

    private func row(_ song: Song) -> some View {
        let isOpen = song.id == studio.song.id

        return Button {
            if !isOpen { studio.open(song) }
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.name)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(detail(song))
                        .chipFont(11)
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
                if isOpen {
                    Text("OPEN")
                        .chipFont(11, weight: .bold)
                        .foregroundStyle(Theme.accentGreen)
                }
            }
            .contentShape(Rectangle())
        }
        // Without this the List tints the whole label with the accent color and
        // every song title renders blue.
        .buttonStyle(.plain)
        // Drag a song out to Files or another app; the drag writes the same
        // `.chipsong` the share action does.
        .draggable(SongFile(song: song))
        .swipeActions(edge: .leading) {
            duplicateAction(song).tint(Theme.panelHigh)
            renameAction(song).tint(Theme.panelHigh)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Full swipe stays off: a song is not recoverable.
            // Without an explicit tint, the NavigationStack's `.tint(Theme.text)`
            // wins and this destructive swipe renders white instead of red.
            deleteAction(song).tint(.red)
            shareAction(song).tint(Theme.panelHigh)
        }
        // The same actions again, for anyone who reaches for a long press
        // instead — and so rename is discoverable without swiping.
        .contextMenu {
            renameAction(song)
            duplicateAction(song)
            shareAction(song)
            deleteAction(song)
        }
    }

    // One definition per action, shared by the swipes and the long-press menu
    // so the two entrances can't drift apart.

    private func renameAction(_ song: Song) -> some View {
        Button {
            renameText = song.name
            renaming = song
        } label: {
            Label("Rename", systemImage: "pencil")
        }
    }

    private func duplicateAction(_ song: Song) -> some View {
        Button {
            studio.duplicate(song)
            claimStorageError()
            reload()
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
    }

    private func shareAction(_ song: Song) -> some View {
        Button {
            studio.share(song)
            claimShareError()
        } label: {
            Label("Share song file", systemImage: "square.and.arrow.up")
        }
    }

    private func deleteAction(_ song: Song) -> some View {
        // Asks first rather than acting on the tap — a song is not recoverable.
        Button(role: .destructive) {
            pendingDelete = song
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func detail(_ song: Song) -> String {
        // Monospace is wider than the proportional caption this used to be, so
        // the clock is dropped to keep the line from wrapping: with it, a
        // 16-pattern song wrapped onto a second line on a 375pt phone.
        return "\(Format.bpm(song.tempo)) · \(Format.count(song.patterns.count, "pattern")) · \(song.modified.formatted(date: .abbreviated, time: .omitted))"
    }
}
