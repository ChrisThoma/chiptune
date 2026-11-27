import Foundation

/// Where the Mac's save panel opens for an export, and what it offers to call
/// the file. Pure apart from `copy`, so the choices are tested without a panel.
enum ExportDestination {
    /// The person's real home folder. A sandboxed app's own home is its
    /// container, whose Movies and Music are not the ones in the Finder
    /// sidebar.
    static var userHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// The export is already named for the song (`ExportFiles.url`); the
    /// folder around it is a per-song UUID and never part of the name.
    static func suggestedName(for url: URL) -> String {
        url.lastPathComponent
    }

    /// Video to Movies, audio and MIDI to Music, a song file to Documents,
    /// anything else to Downloads.
    static func directory(for url: URL, home: URL = userHome) -> URL {
        let folder: String
        switch url.pathExtension.lowercased() {
        case ExportOptions.Format.video.fileExtension, "mov": folder = "Movies"
        case ExportOptions.Format.wav.fileExtension, ExportOptions.Format.midi.fileExtension, "midi":
            folder = "Music"
        case SongDocument.fileExtension: folder = "Documents"
        default: folder = "Downloads"
        }
        return home.appendingPathComponent(folder, isDirectory: true)
    }

    /// Copies rather than moves: the share flow may still offer the same
    /// file again. A file already there is replaced, because the save panel
    /// has asked about that already.
    static func copy(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: try temporaryCopy(of: source))
        } else {
            try fm.copyItem(at: source, to: destination)
        }
    }

    /// `replaceItemAt` consumes the item it's given, so it gets a copy.
    private static func temporaryCopy(of source: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }
}
