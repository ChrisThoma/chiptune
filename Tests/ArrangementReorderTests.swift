import XCTest
@testable import Chiptune

/// Pure index math for the Arrangement list's pointer drag-to-reorder drop.
/// Verified against the real `Array.move(fromOffsets:toOffset:)` semantics
/// that `Studio.moveSection(from:to:)` forwards to, not just the returned
/// integer, so a wrong-but-plausible offset would still fail here.
final class ArrangementReorderTests: XCTestCase {

    func testDragDownMovesPastTheTargetRow() {
        var sections = [0, 1, 2, 3]
        let destination = ArrangementReorder.destination(draggedIndex: 0, overIndex: 2)
        sections.move(fromOffsets: IndexSet(integer: 0), toOffset: destination)
        XCTAssertEqual(sections, [1, 2, 0, 3])
    }

    func testDragUpMovesBeforeTheTargetRow() {
        var sections = [0, 1, 2, 3]
        let destination = ArrangementReorder.destination(draggedIndex: 3, overIndex: 1)
        sections.move(fromOffsets: IndexSet(integer: 3), toOffset: destination)
        XCTAssertEqual(sections, [0, 3, 1, 2])
    }

    func testDropOnItselfIsANoOp() {
        var sections = [0, 1, 2, 3]
        let destination = ArrangementReorder.destination(draggedIndex: 2, overIndex: 2)
        sections.move(fromOffsets: IndexSet(integer: 2), toOffset: destination)
        XCTAssertEqual(sections, [0, 1, 2, 3])
    }
}
