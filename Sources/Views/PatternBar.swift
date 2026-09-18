import SwiftUI

/// The patterns strip: pick which block the grid is editing, and set its length.
struct PatternBar: View {
    @Bindable var studio: Studio
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.chipLayout) private var layout
    // See TransportBar's `trayHeight`: the ratio scales for Dynamic Type,
    // the layout supplies the phone/pad base.
    @ScaledMetric(relativeTo: .body) private var trayHeightScale: CGFloat = 1
    private var trayHeight: CGFloat { layout.trayHeight * trayHeightScale }
    @State private var renaming: Int?
    @State private var renameText = ""
    /// Pattern indices queued behind a confirmation. Both erase work with no
    /// way back, so neither happens straight off a context-menu tap.
    @State private var clearing: Int?
    @State private var deleting: Int?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    patternTray.frame(maxWidth: .infinity, alignment: .leading)
                    steps
                }
            } else {
                HStack(spacing: 8) {
                    patternTray
                    Spacer(minLength: 12)
                    steps
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        // A sheet rather than an alert: a `TextField` inside `.alert` doesn't
        // reliably send every keystroke back through its binding, so the cap
        // below could only ever be applied on commit — you typed
        // "ChorusBridge99", saw all of it, and got "Chorus". An ordinary
        // TextField in a Form does update live, so the field can show the
        // truncation as it happens.
        .sheet(isPresented: Binding(isPresenting: $renaming)) {
            PatternRenameSheet(studio: studio, index: renaming, text: $renameText) {
                renaming = nil
            }
        }
        .confirmationDialog("Clear pattern \(name(clearing))?",
                            isPresented: Binding(isPresenting: $clearing),
                            titleVisibility: .visible) {
            Button("Clear pattern", role: .destructive) {
                // Clears in place — jumping the editor to the cleared pattern
                // reads as "my work just vanished" when it's still in the one
                // you were editing.
                if let index = clearing { studio.clearPattern(at: index) }
                clearing = nil
            }
            Button("Cancel", role: .cancel) { clearing = nil }
        } message: {
            Text(ConfirmationCopy.clearPattern)
        }
        .confirmationDialog("Delete pattern \(name(deleting))?",
                            isPresented: Binding(isPresenting: $deleting),
                            titleVisibility: .visible) {
            Button("Delete pattern", role: .destructive) {
                if let index = deleting { studio.removePattern(at: index) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            // No "can't be undone" here: removePattern checkpoints, and a
            // false warning teaches people to distrust the real ones.
            Text("It's removed from the arrangement too. Undo brings it back.")
        }
    }

    private var patternTray: some View {
            // The tray sits *inside* here rather than around the whole row, so
            // it hugs the chips and grows with them instead of stretching an
            // empty panel across the row. `+` is pinned outside the scrolling
            // part so it can't be scrolled out of reach.
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    chips
                    scrollingChips
                }

                if studio.song.canAddPattern {
                    TrayDivider()
                    addButton
                }
            }
            .chipTray()
    }

    private var steps: some View {
            // Deliberately a separate tray: STEPS belongs to the pattern, not to
            // the strip of chips beside it, and the gap is what says so.
            ChipStepper(label: "STEPS",
                        value: studio.patternLength,
                        range: Chip.patternLengthRange,
                        onChange: { studio.setPatternLength(studio.patternLength + $0 * 4) })
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                .chipTray()
    }

    private func name(_ index: Int?) -> String {
        index.flatMap { studio.song.patterns[safe: $0]?.name } ?? ""
    }

    private var chips: some View {
        HStack(spacing: 4) {
            ForEach(Array(studio.song.patterns.enumerated()), id: \.element.id) { index, pattern in
                // Spelled out rather than left to `ForEach`'s own identity, so
                // `scrollTo(pattern.id)` has a target it can't lose.
                chip(index: index, pattern: pattern)
                    .id(pattern.id)
            }
        }
        .padding(.horizontal, 4)
    }

    /// The overflow case. `ViewThatFits` only reaches this branch when the plain
    /// `chips` row is too wide for the tray, so by the time this renders at all
    /// the strip is *known* to run past both sides once you're scrolling. That's
    /// the whole signal the fades need, so they're painted flat rather than
    /// tracked: measuring live scroll offset from inside a `ViewThatFits`
    /// candidate never worked here — the GeometryReader/PreferenceKey pass runs
    /// against the sizing probe rather than the instance on screen, so the
    /// values stayed frozen at zero and the cue was stuck on or stuck off. A
    /// fade that's a shade early at the very ends beats no cue at all.
    private var scrollingChips: some View {
        // The reader lives *inside* the `ViewThatFits` candidate rather than
        // around the whole tray: only this branch owns a ScrollView, and the
        // sizing probe that renders the other candidate must not be handed a
        // proxy for a scroll area that isn't on screen.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                chips
            }
            // Adding a pattern selects it, and the new chip lands past the
            // trailing edge behind the pinned "+" — so with nothing else
            // happening you tap "+" and no chip looks selected at all. Every
            // selection change is followed, not just this one: the arrangement
            // and the hardware keyboard move it too, and a delete shifts it
            // onto a different pattern.
            .onChange(of: selectedPatternID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            // Coming back to an overflowing strip — first layout, or a rotation
            // that pushed it past the width — should show the chip you're on.
            .onAppear {
                guard let id = selectedPatternID else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
        // Painted *over* the strip rather than masked out of it. A `.mask` here
        // has to survive the ScrollView's own compositing, and it also can't be
        // seen at all unless the alpha it punches reveals something — the tray
        // panel underneath is the thing the chips should melt into, so draw
        // that colour directly and skip the round trip.
        .overlay(alignment: .leading) { fade(.leading) }
        .overlay(alignment: .trailing) { fade(.trailing) }
    }

    /// The scroll target, keyed by identity rather than index: deleting a
    /// pattern can leave `selectedPattern` on the same index while the chip
    /// under it is a different one.
    private var selectedPatternID: UUID? {
        studio.song.patterns[safe: studio.selectedPattern]?.id
    }

    /// How wide each fade is. Roughly a chip's corner plus a little, so it reads
    /// as "there's more behind this" and not as a smudge.
    private static let fadeWidth: CGFloat = 20

    private func fade(_ edge: HorizontalEdge) -> some View {
        LinearGradient(
            colors: edge == .leading
                ? [Theme.panel, Theme.panel.opacity(0)]
                : [Theme.panel.opacity(0), Theme.panel],
            startPoint: .leading,
            endPoint: .trailing)
            .frame(width: Self.fadeWidth)
            // Decoration only — a chip under the fade still has to be tappable.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var addButton: some View {
        Button {
            studio.addPattern()
        } label: {
            Image(systemName: "plus")
                .chipFont(13)
                .foregroundStyle(Theme.text)
                // 36pt of fill, but the whole tray height stays tappable.
                .frame(width: layout.patternAddWidth, height: trayHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("Add pattern")
    }

    private func chip(index: Int, pattern: Pattern) -> some View {
        let selected = studio.selectedPattern == index
        let playing = studio.isPlaying && studio.playingPattern == index

        return Button {
            studio.selectPattern(index)
        } label: {
            HStack(spacing: 4) {
                if playing {
                    // A selected chip fills with near-white, where the usual
                    // bright green scores 1.1:1 and vanishes.
                    Circle()
                        .fill(selected ? Theme.onLightGreen : Theme.accentGreen)
                        .frame(width: 5, height: 5)
                }
                Text(pattern.name)
                    .chipFont(13, weight: selected ? .bold : .semibold)
                    .foregroundStyle(selected ? Theme.onLight : (pattern.isEmpty ? Theme.dim : Theme.text))
            }
            .padding(.horizontal, 12)
            .frame(minWidth: layout.patternChipWidth)
            .frame(height: trayHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.innerRadius)
                    .fill(selected ? Theme.text : Theme.panelHigh)
                    .padding(.vertical, 4)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // Matches the chip's own corners so the glow doesn't spill past it.
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: Theme.innerRadius))
        .accessibilityLabel("Pattern \(pattern.name)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .contextMenu {
            Button {
                renameText = pattern.name
                renaming = index
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                studio.duplicatePattern(at: index)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(!studio.song.canAddPattern)
            Button(role: .destructive) {
                clearing = index
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            Button(role: .destructive) {
                deleting = index
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(studio.song.patterns.count <= 1)
        }
    }
}

/// Renaming one pattern. Chips live in a width-limited strip, so a name is
/// capped at six characters — the field enforces that as you type rather than
/// quietly cutting the name off when you tap Rename.
private struct PatternRenameSheet: View {
    @Bindable var studio: Studio
    /// The pattern being renamed, snapshotted when the sheet was raised.
    let index: Int?
    @Binding var text: String
    let dismiss: () -> Void
    @FocusState private var focused: Bool

    /// Matches `Studio.acceptablePatternName`, which is the one that actually
    /// decides what gets stored.
    private static let maxLength = 6

    private var accepted: String? {
        index.flatMap { studio.acceptablePatternName(text, for: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $text)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit(commit)
                        // Ordinary TextFields do fire this on every edit, which
                        // is the whole reason this isn't an alert any more.
                        .onChange(of: text) { _, newValue in
                            let capped = String(newValue.prefix(Self.maxLength))
                            if capped != newValue { text = capped }
                        }
                        .accessibilityLabel("Pattern name")
                } header: {
                    Text("Name")
                } footer: {
                    Text("Up to \(Self.maxLength) characters — \(text.count) of \(Self.maxLength) used.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Rename pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename", action: commit)
                        // Greyed out rather than silently ignored when the name
                        // is empty or already another pattern's.
                        .disabled(accepted == nil)
                }
            }
        }
        .compactSheetDetents(true)
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }

    private func commit() {
        guard let index, accepted != nil else { return }
        studio.renamePattern(at: index, to: text)
        dismiss()
    }
}
