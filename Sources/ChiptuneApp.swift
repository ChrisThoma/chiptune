import SwiftUI

@main
struct ChiptuneApp: App {
    /// True when this process is hosting a unit-test run. The tests build
    /// their own `Studio`s against throwaway stores, so the app's would only
    /// write real Documents underneath them — and building it is what killed
    /// the TSan job in CI: constructing the audio graph goes through
    /// CoreAudio initialisation, which has an internal RPC timeout that
    /// aborts the whole process when the sanitizer's slowdown blows through
    /// it, before any test has started. XCTest is dyld-inserted at launch,
    /// so the class check is valid this early.
    private static let isTestHost = NSClassFromString("XCTestCase") != nil
    @Environment(\.scenePhase) private var scenePhase
    /// Built after the first frame so the splash is on screen while the audio
    /// engine spins up and the last song is read back off disk.
    @State private var studio: Studio?
    /// A file opened before the studio finished loading.
    @State private var pendingImport: URL?

    var body: some Scene {
        WindowGroup {
            ZStack {
                Theme.background.ignoresSafeArea()
                if let studio {
                    ContentView(studio: studio)
                        .transition(.opacity)
                } else {
                    SplashView()
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                guard studio == nil, !Self.isTestHost else { return }
                // Let the splash paint before the main thread goes away to
                // build the audio engine and read the last song back.
                try? await Task.sleep(nanoseconds: 40_000_000)
                let studio = Studio()
                try? await Task.sleep(nanoseconds: 250_000_000)
                withAnimation(.easeOut(duration: 0.28)) { self.studio = studio }
                if let pendingImport {
                    studio.importSong(from: pendingImport)
                    self.pendingImport = nil
                }
            }
            // A .chipsong tapped in Mail or Files arrives here. The studio may
            // not exist yet — the splash is still up for the first frame — so
            // the URL waits until it does.
            .onOpenURL { url in
                if let studio {
                    studio.importSong(from: url)
                } else {
                    pendingImport = url
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Backgrounding is the one moment autosave's debounce might not
                // have fired yet.
                if phase != .active {
                    studio?.saveNow()
                    studio?.stopEngineIfIdle()
                }
            }
        }
    }
}

/// Shown while the app boots. Four bars, one per starting channel.
struct SplashView: View {
    @State private var animating = false

    private let heights: [CGFloat] = [46, 28, 52, 34]

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.channelColors[i])
                        .frame(width: 11, height: animating ? heights[i] : 12)
                        .animation(
                            .easeInOut(duration: 0.42)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.09),
                            value: animating
                        )
                }
            }
            .frame(height: 52, alignment: .bottom)

            Text("CHIPTUNE")
                .chipFont(20, weight: .bold)
                .foregroundStyle(Theme.text)
                .tracking(6)
        }
        .onAppear { animating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chiptune, loading")
    }
}
