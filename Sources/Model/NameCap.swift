import Foundation

/// The one rule for how much of a typed name a capped text field may show.
/// Characters are grapheme clusters (`String.prefix`), the same unit the saved
/// name uses, so what the field shows is what gets stored.
enum NameCap {
    static func clip(_ text: String, to limit: Int) -> String {
        String(text.prefix(limit))
    }

    /// What a field's draft should become when the stored name changes under
    /// it, or nil to leave the draft alone. A whitespace-only draft is stored
    /// as no name, so that pair already agrees.
    static func draftUpdate(draft: String, stored: String?) -> String? {
        let target = stored ?? ""
        if target == draft { return nil }
        if stored == nil && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return target
    }
}
