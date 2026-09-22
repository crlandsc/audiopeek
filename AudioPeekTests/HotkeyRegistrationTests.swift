import Carbon
import XCTest
@testable import AudioPeek

final class HotkeyRegistrationTests: XCTestCase {
    func testOptionSpaceRegistersOrControlOptionSpaceDoes() {
        let center = HotkeyCenter()
        center.installHandler()
        defer { center.unregisterViewer() }
        let status = center.registerViewer(.optionSpace)
        if status != noErr {
            let fallback = center.registerViewer(.controlOptionSpace)
            let note = "option-space status \(status), control-option-space status \(fallback)"
            try? note.write(toFile: "/tmp/audiopeek-option-space-failed", atomically: true, encoding: .utf8)
            XCTAssertEqual(fallback, noErr, note)
            return
        }
        try? FileManager.default.removeItem(atPath: "/tmp/audiopeek-option-space-failed")
        XCTAssertEqual(status, noErr)
        XCTAssertEqual(center.probe(.optionSpace), OSStatus(eventHotKeyExistsErr))
        center.unregisterViewer()
        XCTAssertEqual(center.probe(HotkeyCombo(keyCode: 49, carbonModifiers: 0)), OSStatus(paramErr))
        XCTAssertEqual(center.probe(HotkeyCombo(keyCode: 123, carbonModifiers: 0)), OSStatus(paramErr))
    }

    func testCompiledFinderEventTargetsSelection() {
        let event = FinderSelectionEvent.make()
        XCTAssertEqual(event.eventID, AEEventID(kAEGetData))
        let text = String(describing: event)
        XCTAssertTrue(text.contains("'seld':'sele'"), text)
        XCTAssertTrue(text.contains("'rtyp':'furl'"), text)
        XCTAssertFalse(text.contains("eles"), text)
    }
}
