import XCTest
@testable import AudioPeek

final class AppearanceTests: XCTestCase {
    func testMagmaEndsAreTheSlipColormap() {
        let start = MagmaColor.components(0)
        XCTAssertEqual(start.0, 0.00146, accuracy: 0.02)
        XCTAssertEqual(start.1, 0.00047, accuracy: 0.02)
        XCTAssertEqual(start.2, 0.01387, accuracy: 0.02)
        let end = MagmaColor.components(1)
        XCTAssertEqual(end.0, 0.98705, accuracy: 0.02)
        XCTAssertEqual(end.1, 0.99144, accuracy: 0.02)
        XCTAssertEqual(end.2, 0.74950, accuracy: 0.02)
        let middle = MagmaColor.components(0.5)
        XCTAssertGreaterThan(middle.0, middle.1)
        XCTAssertGreaterThan(middle.2, middle.1)
    }
}
