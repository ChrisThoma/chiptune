import SwiftUI

/// The song's play order: a list of sections, each naming a pattern and how
/// many times it repeats. SONG mode walks this list from the top and loops.
struct ArrangementView: View {
    @Bindable var studio: Studio
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(studio.song.arrangement.enumerated()), id: \.element.id) { position, section in
                        row(position: position, section: section)
                    }
                    .onDelete { studio.removeSection(at: $0) }
                    .onMove { studio.moveSection(from: $0, to: $1) }

                    Menu {
                        ForEach(studio.song.patterns) { pattern in
                            Button("Pattern \(pattern.name)") {
                                studio.addSection(patternID: pattern.id)
                            }
                        }
                    } label: {
                        Label("Add section", systemImage: "plus")
                    }
                } header: {
                    Text("Play order")
                } footer: {
                    Text(summary)
                }

                Section {
                    Text("Each section plays one pattern. Repeat it to hold a section for longer, and drag to reorder. Switch the transport to SONG to hear the whole thing; PATT keeps looping just the pattern you're editing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Without these the List keeps its translucent system background
            // and the grid shows through the sheet. SongListView does the same.
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Arrangement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var summary: String {
        let song = studio.song
        let blocks = song.chain.count
        let steps = song.arrangementSteps
        let seconds = song.arrangementDuration
        let time = String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
        return "\(blocks) pattern\(blocks == 1 ? "" : "s") · \(steps) steps · \(time) at \(Int(song.tempo)) BPM"
    }

    private func row(position: Int, section: SongSection) -> some View {
        let index = studio.song.patternIndex(id: section.patternID)
        let pattern = index.flatMap { studio.song.patterns[safe: $0] }
        let playing = studio.isPlaying && studio.songMode && studio.playingPattern == index

        return HStack(spacing: 12) {
            Text("\(position + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            Menu {
                ForEach(studio.song.patterns) { candidate in
                    Button(candidate.name) { studio.setSection(section.id, patternID: candidate.id) }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(pattern?.name ?? "?")
                        .font(.system(.body, design: .monospaced).bold())
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.18)))
            }
            .accessibilityLabel("Section \(position + 1), pattern \(pattern?.name ?? "none")")

            if playing {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()

            Stepper(value: Binding(get: { section.repeats },
                                   set: { studio.setSection(section.id, repeats: $0) }),
                    in: 1...SongSection.maxRepeats) {
                Text("×\(section.repeats)")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
    }
}
