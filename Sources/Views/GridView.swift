import SwiftUI

/// The step grid: one column per channel, one row per step.
struct GridView: View {
    @Bindable var studio: Studio

    private let rowHeight: CGFloat = 34
    private let gutterWidth: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(0..<studio.song.length, id: \.self) { step in
                            row(step: step)
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
        .background(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 2) {
            // Height-constrained so it doesn't stretch the header row.
            Color.clear.frame(width: gutterWidth, height: 1)
            ForEach(0..<Chip.channelCount, id: \.self) { channel in
                ChannelHeader(studio: studio, channel: channel)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }

    private func row(step: Int) -> some View {
        HStack(spacing: 2) {
            Text(String(format: "%02d", step))
                .chipFont(11)
                .foregroundStyle(step % 4 == 0 ? Theme.text : Theme.dim)
                .frame(width: gutterWidth)

            ForEach(0..<Chip.channelCount, id: \.self) { channel in
                cell(channel: channel, step: step)
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

    private func cell(channel: Int, step: Int) -> some View {
        let note = studio.note(channel: channel, step: step)
        let filled = note != Chip.emptyNote
        let accent = Theme.color(for: channel)
        let isOff = note == ChipCore.noteOff

        return Button {
            studio.toggleCell(channel: channel, step: step)
        } label: {
            Text(isOff ? "OFF" : (filled ? NoteName.label(note) : "·"))
                .chipFont(filled ? 12 : 14)
                .foregroundStyle(filled ? Color.black.opacity(0.85) : Theme.dim.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(filled
                              ? (isOff ? Theme.dim : accent).opacity(studio.song.tracks[channel].muted ? 0.35 : 1.0)
                              : Theme.rowTint(step: step))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Theme.grid.opacity(0.6), lineWidth: filled ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ChannelKind(rawValue: channel)?.fullName ?? "") step \(step + 1)")
        .accessibilityValue(filled ? NoteName.label(note) : "empty")
    }
}

/// Channel name, mute toggle and a tap target for the instrument editor.
private struct ChannelHeader: View {
    @Bindable var studio: Studio
    let channel: Int
    @State private var showingEditor = false

    var body: some View {
        let accent = Theme.color(for: channel)
        let muted = studio.song.tracks[channel].muted
        let selected = studio.selectedChannel == channel

        VStack(spacing: 3) {
            Text(ChannelKind(rawValue: channel)?.name ?? "")
                .chipFont(12)
                .foregroundStyle(muted ? Theme.dim : accent)

            HStack(spacing: 6) {
                Button {
                    studio.song.tracks[channel].muted.toggle()
                    studio.pushInstrument(channel)
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(muted ? Theme.dim : Theme.text)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(muted ? "Unmute \(ChannelKind(rawValue: channel)?.fullName ?? "")"
                                          : "Mute \(ChannelKind(rawValue: channel)?.fullName ?? "")")

                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.text)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(ChannelKind(rawValue: channel)?.fullName ?? "") sound")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? accent.opacity(0.18) : Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? accent : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { studio.selectedChannel = channel }
        .sheet(isPresented: $showingEditor) {
            InstrumentEditor(studio: studio, channel: channel)
        }
    }
}
