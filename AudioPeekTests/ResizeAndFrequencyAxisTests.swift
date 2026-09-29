import AppKit
import XCTest
@testable import AudioPeek

@MainActor
final class ResizeAndFrequencyAxisTests: XCTestCase {
    func testCursorRegionsUseTheResizeCursorForThatEdge() {
        let view = SlipContentView(frame: NSRect(x: 0, y: 0, width: 860, height: 500))
        let checks: [(NSPoint, NSCursor)] = [
            (NSPoint(x: 3, y: 250), .resizeLeftRight),
            (NSPoint(x: 856, y: 250), .resizeLeftRight),
            (NSPoint(x: 430, y: 3), .resizeUpDown),
            (NSPoint(x: 430, y: 496), .resizeUpDown),
            (NSPoint(x: 3, y: 3), SlipResizeAxis.upLeftCursor),
            (NSPoint(x: 856, y: 496), SlipResizeAxis.upLeftCursor),
            (NSPoint(x: 856, y: 3), SlipResizeAxis.upRightCursor),
            (NSPoint(x: 3, y: 496), SlipResizeAxis.upRightCursor)
        ]
        for (point, cursor) in checks {
            XCTAssertTrue(view.resizeCursor(at: point) === cursor)
        }
        XCTAssertNil(view.resizeCursor(at: NSPoint(x: 430, y: 250)))
        XCTAssertFalse(SlipResize.edges(at: NSPoint(x: 430, y: 250), in: view.bounds).isActive)
    }

    func testResizeFrameFollowsEachEdgeOnce() {
        let start = NSRect(x: 100, y: 200, width: 860, height: 500)
        let minSize = NSSize(width: 420, height: 280)
        let origin = NSPoint(x: 0, y: 0)

        let right = SlipResize.resizedFrame(
            start: start,
            startMouse: origin,
            mouse: NSPoint(x: 80, y: 0),
            edges: SlipResizeEdges(right: true),
            minSize: minSize
        )
        XCTAssertEqual(right, NSRect(x: 100, y: 200, width: 940, height: 500))

        let rightShrink = SlipResize.resizedFrame(
            start: start,
            startMouse: origin,
            mouse: NSPoint(x: -60, y: 0),
            edges: SlipResizeEdges(right: true),
            minSize: minSize
        )
        XCTAssertEqual(rightShrink.width, 800)
        XCTAssertEqual(rightShrink.origin.x, 100)

        let left = SlipResize.resizedFrame(
            start: start,
            startMouse: origin,
            mouse: NSPoint(x: -40, y: 0),
            edges: SlipResizeEdges(left: true),
            minSize: minSize
        )
        XCTAssertEqual(left, NSRect(x: 60, y: 200, width: 900, height: 500))

        let top = SlipResize.resizedFrame(
            start: start,
            startMouse: origin,
            mouse: NSPoint(x: 0, y: 30),
            edges: SlipResizeEdges(top: true),
            minSize: minSize
        )
        XCTAssertEqual(top, NSRect(x: 100, y: 200, width: 860, height: 530))

        let bottom = SlipResize.resizedFrame(
            start: start,
            startMouse: origin,
            mouse: NSPoint(x: 0, y: -25),
            edges: SlipResizeEdges(bottom: true),
            minSize: minSize
        )
        XCTAssertEqual(bottom, NSRect(x: 100, y: 175, width: 860, height: 525))

        let corner = SlipResize.resizedFrame(
            start: start,
            startMouse: origin,
            mouse: NSPoint(x: -20, y: 15),
            edges: SlipResizeEdges(left: true, top: true),
            minSize: minSize
        )
        XCTAssertEqual(corner, NSRect(x: 80, y: 200, width: 880, height: 515))

        let tiny = SlipResize.resizedFrame(
            start: start,
            startMouse: origin,
            mouse: NSPoint(x: 4000, y: 4000),
            edges: SlipResizeEdges(left: true, bottom: true),
            minSize: minSize
        )
        XCTAssertEqual(tiny.size, minSize)

        let wide = SlipResize.resizedFrame(
            start: start,
            startMouse: origin,
            mouse: NSPoint(x: 5000, y: 0),
            edges: SlipResizeEdges(right: true),
            minSize: minSize
        )
        XCTAssertEqual(wide, NSRect(x: 100, y: 200, width: 5860, height: 500))
    }

