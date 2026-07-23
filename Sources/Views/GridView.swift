import SwiftUI

/// The step grid: one column per track, one row per step.
///
/// A song can hold up to `Chip.maxTracks` tracks, so the columns keep a usable
/// tap width and the whole grid scrolls sideways once they stop fitting.
struct GridView: View {
    @Bindable var studio: Studio

    private let rowHeight: CGFloat = 40
    private let gutterWidth: CGFloat = 28
    /// Narrow enough to fit a handful of columns, wide enough to stay tappable.
    private let minColumnWidth: CGFloat = 74
    private let addColumnWidth: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let columnWidth = columnWidth(forAvailable: geo.size.width)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    header(columnWidth: columnWidth)
                    steps(columnWidth: columnWidth)
                }
            }
        }
        .background(Theme.background)
    }

    /// Tracks share the width evenly while they fit; past that they take the
    /// minimum and the row overflows into the horizontal scroll.
    private func columnWidth(forAvailable width: CGFloat) -> CGFloat {
        let reserved = gutterWidth + (studio.song.canAddTrack ? addColumnWidth + 2 : 0) + 12
        let available = width - reserved
        let each = available / CGFloat(max(studio.song.tracks.count, 1))
        return max(minColumnWidth, each)
    }

    private func header(columnWidth: CGFloat) -> some View {
        HStack(spacing: 2) {
            // Height-constrained so it doesn't stretch the header row.
            Color.clear.frame(width: gutterWidth, height: 1)
            ForEach(Array(studio.song.tracks.enumerated()), id: \.element.id) { index, _ in
                TrackHeader(studio: studio, index: index)
                    .frame(width: columnWidth)
            }
            if studio.song.canAddTrack {
                addTrackButton.frame(width: addColumnWidth)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    private var addTrackButton: some View {
        Menu {
            ForEach(ChannelKind.allCases, id: \.self) { kind in
                Button(kind.fullName) { studio.addTrack(kind: kind) }
            }
        } label: {
            Image(systemName: "plus")
                .chipFont(15)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 81)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.panel)
                )
        }
        .accessibilityLabel("Add track")
    }

    private func steps(columnWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(0..<studio.song.length, id: \.self) { step in
                        row(step: step, columnWidth: columnWidth)
                            .id(step)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: studio.playhead) { _, step in
                guard studio.isPlaying, studio.song.length > 16 else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(step, anchor: .center)
                }
            }
        }
    }

    private func row(step: Int, columnWidth: CGFloat) -> some View {
        HStack(spacing: 2) {
            Text(String(format: "%02d", step))
                .chipFont(11)
                .foregroundStyle(step % 4 == 0 ? Theme.text : Theme.dim)
                .frame(width: gutterWidth)

            ForEach(Array(studio.song.tracks.enumerated()), id: \.element.id) { index, _ in
                cell(track: index, step: step)
                    .frame(width: columnWidth)
            }
            if studio.song.canAddTrack {
                Color.clear.frame(width: addColumnWidth, height: 1)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: rowHeight)
        .background(
            studio.isPlaying && studio.playhead == step
                ? Color.white.opacity(0.14)
                : Color.clear
        )
    }

    private func cell(track: Int, step: Int) -> some View {
        let note = studio.note(track: track, step: step)
        let filled = note != Chip.emptyNote
        let accent = Theme.color(for: studio.song.tracks[track].kind)
        let isOff = note == ChipCore.noteOff

        return Button {
            studio.toggleCell(track: track, step: step)
        } label: {
            Text(isOff ? "OFF" : (filled ? NoteName.label(note) : "·"))
                .chipFont(filled ? 12 : 14)
                .foregroundStyle(filled ? Color.black.opacity(0.85) : Theme.dim.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(filled
                              ? (isOff ? Theme.dim : accent).opacity(studio.song.tracks[track].muted ? 0.35 : 1.0)
                              : Theme.rowTint(step: step))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Theme.grid.opacity(0.6), lineWidth: filled ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(studio.song.fullLabel(for: track)) step \(step + 1)")
        .accessibilityValue(filled ? NoteName.label(note) : "empty")
    }
}

/// Track name and mute toggle.
///
/// These were three overlapping tap targets in one thumb-width box, which made
/// them almost impossible to hit. Now there are exactly two, stacked and
/// full-width: the name selects the track (and reopens its sound editor once
/// selected), and the speaker row below it mutes.
private struct TrackHeader: View {
    @Bindable var studio: Studio
    let index: Int
    @State private var showingEditor = false

    var body: some View {
        let track = studio.song.tracks[safe: index]
        let accent = Theme.color(for: track?.kind ?? .pulse1)
        let muted = track?.muted ?? false
        let selected = studio.selectedTrack == index
        let name = studio.song.fullLabel(for: index)

        VStack(spacing: 4) {
            Button {
                // Already selected? The second tap opens the sound editor.
                if selected { showingEditor = true } else { studio.selectedTrack = index }
            } label: {
                HStack(spacing: 4) {
                    Text(studio.song.label(for: index)).chipFont(13).lineLimit(1)
                    if selected {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 9))
                    }
                }
                .foregroundStyle(muted ? Theme.dim : accent)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityHint(selected ? "Opens sound settings" : "Selects this track")

            Button {
                studio.song.tracks[index].muted.toggle()
                studio.pushInstrument(index)
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(muted ? Theme.dim : Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(muted ? Color.black.opacity(0.35) : Theme.panelHigh)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(muted ? "Unmute \(name)" : "Mute \(name)")
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? accent.opacity(0.18) : Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? accent : Color.clear, lineWidth: 1.5)
        )
        // Duplicate and delete also live in the sound editor; this is the
        // shortcut for when you already know what you want.
        .contextMenu {
            Button {
                studio.duplicateTrack(at: index)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(!studio.song.canAddTrack)

            Button(role: .destructive) {
                studio.removeTrack(at: index)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(studio.song.tracks.count <= 1)
        }
        .sheet(isPresented: $showingEditor) {
            InstrumentEditor(studio: studio, index: index)
        }
    }
}
