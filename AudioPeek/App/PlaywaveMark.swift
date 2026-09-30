import AppKit

/// The play mark locked from the tuner.
/// Canvas is 400 units: height 230, left bar 40 wide with corners 11 and 7,
/// gap 12, three bars of width 22 and gap 12, gap 10, tip 40 wide with corners 7 and 11.
/// Rounded bar ends stay inside the triangle.
enum PlaywaveMark {
    static let canvas: CGFloat = 400
    static let menuBarPointSize: CGFloat = 18
    static let iconBlue = CGColor(srgbRed: 10.0 / 255, green: 132.0 / 255, blue: 1, alpha: 1)
    static let iconBackground = CGColor(srgbRed: 243.0 / 255, green: 243.0 / 255, blue: 245.0 / 255, alpha: 1)

    private static let playHeight: CGFloat = 230
    private static let leftWidth: CGFloat = 40
    private static let leftLeftRadius: CGFloat = 11
    private static let leftRightRadius: CGFloat = 7
    private static let gapAfterLeft: CGFloat = 12
    private static let barCount = 3
    private static let barWidth: CGFloat = 22
    private static let barGap: CGFloat = 12
    private static let rightWidth: CGFloat = 40
    private static let tipLeftRadius: CGFloat = 7
    private static let tipPointRadius: CGFloat = 11
    private static let gapBeforeRight: CGFloat = 10
    private static let nudge: CGFloat = 0

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

    /// Scales the 400 canvas so the mark's longer side fills the menu bar image.
    private static func menuBarContentRect(filling imageRect: CGRect) -> CGRect {
        let count = max(1, barCount)
        let barsWidth = CGFloat(count) * barWidth + CGFloat(max(0, count - 1)) * barGap
        let total = leftWidth + gapAfterLeft + barsWidth + gapBeforeRight + rightWidth
        let span = max(total, playHeight)
        let originX = canvas / 2 - span / 2
        let originY = canvas / 2 + nudge - span / 2
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
        draw(
            in: ctx,
            rect: CGRect(x: 0, y: 0, width: side, height: side),
            color: iconBlue,
            background: iconBackground
        )
        return ctx.makeImage()!
    }

    /// Blue mark, no plate, centered with a modest margin. This is the README image.
    static func readmeImage(side: Int) -> CGImage {
        let margin: CGFloat = 48
        let view = playHeight + margin * 2
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
        ctx.setFillColor(color)
        ctx.setStrokeColor(color)

        let count = max(1, barCount)
        let barsWidth = CGFloat(count) * barWidth + CGFloat(max(0, count - 1)) * barGap
        let total = leftWidth + gapAfterLeft + barsWidth + gapBeforeRight + rightWidth
        let x0 = canvas / 2 - total / 2
        let cy = canvas / 2 + nudge
        let halfAt = { (x: CGFloat) -> CGFloat in
            (playHeight / 2) * (1 - (x - x0) / total)
        }

        let leftX = x0
        let leftRight = leftX + leftWidth
        let leftPath = CGMutablePath()
        addRounded(leftPath, points: [
            CGPoint(x: leftX, y: cy - halfAt(leftX)),
            CGPoint(x: leftRight, y: cy - halfAt(leftRight)),
            CGPoint(x: leftRight, y: cy + halfAt(leftRight)),
            CGPoint(x: leftX, y: cy + halfAt(leftX))
        ], radii: [leftLeftRadius, leftRightRadius, leftRightRadius, leftLeftRadius])
        ctx.addPath(leftPath)
        ctx.fillPath()

        var x = x0 + leftWidth + gapAfterLeft
        ctx.setLineWidth(barWidth)
        ctx.setLineCap(.round)
        let slope = (playHeight / 2) / total
        let cap = barWidth / 2 * hypot(1, slope)
        for _ in 0..<count {
            let center = x + barWidth / 2
            let span = halfAt(center) * 2
            var y1 = cy - span / 2 + cap
            var y2 = cy + span / 2 - cap
            if y1 > y2 {
                y1 = cy
                y2 = cy
            }
            ctx.move(to: CGPoint(x: center, y: y1))
            ctx.addLine(to: CGPoint(x: center, y: y2))
            ctx.strokePath()
            x += barWidth + barGap
        }

        let tipX = x0 + total - rightWidth
        let tipPath = CGMutablePath()
        addRounded(tipPath, points: [
            CGPoint(x: tipX, y: cy - halfAt(tipX)),
            CGPoint(x: x0 + total, y: cy),
            CGPoint(x: tipX, y: cy + halfAt(tipX))
        ], radii: [tipLeftRadius, tipPointRadius, tipLeftRadius])
        ctx.addPath(tipPath)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func addRounded(_ path: CGMutablePath, points: [CGPoint], radii: [CGFloat]) {
        let count = points.count
        for index in 0..<count {
            let previous = points[(index - 1 + count) % count]
            let corner = points[index]
            let next = points[(index + 1) % count]
            let incoming = CGPoint(x: corner.x - previous.x, y: corner.y - previous.y)
            let outgoing = CGPoint(x: corner.x - next.x, y: corner.y - next.y)
            let incomingLength = hypot(incoming.x, incoming.y)
            let outgoingLength = hypot(outgoing.x, outgoing.y)
            let safeIncoming = incomingLength == 0 ? 1 : incomingLength
            let safeOutgoing = outgoingLength == 0 ? 1 : outgoingLength
            let radius = min(radii[index], safeIncoming / 2.2, safeOutgoing / 2.2)
            let start = CGPoint(
                x: corner.x - incoming.x / safeIncoming * radius,
                y: corner.y - incoming.y / safeIncoming * radius
            )
            let end = CGPoint(
                x: corner.x - outgoing.x / safeOutgoing * radius,
                y: corner.y - outgoing.y / safeOutgoing * radius
            )
            if index == 0 {
                path.move(to: start)
            } else {
                path.addLine(to: start)
            }
            path.addQuadCurve(to: end, control: corner)
        }
        path.closeSubpath()
    }
}
