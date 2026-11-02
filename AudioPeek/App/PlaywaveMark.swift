import AppKit

/// The eye mark: an outlined eye whose iris is a short waveform.
/// Canvas is 400 units. The eye's corners sit at x 44 and 356 on the midline, and each lid is a
/// quadratic curve with its control 184 units above or below. Lids are a 26 unit round-joined stroke.
/// Seven round-capped bars 18.4 wide, 25.6 apart, step down evenly from the middle.
enum PlaywaveMark {
    static let canvas: CGFloat = 400
    static let menuBarPointSize: CGFloat = 18
    static let iconBlue = CGColor(srgbRed: 10.0 / 255, green: 132.0 / 255, blue: 1, alpha: 1)
    static let iconBackground = CGColor(srgbRed: 243.0 / 255, green: 243.0 / 255, blue: 245.0 / 255, alpha: 1)

    private static let cornerInset: CGFloat = 44
    private static let lidReach: CGFloat = 184
    private static let lidWidth: CGFloat = 26
    private static let barHeights: [CGFloat] = [24, 51, 78, 104, 78, 51, 24]
    private static let barWidth: CGFloat = 18.4
    private static let barStep: CGFloat = 25.6
    /// The icon draws the 400 canvas inside this fraction of its side, centered.
    private static let iconFill: CGFloat = 0.84

    /// The eye's drawn bounds on the canvas, lid stroke included.
    private static var markBounds: CGRect {
        let half = lidWidth / 2
        let height = lidReach + lidWidth
        return CGRect(
            x: cornerInset - half,
            y: canvas / 2 - height / 2,
            width: canvas - cornerInset * 2 + lidWidth,
            height: height
        )
    }

    static func menuBarImage() -> NSImage {
        let side = menuBarPointSize
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            draw(in: ctx, rect: menuBarContentRect(filling: rect), color: black, background: nil)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AudioPeek"
        return image
    }

    /// Scales the 400 canvas so the eye's longer side fills the menu bar image.
    private static func menuBarContentRect(filling imageRect: CGRect) -> CGRect {
        let bounds = markBounds
        let span = max(bounds.width, bounds.height)
        let originX = bounds.midX - span / 2
        let originY = bounds.midY - span / 2
        let scaleX = imageRect.width / span
        let scaleY = imageRect.height / span
        return CGRect(
            x: imageRect.minX - originX * scaleX,
            y: imageRect.maxY + (originY - canvas) * scaleY,
            width: canvas * scaleX,
            height: canvas * scaleY
        )
    }

    static func iconImage(side: Int) -> CGImage {
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
        let full = CGRect(x: 0, y: 0, width: side, height: side)
        ctx.setFillColor(iconBackground)
        ctx.fill(full)
        let inset = CGFloat(side) * (1 - iconFill) / 2
        draw(in: ctx, rect: full.insetBy(dx: inset, dy: inset), color: iconBlue, background: nil)
        return ctx.makeImage()!
    }

    /// Blue eye, no plate, centered with a modest margin. This is the README image.
    static func readmeImage(side: Int) -> CGImage {
        let margin: CGFloat = 48
        let view = markBounds.width + margin * 2
        let origin = canvas / 2 - view / 2
        let scale = CGFloat(side) / view
        let fitted = CGRect(
            x: -origin * scale,
            y: CGFloat(side) + (origin - canvas) * scale,
            width: canvas * scale,
            height: canvas * scale
        )
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
        ctx.clear(CGRect(x: 0, y: 0, width: side, height: side))
        draw(in: ctx, rect: fitted, color: iconBlue, background: nil)
        return ctx.makeImage()!
    }

    static func draw(in ctx: CGContext, rect: CGRect, color: CGColor, background: CGColor?) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: rect.width / canvas, y: -rect.height / canvas)
        ctx.setShouldAntialias(true)
        if let background {
            ctx.setFillColor(background)
            ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        }
        ctx.setStrokeColor(color)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let mid = canvas / 2
        let left = cornerInset
        let right = canvas - cornerInset
        let lids = CGMutablePath()
        lids.move(to: CGPoint(x: left, y: mid))
        lids.addQuadCurve(to: CGPoint(x: right, y: mid), control: CGPoint(x: mid, y: mid - lidReach))
        lids.addQuadCurve(to: CGPoint(x: left, y: mid), control: CGPoint(x: mid, y: mid + lidReach))
        lids.closeSubpath()
        ctx.setLineWidth(lidWidth)
        ctx.addPath(lids)
        ctx.strokePath()

        ctx.setLineWidth(barWidth)
        let first = mid - CGFloat(barHeights.count - 1) / 2 * barStep
        for (index, height) in barHeights.enumerated() {
            let x = first + CGFloat(index) * barStep
            ctx.move(to: CGPoint(x: x, y: mid - height / 2))
            ctx.addLine(to: CGPoint(x: x, y: mid + height / 2))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}
