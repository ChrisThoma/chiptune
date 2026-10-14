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
    /// The two-argument form is the WAV wrapper: it keeps the shape the three
    /// alert builders share (`(String, Error) -> String`).
    static func export(name: String, error: Error) -> String {
        export(name: name, error: error, file: ExportOptions.Format.wav.fileNoun)
    }

    static func export(name: String, error: Error, file: String) -> String {
        "Couldn't export \(shown(name)). \(reasonAndAdvice(for: error, file: file))"
    }

    /// What a file of this extension is called in an alert: an export is
    /// its format's file, and anything else is a song file, the one other
    /// kind of file the app hands over. Android's `fileNoun` is the same rule.
    static func fileNoun(forExtension ext: String) -> String {
        ExportOptions.Format(fileExtension: ext)?.fileNoun ?? "song file"
    }

    /// Named from the file that was offered rather than the sheet's current
    /// format, which may have been switched since the export finished.
    static func fileNoun(for url: URL) -> String {
        fileNoun(forExtension: url.pathExtension)
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

    enum Cause { case permission, space, other }

    /// A failed `FileHandle` write wraps its POSIX cause in a generic Cocoa
    /// write error, so an unrecognized error is looked under before giving up.
    static func cause(of ns: NSError) -> Cause {
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError),
             (NSCocoaErrorDomain, NSFileReadNoPermissionError),
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

    /// The share sheet itself reported a failure. Its error comes from
    /// whichever app or service the user picked, so no cause is named.
    static func sheet(file: String) -> String {
        "Couldn't share the \(file). Try again."
    }
}

/// The "Delete failed" alert's words. Built like Save failed, but only
/// permission is worth naming: running out of space doesn't stop a delete.
enum DeleteFailureMessage {
    static func song(name: String, error: Error) -> String {
        let shown = WriteFailureMessage.shown(name)
        switch WriteFailureMessage.cause(of: error as NSError) {
        case .permission:
            return "Couldn't delete \(shown). The app doesn't have permission to change that file."
        case .space, .other:
            return "Couldn't delete \(shown). Try again."
        }
    }
}

/// The "Import failed" alert's words. Reading a file in can fail because it
/// isn't a song (or is damaged), can't be read, or the app doesn't have permission to
/// read it; saving the imported song can fail the way any save can.
enum ImportFailureMessage {
    /// The picked or opened file didn't become a song.
    static func file(error: Error) -> String {
        let lead = "Couldn't import the file."
        if case SongDocument.ImportError.notASong = error {
            return "\(lead) It isn't a Chiptune song, or it's damaged."
        }
        if WriteFailureMessage.cause(of: error as NSError) == .permission {
            return "\(lead) The app doesn't have permission to read it."
        }
        return "\(lead) Something went wrong reading it. Try again."
    }

    /// The song was read but couldn't be written into the library.
    static func save(name: String, error: Error) -> String {
        "Couldn't import \(WriteFailureMessage.shown(name)). \(WriteFailureMessage.reasonAndAdvice(for: error, file: "song file"))"
    }
}
