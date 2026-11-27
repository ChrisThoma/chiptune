import SwiftUI

/// The Mac app's entry point. A placeholder window for now: the shared core
/// builds and is tested on macOS, and the editor views come over next. It
/// shows the build stamp so a build can be told apart from the last one.
@main
struct ChiptuneMacApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
        }
    }
}

private struct PlaceholderView: View {
    private let build = BuildStamp()

    var body: some View {
        VStack(spacing: 12) {
            Text("Chiptune")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.text)
            ForEach(build.lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
