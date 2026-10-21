import XCTest
@testable import Chiptune

/// A `UTType(exportedAs:)` the Info.plist doesn't declare logs a runtime
/// warning and gets a dynamic type with no conformances. Every identifier
/// the app exports has to be in UTExportedTypeDeclarations.
final class ExportedTypeTests: XCTestCase {
    private func declaration(_ identifier: String) throws -> [String: Any] {
        let declarations = try XCTUnwrap(
            Bundle.main.infoDictionary?["UTExportedTypeDeclarations"] as? [[String: Any]])
        return try XCTUnwrap(declarations.first { $0["UTTypeIdentifier"] as? String == identifier },
                             "\(identifier) is not declared")
    }

    func testDeclaresTheSongFileType() throws {
        let song = try declaration("dev.individuation.chiptune.song")
        XCTAssertEqual(song["UTTypeConformsTo"] as? [String], ["public.json"])
    }

    /// Dragging an arrangement row carries its section as this type.
    func testDeclaresTheArrangementSectionType() throws {
        let section = try declaration("dev.individuation.chiptune.arrangement-section")
        XCTAssertEqual(section["UTTypeConformsTo"] as? [String], ["public.data"])
        XCTAssertEqual(section["UTTypeDescription"] as? String, "Chiptune Arrangement Section")
    }
}
