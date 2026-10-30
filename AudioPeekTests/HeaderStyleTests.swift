import AppKit
import XCTest
@testable import AudioPeek

@MainActor
final class HeaderStyleTests: XCTestCase {
    private func makeView(width: CGFloat = 860, height: CGFloat = 500) -> SlipContentView {
        let view = SlipContentView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testHeaderUsesSystemColorsAndTheAccentForLoopOn() {
        let view = makeView()
        XCTAssertEqual(view.filenameLabel.textColor, .labelColor)
        XCTAssertEqual(view.metadataLabel.textColor, .secondaryLabelColor)
        XCTAssertEqual(view.playButton.contentTintColor, .labelColor)
        XCTAssertEqual(view.gearButton.contentTintColor, .secondaryLabelColor)
        view.setLoop(true)
        XCTAssertEqual(view.loopButton.contentTintColor, .controlAccentColor)
        view.setLoop(false)
        XCTAssertEqual(view.loopButton.contentTintColor, .secondaryLabelColor)
        view.appearance = NSAppearance(named: .darkAqua)
        view.applyPalette()
        XCTAssertEqual(view.filenameLabel.textColor, .labelColor, "dynamic colors survive an appearance flip")
    }

    func testVolumeSliderDrawsItsOwnAccentFill() throws {
        let view = makeView()
        XCTAssertTrue(view.volumeSlider.cell is AccentSliderCell)
        XCTAssertNil(view.volumeSlider.trackFillColor)

        let slider = NSSlider(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        slider.cell = AccentSliderCell()
        slider.controlSize = .small
        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = 0.9
        let rep = try XCTUnwrap(slider.bitmapImageRepForCachingDisplay(in: slider.bounds))
        slider.cacheDisplay(in: slider.bounds, to: rep)
        let accent = try XCTUnwrap(NSColor.controlAccentColor.usingColorSpace(.sRGB))
        // Look along the filled part of the track for a pixel close to the accent color.
        var best = CGFloat.greatestFiniteMagnitude
        for x in stride(from: 4, to: 40, by: 2) {
            for y in 0..<rep.pixelsHigh {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.9 else { continue }
                let distance = abs(color.redComponent - accent.redComponent)
                    + abs(color.greenComponent - accent.greenComponent)
                    + abs(color.blueComponent - accent.blueComponent)
                best = min(best, distance)
            }
        }
        XCTAssertLessThan(best, 0.12, "no accent-colored fill found in the track")
    }

    func testHeaderIsTallerAndControlsShareItsCenter() {
        let view = makeView()
        let mid = SlipLayout.headerHeight / 2
        for control in [view.playButton, view.loopButton, view.gearButton] {
            XCTAssertEqual(control.frame.height, 28)
            XCTAssertEqual(control.frame.midY, mid, accuracy: 0.5)
        }
        XCTAssertEqual(view.volumeSlider.frame.midY, mid, accuracy: 0.5)
        XCTAssertEqual(view.hitKind(at: NSPoint(x: 200, y: 40)), "header")
        XCTAssertEqual(view.hitKind(at: NSPoint(x: 200, y: 120)), "waveform")
    }

    func testTheTimeStaysVisibleAtEveryWidth() throws {
        for width in [420.0, 640.0, 860.0] {
            let view = makeView(width: width)
            view.filenameLabel.stringValue = "A Deliberately Long File Name For Truncation Checks.wav"
            view.metadataLabel.stringValue = "WAV · 44.1 kHz · 2 ch · 0:05 / 84:40"
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            let cell = try XCTUnwrap(view.metadataLabel.cell as? MetadataCell)
            let timeOnly = cell.fittingWidth(within: 0)
            XCTAssertGreaterThanOrEqual(view.metadataLabel.frame.width + 0.5, timeOnly, "time cut at \(width)")
            XCTAssertLessThanOrEqual(view.metadataLabel.frame.maxX, view.volumeSlider.frame.minX)
        }
    }

    func testSplitDragRoundTripsThroughTheLayout() {
        for inset in [CGFloat(0), 12] {
            let layout = SlipLayout(size: NSSize(width: 860, height: 500), inset: inset, gap: inset == 0 ? 1 : 6)
            for split in [0.3, 0.5, 0.7] {
                let divider = layout.panes(waveform: true, spectrogram: true, split: split).divider!
                XCTAssertEqual(layout.splitFraction(atY: divider.midY), split, accuracy: 0.005, "inset \(inset) split \(split)")
            }
        }
    }
}
