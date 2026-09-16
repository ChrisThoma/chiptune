import SwiftUI
import UIKit

enum ArrangementCapacityAnnouncement {
    static func shouldAnnounce(previouslyExceeded: Bool, nowExceeds: Bool) -> Bool {
        !previouslyExceeded && nowExceeds
    }
}

/// The song's play order: a list of sections, each naming a pattern and how
/// many times it repeats. SONG mode walks this list from the top and loops.
struct ArrangementView: View {
    @Bindable var studio: Studio
    /// Presented in an iPad-shaped window, where this arrives as a popover
    /// over the ARR button rather than as a sheet. Passed in rather than read
    /// from the environment, which reports a popover's or a sheet's contents
    /// as compact whatever the window behind it is.
    var regularWidth = false
    @Environment(\.dismiss) private var dismiss
    private var capacityWarning: String {
        "More than \(Chip.maxChain) plays — sections past that won't sound."
    }

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
                        // The row's own content inset, not the label, was the
                        // last dead strip: a full-width label still stops 16pt
                        // short of the cell's trailing edge. Zero the row insets
                        // and re-apply the 16pt as padding inside the tappable
                        // shape, so the shape reaches the real edge while the
                        // text stays aligned with the section rows above.
                        Label("Add section", systemImage: "plus")
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Play order")
                } footer: {
                    Text(summary)
                }

                if studio.song.exceedsChainCapacity {
                    Section {
                        Label(capacityWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Text("Each section plays one pattern. Repeat it to hold a section for longer, and drag to reorder. Switch the transport to SONG to hear the whole thing; PATT keeps looping just the pattern you're editing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: studio.song.exceedsChainCapacity) { exceeded, nowExceeds in
                guard ArrangementCapacityAnnouncement.shouldAnnounce(
                    previouslyExceeded: exceeded,
                    nowExceeds: nowExceeds
                ) else { return }
                UIAccessibility.post(notification: .announcement,
                                     argument: capacityWarning)
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
        .compactSheetDetents(!regularWidth)
        // Regular width means this arrived as a popover, which has no detents
        // and takes whatever size its content states. Taller than the default
        // because the play order is a list that grows.
        .popoverSized(regularWidth, idealHeight: 560)
        .preferredColorScheme(.dark)
    }

    private var summary: String {
        let song = studio.song
        return "\(Format.count(Set(song.chain).count, "pattern")) · \(song.arrangementSteps) steps · \(Format.clock(song.arrangementDuration)) at \(Format.bpm(song.tempo))"
    }

    private func row(position: Int, section: SongSection) -> some View {
        let index = studio.song.patternIndex(id: section.patternID)
        let pattern = index.flatMap { studio.song.patterns[safe: $0] }
        // Keyed on the section, not the pattern: a pattern used by two sections
        // lit both of them at once, which read as playback never leaving the
        // first one.
        let playing = studio.isPlaying && studio.songMode && studio.playingSection == position

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
                .background(RoundedRectangle(cornerRadius: Theme.innerRadius).fill(Color.secondary.opacity(0.18)))
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
            .accessibilityLabel("Repeats")
            .accessibilityValue("\(section.repeats) times")
        }
    }
}
