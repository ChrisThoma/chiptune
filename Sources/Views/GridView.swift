import SwiftUI

/// The step grid: one column per track, one row per step.
///
/// A song can hold up to `Chip.maxTracks` tracks, so the columns keep a usable
/// tap width and the whole grid scrolls sideways once they stop fitting.
struct GridView: View {
    @Bindable var studio: Studio
    /// Row height, gutter and column floor all grow on iPad; see `ChipLayout`.
    @Environment(\.chipLayout) private var layout

    private var rowHeight: CGFloat { layout.gridRowHeight }
    private var gutterWidth: CGFloat { layout.gridGutterWidth }
    private let addColumnWidth: CGFloat = ChipLayout.addColumnWidth

    /// Reorder mode, entered by a long press on a track header. Local to the
    /// grid: nothing outside it cares, and switching songs ends it.
    @State private var reordering = false
    /// The header under the finger while a reorder drag is live.
    @State private var drag: HeaderDrag?

    private struct HeaderDrag: Equatable {
        var id: UUID
        var source: Int
        var translation: CGFloat
        /// The column the drag has reached. Stored rather than derived so a
        /// change of it, and only that, animates the neighbors aside.
        var destination: Int
    }

    /// Header and cell columns sit 2 pt apart, so one column over is this far.
    private func columnStep(_ columnWidth: CGFloat) -> CGFloat { columnWidth + 2 }

