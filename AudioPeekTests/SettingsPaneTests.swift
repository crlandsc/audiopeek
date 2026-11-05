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
        // A Settings window another test hasn't freed yet must not be mistaken for this one.
        let leftoverBox = DefaultsBox()
        let leftover = SettingsWindowController(
            store: SettingsStore(defaults: leftoverBox.defaults),
            onLoginToggle: { _ in },
            onOpenLoginItems: {},
            onOpenAutomation: {},
            onReset: {}
        )
        leftover.select(.general, animate: false)
        defer {
            leftover.window?.close()
            leftoverBox.close()
        }
        let (controller, _) = makeController()
        controller.select(.general, animate: false)
        let window = controller.window
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
        controller.window?.close()
    }

    func testLabelsComeFromEveryPane() {
        let (controller, _) = makeController()
        controller.select(.general, animate: false)
        settle()
        // General is showing, yet controls from the other panes are still found.
        // (SwiftUI-only identifiers need a live accessibility client, so these use AppKit-backed controls.)
        let labels = controller.controlLabels()
        XCTAssertTrue(labels.contains("waveform.colorWell"), "Waveform pane missing from \(labels)")
        XCTAssertTrue(labels.contains("Linear"), "Waveform pane's amplitude control missing from \(labels)")
        controller.window?.close()
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
        controller.window?.close()
    }

    func testEveryTabHasACollapsedAdvancedSectionThatGrowsTheWindow() {
        let (controller, _) = makeController()
        for pane in SettingsPane.allCases {
            XCTAssertFalse(controller.sections.isExpanded(pane), "\(pane) Advanced starts collapsed")
        }
        for pane in SettingsPane.allCases {
            controller.select(pane, animate: false)
            settle()
            let collapsed = controller.frame.height
            let top = controller.frame.maxY
            controller.setAdvanced(pane, expanded: true)
            settle()
            XCTAssertGreaterThan(controller.frame.height, collapsed + 20, "\(pane) Advanced opens")
            XCTAssertEqual(controller.frame.maxY, top, accuracy: 1, "\(pane) keeps its top edge")
            controller.setAdvanced(pane, expanded: false)
            settle()
            XCTAssertEqual(controller.frame.height, collapsed, accuracy: 1, "\(pane) Advanced closes")
        }
        controller.window?.close()
    }

    func testEachTabResetsOnlyItsOwnSettings() {
        let (_, store) = makeController()
        store.update {
            $0.showDockIcon = true
            $0.waveformDual = false
            $0.waveformAmplitude = .decibels
            $0.waveformColor = WaveformColor(usesSystemBlue: false, red: 1, green: 0, blue: 0, alpha: 1)
            $0.spectrogramDual = true
            $0.spectrogram.nFFT = 1024
            $0.spectrogram.colorMap = .gray
            $0.showFrequencyAxis = true
        }
        store.resetWaveformSettings()
        let factory = SettingsBlob.factory
        XCTAssertEqual(store.blob.waveformDual, factory.waveformDual)
        XCTAssertEqual(store.blob.waveformAmplitude, factory.waveformAmplitude)
        XCTAssertEqual(store.blob.waveformColor, factory.waveformColor)
        XCTAssertTrue(store.blob.spectrogramDual, "the Waveform reset leaves the Spectrogram tab alone")
        XCTAssertEqual(store.blob.spectrogram.nFFT, 1024)
        XCTAssertTrue(store.blob.showDockIcon, "the Waveform reset leaves General alone")

        store.resetSpectrogramSettings()
        XCTAssertEqual(store.blob.spectrogram, factory.spectrogram)
        XCTAssertEqual(store.blob.spectrogramDual, factory.spectrogramDual)
        XCTAssertEqual(store.blob.showFrequencyAxis, factory.showFrequencyAxis)
        XCTAssertTrue(store.blob.showDockIcon, "the Spectrogram reset leaves General alone")
    }

    func testAnEditSurvivesSwitchingPanes() {
        let (controller, store) = makeController()
        controller.select(.spectrogram, animate: false)
        store.update { $0.spectrogram.nFFT = 1024 }
        controller.select(.waveform, animate: false)
        controller.select(.spectrogram, animate: false)
        XCTAssertEqual(store.blob.spectrogram.nFFT, 1024)
        controller.window?.close()
    }
}
