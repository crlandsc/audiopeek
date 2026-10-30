import AppKit
import XCTest
@testable import AudioPeek

@MainActor
final class SettingsPaneTests: XCTestCase {
    private var box: DefaultsBox?
    private var controller: SettingsWindowController?

    override func tearDown() {
        controller = nil
        box?.close()
        box = nil
        super.tearDown()
    }

    private func makeController() -> (SettingsWindowController, SettingsStore) {
        let box = DefaultsBox()
        self.box = box
        let store = SettingsStore(defaults: box.defaults)
        let controller = SettingsWindowController(
            store: store,
            onLoginToggle: { _ in },
            onOpenLoginItems: {},
            onOpenAutomation: {},
            onReset: {}
        )
        self.controller = controller
        return (controller, store)
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    func testToolbarOffersTheThreePanesAndTheTitleFollowsTheSelection() {
        let (controller, _) = makeController()
        controller.select(.general, animate: false)
        let window = NSApp.windows.first { $0.toolbar?.identifier == "AudioPeekSettings" }
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.toolbarStyle, .preference)
        XCTAssertEqual(window?.toolbar?.items.map(\.label), ["General", "Waveform", "Spectrogram"])
        XCTAssertFalse(window?.styleMask.contains(.resizable) ?? true)
        XCTAssertEqual(window?.level, .floating, "Settings opens in front of the floating preview")
        for pane in SettingsPane.allCases {
            controller.select(pane, animate: false)
            XCTAssertEqual(controller.currentPane, pane)
            XCTAssertEqual(window?.title, pane.title)
            XCTAssertEqual(window?.toolbar?.selectedItemIdentifier, pane.toolbarIdentifier)
        }
        window?.close()
    }

    func testEachPaneFitsItsContentAndKeepsTheTopEdge() {
        let (controller, _) = makeController()
        controller.select(.general, animate: false)
        settle()
        let top = controller.frame.maxY
        var heights: [SettingsPane: CGFloat] = [:]
        for pane in SettingsPane.allCases {
            controller.select(pane, animate: false)
            settle()
            heights[pane] = controller.frame.height
            XCTAssertEqual(controller.frame.maxY, top, accuracy: 1, "\(pane) moved the top edge")
            XCTAssertEqual(controller.frame.width, SettingsWindowController.paneWidth, accuracy: 1)
        }
        XCTAssertGreaterThan(heights[.general] ?? 0, 250)
        XCTAssertGreaterThan(heights[.spectrogram] ?? 0, heights[.waveform] ?? 0)
        XCTAssertLessThan(heights[.waveform] ?? 0, 520)
        NSApp.windows.first { $0.toolbar?.identifier == "AudioPeekSettings" }?.close()
    }

    func testLabelsComeFromEveryPane() {
        let (controller, _) = makeController()
        controller.select(.general, animate: false)
        settle()
        // General is showing, yet controls from the other panes are still found.
        // (SwiftUI-only identifiers need a live accessibility client, so these use AppKit-backed controls.)
        let labels = controller.controlLabels()
        XCTAssertTrue(labels.contains("waveform.colorWell"), "Waveform pane missing from \(labels)")
        XCTAssertTrue(labels.contains("2,048"), "Spectrogram pane's n_fft field missing from \(labels)")
        NSApp.windows.first { $0.toolbar?.identifier == "AudioPeekSettings" }?.close()
    }

    func testAFinderWarningOpensOnGeneral() {
        let (controller, store) = makeController()
        controller.select(.spectrogram, animate: false)
        store.setFinderMessage("Enable AudioPeek for Finder.")
        controller.show()
        XCTAssertEqual(controller.currentPane, .general)
        let before = controller.frame.height
        store.setFinderMessage("")
        settle()
        XCTAssertLessThan(controller.frame.height, before, "the window shrinks when the warning goes away")
        NSApp.windows.first { $0.toolbar?.identifier == "AudioPeekSettings" }?.close()
    }

    func testAnEditSurvivesSwitchingPanes() {
        let (controller, store) = makeController()
        controller.select(.spectrogram, animate: false)
        store.update { $0.spectrogram.nFFT = 1024 }
        controller.select(.waveform, animate: false)
        controller.select(.spectrogram, animate: false)
        XCTAssertEqual(store.blob.spectrogram.nFFT, 1024)
        NSApp.windows.first { $0.toolbar?.identifier == "AudioPeekSettings" }?.close()
    }
}
