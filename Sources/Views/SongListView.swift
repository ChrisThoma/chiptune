import SwiftUI

/// Browse, open and delete saved songs.
struct SongListView: View {
    @Bindable var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView("No saved songs",
                                           systemImage: "waveform",
                                           description: Text("Save the current song from the ••• menu."))
                } else {
                    List {
                        ForEach(songs) { song in
                            Button {
                                studio.open(song)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(song.name).font(.headline)
                                    Text("\(Int(song.tempo)) BPM · \(song.length) steps · \(song.modified.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { SongStore.shared.delete(songs[index]) }
                            songs.remove(atOffsets: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { songs = SongStore.shared.loadAll() }
    }
}
