import SwiftUI

/// Browse, open, duplicate and delete saved songs. Everything is autosaved, so
/// this is the whole library rather than a list of things you remembered to save.
struct SongListView: View {
    @Bindable var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []

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
                        .onDelete { offsets in
                            for index in offsets { SongStore.shared.delete(songs[index]) }
                            songs.remove(atOffsets: offsets)
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
                    Button {
                        studio.newSong()
                        dismiss()
                    } label: {
                        Label("New song", systemImage: "plus")
                    }
                }
            }
            .tint(Theme.text)
        }
        .preferredColorScheme(.dark)
        .onAppear { songs = SongStore.shared.loadAll() }
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
                var copy = song
                copy.id = UUID()
                copy.name = song.name + " copy"
                SongStore.shared.save(copy)
                songs = SongStore.shared.loadAll()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .tint(Theme.panelHigh)
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