    var body: some View {
        GeometryReader { geo in
            let columnWidth = columnWidth(forAvailable: geo.size.width)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        header(columnWidth: columnWidth)
                        steps(columnWidth: columnWidth)
                    }
                }
                // A new track lands selected at the trailing edge, past where
                // the row was clipped — without this the column (and the "+"
                // beside it) is off screen with nothing hinting that the
                // header scrolls.
                .onChange(of: studio.song.tracks.count) { old, new in
                    if !studio.song.canReorderTracks { endReordering() }
                    guard new > old else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(GridView.trailingEdgeID, anchor: .trailing)
                    }
                }
            }
        }
        .background(Theme.background)
        .overlay(alignment: .bottom) {
            if reordering { reorderBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        // A different song has different tracks.
        .onChange(of: studio.song.id) { _, _ in endReordering() }
    }

    private func beginReordering() {
        guard studio.song.canReorderTracks, !reordering else { return }
        Haptics.reorderBegan()
        withAnimation(.snappy(duration: 0.25)) { reordering = true }
    }

    private func endReordering() {
        guard reordering else { return }
        withAnimation(.snappy(duration: 0.25)) {
            reordering = false
            drag = nil
        }
    }

    /// Says what the mode is for and how to leave it. Pinned to the bottom of
    /// the grid rather than scrolled with the header row, so Done is still on
    /// screen with eight tracks scrolled sideways.
    private var reorderBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.and.right")
                .symbolFont(14)
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)
            Text("Drag a track to move it")
                .font(.subheadline)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Button {
                endReordering()
            } label: {
                Text("Done")
                    .chipFont(14)
                    .foregroundStyle(Theme.onLight)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Theme.text))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.trayRadius)
                .fill(Theme.panelHigh)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
    }

    /// Scroll target for the header row's trailing edge.
    static let trailingEdgeID = "gridTrailingEdge"

    /// Tracks share the width evenly while they fit; past that they take the
    /// minimum and the row overflows into the horizontal scroll.
    private func columnWidth(forAvailable width: CGFloat) -> CGFloat {
        layout.gridColumnWidth(available: width, tracks: studio.song.tracks.count,
                                canAddTrack: studio.song.canAddTrack)
    }

    private func header(columnWidth: CGFloat) -> some View {
        HStack(spacing: 2) {
            // Height-constrained so it doesn't stretch the header row.
            Color.clear.frame(width: gutterWidth, height: 1)
            ForEach(Array(studio.song.tracks.enumerated()), id: \.element.id) { index, track in
                let lifted = drag?.id == track.id
                TrackHeader(studio: studio, index: index, reordering: reordering, lifted: lifted,
                            move: { destination in move(index, to: destination) })
                    .frame(width: columnWidth)
                    .offset(x: columnOffset(index: index, id: track.id, columnWidth: columnWidth))
                    .zIndex(lifted ? 1 : 0)
                    // Simultaneous, so the name and mute buttons inside keep
                    // their taps; a short press never reaches the duration.
                    // Masked off in the mode, where it has nothing to start.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45)
                            .onEnded { _ in beginReordering() },
                        including: reordering ? .subviews : .all)
                    .gesture(reorderDrag(index: index, id: track.id, columnWidth: columnWidth),
                             including: reordering ? .all : .subviews)
            }
            if studio.song.canAddTrack {
                addTrackButton.frame(width: addColumnWidth)
                    // Kept in place rather than removed, so the columns don't
                    // resize under a drag; just out of play until Done.
                    .disabled(reordering)
                    .opacity(reordering ? 0.3 : 1)
            }
        }
        .id(GridView.trailingEdgeID)
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
                .frame(height: layout.trackHeaderHeight)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Theme.panelRadius)
                        .fill(Theme.panel)
                )
        }
        .hoverEffect(.highlight)
        .accessibilityLabel("Add track")
    }

    private func steps(columnWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(0..<studio.patternLength, id: \.self) { step in
                        row(step: step, columnWidth: columnWidth)
                            .id(step)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: studio.playhead) { _, step in
                guard showsPlayhead, studio.patternLength > 16 else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(step, anchor: .center)
                }
            }
            // A pattern switch (yours, or the arrangement's) should put you at
            // the top of the new block rather than wherever you last scrolled.
            .onChange(of: studio.selectedPattern) { _, _ in
                proxy.scrollTo(0, anchor: .top)
            }
            // An arrow key that walks the cursor off the bottom of the visible
            // rows has to bring the grid with it. Yields to the playhead while
            // that's running rather than the two fighting over the offset.
            .onChange(of: studio.selectedStep) { _, step in
                guard studio.hardwareKeyboardInUse, !showsPlayhead else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(step, anchor: .center)
                }
            }
        }
        // In reorder mode the notes are along for the ride, not for editing:
        // dimmed, and a tap anywhere on them means "done" rather than writing
        // a note the user can't see they were about to write.
        .opacity(reordering ? 0.4 : 1)
        .overlay {
            if reordering {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { endReordering() }
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Reordering

    /// Where column `index` draws while a drag is live: the dragged one under
    /// the finger, the ones it has passed slid over to make room.
    private func columnOffset(index: Int, id: UUID, columnWidth: CGFloat) -> CGFloat {
        guard let drag else { return 0 }
        if drag.id == id { return drag.translation }
        return TrackReorder.offset(for: index, dragging: drag.source, to: drag.destination,
                                   columnStep: columnStep(columnWidth))
    }

    /// Global space: the header moves by `.offset` as it's dragged, so a
    /// local translation would chase its own tail.
    private func reorderDrag(index: Int, id: UUID, columnWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                let destination = TrackReorder.destination(
                    from: index, translation: value.translation.width,
                    columnStep: columnStep(columnWidth), count: studio.song.tracks.count)
                let next = HeaderDrag(id: id, source: index,
                                      translation: value.translation.width,
                                      destination: destination)
                if let drag, drag.destination != destination {
                    Haptics.reorderStep()
                    withAnimation(.snappy(duration: 0.2)) { self.drag = next }
                } else {
                    drag = next
                }
            }
            .onEnded { _ in
                guard let drag else { return }
                move(drag.source, to: drag.destination)
            }
    }

    /// One `moveTrack` per drop. Animated together with clearing the drag, so
    /// the dropped column settles from under the finger into its new slot
    /// instead of jumping there.
    private func move(_ source: Int, to destination: Int) {
        withAnimation(.snappy(duration: 0.25)) {
            studio.moveTrack(from: source, to: destination)
            drag = nil
        }
    }

    /// In SONG mode the sequencer can be somewhere else entirely, so the
    /// highlight only runs when the pattern on screen is the one sounding.
    private var showsPlayhead: Bool {
        studio.isPlaying && studio.playingPattern == studio.selectedPattern
    }

    private func row(step: Int, columnWidth: CGFloat) -> some View {
        HStack(spacing: 2) {
            Text(String(format: "%02d", step))
                .chipFont(11)
                .foregroundStyle(step % 4 == 0 ? Theme.text : Theme.dim)
                .frame(width: gutterWidth)

            ForEach(Array(studio.song.tracks.enumerated()), id: \.element.id) { index, track in
                GridCell(studio: studio, track: index, step: step)
                    .frame(width: columnWidth)
                    // The notes travel with the header, so it's plain the
                    // whole part is moving and not just its name.
                    .offset(x: columnOffset(index: index, id: track.id, columnWidth: columnWidth))
                    .zIndex(drag?.id == track.id ? 1 : 0)
            }
            if studio.song.canAddTrack {
                Color.clear.frame(width: addColumnWidth, height: 1)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: rowHeight)
        .background(
            showsPlayhead && studio.playhead == step
                ? Color.white.opacity(0.14)
                : Color.clear
        )
    }

}

/// One step on one track.
///
/// Not a `Button`, which it was until a beta tester pointed out that the only
/// way to hear what was in a cell was to tap it — and tapping it wrote over it.
/// A long press previews instead, and a `Button` can't carry one: the two fire
/// together, so telling them apart needs a did-long-press flag checked and
/// cleared in the button's own action. A shape with both gestures on it
/// arbitrates properly — the long press cancels the tap rather than racing it —
/// at the cost of putting back the press feedback and the button trait that
/// `.buttonStyle(.plain)` was giving away for free.
private struct GridCell: View {
    @Bindable var studio: Studio
    let track: Int
    let step: Int

    @State private var pressed = false

    var body: some View {
        // `track` is an index captured when this cell's `ForEach` last ran.
        // If `studio.song.tracks` shrinks — a song switch swaps the whole
        // array while an old cell is still finishing a removal-transition
        // frame — that capture can outlive the array it indexed into, so
        // every read here has to tolerate a now out-of-range index.
        guard let trackModel = studio.song.tracks[safe: track] else {
            return AnyView(Color.clear)
        }
        let note = studio.note(track: track, step: step)
        let filled = note != Chip.emptyNote
        let isOff = note == Chip.noteOff
        let muted = trackModel.muted
        // Only once a hardware key has been pressed. On a touch-only session
        // there's nothing moving it, and a ringed cell would read as a
        // selection the user didn't make.
        let atCursor = studio.hardwareKeyboardInUse
            && studio.selectedTrack == track
            && studio.selectedStep == step

        // Every ternary lands in an explicitly typed `let`: as one chained
        // expression this body blows Xcode 16.4's type-check budget (CI's
        // compiler), which 26.5 only happens to tolerate.
        let title: String = isOff ? "REST" : (filled ? NoteName.label(note) : "·")
        // Muting fades the fill to 35% over near-black, so the dark
        // note text has to flip light or it scores under 2.6:1.
        let titleColor: Color = filled
            ? (muted ? Theme.text.opacity(0.85) : Theme.onLight.opacity(0.85))
            : Theme.dim.opacity(0.6)
        let accent: Color = Theme.color(for: trackModel.kind)
        let fill: Color = filled
            ? (isOff ? Theme.dim : accent).opacity(muted ? 0.35 : 1.0)
            : Theme.rowTint(step: step)
        // White rather than the channel accent: the cursor has to
        // stand out against a cell already filled with that accent.
        let cursorRing: Color = atCursor ? Theme.text : Color.clear

        return AnyView(Text(title)
            .chipFont(filled ? 12 : 14)
            .foregroundStyle(titleColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cellRadius)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cellRadius)
                    .stroke(Theme.grid.opacity(0.6), lineWidth: filled ? 0 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cellRadius)
                    .stroke(cursorRing, lineWidth: 2)
            )
            // What `.buttonStyle(.plain)` used to do. Without it a tap has no
            // touch-down feedback at all and the grid reads as a picture.
            .opacity(pressed ? 0.6 : 1)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
            // Tap first, long press second. In this order the long press
            // cancels the tap rather than both firing on release.
            .onTapGesture {
                Haptics.gridCell()
                studio.placeCursor(track: track, step: step)
                studio.toggleCell(track: track, step: step)
            }
            .onLongPressGesture {
                studio.previewCell(track: track, step: step)
            } onPressingChanged: { pressing in
                pressed = pressing
            }
            .accessibilityLabel("\(studio.song.fullLabel(for: track)) step \(step + 1)")
            .accessibilityValue(filled ? NoteName.label(note) : "Empty")
            // A shape with gestures on it exposes as plain text, and there is
            // no reaching a long press with VoiceOver — so the trait and the
            // preview both have to be spelled out.
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Preview") {
                studio.previewCell(track: track, step: step)
            })
    }
}

