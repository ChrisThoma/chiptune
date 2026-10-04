import Foundation

/// Words for the "Share failed" alert when a song file can't be prepared.
/// The system's own text names the file and the temp folder (and repeats the
/// song name), so it is never pasted; only a permission or disk-space cause is
/// kept, as one short clause.
enum ShareFailureMessage {
    static let nameLimit = 30

    static func songFile(name: String, error: Error) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown: String
        if trimmed.isEmpty {
            shown = "this song"
        } else if trimmed.count > nameLimit {
            shown = "“" + NameCap.clip(trimmed, to: nameLimit).trimmingCharacters(in: .whitespaces) + "…”"
        } else {
            shown = "“" + trimmed + "”"
        }
        return "Couldn't prepare \(shown) to share. \(reason(for: error)) Try again."
    }

    private static func reason(for error: Error) -> String {
        let ns = error as NSError
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            return "The app doesn't have permission to write the song file."
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError),
             (NSPOSIXErrorDomain, Int(ENOSPC)):
            return "There isn't enough free space to write the song file."
        default:
            return "The song file couldn't be written."
        }
    }
}
