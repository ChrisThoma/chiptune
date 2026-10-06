import Foundation

/// Words for an alert when a song or its file can't be written: Share failed,
/// Save failed, Export failed. The system's own text names the internal file
/// (a UUID) and its folder, and can repeat a long song name, so it is never
/// pasted; only a permission or disk-space cause is kept, as one short
/// sentence, so the three alerts give the same reason for the same cause.
/// "Try again." follows every cause but permission, which retrying can't fix.
enum WriteFailureMessage {
    static let nameLimit = 30

    /// "Couldn't save “Name”. <reason>[ Try again.]"
    static func save(name: String, error: Error) -> String {
        "Couldn't save \(shown(name)). \(reasonAndAdvice(for: error, file: "song file"))"
    }

    /// "Couldn't export “Name”. <reason>[ Try again.]"
    static func export(name: String, error: Error) -> String {
        "Couldn't export \(shown(name)). \(reasonAndAdvice(for: error, file: "WAV file"))"
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
        switch cause(of: error as NSError) {
        case .permission: return "The app doesn't have permission to write the \(file)."
        case .space: return "There isn't enough free space to write the \(file)."
        case .other: return "The \(file) couldn't be written."
        }
    }

    /// The reason, then "Try again." unless the cause is permission.
    static func reasonAndAdvice(for error: Error, file: String) -> String {
        let reason = reason(for: error, file: file)
        return cause(of: error as NSError) == .permission ? reason : reason + " Try again."
    }

    private enum Cause { case permission, space, other }

    /// A failed `FileHandle` write wraps its POSIX cause in a generic Cocoa
    /// write error, so an unrecognized error is looked under before giving up.
    private static func cause(of ns: NSError) -> Cause {
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            return .permission
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError),
             (NSPOSIXErrorDomain, Int(ENOSPC)):
            return .space
        default:
            return (ns.userInfo[NSUnderlyingErrorKey] as? NSError).map(cause(of:)) ?? .other
        }
    }
}

/// The "Share failed" alert's words when a song file can't be prepared.
enum ShareFailureMessage {
    static func songFile(name: String, error: Error) -> String {
        let shown = WriteFailureMessage.shown(name)
        return "Couldn't prepare \(shown) to share. \(WriteFailureMessage.reasonAndAdvice(for: error, file: "song file"))"
    }
}