    func testResizeDragRestartsTheOverviewOnceAndDoesNotStartASecondPlayback() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-resize-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 16_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let slip = makeSlip()
        slip.setInjectedLoad(thermal: "nominal", cpu: 0.1, applyNow: false)
        slip.setOverviewStall(true)
        slip.openFiles([url])
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !(slip.playbackRunning && slip.overviewStartCount >= 1 && slip.panelsMade == 1) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(slip.playbackRunning)
        XCTAssertEqual(slip.panelsMade, 1)
        XCTAssertGreaterThanOrEqual(slip.overviewStartCount, 1)
        XCTAssertTrue(slip.frequencyTickLabels.isEmpty)

        let plays = slip.playbackStartCount
        let starts = slip.overviewStartCount
        XCTAssertGreaterThanOrEqual(plays, 1)

        slip.beginResizeInteraction()
        let origin = slip.frame.origin
        slip.resizePanelForTest(NSRect(x: origin.x, y: origin.y, width: 1100, height: 640))
        slip.resizePanelForTest(NSRect(x: origin.x + 20, y: origin.y - 30, width: 420, height: 280))
        slip.resizePanelForTest(NSRect(x: origin.x - 80, y: origin.y + 10, width: 2400, height: 900))
        slip.sampleGateForTest()
        slip.openFiles([url])
        let store = slipStore
        store?.update {
            $0.windowFrame = StoredWindowFrame(x: 0, y: 0, width: 700, height: 400)
        }
        slip.applySettings()
        XCTAssertEqual(slip.overviewStartCount, starts)
        XCTAssertEqual(slip.playbackStartCount, plays)
        XCTAssertEqual(slip.panelsMade, 1)
        XCTAssertEqual(slip.frame.width, 2400, accuracy: 0.5)
        XCTAssertTrue(slip.playbackRunning)

        slip.endResizeInteraction()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertEqual(slip.overviewStartCount, starts + 1)
        XCTAssertEqual(slip.playbackStartCount, plays)
        XCTAssertEqual(slip.panelsMade, 1)
        XCTAssertTrue(slip.playbackRunning)

        let afterWidth = slip.overviewStartCount
        let heightFrame = slip.frame
        slip.beginResizeInteraction()
        slip.resizePanelForTest(NSRect(
            x: heightFrame.origin.x,
            y: heightFrame.origin.y - 40,
            width: heightFrame.width,
            height: heightFrame.height + 70
        ))
        slip.endResizeInteraction()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertEqual(slip.overviewStartCount, afterWidth)
        XCTAssertEqual(slip.playbackStartCount, plays)
        XCTAssertEqual(slip.panelsMade, 1)

        slip.beginResizeInteraction()
        let again = slip.frame
        slip.resizePanelForTest(NSRect(x: again.origin.x, y: again.origin.y, width: again.width - 120, height: again.height))
        slip.resizePanelForTest(NSRect(x: again.origin.x, y: again.origin.y, width: again.width + 80, height: again.height))
        slip.endResizeInteraction()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        XCTAssertEqual(slip.overviewStartCount, afterWidth + 1)
        XCTAssertEqual(slip.playbackStartCount, plays)
        XCTAssertEqual(slip.panelsMade, 1)
        XCTAssertTrue(slip.audioEngineRunning)

