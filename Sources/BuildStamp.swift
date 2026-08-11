import Foundation

/// Which build this is, for someone holding it and wanting to know what went
/// into it.
///
/// The commit is the answer to that question and the reason this exists: it
/// names the code, it can be pasted into `git log`, and unlike a version
/// number it can't be stale, because a build phase reads it from the checkout
/// rather than from something a person remembered to type. The date is there
/// to make the row legible at a glance — telling last week's build from
/// today's shouldn't need a lookup.
///
/// The marketing version comes last and stands alone, because it answers a
/// different question: which release this belongs to. `CFBundleVersion`, the
/// upload counter, is deliberately absent. It exists so App Store Connect can
/// tell two uploads apart, it means nothing on a device, and mixing it in was
/// what made the first attempt at this read like bookkeeping.
///
/// Nothing here reports whether the tree had uncommitted edits. It's a real
/// distinction, but the app is the wrong place to raise it: on a build anyone
/// but the developer is holding, the tree was clean, so the flag is noise in
/// every case where it's read.
struct BuildStamp: Equatable {
    /// Short commit hash, from `ChiptuneGitCommit`. Nil when the app was built
    /// outside a git checkout — a source tarball, or a machine without git.
    let commit: String?
    /// When the build ran, from `ChiptuneBuildDate`.
    let builtAt: Date?
    /// `CFBundleShortVersionString` — the release a customer would name.
    let version: String?

    init(commit: String?, builtAt: Date?, version: String?) {
        self.commit = Self.present(commit)
        self.builtAt = builtAt
        self.version = Self.present(version)
    }

    init(bundle: Bundle = .main) {
        func string(_ key: String) -> String? {
            bundle.object(forInfoDictionaryKey: key) as? String
        }
        self.init(commit: string("ChiptuneGitCommit"),
                  builtAt: string("ChiptuneBuildDate").flatMap(Self.date(fromISO8601:)),
                  version: string("CFBundleShortVersionString"))
    }

    /// A value has to survive two things that both look like data. An empty or
    /// whitespace-only string is a missing key that reads as present, and a
    /// value still holding `$(…)` is a build setting that never expanded —
    /// which is a live outcome here, since the shipping `Info.plist` is
    /// generated and its version keys are written as substitutions.
    private static func present(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func date(fromISO8601 value: String) -> Date? {
        ISO8601DateFormatter().date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `Built 11 Aug 2026`, in the reader's own date format rather than the
    /// ISO form the plist carries — this line exists to be read, not parsed.
    var builtLine: String? {
        builtAt.map { "Built \($0.formatted(date: .abbreviated, time: .omitted))" }
    }

    var versionLine: String? { version.map { "Version \($0)" } }

    /// The row, top to bottom, with anything unavailable simply absent. A
    /// build made outside a checkout is missing its first two lines rather
    /// than showing placeholders for them; a dash where a hash should be tells
    /// the reader nothing they can act on.
    var lines: [String] { [builtLine, commit, versionLine].compactMap { $0 } }

    /// What lands on the clipboard: the release and the commit, which together
    /// are what a bug report needs. The date is derivable from the commit and
    /// is only on screen to save a lookup.
    var copyText: String {
        [version, commit].compactMap { $0 }.joined(separator: " · ")
    }
}
