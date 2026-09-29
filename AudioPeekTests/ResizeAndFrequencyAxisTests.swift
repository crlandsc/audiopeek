import AppKit
import AVFAudio
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
            CFRunLoopRunInMode(.defaultMode, 0.05, false)
        }
        XCTAssertTrue(slip.playbackRunning)
        XCTAssertEqual(slip.panelsMade, 1)
        XCTAssertGreaterThanOrEqual(slip.overviewStartCount, 1)
        XCTAssertTrue(slip.frequencyTickLabels.isEmpty)

        let plays = slip.playbackStartCount
        let starts = slip.overviewStartCount
        XCTAssertGreaterThanOrEqual(plays, 1)

        slip.beginResizeInteraction()
        XCTAssertTrue(slip.panesAreStretching)
        XCTAssertTrue(slip.panesHoldStretchSnapshot)
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
        XCTAssertFalse(slip.panesAreStretching)
        XCTAssertFalse(slip.panesHoldStretchSnapshot)
        CFRunLoopRunInMode(.defaultMode, 0.35, false)
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
        CFRunLoopRunInMode(.defaultMode, 0.35, false)
        XCTAssertEqual(slip.overviewStartCount, afterWidth)
        XCTAssertEqual(slip.playbackStartCount, plays)
        XCTAssertEqual(slip.panelsMade, 1)

        slip.beginResizeInteraction()
        let again = slip.frame
        slip.resizePanelForTest(NSRect(x: again.origin.x, y: again.origin.y, width: again.width - 120, height: again.height))
        slip.resizePanelForTest(NSRect(x: again.origin.x, y: again.origin.y, width: again.width + 80, height: again.height))
        slip.endResizeInteraction()
        CFRunLoopRunInMode(.defaultMode, 0.35, false)
        XCTAssertEqual(slip.overviewStartCount, afterWidth + 1)
        XCTAssertEqual(slip.playbackStartCount, plays)
        XCTAssertEqual(slip.panelsMade, 1)
        XCTAssertTrue(slip.audioEngineRunning)

        let beforeAxis = slip.overviewStartCount
        store?.update { $0.showFrequencyAxis = true }
        slip.applySettings()
        XCTAssertEqual(slip.overviewStartCount, beforeAxis)
        XCTAssertFalse(slip.frequencyTickLabels.isEmpty)
        XCTAssertFalse(slip.frequencyTickLabels.contains { $0.contains("Hz") })
        XCTAssertEqual(slip.playbackStartCount, plays)
        store?.update { $0.showFrequencyAxis = false }
        slip.applySettings()
        XCTAssertTrue(slip.frequencyTickLabels.isEmpty)
        XCTAssertEqual(slip.overviewStartCount, beforeAxis)
        XCTAssertEqual(slip.panelsMade, 1)

        let beforeTime = slip.overviewStartCount
        store?.update { $0.showTimeAxis = true }
        slip.applySettings()
        XCTAssertEqual(slip.overviewStartCount, beforeTime)
        XCTAssertFalse(slip.timeTickLabels.isEmpty)
        XCTAssertEqual(slip.playbackStartCount, plays)
        store?.update { $0.showTimeAxis = false }
        slip.applySettings()
        XCTAssertTrue(slip.timeTickLabels.isEmpty)
        XCTAssertEqual(slip.overviewStartCount, beforeTime)
    }

    func testResizeDragStretchesASnapshotUntilMouseUp() {
        let pane = SlipPaneView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        let window = NSWindow(
            contentRect: pane.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = pane
        pane.displayIfNeeded()
        pane.beginStretch()
        let drawn = pane.drawCount
        XCTAssertTrue(pane.isStretching)
        XCTAssertTrue(pane.hasStretchSnapshot)
        XCTAssertNotNil(pane.layer?.contents)
        pane.setFrameSize(NSSize(width: 480, height: 200))
        pane.needsDisplay = true
        pane.displayIfNeeded()
        XCTAssertEqual(pane.drawCount, drawn)
        XCTAssertNotNil(pane.layer?.contents)
        pane.endStretch()
        XCTAssertFalse(pane.isStretching)
        XCTAssertFalse(pane.hasStretchSnapshot)
        XCTAssertNil(pane.layer?.contents)
        pane.displayIfNeeded()
        XCTAssertGreaterThan(pane.drawCount, drawn)
    }

    func testHoverCursorChangesOnEdgesCornersAndTheSplit() {
        let view = SlipContentView(frame: NSRect(x: 0, y: 0, width: 860, height: 500))
        view.layout()
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
        let split = NSPoint(x: 430, y: view.divider.frame.midY)
        XCTAssertTrue(view.resizeCursor(at: split) === NSCursor.resizeUpDown)
        XCTAssertNil(view.resizeCursor(at: NSPoint(x: 430, y: 120)))

        let window = SlipWindow(
            contentRect: view.frame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.acceptsMouseMovedEvents = true
        view.updateTrackingAreas()
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertTrue(window.acceptsMouseMovedEvents)
        XCTAssertTrue(view.trackingAreas.contains { area in
            area.options.contains(.mouseMoved) && area.options.contains(.activeAlways)
        })
    }

    func testFrequencyFormatUsesPlainNumbersAndKilohertz() {
        XCTAssertEqual(FrequencyAxisTicks.format(20), "20")
        XCTAssertEqual(FrequencyAxisTicks.format(200), "200")
        XCTAssertEqual(FrequencyAxisTicks.format(400), "400")
        XCTAssertEqual(FrequencyAxisTicks.format(800), "800")
        XCTAssertEqual(FrequencyAxisTicks.format(1000), "1k")
        XCTAssertEqual(FrequencyAxisTicks.format(2000), "2k")
        XCTAssertEqual(FrequencyAxisTicks.format(4000), "4k")
        for hertz in [20.0, 200, 400, 800, 1000, 2000, 4000, 22050] {
            let label = FrequencyAxisTicks.format(hertz)
            XCTAssertFalse(label.contains("Hz"), label)
            XCTAssertFalse(label.contains("kHz"), label)
        }
    }

    func testFrequencyLabelsUseASoftBackingAndAShortTick() {
        XCTAssertEqual(AxisLabelChrome.fadeAlphas.last, 0)
        XCTAssertGreaterThan(AxisLabelChrome.fadeAlphas[0], AxisLabelChrome.fadeAlphas[1])
        XCTAssertGreaterThan(AxisLabelChrome.tickLength, 2)
        XCTAssertLessThan(AxisLabelChrome.tickLength, 12)

        let width = 200
        let height = 80
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return XCTFail("bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return XCTFail("context")
        }
        NSGraphicsContext.current = context
        let fill = NSColor(srgbRed: 1, green: 0.45, blue: 0.05, alpha: 1)
        fill.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        AxisLabelChrome.drawLabel("800", textOrigin: NSPoint(x: 28, y: 34), in: host)
        AxisLabelChrome.drawTick(from: NSPoint(x: 8, y: 40), to: NSPoint(x: 8 + AxisLabelChrome.tickLength, y: 40))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        func sample(_ x: Int, _ y: Int) -> NSColor? {
            rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
        }
        guard let corner = sample(width - 2, 2) else { return XCTFail("pixels") }
        XCTAssertGreaterThan(corner.redComponent, 0.9)
        var darkened = 0
        var sawPartial = false
        var sawTick = false
        for y in 0..<height {
            for x in 0..<width {
                guard let color = sample(x, y) else { continue }
                let redDrop = corner.redComponent - color.redComponent
                if redDrop > 0.08 {
                    darkened += 1
                }
                if redDrop > 0.05 && redDrop < 0.45 {
                    sawPartial = true
                }
                if x < 22,
                   color.blueComponent > corner.blueComponent + 0.2,
                   color.greenComponent > corner.greenComponent + 0.15 {
                    sawTick = true
                }
            }
        }
        XCTAssertGreaterThan(darkened, 12)
        XCTAssertLessThan(darkened, (width * height) / 2)
        XCTAssertTrue(sawPartial)
        XCTAssertTrue(sawTick)
    }

    func testTimeTicksForAShortFileAndAnHourDoNotOverlap() throws {
        XCTAssertFalse(SettingsBlob.factory.showTimeAxis)
        let data = try JSONEncoder().encode(SettingsBlob.factory)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "showTimeAxis")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SettingsBlob.self, from: stripped)
        XCTAssertFalse(decoded.showTimeAxis)

        let widths: [CGFloat] = [120, 280, 860, 1400]
        for width in widths {
            let shortStep = TimeAxisTicks.step(duration: 10, width: width)
            let longStep = TimeAxisTicks.step(duration: 3600, width: width)
            XCTAssertGreaterThan(longStep, shortStep * 8, "width \(width)")
            XCTAssertGreaterThanOrEqual(longStep, 10, "width \(width)")
            assertTimeLabelsFit(TimeAxisTicks.layout(width: width, duration: 10), width: width)
            assertTimeLabelsFit(TimeAxisTicks.layout(width: width, duration: 3600), width: width)
        }
        XCTAssertLessThan(TimeAxisTicks.step(duration: 10, width: 860), 1)
        XCTAssertGreaterThanOrEqual(TimeAxisTicks.step(duration: 3600, width: 4000), 10)

        let pane = SlipPaneView(frame: NSRect(x: 0, y: 0, width: 860, height: 140))
        pane.setTimeAxis(shown: false, duration: 10)
        XCTAssertTrue(pane.timeTickLabels.isEmpty)
        pane.setTimeAxis(shown: true, duration: 10)
        let wide = pane.timeTickLabels
        XCTAssertFalse(wide.isEmpty)
        pane.setFrameSize(NSSize(width: 160, height: 140))
        XCTAssertNotEqual(pane.timeTickLabels, wide)
        pane.beginStretch()
        let draws = pane.drawCount
        pane.setFrameSize(NSSize(width: 420, height: 180))
        pane.needsDisplay = true
        pane.displayIfNeeded()
        XCTAssertEqual(pane.drawCount, draws)
        pane.endStretch()
        XCTAssertFalse(pane.isStretching)
    }

    func testSplitDragWritesTheSettingsFractionIncludingTheSnap() {
        let slip = makeSlip()
        slip.applySplitDragForTest(rawFraction: 0.25)
        XCTAssertEqual(slipStore?.blob.splitFraction ?? -1, SplitSnap.value(0.25), accuracy: 0.0001)
        XCTAssertEqual(slip.splitFraction, slipStore?.blob.splitFraction ?? -1, accuracy: 0.0001)
        slip.applySplitDragForTest(rawFraction: 0.49)
        XCTAssertEqual(slipStore?.blob.splitFraction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(slip.splitFraction, 0.5, accuracy: 0.0001)
        slip.applySplitDragForTest(rawFraction: 0.51)
        XCTAssertEqual(slipStore?.blob.splitFraction ?? -1, SplitSnap.value(0.51), accuracy: 0.0001)
        XCTAssertEqual(slip.splitFraction, slipStore?.blob.splitFraction ?? -1, accuracy: 0.0001)
    }

    func testPlayingSeekDoesNotStopTheEngineBeforeScheduling() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-seek-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 44_100 * 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        playback.setGain(0)
        XCTAssertNotNil(playback.open(url: url))
        playback.toggle()
        let started = Date()
        while playback.position < 0.3, Date().timeIntervalSince(started) < 2 {
            CFRunLoopRunInMode(.defaultMode, 0.05, false)
            playback.refreshPosition()
        }
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.engine.isRunning)
        let stops = playback.engineStopCount
        let starts = playback.playStartCount

        playback.seek(toFraction: 0.4)
        XCTAssertEqual(playback.engineStopCount, stops)
        XCTAssertTrue(playback.engine.isRunning)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.playStartCount, starts + 1)

        playback.beginScrub(toFraction: 0.25)
        playback.endScrub(toFraction: 0.25)
        XCTAssertTrue(playback.isPlaying, playback.clockDescription)
        XCTAssertTrue(playback.engine.isRunning)
        XCTAssertEqual(playback.engineStopCount, stops)

        playback.beginScrub(toFraction: 0.2)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertTrue(playback.engine.isRunning)
        XCTAssertEqual(playback.engineStopCount, stops)
        let during = playback.playStartCount
        playback.moveScrub(toFraction: 0.45)
        playback.moveScrub(toFraction: 0.62)
        XCTAssertEqual(playback.playStartCount, during)
        XCTAssertEqual(playback.engineStopCount, stops)
        XCTAssertFalse(playback.isPlaying)
        playback.endScrub(toFraction: 0.62)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.engine.isRunning)
        XCTAssertEqual(playback.engineStopCount, stops)
        XCTAssertEqual(playback.playStartCount, during + 1)

        let seekAt = playback.position
        var previous = seekAt
        let after = Date()
        while Date().timeIntervalSince(after) < 0.35 {
            CFRunLoopRunInMode(.defaultMode, 0.05, false)
            playback.refreshPosition()
            XCTAssertGreaterThan(playback.position, previous - 0.08, playback.clockDescription)
            XCTAssertLessThan(playback.position, previous + 0.4, playback.clockDescription)
            previous = playback.position
        }
        XCTAssertGreaterThan(playback.position, seekAt + 0.05, playback.clockDescription)
        playback.stop()
    }

    private func assertTimeLabelsFit(_ ticks: [TimeAxisTicks.Tick], width: CGFloat) {
        let font = TimeAxisTicks.labelFont
        var previousRight = -CGFloat.greatestFiniteMagnitude
        for tick in ticks where !tick.label.isEmpty {
            let textWidth = ceil((tick.label as NSString).size(withAttributes: [.font: font]).width)
            let left = tick.centerX - textWidth / 2
            let right = left + textWidth
            XCTAssertGreaterThanOrEqual(left, 0.5, tick.label)
            XCTAssertLessThanOrEqual(right, width - 0.5, tick.label)
            XCTAssertGreaterThanOrEqual(left, previousRight + 4, tick.label)
            previousRight = right
        }
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