/// Track name and mute toggle.
///
/// These were three overlapping tap targets in one thumb-width box, which made
/// them almost impossible to hit. Now there are exactly two, stacked and
/// full-width: the name selects the track (and reopens its sound editor once
/// selected), and the speaker row below it mutes.
///
/// A long press (handled by `GridView`, which owns the mode) switches every
/// header into reorder mode: the name stops being a button so a drag anywhere
/// on the header picks the track up, and the mute row becomes a grip between
/// two arrows for moving one column at a time.
private struct TrackHeader: View {
    @Bindable var studio: Studio
    let index: Int
    var reordering = false
    /// Under the finger in a reorder drag.
    var lifted = false
    /// Moves this track to the given column.
    var move: (Int) -> Void = { _ in }
    @Environment(\.chipLayout) private var layout
    @State private var showingEditor = false

    /// The two stacked buttons share the header box, keeping the name row a
    /// little taller than the mute row at any size.
    private var nameHeight: CGFloat { (layout.trackHeaderHeight - 14) * 0.53 }
    private var muteHeight: CGFloat { (layout.trackHeaderHeight - 14) * 0.47 }

    var body: some View {
        let track = studio.song.tracks[safe: index]
        let accent = Theme.color(for: track?.kind ?? .pulse1)
        let muted = track?.muted ?? false
        let selected = studio.selectedTrack == index
        let name = studio.song.fullLabel(for: index)

        VStack(spacing: 4) {
            Button {
                // The long press that starts reorder mode lets go on this
                // button, and a plain `Button` fires on release however long
                // it was held. By then the mode is on, so this is where that
                // stray tap is dropped rather than selecting or opening.
                guard !reordering else { return }
                // Every tap demos the sound, whichever of the two things below
                // it also does. A tester tapped along this row expecting to
                // hear what each channel sounded like and got silence.
                studio.previewTrack(index)
                // Already selected? The second tap opens the sound editor —
                // unless the editor is docked in the side column, where it's
                // already on screen showing this track and there's nothing for
                // a second tap to open.
                if selected && !layout.docksInstrumentEditor {
                    showingEditor = true
                } else {
                    studio.selectedTrack = index
                }
            } label: {
                HStack(spacing: 4) {
                    // A column is ~7 characters wide on a four-track phone, so
                    // a name that doesn't fit truncates rather than shrinking
                    // the header out of step with its neighbors.
                    Text(studio.song.label(for: index))
                        .chipFont(13)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if selected && !reordering {
                        Image(systemName: "slider.horizontal.3").symbolFont(9)
                    }
                }
                .foregroundStyle(muted ? Theme.dim : accent)
                .frame(maxWidth: .infinity)
                .frame(height: nameHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
            // Out of the way in the mode, so a drag that starts on the name
            // reaches the header's drag gesture instead of a dead button.
            .allowsHitTesting(!reordering)
            .accessibilityLabel(name)
            .accessibilityHint(selected && !layout.docksInstrumentEditor
                               ? "Opens sound settings"
                               : "Selects this track")

            if reordering {
                reorderRow
            } else {
                muteButton(muted: muted, name: name)
            }
        }
        .padding(5)
        // A rotation into the side arrangement docks the editor; leaving the
        // popover up as well would show the same controls twice.
        .onChange(of: layout.docksInstrumentEditor) { _, docks in
            if docks { showingEditor = false }
        }
        // The screenshot shoot opens this from a launch argument. Driven from
        // here rather than from `ContentView` so the shot shows the real
        // presentation for the window it was taken in; see `ScreenshotMode`.
        .task {
            guard index == 0, ScreenshotMode.requested == .instrument,
                  !layout.docksInstrumentEditor else { return }
            showingEditor = true
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.panelRadius)
                .fill(selected ? accent.opacity(0.18) : Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius)
                .stroke(selected ? accent : Color.clear, lineWidth: 1.5)
        )
        // The mode's outline: every header gets one, in its own color, so the
        // whole row reads as picked up rather than just the selected track.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius)
                .strokeBorder(accent.opacity(reordering && !selected ? 0.7 : 0),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        )
        // The whole box is the drag target in the mode, gaps included.
        .contentShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
        .scaleEffect(lifted ? 1.06 : 1)
        .shadow(color: .black.opacity(lifted ? 0.6 : 0), radius: 10, y: 4)
        // Duplicate and delete used to sit in a long-press menu here; they
        // live in the sound settings now, and the long press reorders. The
        // move is offered to VoiceOver directly, since a drag isn't reachable.
        .accessibilityActions {
            if index > 0 {
                Button("Move left") { move(index - 1) }
            }
            if index < studio.song.tracks.count - 1 {
                Button("Move right") { move(index + 1) }
            }
        }
        // A popover at regular width, anchored here so the controls sit beside
        // the track they change and the grid stays visible behind them. On a
        // phone this adapts back to the sheet it has always been.
        .popover(isPresented: $showingEditor, attachmentAnchor: .rect(.bounds),
                 arrowEdge: .top) {
            InstrumentEditor(studio: studio, index: index,
                             popover: layout.presentsInstrumentAsPopover)
                .presentationCompactAdaptation(.sheet)
        }
    }

    private func muteButton(muted: Bool, name: String) -> some View {
        Button {
            studio.checkpoint()
            studio.song.tracks[index].muted.toggle()
            studio.pushInstrument(index)
        } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .symbolFont(13)
                .foregroundStyle(muted ? Theme.dim : Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: muteHeight)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Theme.cellRadius)
                        .fill(muted ? Color.black.opacity(0.35) : Theme.panelHigh)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // A label that flips between Mute/Unmute isn't announced after
        // activation; a value change is, so the label stays put and the
        // state moves into a toggle value instead.
        .accessibilityLabel("Mute \(name)")
        .accessibilityValue(muted ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    /// Stands in for the mute row in reorder mode. The grip says "drag me";
    /// the arrows are there for a one-column nudge, and for anyone who finds
    /// a sideways drag across a scrolling grid awkward.
    private var reorderRow: some View {
        HStack(spacing: 0) {
            nudge("chevron.left", to: index - 1, enabled: index > 0)
            Image(systemName: "line.3.horizontal")
                .symbolFont(13, weight: .semibold)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            nudge("chevron.right", to: index + 1,
                  enabled: index < studio.song.tracks.count - 1)
        }
        .frame(height: muteHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.cellRadius)
                .fill(Theme.panelHigh)
        )
    }

    private func nudge(_ symbol: String, to destination: Int, enabled: Bool) -> some View {
        Button {
            move(destination)
        } label: {
            Image(systemName: symbol)
                .symbolFont(12, weight: .bold)
                .foregroundStyle(enabled ? Theme.text : Theme.dim.opacity(0.4))
                .frame(width: 26)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(!enabled)
        // The header already offers these as actions; two copies of each
        // would only lengthen the swipe through the row.
        .accessibilityHidden(true)
    }
}
