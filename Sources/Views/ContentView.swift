import SwiftUI

struct ContentView: View {
    @State private var studio = Studio()
    @State private var showingSongs = false
    @State private var showingShare = false

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            TransportBar(studio: studio)
            GridView(studio: studio)
            KeyboardView(studio: studio)
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSongs) {
            SongListView(studio: studio)
        }
        .sheet(isPresented: $showingShare) {
            if let url = studio.exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            TextField("Song name", text: $studio.song.name)
                .chipFont(16, weight: .bold)
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)

            Menu {
                Button {
                    studio.save()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                Button {
                    showingSongs = true
                } label: {
                    Label("Open…", systemImage: "folder")
                }
                Button {
                    studio.newSong()
                } label: {
                    Label("New song", systemImage: "doc.badge.plus")
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
                    studio.clearAll()
                } label: {
                    Label("Clear all", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.text)
            }
            .accessibilityLabel("Song menu")
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

/// Play/stop, tempo and pattern length.
struct TransportBar: View {
    @Bindable var studio: Studio

    var body: some View {
        HStack(spacing: 12) {
            Button {
                studio.togglePlay()
            } label: {
                Image(systemName: studio.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.black)
                    .frame(width: 52, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(studio.isPlaying ? Color(red: 1, green: 0.4, blue: 0.45) : Color(red: 0.4, green: 0.95, blue: 0.6))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(studio.isPlaying ? "Stop" : "Play")

            stepper(label: "BPM",
                    value: Int(studio.song.tempo),
                    onChange: { delta in
                        studio.song.tempo = min(max(studio.song.tempo + Double(delta) * 4, 40), 300)
                        studio.pushTransport()
                    })

            stepper(label: "STEPS",
                    value: studio.song.length,
                    onChange: { delta in
                        studio.song.length = min(max(studio.song.length + delta * 4, 4), Chip.maxSteps)
                        studio.pushTransport()
                    })
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func stepper(label: String, value: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            Button { onChange(-1) } label: {
                Image(systemName: "minus").chipFont(13)
                    .frame(width: 44, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Decrease \(label)")

            VStack(spacing: 0) {
                Text("\(value)").chipFont(15, weight: .bold).foregroundStyle(Theme.text)
                Text(label).chipFont(8).foregroundStyle(Theme.dim)
            }
            .frame(minWidth: 36)
            // Not a control itself, so it must not swallow taps meant for +/-.
            .allowsHitTesting(false)

            Button { onChange(1) } label: {
                Image(systemName: "plus").chipFont(13)
                    .frame(width: 44, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Increase \(label)")
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
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
