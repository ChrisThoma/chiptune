import SwiftUI
import UIKit

enum SongRenameAlertStyle {
    /// SwiftUI's iOS 17 alert field is white even under our forced dark scheme.
    static let fieldText = Theme.onLight
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
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?",
                            isPresented: Binding(isPresenting: $pendingDelete),
                            titleVisibility: .visible) {
            Button("Delete song", role: .destructive) {
                if let song = pendingDelete { studio.delete(song) }
                pendingDelete = nil
                reload()
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [SongDocument.contentType, .json],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first, studio.importSong(from: url) { dismiss() }
            case .failure(let error):
                studio.importError = error.localizedDescription
            }
        }
        .songShareSheet(for: studio)
        .errorAlert("Import failed", message: $studio.importError)
        // The library shares too, from the row's swipe action.
        .errorAlert("Share failed", message: $studio.shareError)
        .background {
            SongRenameAlertAccessibilityBridge(isPresented: renaming != nil)
        }
        .alert("Rename song", isPresented: Binding(isPresenting: $renaming)) {
            TextField("Name", text: $renameText)
                .foregroundStyle(SongRenameAlertStyle.fieldText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let song = renaming { studio.rename(song, to: renameText) }
                renaming = nil
                reload()
            }
            // A blank name is rejected by the model; grey the button out
            // instead of letting it dismiss and silently do nothing.
            .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
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
        // Without this the List tints the whole label with the accent colour and
        // every song title renders blue.
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            duplicateAction(song).tint(Theme.panelHigh)
            renameAction(song).tint(Theme.panelHigh)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Full swipe stays off: a song is not recoverable.
            deleteAction(song)
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
            reload()
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
    }

    private func shareAction(_ song: Song) -> some View {
        Button {
            studio.share(song)
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
        // the clock is dropped to keep the line from wrapping.
        return "\(Format.bpm(song.tempo)) · \(Format.count(song.patterns.count, "pattern")) · \(Format.clock(song.arrangementDuration)) · \(song.modified.formatted(date: .abbreviated, time: .omitted))"
    }
}
