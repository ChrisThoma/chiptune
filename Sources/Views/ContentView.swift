import SwiftUI

struct ContentView: View {
    @Bindable var studio: Studio
    @State private var showingSongs = false
    @State private var showingArrangement = false
    @State private var showingShare = false

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            TransportBar(studio: studio, showingArrangement: $showingArrangement)
            PatternBar(studio: studio)
            GridView(studio: studio)
            // The grid used to run straight into the keys; this is the breathing
            // room between the two.
            Rectangle()
                .fill(Theme.grid.opacity(0.5))
                .frame(height: 1)
                .padding(.top, 10)
                .padding(.horizontal, 14)
            KeyboardView(studio: studio)
                .padding(.top, 10)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSongs) {
            SongListView(studio: studio)
        }
        .sheet(isPresented: $showingArrangement) {
            ArrangementView(studio: studio)
        }
        .sheet(isPresented: $showingShare) {
            if let url = studio.exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            // Browsing saved songs used to be buried two levels into the •••
            // menu, which made it feel like the app had no library at all.
            Button {
                studio.saveNow()
                showingSongs = true
            } label: {
                Image(systemName: "music.note.list")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Songs")

            TextField("Song name", text: $studio.song.name)
                .chipFont(16, weight: .bold)
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)

            Menu {
                Button {
                    studio.newSong()
                } label: {
                    Label("New song", systemImage: "doc.badge.plus")
                }
                Button {
                    studio.duplicateSong()
                } label: {
                    Label("Duplicate song", systemImage: "plus.square.on.square")
                }
                Divider()
                Button {
                    studio.export()
                    // Only offer the share sheet once a file actually exists.
                    if studio.exportURL != nil { showingShare = true }
                } label: {
                    Label("Export WAV", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    studio.clearPattern()
                } label: {
                    Label("Clear pattern \(studio.pattern.name)", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Song menu")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

/// Play/stop, tempo, and the pattern/song mode switch.
struct TransportBar: View {
    @Bindable var studio: Studio
    @Binding var showingArrangement: Bool
    @State private var editingTempo = false
    @State private var tempoText = ""

    var body: some View {
        HStack(spacing: 8) {
            // The only saturated fill in the chrome, and the biggest target, so
            // the eye lands here first.
            Button {
                studio.togglePlay()
            } label: {
                Image(systemName: studio.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.onLight)
                    .frame(width: 56, height: Theme.trayHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.trayRadius)
                            .fill(studio.isPlaying ? Theme.accentRed : Theme.accentGreen)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(studio.isPlaying ? "Stop" : "Play")

            // What plays: the mode you're in and the arrangement behind it.
            HStack(spacing: 0) {
                modeToggle

                TrayDivider()

                Button {
                    showingArrangement = true
                } label: {
                    Text("ARR")
                        .chipFont(11, weight: .semibold)
                        .foregroundStyle(Theme.text)
                        .frame(width: 48, height: Theme.trayHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Arrangement")
            }
            .chipTray()

            Spacer(minLength: 12)

            // Trails the row so it lines up with STEPS below — the two steppers
            // read as a pair rather than as more transport buttons.
            //
            // The value is a button as well as a readout — nudging from 120 to
            // 174 four BPM at a time is nobody's idea of a good afternoon.
            ChipStepper(label: "BPM",
                        value: Int(studio.song.tempo),
                        onChange: { studio.setTempo(studio.song.tempo + Double($0) * 4) },
                        onTapValue: {
                            tempoText = String(Int(studio.song.tempo))
                            editingTempo = true
                        })
                .chipTray()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .alert("Tempo", isPresented: $editingTempo) {
            TextField("BPM", text: $tempoText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                if let bpm = Double(tempoText.trimmingCharacters(in: .whitespaces)) {
                    studio.setTempo(bpm)
                }
            }
        } message: {
            Text("40 to 300 BPM")
        }
    }

    /// PATT loops the pattern you're editing so you can work on it; SONG plays
    /// the arrangement from the top.
    private var modeToggle: some View {
        HStack(spacing: 0) {
            segment("PATT", on: !studio.songMode) { studio.setSongMode(false) }
            segment("SONG", on: studio.songMode) { studio.setSongMode(true) }
        }
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .chipFont(11, weight: on ? .bold : .semibold)
                .foregroundStyle(on ? Theme.onLight : Theme.dim)
                .frame(width: 52, height: Theme.trayHeight)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Theme.innerRadius)
                        .fill(on ? Theme.text : Color.clear)
                        .padding(4)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Where the pattern strip is scrolled to, and how much of it there is.
struct StripMetrics: Equatable {
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
    @State private var renaming: Int?
    @State private var renameText = ""
    @State private var strip = StripMetrics()
    @State private var stripViewport: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
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

            // Now that the chip tray hugs its contents, STEPS would drift left
            // with it; this keeps it pinned under BPM so the two steppers line
            // up as a column down the right edge.
            Spacer(minLength: 12)

            // Deliberately a separate tray: STEPS belongs to the pattern, not to
            // the strip of chips beside it, and the gap is what says so.
            ChipStepper(label: "STEPS",
                        value: studio.patternLength,
                        onChange: { studio.setPatternLength(studio.patternLength + $0 * 4) })
                .chipTray()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .alert("Rename pattern", isPresented: Binding(get: { renaming != nil },
                                                      set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let index = renaming { studio.renamePattern(at: index, to: renameText) }
                renaming = nil
            }
        }
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
                .frame(width: 42, height: Theme.trayHeight)
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
            .frame(height: Theme.trayHeight)
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
                studio.selectPattern(index)
                studio.clearPattern()
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            Button(role: .destructive) {
                studio.removePattern(at: index)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(studio.song.patterns.count <= 1)
        }
    }
}

/// −/value/+ control. The value is tappable when `onTapValue` is supplied.
///
/// Draws no background of its own so it can sit inside a shared `chipTray`
/// alongside other controls; standalone uses apply `.chipTray()` themselves.
struct ChipStepper: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void
    var onTapValue: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button { onChange(-1) } label: {
                Image(systemName: "minus").chipFont(13)
                    .frame(width: 38, height: Theme.trayHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Decrease \(label)")

            Group {
                if let onTapValue {
                    Button(action: onTapValue) { readout }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(label) \(value), edit")
                } else {
                    readout.allowsHitTesting(false)
                }
            }

            Button { onChange(1) } label: {
                Image(systemName: "plus").chipFont(13)
                    .frame(width: 38, height: Theme.trayHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Increase \(label)")
        }
    }

    private var readout: some View {
        VStack(spacing: 0) {
            Text("\(value)").chipFont(15, weight: .bold).foregroundStyle(Theme.text)
            Text(label).chipFont(8).foregroundStyle(Theme.dim)
        }
        .frame(minWidth: 38)
        .frame(height: Theme.trayHeight)
        .contentShape(Rectangle())
    }
}

/// UIActivityViewController wrapper for sharing the exported WAV.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // UIKit-presented, so it doesn't inherit the app's forced dark scheme
        // and would otherwise flash white on a light-mode device.
        controller.overrideUserInterfaceStyle = .dark
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
