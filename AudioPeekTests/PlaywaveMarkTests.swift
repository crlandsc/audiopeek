import AppKit
import ImageIO
import XCTest
@testable import AudioPeek

final class PlaywaveMarkTests: XCTestCase {
    func testLockedIconMatchesTheCommittedArtwork() throws {
        let drawn = PlaywaveMark.iconImage(side: 400)
        let leftBar = rgba(drawn, x: 115, y: 200)
        let gap = rgba(drawn, x: 140, y: 200)
        let outside = rgba(drawn, x: 40, y: 200)
        let tip = rgba(drawn, x: 285, y: 200)

        XCTAssertTrue(isBlue(leftBar), "left bar \(leftBar)")
        XCTAssertTrue(isBlue(tip), "tip \(tip)")
        XCTAssertTrue(isBackground(gap), "gap \(gap)")
        XCTAssertTrue(isBackground(outside), "outside \(outside)")
        XCTAssertEqual(PlaywaveMark.menuBarImage().size, NSSize(width: 18, height: 18))
        XCTAssertTrue(PlaywaveMark.menuBarImage().isTemplate)

        let committed = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../AudioPeek/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png")
        let bytes = try Data(contentsOf: committed)
        let source = CGImageSourceCreateWithData(bytes as CFData, nil)
        let fileImage = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        let saved = try XCTUnwrap(fileImage)
        XCTAssertEqual(saved.width, 64)
        XCTAssertEqual(saved.height, 64)
        let fresh = PlaywaveMark.iconImage(side: 64)
        let filed = redraw(saved, side: 64)
        var mismatch: String?
        compare: for y in 0..<64 {
            for x in 0..<64 {
                let a = rgba(fresh, x: x, y: y)
                let b = rgba(filed, x: x, y: y)
                for channel in 0..<4 where abs(Int(a[channel]) - Int(b[channel])) > 1 {
                    mismatch = "\(x),\(y) \(a) \(b)"
                    break compare
                }
            }
        }
        XCTAssertNil(mismatch)
    }

    private func redraw(_ image: CGImage, side: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }

    private func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]]
    }

    private func isBlue(_ pixel: [UInt8]) -> Bool {
        pixel[0] < 30 && pixel[1] > 110 && pixel[2] > 230
    }

    private func isBackground(_ pixel: [UInt8]) -> Bool {
        pixel[0] > 230 && pixel[1] > 230 && pixel[2] > 230
    }
}
