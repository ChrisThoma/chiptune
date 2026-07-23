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
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.text)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
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
                    studio.saveNow()
                    showingSongs = true
                } label: {
                    Label("Songs…", systemImage: "music.note.list")
                }
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
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.text)
                    .frame(width: 40, height: 40)
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
            Button {
                studio.togglePlay()
            } label: {
                Image(systemName: studio.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.black)
                    .frame(width: 50, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(studio.isPlaying ? Color(red: 1, green: 0.4, blue: 0.45) : Color(red: 0.4, green: 0.95, blue: 0.6))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(studio.isPlaying ? "Stop" : "Play")

            // The value is a button as well as a readout — nudging from 120 to
            // 174 four BPM at a time is nobody's idea of a good afternoon.
            ChipStepper(label: "BPM",
                        value: Int(studio.song.tempo),
                        onChange: { studio.setTempo(studio.song.tempo + Double($0) * 4) },
                        onTapValue: {
                            tempoText = String(Int(studio.song.tempo))
                            editingTempo = true
                        })

            modeToggle

            Button {
                showingArrangement = true
            } label: {
                Image(systemName: "list.number")
                    .chipFont(14)
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 46)
                    .contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Arrangement")
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
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
    }

    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .chipFont(11, weight: on ? .bold : .semibold)
                .foregroundStyle(on ? Color.black : Theme.dim)
                .frame(width: 48, height: 42)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(on ? Theme.text : Color.clear)
                        .padding(2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The patterns strip: pick which block the grid is editing, and set its length.
struct PatternBar: View {
    @Bindable var studio: Studio
    @State private var renaming: Int?
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(studio.song.patterns.enumerated()), id: \.element.id) { index, pattern in
                        chip(index: index, pattern: pattern)
                    }
                    if studio.song.canAddPattern {
                        Button {
                            studio.addPattern()
                        } label: {
                            Image(systemName: "plus")
                                .chipFont(13)
                                .foregroundStyle(Theme.text)
                                .frame(width: 38, height: 40)
                                .contentShape(Rectangle())
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add pattern")
                    }
                }
                .padding(.horizontal, 2)
            }

            ChipStepper(label: "STEPS",
                        value: studio.patternLength,
                        onChange: { studio.setPatternLength(studio.patternLength + $0 * 4) })
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

    private func chip(index: Int, pattern: Pattern) -> some View {
        let selected = studio.selectedPattern == index
        let playing = studio.isPlaying && studio.playingPattern == index

        return Button {
            studio.selectPattern(index)
        } label: {
            HStack(spacing: 4) {
                if playing {
                    Circle()
                        .fill(Color(red: 0.4, green: 0.95, blue: 0.6))
                        .frame(width: 5, height: 5)
                }
                Text(pattern.name)
                    .chipFont(13, weight: selected ? .bold : .semibold)
                    .foregroundStyle(selected ? Color.black : (pattern.isEmpty ? Theme.dim : Theme.text))
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 40, minHeight: 40)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Theme.text : Theme.panel)
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
struct ChipStepper: View {
    let label: String
    let value: Int
    let onChange: (Int) -> Void
    var onTapValue: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button { onChange(-1) } label: {
                Image(systemName: "minus").chipFont(13)
                    .frame(width: 38, height: 46)
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
                    .frame(width: 38, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Increase \(label)")
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
    }

    private var readout: some View {
        VStack(spacing: 0) {
            Text("\(value)").chipFont(15, weight: .bold).foregroundStyle(Theme.text)
            Text(label).chipFont(8).foregroundStyle(Theme.dim)
        }
        .frame(minWidth: 38)
        .frame(height: 46)
        .contentShape(Rectangle())
    }
}

/// UIActivityViewController wrapper for sharing the exported WAV.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
