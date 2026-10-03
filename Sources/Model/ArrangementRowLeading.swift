import Foundation

/// What an arrangement row shows in its leading slot.
///
/// The playing marker replaces the section number instead of being added
/// as another element, so the playing row keeps the same width budget as
/// every other row. In edit mode (delete circle + drag handle) the extra
/// marker element was enough to truncate a wide pattern name to "WW…".
enum ArrangementRowLeading: Equatable {
    case number(String)
    case playingMarker

    static func content(position: Int, playing: Bool) -> ArrangementRowLeading {
        playing ? .playingMarker : .number("\(position + 1)")
    }
}
