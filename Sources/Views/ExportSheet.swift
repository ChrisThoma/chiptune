import SwiftUI

/// Export options, and the progress of the render they kick off.
///
/// A sheet rather than more items in the ••• menu: the render can take real
/// time on a long arrangement, and it needs somewhere to show how far along it
/// is and a way to stop it.
struct ExportSheet: View {
    @Bindable var studio: Studio
    @Environment(\.dismiss) private var dismiss
    @State private var options = ExportOptions()
    // Separate from `studio.isExporting`: SwiftUI can miss a render that starts
    // and finishes between update passes. The model's monotonic attempt token
    // cannot be coalesced away, so failures and cancellations reliably retry.
    @State private var startedAttempt: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $options.loopCount, in: 1...ExportOptions.maxLoopCount) {
                        HStack {
                            Text("Repeats")
                            Spacer()
                            Text("\(options.loopCount)×")
                                .chipFont(15, weight: .bold)
                                .foregroundStyle(Theme.dim)
                        }
                    }
                } footer: {
                    Text("The whole arrangement, \(Format.count(options.loopCount, "time")) — \(duration).")
                }

                Section {
                    Picker("Ending", selection: $options.tailMode) {
                        Text("Seamless loop").tag(ExportOptions.TailMode.seamlessLoop)
                        Text("Ring out").tag(ExportOptions.TailMode.ringOut)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Ending")
                } footer: {
                    Text(options.tailMode == .seamlessLoop
                         ? "The last notes ring on into the start, so the file loops with no gap. Best for dropping into something else."
                         : "The last notes fade out past the end and the file finishes in silence. Best when the file is the finished thing.")
                }

                Section {
                    if studio.isExporting {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: studio.exportProgress)
                                .tint(Theme.accentGreen)
                            Text("Rendering… \(Int(studio.exportProgress * 100))%")
                                .chipFont(11)
                                .foregroundStyle(Theme.dim)
                        }
                        Button("Cancel export", role: .destructive) {
                            studio.cancelExport()
                        }
                    } else {
                        Button {
                            guard startedAttempt == nil else { return }
                            startedAttempt = studio.export(options: options)
                        } label: {
                            Label("Export WAV", systemImage: "square.and.arrow.up")
                        }
                        .disabled(startedAttempt != nil)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        studio.cancelExport()
                        dismiss()
                    }
                }
            }
            .tint(Theme.text)
        }
        .onChange(of: studio.completedExportAttempt) { _, completedAttempt in
            guard startedAttempt == completedAttempt,
                  studio.exportURL == nil else { return }
            startedAttempt = nil
        }
        .preferredColorScheme(.dark)
    }

    /// Rough length of the file, so the repeat count means something.
    private var duration: String {
        var seconds = studio.song.arrangementDuration * Double(options.loopCount)
        if options.tailMode == .ringOut { seconds += 1 }
        return Format.clock(seconds)
    }
}
