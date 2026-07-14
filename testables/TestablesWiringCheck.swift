import XCTest
@testable import TestablesKit

/// Proof that the `testables/` folder is wired into the `SteelmanTests` target.
final class TestablesWiringCheck: XCTestCase {
    func test_targetIsWiredToTestablesKit() throws {
        let item = Testable(id: "wiring-check", description: "x", testInstructions: [])
        XCTAssertEqual(item.id, "wiring-check")
    }
}
