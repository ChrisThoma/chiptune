import Foundation

/// The one decision behind the rename sheet: what a typed name would store,
/// and why Rename is dimmed when it can't. The button and the footer both read
/// this, so they cannot disagree.
enum PatternNameCheck: Equatable {
    case accepted(String)
    case blank
    case duplicate

    static let maxLength = 6

    /// Trimmed, truncated, case-sensitive; another pattern's name is a duplicate.
    static func evaluate(_ name: String, among names: [String], renaming index: Int) -> PatternNameCheck {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(maxLength))
        guard !trimmed.isEmpty else { return .blank }
        let taken = names.enumerated().contains { $0.offset != index && $0.element == trimmed }
        return taken ? .duplicate : .accepted(trimmed)
    }

    var acceptedName: String? {
        if case .accepted(let name) = self { return name }
        return nil
    }

    static func footer(for text: String, among names: [String], renaming index: Int) -> String {
        if evaluate(text, among: names, renaming: index) == .duplicate {
            return "Another pattern already uses this name."
        }
        return "Up to \(maxLength) characters — \(text.count) of \(maxLength) used."
    }
}
