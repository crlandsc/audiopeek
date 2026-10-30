import AppKit
import XCTest
@testable import AudioPeek

@MainActor
final class GlassPanelTests: XCTestCase {
    private func makeView(width: CGFloat = 860, height: CGFloat = 500) -> SlipContentView {
        let view = SlipContentView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testPanesAreInsetCardsClearOfEveryGrabZone() {
        let view = makeView()
        XCTAssertGreaterThanOrEqual(SlipLayout.rim, SlipResize.margin, "a click at the start of the waveform must seek, not resize")
        let wave = view.waveformPane.frame
        let spec = view.spectrogramPane.frame
        XCTAssertEqual(wave.minX, SlipLayout.rim)
        XCTAssertEqual(view.bounds.maxX - wave.maxX, SlipLayout.rim)
        XCTAssertEqual(view.bounds.maxY - spec.maxY, SlipLayout.rim)
        XCTAssertEqual(spec.minY - wave.maxY, SlipLayout.paneGap, accuracy: 0.01)
        for pane in [view.waveformPane, view.spectrogramPane] {
            XCTAssertTrue(pane.layer?.masksToBounds ?? false)
            XCTAssertEqual(pane.layer?.cornerRadius, SlipLayout.paneRadius)
            XCTAssertEqual(pane.layer?.cornerCurve, .continuous)
        }
        for x in stride(from: wave.minX, through: wave.maxX, by: 4) {
            for y in stride(from: wave.minY, through: spec.maxY, by: 4) {
                XCTAssertFalse(view.resizeEdges(at: NSPoint(x: x, y: y)).isActive, "(\(x), \(y)) inside the panes resizes")
            }
        }
    }

    func testGlassDropsOurBackgroundAndTheSolidFallbackKeepsIt() {
        let view = makeView()
        view.usesGlass = true
        XCTAssertNil(view.layer?.backgroundColor)
        XCTAssertEqual(view.layer?.borderWidth, 0)
        view.appearance = NSAppearance(named: .darkAqua)
        view.applyPalette()
        XCTAssertNil(view.layer?.backgroundColor, "an appearance change must not bring the background back")
        view.usesGlass = false
        XCTAssertNotNil(view.layer?.backgroundColor)
        XCTAssertEqual(view.layer?.borderWidth, 1)
        XCTAssertEqual(view.layer?.cornerRadius, SlipLayout.cornerRadius)
        XCTAssertEqual(view.layer?.cornerCurve, .continuous)
    }

    func testCutAwayCornersAreNotGrabAreas() {
        let bounds = NSRect(x: 0, y: 0, width: 860, height: 500)
        XCTAssertFalse(SlipResize.edges(at: NSPoint(x: 1, y: 1), in: bounds).isActive)
        XCTAssertFalse(SlipResize.edges(at: NSPoint(x: 859, y: 499), in: bounds).isActive)
        XCTAssertTrue(SlipResize.edges(at: NSPoint(x: 6, y: 6), in: bounds).isActive)
        XCTAssertEqual(SlipResize.cornerLength, max(20, SlipLayout.cornerRadius + 8))
    }

    func testGlassContentFollowsTheGlassFrame() throws {
        guard #available(macOS 26, *) else { throw XCTSkip("Liquid Glass needs macOS 26") }
        let view = makeView()
        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: 860, height: 500))
        view.frame = glass.bounds
        view.autoresizingMask = [.width, .height]
        glass.contentView = view
        glass.setFrameSize(NSSize(width: 640, height: 320))
        glass.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.size, glass.bounds.size)
        let window = SlipWindow(contentRect: glass.frame, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = glass
        window.slipContent = view
        view.layoutSubtreeIfNeeded()
        let header = NSPoint(x: 300, y: 20)
        let inPane = NSPoint(x: 300, y: view.waveformPane.frame.midY)
        XCTAssertTrue(glass.hitTest(view.convert(header, to: glass)) === view)
        let paneHit = glass.hitTest(view.convert(inPane, to: glass))
        XCTAssertTrue(paneHit === view.waveformPane || paneHit?.isDescendant(of: view.waveformPane) == true)
    }

    func testRimGlowFollowsThePointerSmoothlyAllTheWayAround() {
        let view = makeView()
        let highlight = view.resizeHighlight
        // A path 5pt inside the panel edge, all the way around: always on the rim.
        let path = SlipResizeHighlight.outline(of: view.bounds.insetBy(dx: 5, dy: 5), radius: SlipLayout.cornerRadius - 5)
        let length = CGFloat(SlipResizeHighlight.outline(of: view.bounds, radius: SlipLayout.cornerRadius).count)
        var previous: CGFloat?
        var gaps = 0
        var biggestStep: CGFloat = 0
        for point in path {
            let isControl = [view.playButton, view.volumeSlider, view.loopButton, view.gearButton].contains { $0.frame.contains(point) }
            if isControl { previous = nil; continue }
            view.updateResizeHighlight(at: point, panelHit: true)
            if !highlight.edges.isActive { gaps += 1 }
            guard let position = highlight.position else { continue }
            if let previous {
                var step = abs(position - previous)
                step = min(step, length - step)
                biggestStep = max(biggestStep, step)
            }
            previous = position
        }
        XCTAssertEqual(gaps, 0, "the rim has spots where the panel cannot be grabbed")
        XCTAssertLessThanOrEqual(biggestStep, 3, "the glow jumps instead of gliding")
        view.updateResizeHighlight(at: NSPoint(x: 430, y: 250), panelHit: true)
        XCTAssertFalse(highlight.edges.isActive)
        XCTAssertEqual(highlight.intensity, 0, "off the rim the glow goes away")
    }

    func testRimGlowLightsOnlyTheRim() throws {
        let view = makeView()
        let highlight = view.resizeHighlight
        view.updateResizeHighlight(at: NSPoint(x: 5, y: 250), panelHit: true)
        XCTAssertEqual(highlight.intensity, 1)
        let rep = try XCTUnwrap(highlight.bitmapImageRepForCachingDisplay(in: highlight.bounds))
        highlight.cacheDisplay(in: highlight.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / highlight.bounds.width
        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? 0
        }
        XCTAssertGreaterThan(alpha(1.5, 250), 0.05, "the rim next to the pointer is lit")
        XCTAssertEqual(alpha(SlipLayout.rim + 2, 250), 0, "nothing is drawn on the waveform card")
        XCTAssertEqual(alpha(1.5, 250 + SlipResizeHighlight.poolRadius + 10), 0, "the glow stays a pool around the pointer")
    }
}
