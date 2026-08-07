import SwiftUI

enum SongRenameAlertStyle {
    /// SwiftUI's iOS 17 alert field is white even under our forced dark scheme.
    static let fieldText = Theme.onLight
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
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
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .tint(Theme.text)
        }
        .preferredColorScheme(.dark)
        .onAppear { reload() }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
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
        .sheet(isPresented: Binding(get: { studio.shareURL != nil },
                                    set: { if !$0 { studio.shareURL = nil } })) {
            if let url = studio.shareURL {
                ShareSheet(items: [url])
            }
        }
        .errorAlert("Import failed", message: $studio.importError)
        // The library shares too, from the row's swipe action.
        .errorAlert("Share failed", message: $studio.shareError)
        .alert("Rename song", isPresented: Binding(get: { renaming != nil },
                                                   set: { if !$0 { renaming = nil } })) {
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
            Button {
                studio.duplicate(song)
                reload()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(Theme.panelHigh)

            Button {
                renameText = song.name
                renaming = song
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(Theme.panelHigh)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Asks first rather than deleting on the swipe — a song is not
            // recoverable. Full swipe stays off for the same reason.
            Button(role: .destructive) {
                pendingDelete = song
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                studio.share(song)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(Theme.panelHigh)
        }
        // Same three actions as the swipes, for anyone who reaches for a long
        // press instead — and so rename is discoverable without swiping.
        .contextMenu {
            Button {
                renameText = song.name
                renaming = song
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                studio.duplicate(song)
                reload()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Button {
                studio.share(song)
            } label: {
                Label("Share song file", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                pendingDelete = song
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func detail(_ song: Song) -> String {
        let patterns = song.patterns.count
        let seconds = song.arrangementDuration
        let time = String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
        // Monospace is wider than the proportional caption this used to be, so
        // the clock is dropped to keep the line from wrapping.
        return "\(Int(song.tempo)) BPM · \(patterns) pattern\(patterns == 1 ? "" : "s") · \(time) · \(song.modified.formatted(date: .abbreviated, time: .omitted))"
    }
}