        let beforeAxis = slip.overviewStartCount
        store?.update { $0.showFrequencyAxis = true }
        slip.applySettings()
        XCTAssertEqual(slip.overviewStartCount, beforeAxis)
        XCTAssertFalse(slip.frequencyTickLabels.isEmpty)
        XCTAssertEqual(slip.playbackStartCount, plays)
        store?.update { $0.showFrequencyAxis = false }
        slip.applySettings()
        XCTAssertTrue(slip.frequencyTickLabels.isEmpty)
        XCTAssertEqual(slip.overviewStartCount, beforeAxis)
        XCTAssertEqual(slip.panelsMade, 1)
    }

    func testFrequencyLabelsStayOffUntilTheSettingIsOn() throws {
        XCTAssertFalse(SettingsBlob.factory.showFrequencyAxis)
        let data = try JSONEncoder().encode(SettingsBlob.factory)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "showFrequencyAxis")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SettingsBlob.self, from: stripped)
        XCTAssertFalse(decoded.showFrequencyAxis)

        let pane = SlipPaneView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        pane.setFrequencyAxis(shown: false, sampleRate: 44_100)
        XCTAssertTrue(pane.frequencyTickLabels.isEmpty)
        pane.setFrequencyAxis(shown: true, sampleRate: 44_100)
        XCTAssertFalse(pane.frequencyTickLabels.isEmpty)
        pane.setFrequencyAxis(shown: false, sampleRate: 44_100)
        XCTAssertTrue(pane.frequencyTickLabels.isEmpty)
    }

    func testFrequencyTicksStayInsideAndAShortPaneHasFewer() {
        let heights: [CGFloat] = [48, 70, 140, 360]
        let nyquists = [1_000.0, 8_000.0, 22_050.0, 96_000.0]
        for height in heights {
            for nyquist in nyquists {
                let ticks = FrequencyAxisTicks.layout(height: height, nyquist: nyquist)
                var previous = -CGFloat.greatestFiniteMagnitude
                for tick in ticks {
                    let top = tick.centerY - FrequencyAxisTicks.labelHeight / 2
                    let bottom = tick.centerY + FrequencyAxisTicks.labelHeight / 2
                    XCTAssertGreaterThanOrEqual(top, -0.01, "\(tick.label) leaves the top at height \(height)")
                    XCTAssertLessThanOrEqual(bottom, height + 0.01, "\(tick.label) leaves the bottom at height \(height)")
                    XCTAssertGreaterThanOrEqual(
                        tick.centerY - previous,
                        FrequencyAxisTicks.minSeparation - 0.01,
                        "\(tick.label) overlaps the label above it"
                    )
                    previous = tick.centerY
                }
            }
        }
        XCTAssertTrue(FrequencyAxisTicks.layout(height: 10, nyquist: 22_050).isEmpty)
        XCTAssertLessThan(
            FrequencyAxisTicks.layout(height: 70, nyquist: 22_050).count,
            FrequencyAxisTicks.layout(height: 360, nyquist: 22_050).count
        )
        XCTAssertLessThan(
            FrequencyAxisTicks.layout(height: 48, nyquist: 8_000).count,
            FrequencyAxisTicks.layout(height: 360, nyquist: 8_000).count
        )
        XCTAssertLessThan(
            FrequencyAxisTicks.layout(height: 70, nyquist: 96_000).count,
            FrequencyAxisTicks.layout(height: 360, nyquist: 96_000).count
        )
    }

    private var slipStore: SettingsStore?

    private func makeSlip() -> SlipPanelController {
        let suite = "audiopeek.resize.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: defaults)
        slipStore = store
        return SlipPanelController(
            store: store,
            finder: IdleResizeFinder(),
            hotkey: HotkeyCenter(),
            onOpenSettings: {}
        )
    }

    private func writeWav(to url: URL, frames: Int) throws {
        var data = Data()
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append32(UInt32(36 + frames * 2))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        append32(16)
        append16(1)
        append16(1)
        append32(44100)
        append32(44100 * 2)
        append16(2)
        append16(16)
        data.append(contentsOf: "data".utf8)
        append32(UInt32(frames * 2))
        data.append(Data(count: frames * 2))
        try data.write(to: url)
    }
}

private final class IdleResizeFinder: FinderSelectionSource {
    func requestSelection(_ completion: @escaping (FinderRead) -> Void) {}
}
