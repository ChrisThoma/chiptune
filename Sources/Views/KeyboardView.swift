import SwiftUI

/// One-octave piano used to pick the note that taps write into the grid.
struct KeyboardView: View {
    @Bindable var studio: Studio
    @State private var octave: Int = 5

    /// Semitone offsets of the white keys, C through the octave's C.
    private let whiteOffsets = [0, 2, 4, 5, 7, 9, 11, 12]
    /// Black keys as (semitone offset, index of the white key it sits after).
    private let blackKeys: [(offset: Int, after: Int)] = [
        (1, 0), (3, 1), (6, 3), (8, 4), (10, 5)
    ]

    private var baseMidi: Int { octave * 12 }

    var body: some View {
        VStack(spacing: 8) {
            controls
            GeometryReader { geo in
                let whiteWidth = geo.size.width / CGFloat(whiteOffsets.count)
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        ForEach(whiteOffsets, id: \.self) { offset in
                            key(midi: baseMidi + offset, black: false)
                        }
                    }
                    ForEach(blackKeys, id: \.offset) { black in
                        key(midi: baseMidi + black.offset, black: true)
                            .frame(width: whiteWidth * 0.58, height: geo.size.height * 0.6)
                            .offset(x: whiteWidth * CGFloat(black.after + 1) - whiteWidth * 0.29)
                    }
                }
            }
            .frame(height: 110)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                octave = max(0, octave - 1)
            } label: {
                Image(systemName: "chevron.left").chipFont(13)
            }
            .buttonStyle(PadStyle())
            .disabled(octave <= 0)
            .accessibilityLabel("Octave down")

            Text("OCT \(octave - 1)")
                .chipFont(12)
                .foregroundStyle(Theme.dim)
                .frame(width: 62)

            Button {
                octave = min(8, octave + 1)
            } label: {
                Image(systemName: "chevron.right").chipFont(13)
            }
            .buttonStyle(PadStyle())
            .disabled(octave >= 8)
            .accessibilityLabel("Octave up")

            Spacer()

            Text(NoteName.label(studio.selectedNote))
                .chipFont(15, weight: .bold)
                .foregroundStyle(Theme.color(for: studio.selectedChannel))

            Spacer()

            // Writes a note-off into the grid instead of a pitch, for cutting
            // sustained notes on the triangle channel.
            Button {
                studio.selectedNote = ChipCore.noteOff
            } label: {
                Text("OFF").chipFont(12)
            }
            .buttonStyle(PadStyle(active: studio.selectedNote == ChipCore.noteOff))
            .accessibilityLabel("Select note off")
        }
    }

    private func key(midi: Int, black: Bool) -> some View {
        let note = Int8(clamping: midi)
        let selected = studio.selectedNote == note
        let accent = Theme.color(for: studio.selectedChannel)

        return RoundedRectangle(cornerRadius: 5)
            .fill(selected ? accent : (black ? Color(white: 0.13) : Color(white: 0.88)))
            .overlay(alignment: .bottom) {
                if !black {
                    Text(NoteName.label(note))
                        .chipFont(9)
                        .foregroundStyle(selected ? Color.black.opacity(0.7) : Color.black.opacity(0.45))
                        .padding(.bottom, 5)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                studio.selectedNote = note
                studio.audition(note)
            }
            .accessibilityLabel("Note \(NoteName.label(note))")
    }
}

/// Small dark control button used across the transport and keyboard rows.
struct PadStyle: ButtonStyle {
    var active: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? Color.black : Theme.text)
            .padding(.horizontal, 14)
            // Meets the 44pt minimum touch target on its own.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(active ? Theme.text : Theme.panelHigh)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
