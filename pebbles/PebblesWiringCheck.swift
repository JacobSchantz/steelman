import XCTest
@testable import PebblesKit

/// Proof that the `pebbles/` folder is wired into the `SteelmanTests` target.
final class PebblesWiringCheck: XCTestCase {
    func test_targetIsWiredToPebblesKit() throws {
        let item = Pebble(id: "wiring-check", description: "x", testInstructions: [])
        XCTAssertEqual(item.id, "wiring-check")
    }
}
