import Foundation

/// Words for an alert when a song or its file can't be written: Share failed,
/// Save failed, Export failed. The system's own text names the internal file
/// (a UUID) and its folder, and can repeat a long song name, so it is never
/// pasted; only a permission or disk-space cause is kept, as one short
/// sentence, so the three alerts give the same reason for the same cause.
enum WriteFailureMessage {
    static let nameLimit = 30

    /// "Couldn't save “Name”. <reason> Try again."
    static func save(name: String, error: Error) -> String {
        "Couldn't save \(shown(name)). \(reason(for: error, file: "song file")) Try again."
    }

    /// The song's name in quotes, clipped with an ellipsis past `nameLimit`
    /// characters, or "this song" when it's blank.
    static func shown(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "this song"
        } else if trimmed.count > nameLimit {
            return "“" + NameCap.clip(trimmed, to: nameLimit).trimmingCharacters(in: .whitespaces) + "…”"
        } else {
            return "“" + trimmed + "”"
        }
    }

    static func reason(for error: Error, file: String) -> String {
        let ns = error as NSError
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            return "The app doesn't have permission to write the \(file)."
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError),
             (NSPOSIXErrorDomain, Int(ENOSPC)):
            return "There isn't enough free space to write the \(file)."
        default:
            return "The \(file) couldn't be written."
        }
    }
}

/// The "Share failed" alert's words when a song file can't be prepared.
enum ShareFailureMessage {
    static func songFile(name: String, error: Error) -> String {
        let shown = WriteFailureMessage.shown(name)
        return "Couldn't prepare \(shown) to share. \(WriteFailureMessage.reason(for: error, file: "song file")) Try again."
    }
}
