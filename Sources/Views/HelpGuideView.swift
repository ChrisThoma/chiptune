import SwiftUI

/// "How it works": one line per control, grouped the way the screen is. Reached
/// from the `…` menu, or from a (?) on a sheet, which opens it at that sheet's
/// section so nobody has to hunt for the part they were stuck on.
struct HelpGuideView: View {
    var start: HelpGuide.SectionID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Wide enough for "Add section" on one line at the default text size.
    @ScaledMetric(relativeTo: .caption) private var termWidth: CGFloat = 86

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(HelpGuide.sections) { section in
                            sectionView(section).id(section.id)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    if let start { proxy.scrollTo(start, anchor: .top) }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sectionView(_ section: HelpGuide.Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title.uppercased())
                .chipFont(11, weight: .bold)
                .foregroundStyle(Theme.dim)
                .tracking(2)
                .accessibilityAddTraits(.isHeader)
            ForEach(section.entries) { entry in
                row(entry)
            }
        }
    }

    /// At the accessibility text sizes a chip column would leave the sentence
    /// a few characters a line, so the chip goes above it instead.
    @ViewBuilder
    private func row(_ entry: HelpGuide.Entry) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            term(entry)
            Text(entry.text)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.term). \(entry.text)")
    }

    private func term(_ entry: HelpGuide.Entry) -> some View {
        Group {
            if let symbol = entry.symbol {
                Image(systemName: symbol).symbolFont(13)
            } else {
                Text(entry.term)
                    .chipFont(11, weight: .bold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : termWidth)
        .frame(minHeight: 28)
        .background(RoundedRectangle(cornerRadius: Theme.innerRadius).fill(Theme.panelHigh))
    }
}

/// The small (?) on a sheet's header.
struct HelpGuideButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .symbolFont(15)
                .foregroundStyle(Theme.dim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("How it works")
    }
}

extension View {
    /// Raises the guide, and tells the studio so the editor's chords stand
    /// down: the docked sound panel isn't itself a presentation, so nothing
    /// else would say the editor is covered.
    func helpGuide(isPresented: Binding<Bool>, start: HelpGuide.SectionID?,
                   studio: Studio) -> some View {
        sheet(isPresented: isPresented) {
            HelpGuideView(start: start)
        }
        .reportsPresentation(.guide, isPresented: isPresented.wrappedValue, studio: studio)
    }
}
