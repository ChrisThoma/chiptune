import SwiftUI

/// One-octave piano used to pick the note that taps write into the grid.
struct KeyboardView: View {
    @Bindable var studio: Studio
    @Environment(\.chipLayout) private var layout
    @ScaledMetric(relativeTo: .body) private var octaveWidth: CGFloat = 62
    /// Lives on the model rather than here, so the hardware note keys and
    /// these buttons can't end up an octave apart; see `NoteKeys`.
    private var octave: Int { studio.octave }

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
            .frame(height: layout.keyboardHeight)
            // On an iPad the keys stop widening partway across the window and
            // centre; eight white keys spread over the full width are wider
            // than a hand and stop looking like an instrument.
            .frame(maxWidth: layout.keyboardMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                studio.shiftOctave(-1)
            } label: {
                Image(systemName: "chevron.left").chipFont(13)
            }
            .buttonStyle(PadStyle())
            .disabled(octave <= Studio.octaveRange.lowerBound)
            .accessibilityLabel("Octave down")

            Text("OCT \(octave - 1)")
                .chipFont(12)
                .foregroundStyle(Theme.dim)
                .frame(width: octaveWidth)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Octave")
                .accessibilityValue("\(octave - 1)")

            Button {
                studio.shiftOctave(1)
            } label: {
                Image(systemName: "chevron.right").chipFont(13)
            }
            .buttonStyle(PadStyle())
            .disabled(octave >= Studio.octaveRange.upperBound)
            .accessibilityLabel("Octave up")

            Spacer()

            // Which track a tap lands on matters more now that a song can hold
            // several of the same kind, so the target is named here.
            VStack(spacing: 1) {
                Text(NoteName.label(studio.selectedNote))
                    .chipFont(15, weight: .bold)
                    .foregroundStyle(Theme.color(for: studio.selectedKind))
                // The full label: this slot is flexible, and it's the readout
                // that says where a tap is about to land.
                //
                // Except while OFF is armed, when the line above already reads
                // "OFF" in the track's colour and the track name is the least
                // useful thing on screen. A tester's "I don't understand what
                // the off button does" had nowhere to be answered — the only
                // prose about it in the app is buried in the sound editor — and
                // borrowing this line costs no height, so the keyboard can't
                // jump and the grid doesn't lose a row to it.
                Text(studio.noteOffArmed
                     ? "cuts a held note"
                     : studio.song.fullLabel(for: studio.selectedTrack))
                    .chipFont(9)
                    .lineLimit(1)
                    .foregroundStyle(Theme.dim)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            // Writes a note-off into the grid instead of a pitch, for cutting
            // sustained notes on a channel that holds. Tapping it again puts
            // the previous pitch back, so it can be undone where it was armed
            // rather than by hunting for a key on the keyboard below.
            let armed = studio.noteOffArmed
            Button {
                studio.toggleNoteOff()
            } label: {
                Text("OFF").chipFont(12)
            }
            .buttonStyle(PadStyle(active: armed))
            .accessibilityLabel("Note off")
            .accessibilityAddTraits(armed ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(armed ? "Disarms, back to the note you had" : "Writes a note off")
        }
    }

    private func key(midi: Int, black: Bool) -> some View {
        let note = Int8(clamping: midi)
        let selected = studio.selectedNote == note
        let accent = Theme.color(for: studio.selectedKind)

        return RoundedRectangle(cornerRadius: Theme.cellRadius)
            .fill(selected ? accent : (black ? Color(white: 0.13) : Color(white: 0.88)))
            .overlay(alignment: .bottom) {
                if !black {
                    Text(NoteName.label(note))
                        .chipFont(layout.keyLabelSize)
                        // 0.45 over an 0.88 key cap only reaches 3.2:1 at 9pt.
                        .foregroundStyle(selected ? Theme.onLight.opacity(0.7) : Theme.onLight.opacity(0.62))
                        .padding(.bottom, 5)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cellRadius)
                    .stroke(Color.black.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
            // A key that doesn't light up under a pointer reads as a picture
            // of a keyboard rather than one.
            .hoverEffect(.lift)
            .onTapGesture {
                studio.selectedNote = note
                studio.audition(note)
            }
            .accessibilityLabel("Note \(NoteName.label(note))")
            // A shape with a tap gesture exposes as plain text/container;
            // VoiceOver needs the trait to announce the key as tappable.
            .accessibilityAddTraits(.isButton)
    }
}

/// Small dark control button used across the transport and keyboard rows.
struct PadStyle: ButtonStyle {
    var active: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? Theme.onLight : Theme.text)
            .padding(.horizontal, 14)
            // Meets the 44pt minimum touch target on its own.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
            .background(
                RoundedRectangle(cornerRadius: Theme.innerRadius)
                    .fill(active ? Theme.text : Theme.panelHigh)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
