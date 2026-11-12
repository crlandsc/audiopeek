import AppKit

/// The eye mark: an outlined eye whose iris is a short waveform.
/// Canvas is 400 units. The eye's corners sit at x 44 and 356 on the midline, and each lid is a
/// quadratic curve with its control 184 units above or below. Lids are a 26 unit round-joined stroke.
/// Seven round-capped bars 18.4 wide, 31.2 apart. Their heights sit a quarter of the way from an even
/// step-down toward the eye's own curve, so the middle bar keeps a clear gap to the lid.
enum PlaywaveMark {
    static let canvas: CGFloat = 400
    static let menuBarPointSize: CGFloat = 18
    static let iconBlue = CGColor(srgbRed: 10.0 / 255, green: 132.0 / 255, blue: 1, alpha: 1)
    static let iconBackground = CGColor(srgbRed: 243.0 / 255, green: 243.0 / 255, blue: 245.0 / 255, alpha: 1)

    private static let cornerInset: CGFloat = 44
    private static let lidReach: CGFloat = 184
    private static let lidWidth: CGFloat = 26
    private static let barHeights: [CGFloat] = [27.4, 56.9, 82.7, 104, 82.7, 56.9, 27.4]
    private static let barWidth: CGFloat = 18.4
    private static let barStep: CGFloat = 31.2
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

    /// The dot drawn at the top right of the menu bar eye while an update is waiting.
    static let updateDotDiameter: CGFloat = 6

    /// The menu bar eye, as a template image so it follows light and dark menu bars.
    /// With `updateDot`, a small dot sits at the top right, cut clear of the eye.
    static func menuBarImage(updateDot: Bool = false) -> NSImage {
        let side = menuBarPointSize
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
            draw(in: ctx, rect: menuBarContentRect(filling: rect), color: black, background: nil)
            if updateDot {
                let dot = CGRect(
                    x: rect.maxX - updateDotDiameter,
                    y: rect.maxY - updateDotDiameter,
                    width: updateDotDiameter,
                    height: updateDotDiameter
                )
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: dot.insetBy(dx: -1.5, dy: -1.5))
                ctx.setBlendMode(.normal)
                ctx.setFillColor(black)
                ctx.fillEllipse(in: dot)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = updateDot ? "AudioPeek, update available" : "AudioPeek"
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

    /// Blue eye, no plate, cropped to the eye with a thin margin. This is the README image.
    static func readmeImage(width: Int) -> CGImage {
        let margin: CGFloat = 8
        let view = markBounds.insetBy(dx: -margin, dy: -margin)
        let scale = CGFloat(width) / view.width
        let height = Int((view.height * scale).rounded())
        let fitted = CGRect(
            x: -view.minX * scale,
            y: CGFloat(height) + (view.minY - canvas) * scale,
            width: canvas * scale,
            height: canvas * scale
        )
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
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
