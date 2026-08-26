import SwiftUI

/// Where the pattern strip is scrolled to, and how much of it there is.
private struct StripMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
}

private struct StripMetricsKey: PreferenceKey {
    static let defaultValue = StripMetrics()
    static func reduce(value: inout StripMetrics, nextValue: () -> StripMetrics) {
        value = nextValue()
    }
}

private struct StripViewportKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The patterns strip: pick which block the grid is editing, and set its length.
struct PatternBar: View {
    @Bindable var studio: Studio
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var trayHeight = Theme.trayHeight
    @State private var renaming: Int?
    @State private var renameText = ""
    /// Pattern indices queued behind a confirmation. Both erase work with no
    /// way back, so neither happens straight off a context-menu tap.
    @State private var clearing: Int?
    @State private var deleting: Int?
    @State private var strip = StripMetrics()
    @State private var stripViewport: CGFloat = 0

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
        .alert("Rename pattern", isPresented: Binding(isPresenting: $renaming)) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let index = renaming { studio.renamePattern(at: index, to: renameText) }
                renaming = nil
            }
            // Greyed out rather than silently ignored when the name is empty
            // or already another pattern's.
            .disabled(renaming.map { studio.acceptablePatternName(renameText, for: $0) == nil } ?? true)
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
                chip(index: index, pattern: pattern)
            }
        }
        .padding(.horizontal, 4)
    }

    /// The overflow case. Fades whichever edge still has chips behind it, so a
    /// half-cut chip isn't the only clue that the strip scrolls.
    private var scrollingChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            chips
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: StripMetricsKey.self,
                            value: StripMetrics(offset: geo.frame(in: .named("patternStrip")).minX,
                                                content: geo.size.width))
                    }
                )
        }
        .coordinateSpace(name: "patternStrip")
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: StripViewportKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(StripMetricsKey.self) { strip = $0 }
        .onPreferenceChange(StripViewportKey.self) { stripViewport = $0 }
        .mask(edgeFade)
    }

    private var edgeFade: some View {
        // A point of slack keeps the fade from flickering on at the extremes.
        let leading = strip.offset < -1
        let trailing = strip.content + strip.offset > stripViewport + 1
        return LinearGradient(
            stops: [
                .init(color: leading ? .clear : .black, location: 0),
                .init(color: .black, location: leading ? 0.07 : 0),
                .init(color: .black, location: trailing ? 0.93 : 1),
                .init(color: trailing ? .clear : .black, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing)
    }

    private var addButton: some View {
        Button {
            studio.addPattern()
        } label: {
            Image(systemName: "plus")
                .chipFont(13)
                .foregroundStyle(Theme.text)
                // 36pt of fill, but the whole tray height stays tappable.
                .frame(width: 42, height: trayHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            .frame(minWidth: 40)
            .frame(height: trayHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.innerRadius)
                    .fill(selected ? Theme.text : Theme.panelHigh)
                    .padding(.vertical, 4)
            )
        }
        .buttonStyle(.plain)
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
