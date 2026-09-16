import Foundation

/// The index math for a pointer drag-to-reorder drop in `ArrangementView`.
///
/// `Studio.moveSection(from:to:)` forwards straight to `Array.move(fromOffsets:toOffset:)`,
/// whose `to:` destination has to be expressed in terms of the array *before*
/// the dragged element is removed: dropping past an element (dragging down)
/// needs `overIndex + 1` so the dragged row lands after it, while dropping
/// before an element (dragging up) needs `overIndex` itself. Dropping a row
/// on itself is a no-op.
enum ArrangementReorder {
    static func destination(draggedIndex: Int, overIndex: Int) -> Int {
        guard draggedIndex != overIndex else { return draggedIndex }
        return draggedIndex < overIndex ? overIndex + 1 : overIndex
    }
}
