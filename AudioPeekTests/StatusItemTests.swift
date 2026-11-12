import XCTest
@testable import AudioPeek

@MainActor
final class StatusItemTests: XCTestCase {
    func testMenuIsSettingsAndQuitAndCanHide() {
        var opened = 0
        let controller = StatusItemController(updates: UpdateController(driver: RecordingUpdaterDriver())) { opened += 1 }
        controller.setVisible(true)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.menuTitles, ["AudioPeek Settings", "Check for Updates…", "Quit"])
        XCTAssertTrue(controller.statusImageIsTemplate)
        XCTAssertEqual(controller.statusImageSize, NSSize(width: PlaywaveMark.menuBarPointSize, height: PlaywaveMark.menuBarPointSize))
        XCTAssertEqual(controller.statusButtonTitle, "")
        controller.setVisible(true)
        XCTAssertEqual(controller.menuTitles, ["AudioPeek Settings", "Check for Updates…", "Quit"])
        controller.setVisible(false)
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(controller.menuTitles, [])
        XCTAssertEqual(opened, 0)
    }
}
