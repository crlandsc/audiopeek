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

    func testResizeZonesHaveRoomyCornersAndLeaveHeaderButtonsClickable() {
        let view = SlipContentView(frame: NSRect(x: 0, y: 0, width: 1580, height: 644))
        view.layout()
        let bounds = view.bounds
        // The corner grab that landed 1.4 pt outside the old 8 pt right band.
        XCTAssertEqual(SlipResize.edges(at: NSPoint(x: 1570.6, y: 640), in: bounds), SlipResizeEdges(right: true, bottom: true))
        XCTAssertEqual(SlipResize.edges(at: NSPoint(x: 1575, y: 630), in: bounds), SlipResizeEdges(right: true, bottom: true))
        XCTAssertEqual(SlipResize.edges(at: NSPoint(x: 1560, y: 640), in: bounds), SlipResizeEdges(right: true, bottom: true))
        XCTAssertEqual(SlipResize.edges(at: NSPoint(x: 1575, y: 300), in: bounds), SlipResizeEdges(right: true))
        XCTAssertEqual(SlipResize.edges(at: NSPoint(x: 9, y: 300), in: bounds), SlipResizeEdges(left: true))
        XCTAssertFalse(SlipResize.edges(at: NSPoint(x: 11, y: 300), in: bounds).isActive)
        for control in [view.playButton, view.gearButton] {
            let point = NSPoint(x: control.frame.midX, y: control.frame.minY + 1)
            XCTAssertTrue(SlipResize.edges(at: point, in: bounds).isActive)
            XCTAssertFalse(view.resizeEdges(at: point).isActive)
            XCTAssertNil(view.resizeCursor(at: point))
        }
    }

    func testHoverHighlightsTheGrabZoneEvenWhileAnotherAppIsFront() {
        let view = SlipContentView(frame: NSRect(x: 0, y: 0, width: 860, height: 500))
        view.layout()
        XCTAssertEqual(view.resizeHighlight.frame, view.bounds)
        let checks: [(NSPoint, Bool, SlipResizeEdges)] = [
            (NSPoint(x: 856, y: 250), true, SlipResizeEdges(right: true)),
            (NSPoint(x: 856, y: 490), true, SlipResizeEdges(right: true, bottom: true)),
            (NSPoint(x: 430, y: 250), true, SlipResizeEdges()),
            (NSPoint(x: 856, y: 250), false, SlipResizeEdges()),
            (NSPoint(x: view.playButton.frame.midX, y: view.playButton.frame.minY + 1), true, SlipResizeEdges())
        ]
        for (point, panelHit, edges) in checks {
            view.updateResizeHighlight(at: point, panelHit: panelHit)
            XCTAssertEqual(view.resizeHighlight.edges, edges, "\(point) panelHit=\(panelHit)")
        }
        view.updateResizeHighlight(at: NSPoint(x: 3, y: 250), panelHit: true)
        XCTAssertFalse(view.hitTest(NSPoint(x: 3, y: 250)) === view.resizeHighlight)
        XCTAssertFalse(view.resizeHighlight.isAccessibilityElement())
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
        try writeWav(to: url, frames: 44_100 * 8)
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

    func testASettingsChangeRightAfterAResizeKeepsTheNewSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-snap-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 44_100 * 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let slip = makeSlip()
        let store = try XCTUnwrap(slipStore)
        store.onChange = { [weak slip] in slip?.applySettings() }
        slip.setInjectedLoad(thermal: "nominal", cpu: 0.1, applyNow: false)
        slip.openFiles([url])
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, slip.panelsMade == 0 {
            CFRunLoopRunInMode(.defaultMode, 0.05, false)
        }
        let start = slip.frame
        slip.beginResizeInteraction()
        slip.resizePanelForTest(NSRect(x: start.origin.x, y: start.origin.y, width: start.width + 300, height: start.height))
        slip.endResizeInteraction()
        store.update { $0.loopEnabled.toggle() }
        XCTAssertEqual(slip.frame.width, start.width + 300, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(store.blob.windowFrame).width, start.width, accuracy: 0.5)

        store.update {
            $0.windowFrame = StoredWindowFrame(x: start.origin.x, y: start.origin.y, width: 700, height: 400)
        }
        XCTAssertEqual(slip.frame.width, 700, accuracy: 0.5)
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

    func testStretchOnScreenUsesAnImageThatScalesWithThePane() throws {
        let pane = SlipPaneView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        let window = NSWindow(
            contentRect: pane.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = pane
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        pane.displayIfNeeded()
        CFRunLoopRunInMode(.defaultMode, 0.1, false)
        XCTAssertNotNil(pane.layer?.contents)
        // AppKit's own backing store does not scale when the pane grows, which
        // showed a gray box. The stretch has to hold a plain image.
        pane.beginStretch()
        let contents = try XCTUnwrap(pane.layer?.contents)
        XCTAssertEqual(CFGetTypeID(contents as CFTypeRef), CGImage.typeID)
        XCTAssertEqual(pane.layer?.contentsGravity, .resize)
        let drawn = pane.drawCount
        pane.setFrameSize(NSSize(width: 480, height: 200))
        pane.displayIfNeeded()
        XCTAssertEqual(pane.drawCount, drawn)
        XCTAssertTrue(pane.layer?.contents as AnyObject === contents as AnyObject)
        pane.endStretch()
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
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertTrue(window.acceptsMouseMovedEvents)
        XCTAssertTrue(view.hoverPollIsRunning)
        XCTAssertEqual(view.hoverPollInterval, 1.0 / 60.0, accuracy: 0.001)
        XCTAssertTrue(view.trackingAreas.contains { area in
            area.options.contains(.mouseMoved) && area.options.contains(.activeAlways)
        })
        for (point, cursor) in checks {
            XCTAssertTrue(view.hoverCursor(at: point, panelHit: true) === cursor)
        }
        XCTAssertTrue(view.hoverCursor(at: split, panelHit: true) === NSCursor.resizeUpDown)
        XCTAssertTrue(view.hoverCursor(at: NSPoint(x: 430, y: 200), panelHit: true) === NSCursor.arrow)
        XCTAssertNil(view.hoverCursor(at: NSPoint(x: 3, y: 250), panelHit: false))
        XCTAssertNil(view.hoverCursor(at: NSPoint(x: -4, y: 250), panelHit: true))
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

    func testDividerDoubleClickResetsTheSplitToHalf() {
        let slip = makeSlip()
        slip.applySplitDragForTest(rawFraction: 0.25)
        XCTAssertEqual(slip.splitFraction, SplitSnap.value(0.25), accuracy: 0.0001)
        XCTAssertNotEqual(slip.splitFraction, 0.5, accuracy: 0.02)
        XCTAssertTrue(slip.dividerClickForTest(clickCount: 2))
        XCTAssertEqual(slip.splitFraction, SettingsBlob.factory.splitFraction, accuracy: 0.0001)
        XCTAssertEqual(slip.splitFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(slipStore?.blob.splitFraction ?? -1, 0.5, accuracy: 0.0001)
    }

    func testAxisUnitsAvoidTickLabels() {
        XCTAssertEqual(FrequencyAxisTicks.unitText, "Hz")
        XCTAssertEqual(TimeAxisTicks.unitText(duration: 10), "s")
        XCTAssertEqual(TimeAxisTicks.unitText(duration: 197), "min:sec")
        XCTAssertEqual(TimeAxisTicks.unitText(duration: 3600), "h:mm:ss")
        XCTAssertFalse(FrequencyAxisTicks.format(22050).contains("Hz"))
        XCTAssertFalse(TimeAxisTicks.format(20, step: 1).contains("s"))

        for height in [CGFloat(140), 360] {
            let ticks = FrequencyAxisTicks.layout(height: height, nyquist: 22_050)
            var previous = -CGFloat.greatestFiniteMagnitude
            for tick in ticks {
                XCTAssertGreaterThanOrEqual(tick.centerY - previous, FrequencyAxisTicks.minSeparation - 0.01, tick.label)
                previous = tick.centerY
            }
            let area = NSRect(x: 0, y: 0, width: 860, height: height)
            let unit = FrequencyAxisTicks.placedUnit(ticks: ticks, in: area)
            XCTAssertEqual(unit?.text, "Hz")
            if let unit {
                assertUnitClearsLabels(unit.frame, ticks.map { FrequencyAxisTicks.labelFrame(for: $0, in: area) }, area: area)
            }
        }
        XCTAssertNil(FrequencyAxisTicks.placedUnit(
            ticks: [FrequencyAxisTicks.Tick(hertz: 22_050, centerY: 8, label: "22.1k")],
            in: NSRect(x: 0, y: 0, width: 4, height: 20)
        ))

        for width in [CGFloat(280), 860] {
            let ticks = TimeAxisTicks.layout(width: width, duration: 10)
            assertTimeLabelsFit(ticks, width: width)
            let pane = NSRect(x: 0, y: 0, width: width, height: 120)
            let tickTop = pane.maxY - 2 - AxisLabelChrome.tickLength
            let unit = TimeAxisTicks.placedUnit(ticks: ticks, duration: 10, pane: pane, tickTop: tickTop)
            XCTAssertEqual(unit?.text, "s")
            if let unit {
                let labels = ticks.compactMap { TimeAxisTicks.labelFrame(for: $0, width: width, tickTop: tickTop) }
                assertUnitClearsLabels(unit.frame, labels, area: pane)
            }
            let longTicks = TimeAxisTicks.layout(width: width, duration: 3600)
            assertTimeLabelsFit(longTicks, width: width)
            let longUnit = TimeAxisTicks.placedUnit(ticks: longTicks, duration: 3600, pane: pane, tickTop: tickTop)
            XCTAssertEqual(longUnit?.text, "h:mm:ss")
        }

        let crowded = TimeAxisTicks.placedUnit(
            ticks: [
                TimeAxisTicks.Tick(seconds: 0, centerX: 12, label: "0:00"),
                TimeAxisTicks.Tick(seconds: 60, centerX: 28, label: "1:00")
            ],
            duration: 90,
            pane: NSRect(x: 0, y: 0, width: 20, height: 18),
            tickTop: 16
        )
        XCTAssertNil(crowded)
    }

    func testSpectrogramLabelDrawingIsClippedToThePane() {
        XCTAssertLessThanOrEqual(AxisLabelChrome.fadePadding, 4)
        XCTAssertGreaterThan(AxisLabelChrome.fadePadding, 0.5)

        let width = 160
        let height = 120
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
        let pane = SlipPaneView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let clip = NSRect(x: 0, y: 24, width: CGFloat(width), height: CGFloat(height - 24))
        let origin = NSPoint(x: 28, y: 20)
        pane.drawSpectrogramAxisChromeForTest(
            label: "22.1k",
            textOrigin: origin,
            tickStart: NSPoint(x: 8, y: 32),
            tickEnd: NSPoint(x: 8, y: 10),
            clip: clip
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        func sample(_ x: Int, _ y: Int) -> NSColor? {
            rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
        }
        guard let crossed = sample(40, 18), let tickCross = sample(8, 14), let corner = sample(width - 2, 2) else {
            return XCTFail("pixels")
        }
        XCTAssertGreaterThan(crossed.redComponent, 0.9, "22.1k fade crossed the pane edge")
        XCTAssertGreaterThan(tickCross.redComponent, 0.9, "tick crossed the pane edge")
        XCTAssertGreaterThan(corner.redComponent, 0.9)

        let glyphs = NSRect(origin: origin, size: AxisLabelChrome.glyphSize(of: "22.1k"))
        var painted = 0
        var outside = 0
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        for y in 0..<height {
            for x in 0..<width {
                guard let color = sample(x, y) else { continue }
                let redDrop = corner.redComponent - color.redComponent
                guard redDrop > 0.08 else { continue }
                painted += 1
                if CGFloat(y) < clip.minY - 1 || CGFloat(x) < clip.minX - 1 || CGFloat(y) > clip.maxY + 1 {
                    outside += 1
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        XCTAssertGreaterThan(painted, 8)
        XCTAssertEqual(outside, 0)
        let bounds = NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        XCTAssertLessThanOrEqual(bounds.width, glyphs.width + AxisLabelChrome.fadePadding * 2 + 8)
        XCTAssertLessThanOrEqual(bounds.height, glyphs.height + AxisLabelChrome.fadePadding * 2 + 8)
    }

    func testPlayheadTimeTextUpdatesWhenPositionChanges() throws {
        XCTAssertEqual(
            AudioFileKind.metadataLine(format: "WAV", sampleRate: 44_100, channels: 1, duration: 197, position: 20),
            "WAV · 44.1 kHz · 1 ch · 0:20 / 3:17"
        )
        XCTAssertEqual(
            AudioFileKind.metadataLine(format: "WAV", sampleRate: 44_100, channels: 1, duration: 197, position: 0),
            "WAV · 44.1 kHz · 1 ch · 0:00 / 3:17"
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-clock-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 44_100 * 10)
        defer { try? FileManager.default.removeItem(at: url) }
        let slip = makeSlip()
        slip.setInjectedLoad(thermal: "nominal", cpu: 0.1, applyNow: false)
        slip.setOverviewStall(true)
        let read = try XCTUnwrap(PlaybackController.readFile(at: url))
        slip.stageOpenForTest(url: url, generation: 1, panelUp: true)
        slip.deliverOpenForTest(url: url, generation: 1, read: read)
        XCTAssertTrue(slip.metadata.contains("0:00 / 0:10"), slip.metadata)

        slip.applyScrubForTest(fraction: 0.2, phase: .began)
        XCTAssertTrue(slip.metadata.contains("0:02 / 0:10"), slip.metadata)
        slip.applyScrubForTest(fraction: 0.45, phase: .moved)
        XCTAssertTrue(slip.metadata.contains("0:04 / 0:10"), slip.metadata)
        slip.applyScrubForTest(fraction: 0.2, phase: .ended)
    }

    private func assertUnitClearsLabels(_ unit: NSRect, _ labels: [NSRect], area: NSRect) {
        XCTAssertGreaterThanOrEqual(unit.minX, area.minX - 0.01)
        XCTAssertLessThanOrEqual(unit.maxX, area.maxX + 0.01)
        XCTAssertGreaterThanOrEqual(unit.minY, area.minY - 0.01)
        XCTAssertLessThanOrEqual(unit.maxY, area.maxY + 0.01)
        for label in labels {
            XCTAssertFalse(label.insetBy(dx: -AxisMarkLayout.gap, dy: -AxisMarkLayout.gap).intersects(unit))
        }
    }

    func testSwitchingFilesKeepsTheAudioEngineRunning() throws {
        let first = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-switch-a-\(UUID().uuidString).wav")
        let second = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-switch-b-\(UUID().uuidString).wav")
        try writeWav(to: first, frames: 44_100 * 2)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        try AVAudioFile(forWriting: second, settings: format.settings).write(from: buffer)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let playback = PlaybackController()
        playback.setGain(0)
        XCTAssertNotNil(playback.open(url: first))
        playback.toggle()
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.engine.isRunning)
        let stops = playback.engineStopCount

        playback.unload()
        playback.install(try XCTUnwrap(PlaybackController.readFile(at: second)))
        XCTAssertTrue(playback.engine.isRunning)
        playback.applyGate(allows: true)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.engineStopCount, stops)

        playback.stop()
        XCTAssertFalse(playback.engine.isRunning)
    }

    func testPauseCloseAndTheEndOfAFileKeepTheEngineWarmBriefly() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-warm-\(UUID().uuidString).wav")
        let short = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-warm-short-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 44_100 * 4)
        try writeWav(to: short, frames: 44_100 / 4)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: short)
        }
        func wait(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
        let playback = PlaybackController()
        playback.warmEngineTimeout = 0.3
        playback.setGain(0)
        XCTAssertNotNil(playback.open(url: url))
        playback.toggle()
        XCTAssertTrue(playback.engine.isRunning)
        let stops = playback.engineStopCount

        // A pause keeps the engine running, so playing again inside the window starts warm.
        playback.toggle()
        XCTAssertFalse(playback.isPlaying)
        XCTAssertTrue(playback.engine.isRunning)
        wait(0.1)
        playback.toggle()
        XCTAssertTrue(playback.isPlaying)
        wait(0.5)
        XCTAssertTrue(playback.engine.isRunning)
        XCTAssertEqual(playback.engineStopCount, stops)

        // Left paused, the engine stops once the window runs out.
        playback.toggle()
        wait(0.5)
        XCTAssertFalse(playback.engine.isRunning)
        XCTAssertEqual(playback.engineStopCount, stops + 1)

        // Closing the panel works the same way.
        playback.toggle()
        XCTAssertTrue(playback.engine.isRunning)
        playback.stopKeepingEngineWarm()
        XCTAssertFalse(playback.isPlaying)
        XCTAssertTrue(playback.engine.isRunning)
        wait(0.5)
        XCTAssertFalse(playback.engine.isRunning)

        // So does a file that plays to its end.
        let ending = PlaybackController()
        ending.warmEngineTimeout = 0.3
        ending.setGain(0)
        XCTAssertNotNil(ending.open(url: short))
        ending.toggle()
        let started = Date()
        while ending.isPlaying, Date().timeIntervalSince(started) < 2 {
            wait(0.05)
            ending.refreshPosition()
        }
        XCTAssertFalse(ending.isPlaying)
        XCTAssertTrue(ending.engine.isRunning)
        wait(0.5)
        XCTAssertFalse(ending.engine.isRunning)
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
