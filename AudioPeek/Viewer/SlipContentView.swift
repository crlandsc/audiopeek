import AppKit

struct SlipPalette {
    var background: NSColor
    var ink: NSColor
    var muted: NSColor
    var line: NSColor
    var pane: NSColor
    var head: NSColor

    static func current(_ appearance: NSAppearance) -> SlipPalette {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return SlipPalette(
                background: NSColor(srgbRed: 0x2A / 255, green: 0x2A / 255, blue: 0x2C / 255, alpha: 1),
                ink: NSColor(srgbRed: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1),
                muted: NSColor(srgbRed: 0x98 / 255, green: 0x98 / 255, blue: 0x9D / 255, alpha: 1),
                line: NSColor(srgbRed: 0x3D / 255, green: 0x3D / 255, blue: 0x40 / 255, alpha: 1),
                pane: NSColor(srgbRed: 0x12 / 255, green: 0x12 / 255, blue: 0x14 / 255, alpha: 1),
                head: NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
            )
        }
        return SlipPalette(
            background: NSColor(srgbRed: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF5 / 255, alpha: 1),
            ink: NSColor(srgbRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1),
            muted: NSColor(srgbRed: 0x6E / 255, green: 0x6E / 255, blue: 0x73 / 255, alpha: 1),
            line: NSColor(srgbRed: 0xD5 / 255, green: 0xD5 / 255, blue: 0xDA / 255, alpha: 1),
            pane: NSColor(srgbRed: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF8 / 255, alpha: 1),
            head: NSColor(srgbRed: 1, green: 0x3B / 255, blue: 0x30 / 255, alpha: 1)
        )
    }
}

struct SlipResizeEdges: Equatable {
    var left = false
    var right = false
    var top = false
    var bottom = false

    var isActive: Bool { left || right || top || bottom }

    var axis: SlipResizeAxis? {
        if (left && top) || (right && bottom) { return .diagonalUpLeft }
        if (right && top) || (left && bottom) { return .diagonalUpRight }
        if left || right { return .horizontal }
        if top || bottom { return .vertical }
        return nil
    }
}

enum SlipResizeAxis: Equatable {
    case horizontal
    case vertical
    case diagonalUpLeft
    case diagonalUpRight

    var cursor: NSCursor {
        switch self {
        case .horizontal:
            return .resizeLeftRight
        case .vertical:
            return .resizeUpDown
        case .diagonalUpLeft:
            return Self.upLeftCursor
        case .diagonalUpRight:
            return Self.upRightCursor
        }
    }

    static let upLeftCursor = SlipSystemCursors.named(
        "resizenorthwestsoutheast",
        fallback: .resizeLeftRight
    )
    static let upRightCursor = SlipSystemCursors.named(
        "resizenortheastsouthwest",
        fallback: .resizeUpDown
    )
}

enum SlipSystemCursors {
    private static let root = URL(fileURLWithPath: "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors")

    static func named(_ folder: String, fallback: NSCursor) -> NSCursor {
        let directory = root.appendingPathComponent(folder)
        guard let image = NSImage(contentsOf: directory.appendingPathComponent("cursor.pdf")) else {
            return fallback
        }
        var hot = NSPoint(x: image.size.width / 2, y: image.size.height / 2)
        if let info = NSDictionary(contentsOf: directory.appendingPathComponent("info.plist")),
           let x = info["hotx"] as? NSNumber,
           let y = info["hoty"] as? NSNumber {
            hot = NSPoint(x: x.doubleValue, y: y.doubleValue)
        }
        return NSCursor(image: image, hotSpot: hot)
    }
}

enum SlipResize {
    static let margin: CGFloat = 10
    static let cornerLength: CGFloat = 20

    static func edges(at point: NSPoint, in bounds: NSRect) -> SlipResizeEdges {
        guard bounds.width > 0, bounds.height > 0 else { return SlipResizeEdges() }
        guard point.x >= bounds.minX, point.x <= bounds.maxX,
              point.y >= bounds.minY, point.y <= bounds.maxY else {
            return SlipResizeEdges()
        }
        var left = point.x <= bounds.minX + margin
        var right = point.x >= bounds.maxX - margin
        var top = point.y <= bounds.minY + margin
        var bottom = point.y >= bounds.maxY - margin
        if left && right {
            if point.x - bounds.minX <= bounds.maxX - point.x {
                right = false
            } else {
                left = false
            }
        }
        if top && bottom {
            if point.y - bounds.minY <= bounds.maxY - point.y {
                bottom = false
            } else {
                top = false
            }
        }
        // The last stretch of a band before a corner resizes both ways, so a
        // corner is an easy target rather than the small square where two
        // bands overlap.
        if (left || right) && !top && !bottom {
            if point.y <= bounds.minY + cornerLength {
                top = true
            } else if point.y >= bounds.maxY - cornerLength {
                bottom = true
            }
        }
        if (top || bottom) && !left && !right {
            if point.x <= bounds.minX + cornerLength {
                left = true
            } else if point.x >= bounds.maxX - cornerLength {
                right = true
            }
        }
        return SlipResizeEdges(left: left, right: right, top: top, bottom: bottom)
    }

    static func resizedFrame(
        start: NSRect,
        startMouse: NSPoint,
        mouse: NSPoint,
        edges: SlipResizeEdges,
        minSize: NSSize
    ) -> NSRect {
        var frame = start
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        if edges.right {
            frame.size.width = max(minSize.width, start.width + dx)
        }
        if edges.left {
            let width = max(minSize.width, start.width - dx)
            frame.origin.x = start.origin.x + (start.width - width)
            frame.size.width = width
        }
        if edges.top {
            frame.size.height = max(minSize.height, start.height + dy)
        }
        if edges.bottom {
            let height = max(minSize.height, start.height - dy)
            frame.origin.y = start.origin.y + (start.height - height)
            frame.size.height = height
        }
        return frame
    }
}

/// An accent line along the resize edge or corner under the pointer. Finder
/// ignores cursor changes from AudioPeek while Finder is front, so this is the
/// hint that shows where the panel can be grabbed.
final class SlipResizeHighlight: NSView {
    var edges = SlipResizeEdges() {
        didSet {
            if edges != oldValue {
                needsDisplay = true
            }
        }
    }
    var cornerRadius: CGFloat = 10

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard edges.isActive else { return }
        let line: CGFloat = 3
        let isCorner = (edges.left || edges.right) && (edges.top || edges.bottom)
        let reach = isCorner ? SlipResize.cornerLength * 2 : SlipResize.margin
        var region = bounds
        if edges.left {
            region.size.width = reach
        }
        if edges.right {
            region.origin.x = bounds.maxX - reach
            region.size.width = reach
        }
        if edges.top {
            region.size.height = reach
        }
        if edges.bottom {
            region.origin.y = bounds.maxY - reach
            region.size.height = reach
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: region).addClip()
        let inset = line / 2
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: max(0, cornerRadius - inset),
            yRadius: max(0, cornerRadius - inset)
        )
        path.lineWidth = line
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

enum FrequencyAxisTicks {
    static let audibleFloor = 20.0
    static let labelHeight: CGFloat = 12
    static let minSeparation: CGFloat = labelHeight + 4

    struct Tick: Equatable {
        var hertz: Double
        var centerY: CGFloat
        var label: String
    }

    static func layout(height: CGFloat, nyquist: Double, labelHeight: CGFloat = FrequencyAxisTicks.labelHeight) -> [Tick] {
        guard height > 0, nyquist > audibleFloor else { return [] }
        let separation = labelHeight + 4
        let pad: CGFloat = 2
        let half = labelHeight / 2
        let minY = half + pad
        let maxY = height - half - pad
        guard maxY >= minY else { return [] }
        let usable = maxY - minY
        let capacity = max(1, Int(floor(usable / separation)) + 1)
        let span = nyquist - audibleFloor
        var step = niceStep(span / Double(max(capacity - 1, 1)))
        var placed: [Tick] = []
        for _ in 0..<8 {
            let ticks = frequencies(nyquist: nyquist, step: step)
            placed = place(
                ticks,
                height: height,
                nyquist: nyquist,
                minY: minY,
                maxY: maxY,
                separation: separation,
                labelHeight: labelHeight
            )
            if !placed.isEmpty, placed.count <= capacity, separated(placed, by: separation) {
                return placed
            }
            step = niceStep(step * 2.01)
        }
        return placed
    }

    static func format(_ hertz: Double) -> String {
        let rounded = hertz.rounded()
        if rounded >= 1000 {
            let kilo = rounded / 1000
            let whole = kilo.rounded()
            if abs(kilo - whole) < 0.05 {
                return "\(Int(whole))k"
            }
            return String(format: "%.1fk", kilo)
        }
        return "\(Int(rounded))"
    }

    static let unitText = "Hz"

    static func labelFrame(for tick: Tick, in lane: NSRect) -> NSRect {
        let labelSize = AxisLabelChrome.size(of: tick.label)
        return NSRect(
            x: lane.minX + 4 + AxisLabelChrome.tickLength + 3,
            y: lane.minY + tick.centerY - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
    }

    static func placedUnit(ticks: [Tick], in area: NSRect, avoiding extra: [NSRect] = []) -> AxisPlacedUnit? {
        let size = AxisLabelChrome.unitSize(unitText)
        let labels = ticks.map { labelFrame(for: $0, in: area) }
        var candidates: [NSRect] = []
        if let top = labels.min(by: { $0.minY < $1.minY }) {
            candidates.append(NSRect(x: top.maxX + 4, y: top.minY, width: size.width, height: size.height))
            candidates.append(NSRect(x: top.minX, y: top.maxY + 4, width: size.width, height: size.height))
        }
        let right = (labels.map(\.maxX).max() ?? area.minX) + 4
        candidates.append(NSRect(
            x: right,
            y: area.midY - size.height / 2,
            width: size.width,
            height: size.height
        ))
        if labels.isEmpty {
            candidates.append(NSRect(x: area.minX + 4, y: area.minY + 2, width: size.width, height: size.height))
        }
        guard let frame = AxisMarkLayout.firstFit(candidates, in: area, avoiding: labels + extra) else { return nil }
        return AxisPlacedUnit(text: unitText, frame: frame)
    }

    private static func niceStep(_ raw: Double) -> Double {
        let value = max(raw, 1)
        let exponent = pow(10, floor(log10(value)))
        let fraction = value / exponent
        let nice: Double
        if fraction <= 1 {
            nice = 1
        } else if fraction <= 2 {
            nice = 2
        } else if fraction <= 5 {
            nice = 5
        } else {
            nice = 10
        }
        return nice * exponent
    }

    private static func frequencies(nyquist: Double, step: Double) -> [Double] {
        guard step > 0 else { return [audibleFloor, nyquist] }
        var values = [audibleFloor]
        var cursor = ceil((audibleFloor + step * 0.01) / step) * step
        while cursor < nyquist - step * 0.15 {
            if cursor > audibleFloor + 0.001 {
                values.append(cursor)
            }
            cursor += step
        }
        if let last = values.last, abs(last - nyquist) > 0.001 {
            values.append(nyquist)
        }
        return values
    }

    private static func place(
        _ frequencies: [Double],
        height: CGFloat,
        nyquist: Double,
        minY: CGFloat,
        maxY: CGFloat,
        separation: CGFloat,
        labelHeight: CGFloat
    ) -> [Tick] {
        func yPosition(_ hertz: Double) -> CGFloat {
            let span = nyquist - audibleFloor
            let unit = (hertz - audibleFloor) / span
            return height * CGFloat(1 - unit)
        }
        func clamp(_ value: CGFloat) -> CGFloat {
            min(maxY, max(minY, value))
        }
        var kept: [(Double, CGFloat)] = []
        func tryAdd(_ hertz: Double) {
            let center = clamp(yPosition(hertz))
            let top = center - labelHeight / 2
            let bottom = center + labelHeight / 2
            guard top >= -0.01, bottom <= height + 0.01 else { return }
            for existing in kept where abs(existing.1 - center) < separation - 0.01 {
                return
            }
            kept.append((hertz, center))
        }
        if let first = frequencies.first {
            tryAdd(first)
        }
        if let last = frequencies.last, frequencies.count > 1 {
            tryAdd(last)
        }
        if frequencies.count > 2 {
            for hertz in frequencies.dropFirst().dropLast() {
                tryAdd(hertz)
            }
        }
        return kept
            .sorted { $0.1 < $1.1 }
            .map { Tick(hertz: $0.0, centerY: $0.1, label: format($0.0)) }
    }

    private static func separated(_ ticks: [Tick], by separation: CGFloat) -> Bool {
        for index in 1..<ticks.count where ticks[index].centerY - ticks[index - 1].centerY < separation - 0.01 {
            return false
        }
        return true
    }
}

enum TimeAxisTicks {
    static let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    static let minGap: CGFloat = 8

    struct Tick: Equatable {
        var seconds: Double
        var centerX: CGFloat
        var label: String
    }

    static func step(duration: Double, width: CGFloat) -> Double {
        guard duration > 0, width > 0 else { return 1 }
        let slots = max(1, width / 32)
        var raw = duration / Double(slots)
        if duration >= 3600 {
            raw = max(raw, 10)
        } else if duration >= 600 {
            raw = max(raw, 1)
        }
        return niceStep(max(raw, 0.001))
    }

    static func layout(width: CGFloat, duration: Double) -> [Tick] {
        guard width > 1, duration > 0 else { return [] }
        let chosen = step(duration: duration, width: width)
        let count = max(0, Int((duration / chosen).rounded(.down)))
        var ticks: [Tick] = []
        ticks.reserveCapacity(count + 1)
        for index in 0...count {
            let seconds = min(duration, Double(index) * chosen)
            let x = CGFloat(seconds / duration) * width
            ticks.append(Tick(seconds: seconds, centerX: x, label: format(seconds, step: chosen)))
        }
        return droppingOverlaps(ticks, width: width)
    }

    static func format(_ seconds: Double, step: Double) -> String {
        let clamped = max(0, seconds)
        if step < 1, clamped < 60 {
            if abs(clamped - clamped.rounded()) < 0.001 {
                return String(format: "%.0f", clamped)
            }
            return String(format: "%g", clamped)
        }
        let whole = Int((clamped + 0.001).rounded(.down))
        if whole >= 3600 || step >= 3600 {
            return String(format: "%d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
        }
        if whole >= 60 || step >= 60 {
            return String(format: "%d:%02d", whole / 60, whole % 60)
        }
        return "\(whole)"
    }

    private static let steps: [Double] = [
        0.001, 0.002, 0.005,
        0.01, 0.02, 0.05,
        0.1, 0.2, 0.5,
        1, 2, 5, 10, 15, 30,
        60, 120, 300, 600, 900, 1800,
        3600, 7200, 14400, 21600, 43200, 86400
    ]

    private static func niceStep(_ raw: Double) -> Double {
        for candidate in steps where candidate + 1e-9 >= raw {
            return candidate
        }
        var candidate = steps[steps.count - 1]
        while candidate < raw {
            candidate *= 2
        }
        return candidate
    }

    static func unitText(duration: Double) -> String {
        if duration >= 3600 { return "h:mm:ss" }
        if duration >= 60 { return "min:sec" }
        return "s"
    }

    static func labelFrame(for tick: Tick, width: CGFloat, tickTop: CGFloat) -> NSRect? {
        guard !tick.label.isEmpty else { return nil }
        let labelSize = AxisLabelChrome.size(of: tick.label)
        var x = tick.centerX - labelSize.width / 2
        x = min(max(1, x), max(1, width - labelSize.width - 1))
        let y = tickTop - labelSize.height - 1
        guard y >= 0 else { return nil }
        return NSRect(x: x, y: y, width: labelSize.width, height: labelSize.height)
    }

    static func placedUnit(ticks: [Tick], duration: Double, pane: NSRect, tickTop: CGFloat) -> AxisPlacedUnit? {
        let text = unitText(duration: duration)
        let size = AxisLabelChrome.unitSize(text)
        let labels = ticks.compactMap { labelFrame(for: $0, width: pane.width, tickTop: tickTop) }
        var candidates: [NSRect] = []
        let rowY = labels.map(\.minY).min() ?? (tickTop - size.height - 1)
        let aboveY = rowY - size.height - 4
        candidates.append(NSRect(x: pane.maxX - size.width - 4, y: aboveY, width: size.width, height: size.height))
        candidates.append(NSRect(x: pane.minX + 4, y: aboveY, width: size.width, height: size.height))
        candidates.append(NSRect(x: pane.maxX - size.width - 2, y: rowY, width: size.width, height: size.height))
        let sorted = labels.sorted { $0.minX < $1.minX }
        if sorted.count > 1 {
            for index in 0..<(sorted.count - 1) {
                let gapX = sorted[index].maxX
                let gapWidth = sorted[index + 1].minX - gapX
                guard gapWidth >= size.width + 8 else { continue }
                let x = gapX + (gapWidth - size.width) / 2
                candidates.append(NSRect(x: x, y: sorted[index].minY, width: size.width, height: size.height))
            }
        }
        guard let frame = AxisMarkLayout.firstFit(candidates, in: pane, avoiding: labels) else { return nil }
        return AxisPlacedUnit(text: text, frame: frame)
    }

    private static func droppingOverlaps(_ ticks: [Tick], width: CGFloat) -> [Tick] {
        var lastRight = -CGFloat.greatestFiniteMagnitude
        return ticks.map { tick in
            let textWidth = ceil((tick.label as NSString).size(withAttributes: [.font: labelFont]).width)
            let left = tick.centerX - textWidth / 2
            let right = left + textWidth
            let fits = left >= 1 && right <= width - 1 && left >= lastRight + minGap
            if fits {
                lastRight = right
                return tick
            }
            return Tick(seconds: tick.seconds, centerX: tick.centerX, label: "")
        }
    }
}

struct AxisPlacedUnit: Equatable {
    var text: String
    var frame: NSRect
}

enum AxisMarkLayout {
    static let gap: CGFloat = 3

    static func firstFit(_ candidates: [NSRect], in area: NSRect, avoiding obstacles: [NSRect]) -> NSRect? {
        for rect in candidates {
            guard rect.width > 0, rect.height > 0 else { continue }
            guard rect.minX >= area.minX - 0.01, rect.maxX <= area.maxX + 0.01,
                  rect.minY >= area.minY - 0.01, rect.maxY <= area.maxY + 0.01 else { continue }
            let hits = obstacles.contains { obstacle in
                obstacle.insetBy(dx: -gap, dy: -gap).intersects(rect)
            }
            if hits { continue }
            return rect
        }
        return nil
    }
}

enum AxisLabelChrome {
    static let font = NSFont.systemFont(ofSize: 10, weight: .medium)
    static let unitFont = NSFont.systemFont(ofSize: 9, weight: .regular)
    static let tickLength: CGFloat = 6
    static let fadePadding: CGFloat = 3
    static let fadeAlphas: [CGFloat] = [0.6, 0.24, 0]

    static func glyphSize(of label: String) -> NSSize {
        let raw = (label as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(raw.width), height: ceil(raw.height))
    }

    static func size(of label: String) -> NSSize {
        let raw = glyphSize(of: label)
        return NSSize(width: raw.width + 6, height: raw.height + 2)
    }

    static func unitSize(_ text: String) -> NSSize {
        let raw = (text as NSString).size(withAttributes: [.font: unitFont])
        return NSSize(width: ceil(raw.width), height: ceil(raw.height))
    }

    static func drawTick(from start: NSPoint, to end: NSPoint, clip: NSRect? = nil) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if let clip {
            ctx.clip(to: clip)
        }
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineCap(.butt)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func drawLabel(_ label: String, textOrigin: NSPoint, in view: NSView, clip: NSRect? = nil) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if let clip {
            ctx.clip(to: clip)
        }
        let glyphs = NSRect(origin: textOrigin, size: glyphSize(of: label))
        drawFade(around: glyphs)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        (label as NSString).draw(at: textOrigin, withAttributes: attributes)
        ctx.restoreGState()
    }

    static func drawUnit(_ text: String, frame: NSRect, clip: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: clip)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: unitFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.72)
        ]
        (text as NSString).draw(at: frame.origin, withAttributes: attributes)
        ctx.restoreGState()
    }

    private static func drawFade(around glyphs: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let outer = glyphs.insetBy(dx: -fadePadding, dy: -fadePadding)
        ctx.saveGState()
        ctx.clip(to: outer)
        if fadeAlphas.count > 1, fadeAlphas[1] > 0 {
            NSColor.black.withAlphaComponent(fadeAlphas[1]).setFill()
            NSBezierPath(roundedRect: outer, xRadius: 2, yRadius: 2).fill()
        }
        if let core = fadeAlphas.first, core > 0 {
            NSColor.black.withAlphaComponent(core).setFill()
            NSBezierPath(roundedRect: glyphs, xRadius: 1.5, yRadius: 1.5).fill()
        }
        ctx.restoreGState()
    }
}

// Draws the metadata line so the trailing time ("0:06 / 84:40") always shows in full.
// When space runs short, whole segments drop off the end of the format/rate/channel part instead.
final class MetadataCell: NSTextFieldCell {
    private static let separator = " · "

    private var segments: [String] {
        stringValue.components(separatedBy: Self.separator)
    }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: textColor ?? .secondaryLabelColor]
    }

    private func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }

    private var padding: CGFloat {
        cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 40)).width - textWidth(stringValue)
    }

    // The longest form of the line that fits: the full line, then fewer leading segments, then just the time.
    private func shown(within textSpace: CGFloat) -> String {
        let segments = self.segments
        guard let time = segments.last, segments.count > 1, textWidth(stringValue) > textSpace + 0.5 else {
            return stringValue
        }
        let info = segments.dropLast()
        return (0..<info.count).reversed()
            .map { (Array(info.prefix($0)) + [time]).joined(separator: Self.separator) }
            .first { textWidth($0) <= textSpace } ?? time
    }

    // Cell width for the text shown within `maxWidth`, never narrower than the time itself.
    func fittingWidth(within maxWidth: CGFloat) -> CGFloat {
        guard !stringValue.isEmpty else { return 0 }
        let padding = self.padding
        return ceil(textWidth(shown(within: maxWidth - padding)) + padding)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let rect = titleRect(forBounds: cellFrame)
        let text = shown(within: rect.width)
        guard text != stringValue else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }
        let width = textWidth(text)
        (text as NSString).draw(at: NSPoint(x: rect.maxX - width, y: rect.minY), withAttributes: attributes)
    }
}

/// Panel geometry in the content view's flipped coordinates. Layout, hit testing and
/// split dragging all read it, so they always agree.
struct SlipLayout {
    static let headerHeight: CGFloat = 46
    static let minPane: CGFloat = 48

    var size: NSSize
    /// Glass rim between the panel edge and the panes, on the sides and bottom.
    var inset: CGFloat = 0
    /// Space between the two panes; the split handle sits in it.
    var gap: CGFloat = 1

    var bodyTop: CGFloat { Self.headerHeight + (inset == 0 ? 1 : 0) }

    var body: NSRect {
        NSRect(
            x: inset,
            y: bodyTop,
            width: max(0, size.width - inset * 2),
            height: max(0, size.height - bodyTop - inset)
        )
    }

    func panes(waveform: Bool, spectrogram: Bool, split: Double) -> (wave: NSRect?, divider: NSRect?, spec: NSRect?) {
        let body = self.body
        guard waveform && spectrogram else {
            return (waveform ? body : nil, nil, spectrogram ? body : nil)
        }
        let available = max(0, body.height - gap)
        let waveHeight = min(max(available * CGFloat(split), Self.minPane), max(Self.minPane, available - Self.minPane))
        let wave = NSRect(x: body.minX, y: body.minY, width: body.width, height: waveHeight)
        let divider = NSRect(x: body.minX, y: wave.maxY, width: body.width, height: gap)
        let spec = NSRect(x: body.minX, y: divider.maxY, width: body.width, height: max(0, body.maxY - divider.maxY))
        return (wave, divider, spec)
    }

    /// The split fraction that puts the middle of the gap at `y`.
    func splitFraction(atY y: CGFloat) -> Double {
        let available = max(1, body.height - gap)
        return Double((y - body.minY - gap / 2) / available)
    }
}

/// Draws the volume track with the accent fill. The panel never becomes key, and the
/// system draws a slider in a non-key window with a gray fill, ignoring trackFillColor.
final class AccentSliderCell: NSSliderCell {
    static let thickness: CGFloat = 4

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let thickness = Self.thickness
        let track = NSRect(x: rect.minX, y: rect.midY - thickness / 2, width: rect.width, height: thickness)
        let radius = thickness / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let knob = knobRect(flipped: flipped)
        let fillEnd = min(max(knob.midX, track.minX), track.maxX)
        guard fillEnd > track.minX else { return }
        NSColor.controlAccentColor.setFill()
        let filled = NSRect(x: track.minX, y: track.minY, width: fillEnd - track.minX, height: thickness)
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}

final class SlipContentView: NSView {
    let playButton = NSButton()
    let filenameLabel = NSTextField(labelWithString: "")
    let metadataLabel: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.cell = MetadataCell(textCell: "")
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        return field
    }()
    let volumeSlider = NSSlider()
    let loopButton = NSButton()
    let gearButton = NSButton()
    let waveformPane = SlipPaneView()
    let spectrogramPane = SlipPaneView()
    let divider = NSView()
    let waveformPlayhead = NSView()
    let spectrogramPlayhead = NSView()
    let progressFill = NSView()
    let resizeHighlight = SlipResizeHighlight()

    var onPlay: () -> Void = {}
    var onVolume: (Double) -> Void = { _ in }
    var onGear: () -> Void = {}
    var onLoop: (Bool) -> Void = { _ in }
    var onSplit: (Double) -> Void = { _ in }
    var onSeek: (String, Double) -> Void = { _, _ in }
    var onScrub: (String, Double, ScrubPhase) -> Void = { _, _, _ in }
    var onResizeBegan: () -> Void = {}
    var onResizeEnded: () -> Void = {}
    var onAppearance: () -> Void = {}
    var onRevealTargetRaised: () -> Void = {}
    private var playheadFraction = 0.0

    var showWaveform = true
    var showSpectrogram = true
    var splitFraction = 0.5
    private(set) var playClicks = 0
    private var draggingSplit = false
    private var palette = SlipPalette.current(NSApp.effectiveAppearance)
    private var showProgress = false
    private var progressFraction = 0.0
    private(set) var isResizeDrag = false
    private var resizeTracking: NSTrackingArea?
    let hoverPollInterval: TimeInterval = 1.0 / 60.0
    private var hoverTimer: Timer?
    private var hoverCursorHeld = false
    var hoverPollIsRunning: Bool { hoverTimer?.isValid == true }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        configurePlay(playButton)
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play or pause")
        playButton.action = #selector(playPressed)
        playButton.setAccessibilityIdentifier("slip.play")

        filenameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        filenameLabel.lineBreakMode = .byTruncatingTail
        filenameLabel.setAccessibilityIdentifier("slip.filename")
        // Fixed-width digits keep the ticking time from nudging the row.
        metadataLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        metadataLabel.alignment = .right
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.setAccessibilityIdentifier("slip.metadata")

        volumeSlider.cell = AccentSliderCell()
        volumeSlider.controlSize = .small
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.doubleValue = 1
        volumeSlider.isContinuous = true
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeSlider.setAccessibilityIdentifier("slip.volume")
        volumeSlider.setAccessibilityLabel("Volume")

        configurePlay(loopButton)
        loopButton.setButtonType(.toggle)
        loopButton.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: "Loop")
        loopButton.action = #selector(loopPressed)
        loopButton.setAccessibilityIdentifier("slip.loop")
        loopButton.setAccessibilityLabel("Loop")

        configurePlay(gearButton)
        gearButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Open settings")
        gearButton.action = #selector(gearPressed)
        gearButton.setAccessibilityIdentifier("slip.settings")
        gearButton.setAccessibilityLabel("Open settings")

        waveformPane.setAccessibilityIdentifier("slip.waveform")
        spectrogramPane.setAccessibilityIdentifier("slip.spectrogram")
        waveformPane.layerContentsRedrawPolicy = .onSetNeedsDisplay
        waveformPane.onScrub = { [weak self] fraction, phase in
            self?.onScrub("waveform", fraction, phase)
        }
        spectrogramPane.onScrub = { [weak self] fraction, phase in
            self?.onScrub("spectrogram", fraction, phase)
        }
        waveformPane.onRevealTargetRaised = { [weak self] in
            self?.onRevealTargetRaised()
        }
        spectrogramPane.onRevealTargetRaised = { [weak self] in
            self?.onRevealTargetRaised()
        }
        waveformPlayhead.setAccessibilityIdentifier("slip.playhead.waveform")
        spectrogramPlayhead.setAccessibilityIdentifier("slip.playhead.spectrogram")
        progressFill.wantsLayer = true
        progressFill.isHidden = true
        progressFill.setAccessibilityIdentifier("slip.progress")

        for view in [playButton, filenameLabel, metadataLabel, volumeSlider, loopButton, gearButton, waveformPane, spectrogramPane, divider, progressFill, resizeHighlight] {
            addSubview(view)
        }
        waveformPane.addSubview(waveformPlayhead)
        spectrogramPane.addSubview(spectrogramPlayhead)
        applyPalette()
        // Follow a change of the system accent color without a relaunch.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemColorsChanged),
            name: NSColor.systemColorsDidChangeNotification,
            object: nil
        )
    }

    @objc private func systemColorsChanged() {
        volumeSlider.needsDisplay = true
        loopButton.needsDisplay = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    var headerOrder: [String] {
        ["play", "filename", "metadata", "volume", "loop", "settings"]
    }

    func setPlaying(_ playing: Bool) {
        let name = playing ? "pause.fill" : "play.fill"
        playButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Play or pause")
    }

    func setPlayhead(fraction: Double) {
        playheadFraction = min(max(fraction, 0), 1)
        placePlayhead(waveformPlayhead, in: waveformPane)
        placePlayhead(spectrogramPlayhead, in: spectrogramPane)
    }

    func seekFraction(in pane: String) -> ((Double) -> Void)? {
        switch pane {
        case "waveform":
            return showWaveform ? { self.onSeek("waveform", $0) } : nil
        case "spectrogram":
            return showSpectrogram ? { self.onSeek("spectrogram", $0) } : nil
        default:
            return nil
        }
    }

    func setLoop(_ enabled: Bool) {
        loopButton.state = enabled ? .on : .off
        loopButton.contentTintColor = enabled ? .controlAccentColor : .secondaryLabelColor
    }

    func apply(showWaveform: Bool, showSpectrogram: Bool, split: Double, volume: Double) {
        self.showWaveform = showWaveform
        self.showSpectrogram = showSpectrogram
        splitFraction = min(max(split, 0), 1)
        if abs(volumeSlider.doubleValue - volume) > 0.001 {
            volumeSlider.doubleValue = volume
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let geometry = currentLayout
        let headerHeight = SlipLayout.headerHeight
        let pad: CGFloat = 10
        let gap: CGFloat = 8
        let textGap: CGFloat = 12
        let button: CGFloat = 28
        let volumeWidth: CGFloat = 72
        let midY = headerHeight / 2
        let buttonY = midY - button / 2
        playButton.frame = NSRect(x: pad, y: buttonY, width: button, height: button)
        let gearX = bounds.width - pad - button
        gearButton.frame = NSRect(x: gearX, y: buttonY, width: button, height: button)
        let loopX = gearX - gap - button
        loopButton.frame = NSRect(x: loopX, y: buttonY, width: button, height: button)
        let volumeX = loopX - gap - volumeWidth
        let sliderHeight = volumeSlider.fittingSize.height
        volumeSlider.frame = NSRect(x: volumeX, y: midY - sliderHeight / 2, width: volumeWidth, height: sliderHeight)
        let nameX = pad + button + gap
        // Squeeze order: the metadata info truncates first, then the filename, and the time never does.
        let minNameWidth: CGFloat = 80
        let available = max(0, volumeX - textGap - nameX - minNameWidth - textGap)
        let metaWidth = (metadataLabel.cell as? MetadataCell)?.fittingWidth(within: available)
            ?? min(fieldWidth(metadataLabel), available)
        let metaX = volumeX - textGap - metaWidth
        let nameWidth = max(0, metaX - textGap - nameX)
        // Both labels share one baseline, placed so the title's caps sit on the row's center like the icons.
        let baseline = (midY + (filenameLabel.font?.capHeight ?? 9) / 2).rounded()
        filenameLabel.frame = labelFrame(filenameLabel, x: nameX, width: nameWidth, baseline: baseline)
        metadataLabel.frame = labelFrame(metadataLabel, x: metaX, width: metaWidth, baseline: baseline)
        filenameLabel.toolTip = filenameLabel.stringValue.isEmpty ? nil : filenameLabel.stringValue
        metadataLabel.toolTip = metadataLabel.stringValue.isEmpty ? nil : metadataLabel.stringValue
        filenameLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.lineBreakMode = .byTruncatingTail
        progressFill.isHidden = !showProgress
        progressFill.frame = NSRect(
            x: 0,
            y: headerHeight - 2,
            width: bounds.width * progressFraction,
            height: 2
        )

        waveformPane.isHidden = !showWaveform
        spectrogramPane.isHidden = !showSpectrogram
        let panes = geometry.panes(waveform: showWaveform, spectrogram: showSpectrogram, split: splitFraction)
        divider.isHidden = panes.divider == nil
        if let wave = panes.wave { waveformPane.frame = wave }
        if let divide = panes.divider { divider.frame = divide }
        if let spec = panes.spec { spectrogramPane.frame = spec }
        placePlayhead(waveformPlayhead, in: waveformPane)
        placePlayhead(spectrogramPlayhead, in: spectrogramPane)
        resizeHighlight.frame = bounds
        resizeHighlight.cornerRadius = layer?.cornerRadius ?? 10
    }

    private func placePlayhead(_ playhead: NSView, in pane: NSView) {
        let x = max(0, min(pane.bounds.width - 1, pane.bounds.width * playheadFraction))
        playhead.frame = NSRect(x: x, y: 0, width: 1, height: pane.bounds.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
        onAppearance()
    }

    var appearanceName: String {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
    }

    var chromeRGB: (Double, Double, Double) { Self.rgb(palette.background) }

    var playheadRGB: (Double, Double, Double) { Self.rgb(palette.head) }

    var playheadWidth: Double { Double(waveformPlayhead.frame.width) }

    func waveformRGB() -> (Double, Double, Double) {
        waveformPane.resolvedWaveformRGB(appearance: effectiveAppearance)
    }

    func apply(appearance name: String) {
        let appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
        self.appearance = appearance
        applyPalette()
    }

    private static func rgb(_ color: NSColor) -> (Double, Double, Double) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard window != nil else {
            endHoverCursor()
            return
        }
        // Cursor changes only while AudioPeek is already active. Activating
        // the app to force a cursor makes Finder flicker, so this poll does
        // not take focus.
        let timer = Timer(timeInterval: hoverPollInterval, repeats: true) { [weak self] _ in
            self?.sampleHoverCursor()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    deinit {
        hoverTimer?.invalidate()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let resizeTracking {
            removeTrackingArea(resizeTracking)
        }
        // Cursor rects only apply while the window is key, and this panel cannot
        // become key. The hover poll is what sets the resize cursor while Finder
        // is the front app.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        resizeTracking = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        discardCursorRects()
        let margin = SlipResize.margin
        let corner = SlipResize.cornerLength
        let width = bounds.width
        let height = bounds.height
        guard width > corner * 2, height > corner * 2 else { return }
        addCursorRect(NSRect(x: corner, y: 0, width: width - corner * 2, height: margin), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: corner, y: height - margin, width: width - corner * 2, height: margin), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: corner, width: margin, height: height - corner * 2), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: width - margin, y: corner, width: margin, height: height - corner * 2), cursor: .resizeLeftRight)
        // Each corner is an L: the last stretch of the two bands that meet there.
        let corners: [(x: CGFloat, y: CGFloat, cursor: NSCursor)] = [
            (0, 0, SlipResizeAxis.upLeftCursor),
            (width - corner, 0, SlipResizeAxis.upRightCursor),
            (0, height - corner, SlipResizeAxis.upRightCursor),
            (width - corner, height - corner, SlipResizeAxis.upLeftCursor)
        ]
        for spot in corners {
            let bandY = spot.y == 0 ? 0 : height - margin
            let bandX = spot.x == 0 ? 0 : width - margin
            addCursorRect(NSRect(x: spot.x, y: bandY, width: corner, height: margin), cursor: spot.cursor)
            addCursorRect(NSRect(x: bandX, y: spot.y, width: margin, height: corner), cursor: spot.cursor)
        }
        if !divider.isHidden, divider.frame.width > margin * 2, divider.frame.height > 0 {
            let hit = divider.frame.insetBy(dx: margin, dy: -6)
            if hit.width > 0, hit.height > 0 {
                addCursorRect(hit, cursor: .resizeUpDown)
            }
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateHoverCursor(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverCursor(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        resizeHighlight.edges = SlipResizeEdges()
        endHoverCursor()
    }

    /// Resize edges at a point, except over a header control that reaches into a band.
    func resizeEdges(at point: NSPoint) -> SlipResizeEdges {
        let controls = [playButton, volumeSlider, loopButton, gearButton]
        if controls.contains(where: { !$0.isHidden && $0.frame.contains(point) }) {
            return SlipResizeEdges()
        }
        return SlipResize.edges(at: point, in: bounds)
    }

    func resizeCursor(at point: NSPoint) -> NSCursor? {
        if let cursor = resizeEdges(at: point).axis?.cursor {
            return cursor
        }
        if splitHit(point) {
            return .resizeUpDown
        }
        return nil
    }

    func hoverCursor(at point: NSPoint, panelHit: Bool) -> NSCursor? {
        guard panelHit, containsPointer(point) else { return nil }
        return resizeCursor(at: point) ?? .arrow
    }

    /// Shows the grab zone under the pointer. Unlike the cursor, this works
    /// while Finder is the front app.
    func updateResizeHighlight(at point: NSPoint, panelHit: Bool) {
        resizeHighlight.edges = panelHit && containsPointer(point) ? resizeEdges(at: point) : SlipResizeEdges()
    }

    func sampleHoverCursor() {
        if isResizeDrag || draggingSplit { return }
        guard let window, window.isVisible else {
            resizeHighlight.edges = SlipResizeEdges()
            endHoverCursor()
            return
        }
        let screen = NSEvent.mouseLocation
        let frame = window.frame
        let panelHit = frame.contains(screen)
            || NSWindow.windowNumber(at: screen, belowWindowWithWindowNumber: 0) == window.windowNumber
        let local = convert(window.convertPoint(fromScreen: screen), from: nil)
        updateResizeHighlight(at: local, panelHit: panelHit)
        applyHoverCursor(hoverCursor(at: local, panelHit: panelHit))
    }

    func updateHoverCursor(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateResizeHighlight(at: point, panelHit: true)
        applyHoverCursor(hoverCursor(at: point, panelHit: true))
    }

    private func containsPointer(_ point: NSPoint) -> Bool {
        point.x >= bounds.minX && point.x <= bounds.maxX && point.y >= bounds.minY && point.y <= bounds.maxY
    }

    private func applyHoverCursor(_ cursor: NSCursor?) {
        guard NSApp.isActive else { return }
        let resize = cursor.flatMap { $0 === NSCursor.arrow ? nil : $0 }
        guard let resize else {
            endHoverCursor()
            return
        }
        resize.set()
        hoverCursorHeld = true
    }

    private func endHoverCursor() {
        guard hoverCursorHeld else { return }
        hoverCursorHeld = false
        NSCursor.arrow.set()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if splitHit(local) || resizeEdges(at: local).isActive || headerBackground(local) {
            return self
        }
        return super.hitTest(point)
    }

    var currentLayout: SlipLayout {
        SlipLayout(size: bounds.size)
    }

    func hitKind(at point: NSPoint) -> String {
        if headerBackground(point) { return "header" }
        if !waveformPane.isHidden, waveformPane.frame.contains(point) { return "waveform" }
        if !spectrogramPane.isHidden, spectrogramPane.frame.contains(point) { return "spectrogram" }
        return "other"
    }

    private func headerBackground(_ point: NSPoint) -> Bool {
        guard point.y >= 0, point.y < SlipLayout.headerHeight, bounds.contains(point) else { return false }
        let controls = [playButton, volumeSlider, loopButton, gearButton]
        return !controls.contains { $0.frame.contains(point) }
    }

    private func labelFrame(_ field: NSTextField, x: CGFloat, width: CGFloat, baseline: CGFloat) -> NSRect {
        let height = ceil(field.cell?.cellSize.height ?? 16)
        let font = field.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let ascent = ceil(font.ascender)
        return NSRect(x: x, y: baseline - ascent, width: width, height: height)
    }

    private func fieldWidth(_ field: NSTextField) -> CGFloat {
        guard !field.stringValue.isEmpty, let cell = field.cell else { return 0 }
        let fitted = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 40)).width
        return ceil(fitted)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let edges = resizeEdges(at: local)
        if edges.isActive {
            resizeWindow(from: event, edges: edges)
            return
        }
        if headerBackground(local) {
            window?.performDrag(with: event)
            return
        }
        guard splitHit(local) else {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount >= 2 {
            resetSplitToDefault()
            return
        }
        draggingSplit = true
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event else { return }
            if event.type == .leftMouseUp {
                self.draggingSplit = false
                stop.pointee = true
                return
            }
            self.updateSplit(with: event)
        }
    }

    func beginResizeStretch() {
        guard !isResizeDrag else { return }
        layoutSubtreeIfNeeded()
        isResizeDrag = true
        waveformPane.beginStretch()
        spectrogramPane.beginStretch()
        waveformPlayhead.isHidden = true
        spectrogramPlayhead.isHidden = true
    }

    func endResizeStretch() {
        guard isResizeDrag else { return }
        isResizeDrag = false
        waveformPane.endStretch()
        spectrogramPane.endStretch()
        waveformPlayhead.isHidden = false
        spectrogramPlayhead.isHidden = false
        needsLayout = true
    }

    func redisplayPicture() {
        waveformPane.needsDisplay = true
        spectrogramPane.needsDisplay = true
        needsDisplay = true
    }

    private func resizeWindow(from event: NSEvent, edges: SlipResizeEdges) {
        guard let window, !isResizeDrag else { return }
        // Measure the drag from where the button went down, so any movement
        // before this handler runs still moves the edge.
        let startFrame = window.frame
        let startMouse = window.convertPoint(toScreen: event.locationInWindow)
        onResizeBegan()
        let cursor = edges.axis?.cursor
        cursor?.set()
        let minSize = window.minSize
        var ended = false
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event else {
                stop.pointee = true
                return
            }
            if event.type == .leftMouseUp {
                ended = true
                stop.pointee = true
                self.onResizeEnded()
                return
            }
            cursor?.set()
            let frame = SlipResize.resizedFrame(
                start: startFrame,
                startMouse: startMouse,
                mouse: NSEvent.mouseLocation,
                edges: edges,
                minSize: minSize
            )
            window.setFrame(frame, display: false)
            self.layoutSubtreeIfNeeded()
        }
        if !ended {
            onResizeEnded()
        }
    }

    func resetSplitToDefault() {
        let fraction = SettingsBlob.factory.splitFraction
        splitFraction = fraction
        onSplit(fraction)
        needsLayout = true
    }

    func applySplitDrag(rawFraction: Double) {
        let clamped = min(max(rawFraction, 0.08), 0.92)
        let fraction = SplitSnap.value(clamped)
        splitFraction = fraction
        onSplit(fraction)
        needsLayout = true
    }

    private func updateSplit(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        applySplitDrag(rawFraction: currentLayout.splitFraction(atY: local.y))
    }

    private func splitHit(_ point: NSPoint) -> Bool {
        guard !divider.isHidden else { return false }
        return divider.frame.insetBy(dx: 0, dy: -6).contains(point)
    }

    private func configurePlay(_ button: NSButton) {
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.target = self
    }

    func applyPalette() {
        palette = SlipPalette.current(effectiveAppearance)
        layer?.backgroundColor = palette.background.cgColor
        layer?.borderColor = palette.line.cgColor
        // Header text and icons use system colors so they stay legible on glass and follow Increase Contrast.
        filenameLabel.textColor = .labelColor
        metadataLabel.textColor = .secondaryLabelColor
        playButton.contentTintColor = .labelColor
        gearButton.contentTintColor = .secondaryLabelColor
        loopButton.contentTintColor = loopButton.state == .on ? .controlAccentColor : .secondaryLabelColor
        volumeSlider.trackFillColor = nil
        waveformPane.wantsLayer = true
        spectrogramPane.wantsLayer = true
        spectrogramPane.clipsToBounds = true
        spectrogramPane.layer?.masksToBounds = true
        divider.wantsLayer = true
        waveformPane.layer?.backgroundColor = palette.pane.cgColor
        spectrogramPane.layer?.backgroundColor = palette.pane.cgColor
        divider.layer?.backgroundColor = palette.line.cgColor
        waveformPlayhead.wantsLayer = true
        spectrogramPlayhead.wantsLayer = true
        waveformPlayhead.layer?.backgroundColor = palette.head.cgColor
        spectrogramPlayhead.layer?.backgroundColor = palette.head.cgColor
        progressFill.layer?.backgroundColor = palette.ink.cgColor
        waveformPane.needsDisplay = true
        spectrogramPane.needsDisplay = true
    }

    func setProgress(visible: Bool, fraction: Double) {
        showProgress = visible
        progressFraction = min(max(fraction, 0), 1)
        needsLayout = true
    }

    func advanceReveal() {
        waveformPane.advanceReveal()
        spectrogramPane.advanceReveal()
    }

    var revealCaughtUp: Bool {
        waveformPane.revealCaughtUp && spectrogramPane.revealCaughtUp
    }

    func setWaveform(snapshot: WaveformSnapshot, amplitude: WaveformAmplitude, color: WaveformColor) {
        waveformPane.setWaveform(snapshot: snapshot, amplitude: amplitude, color: color)
    }

    func clearWaveform() {
        waveformPane.clearWaveform()
    }

    func setSpectrogram(
        columns: [[[Float]]],
        totalColumns: Int,
        type: SpectrogramType,
        nFFT: Int,
        sampleRate: Double,
        fmin: Double,
        fmax: Double,
        decibels: Bool,
        dbFloor: Double,
        dbRange: Double,
        colorMap: SpectrogramColorMap
    ) {
        spectrogramPane.setSpectrogram(
            columns: columns,
            totalColumns: totalColumns,
            type: type,
            nFFT: nFFT,
            sampleRate: sampleRate,
            fmin: fmin,
            fmax: fmax,
            decibels: decibels,
            dbFloor: dbFloor,
            dbRange: dbRange,
            colorMap: colorMap
        )
    }

    func clearSpectrogram() {
        spectrogramPane.clearSpectrogram()
    }

    func setFrequencyAxis(shown: Bool, sampleRate: Double) {
        spectrogramPane.setFrequencyAxis(shown: shown, sampleRate: sampleRate)
    }

    func setTimeAxis(shown: Bool, duration: Double) {
        let onWaveform = shown && showWaveform && !showSpectrogram
        let onSpectrogram = shown && showSpectrogram
        waveformPane.setTimeAxis(shown: onWaveform, duration: duration)
        spectrogramPane.setTimeAxis(shown: onSpectrogram, duration: duration)
    }

}

enum ScrubPhase {
    case began
    case moved
    case ended
}

final class SlipPaneView: NSView {
    var onScrub: ((Double, ScrubPhase) -> Void)?
    private let imageQueue = DispatchQueue(label: "com.landschoot.audiopeek.spectrogram-image")
    private let buildLock = NSLock()
    private var lanes: [[WaveformColumn]] = []
    private var columnCount = 0
    private var amplitude = WaveformAmplitude.linear
    private var waveformColor = WaveformColor.systemBlue
    private var spectrogramImages: [CGImage] = []
    private var spectrogramColumnCount = 0
    private var spectrogramBuild = 0
    private var revealedColumns: CGFloat = 0
    private var targetColumns: CGFloat = 0
    var onRevealTargetRaised: () -> Void = {}
    var revealedColumnCount: CGFloat { revealedColumns }
    var revealTarget: CGFloat { targetColumns }
    private(set) var showsFrequencyAxis = false
    private var frequencyNyquist = 0.0
    private(set) var showsTimeAxis = false
    private var timeDuration = 0.0
    private(set) var isStretching = false
    private var stretchSnapshot: NSBitmapImageRep?
    private(set) var drawCount = 0

    var hasStretchSnapshot: Bool { stretchSnapshot != nil }

    override var wantsUpdateLayer: Bool { isStretching }

    override var isFlipped: Bool { true }

    func setWaveform(snapshot: WaveformSnapshot, amplitude: WaveformAmplitude, color: WaveformColor) {
        lanes = snapshot.lanes
        columnCount = snapshot.columnCount
        self.amplitude = amplitude
        waveformColor = color
        setRevealTarget(snapshot.lanes.map(\.count).max() ?? 0)
        if !isStretching {
            needsDisplay = true
        }
    }

    func clearWaveform() {
        lanes = []
        columnCount = 0
        revealedColumns = 0
        targetColumns = 0
        if !isStretching {
            needsDisplay = true
        }
    }

    func setSpectrogram(
        columns: [[[Float]]],
        totalColumns: Int,
        type: SpectrogramType,
        nFFT: Int,
        sampleRate: Double,
        fmin: Double,
        fmax: Double,
        decibels: Bool,
        dbFloor: Double,
        dbRange: Double,
        colorMap: SpectrogramColorMap
    ) {
        spectrogramColumnCount = max(totalColumns, columns.first?.count ?? 0)
        let build = nextSpectrogramBuild()
        let captured = columns
        imageQueue.async { [weak self] in
            guard let self, self.isCurrentSpectrogramBuild(build) else { return }
            let images = SpectrogramImage.make(
                columns: captured,
                type: type,
                nFFT: nFFT,
                sampleRate: sampleRate,
                fmin: fmin,
                fmax: fmax,
                decibels: decibels,
                dbFloor: dbFloor,
                dbRange: dbRange,
                colorMap: colorMap
            )
            DispatchQueue.main.async {
                guard self.isCurrentSpectrogramBuild(build) else { return }
                self.spectrogramImages = images
                self.setRevealTarget(images.first?.width ?? 0)
                if !self.isStretching {
                    self.needsDisplay = true
                }
            }
        }
    }

    func clearSpectrogram() {
        spectrogramImages = []
        spectrogramColumnCount = 0
        _ = nextSpectrogramBuild()
        revealedColumns = 0
        targetColumns = 0
        if !isStretching {
            needsDisplay = true
        }
    }

    func setFrequencyAxis(shown: Bool, sampleRate: Double) {
        let nyquist = sampleRate > 0 ? sampleRate / 2 : 0
        let changed = shown != showsFrequencyAxis || nyquist != frequencyNyquist
        showsFrequencyAxis = shown
        frequencyNyquist = nyquist
        if changed, !isStretching {
            needsDisplay = true
        }
    }

    func setTimeAxis(shown: Bool, duration: Double) {
        let changed = shown != showsTimeAxis || abs(duration - timeDuration) > 0.0001
        showsTimeAxis = shown
        timeDuration = duration
        if changed, !isStretching {
            needsDisplay = true
        }
    }

    var frequencyTickLabels: [String] {
        guard showsFrequencyAxis else { return [] }
        return FrequencyAxisTicks.layout(height: bounds.height, nyquist: frequencyNyquist).map(\.label)
    }

    var timeTickLabels: [String] {
        guard showsTimeAxis else { return [] }
        return TimeAxisTicks.layout(width: bounds.width, duration: timeDuration).compactMap { tick in
            tick.label.isEmpty ? nil : tick.label
        }
    }

    func beginStretch() {
        guard !isStretching else { return }
        wantsLayer = true
        let snapshot = captureSnapshot()
        isStretching = true
        stretchSnapshot = snapshot
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contents = snapshot?.cgImage
    }

    func endStretch() {
        guard isStretching else { return }
        isStretching = false
        stretchSnapshot = nil
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.contents = nil
        needsDisplay = true
    }

    override func updateLayer() {
        guard isStretching else { return }
        layer?.contentsGravity = .resize
        layer?.contents = stretchSnapshot?.cgImage
    }

    private func captureSnapshot() -> NSBitmapImageRep? {
        let rect = bounds
        guard rect.width > 1, rect.height > 1 else { return nil }
        if let rep = bitmapImageRepForCachingDisplay(in: rect) {
            cacheDisplay(in: rect, to: rep)
            return rep
        }
        let pixelsWide = max(1, Int(rect.width.rounded(.up)))
        let pixelsHigh = max(1, Int(rect.height.rounded(.up)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        cacheDisplay(in: rect, to: rep)
        return rep
    }

    private func nextSpectrogramBuild() -> Int {
        buildLock.lock()
        spectrogramBuild += 1
        let build = spectrogramBuild
        buildLock.unlock()
        return build
    }

    private func isCurrentSpectrogramBuild(_ build: Int) -> Bool {
        buildLock.lock()
        let current = spectrogramBuild == build
        buildLock.unlock()
        return current
    }

    func advanceReveal() {
        if isStretching { return }
        let gap = targetColumns - revealedColumns
        if revealCaughtUp {
            guard revealedColumns != targetColumns else { return }
            revealedColumns = targetColumns
            needsDisplay = true
            return
        }
        let step = max(gap * (1.0 / 60.0) / 0.12, 0.2)
        revealedColumns = min(targetColumns, revealedColumns + step)
        needsDisplay = true
    }

    var revealCaughtUp: Bool {
        targetColumns - revealedColumns <= 0.35
    }

    private func setRevealTarget(_ count: Int) {
        let next = CGFloat(max(count, 0))
        let raised = next > targetColumns
        let rewound = next + 1 < targetColumns
        if rewound {
            revealedColumns = 0
        }
        targetColumns = next
        if raised || rewound {
            onRevealTargetRaised()
        }
    }

    private func revealClipWidth(total: Int) -> CGFloat {
        let span = CGFloat(max(total, 1))
        return bounds.width * min(max(revealedColumns, 0), span) / span
    }

    override func draw(_ dirtyRect: NSRect) {
        if isStretching { return }
        drawCount += 1
        if !spectrogramImages.isEmpty {
            drawSpectrogram()
            drawFrequencyAxis()
        } else {
            drawWaveform()
        }
        drawTimeAxis()
    }

    private func drawWaveform() {
        guard columnCount > 0, let lane = lanes.first, !lane.isEmpty else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: revealClipWidth(total: columnCount), height: bounds.height))
        defer { ctx.restoreGState() }
        let color = resolvedColor()
        let gap: CGFloat = lanes.count > 1 ? 3 : 0
        let laneHeight = max(1, (bounds.height - gap * CGFloat(max(lanes.count - 1, 0))) / CGFloat(lanes.count))
        let slot = bounds.width / CGFloat(columnCount)
        for (index, lane) in lanes.enumerated() {
            let count = min(lane.count, columnCount)
            guard count > 0 else { continue }
            let y0 = CGFloat(index) * (laneHeight + gap)
            // A CGPath, not an NSBezierPath: stroking this many-point outline
            // through NSBezierPath ran about 30 times slower on the main thread.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: yPosition(lane[0].maximum, y0: y0, height: laneHeight)))
            for column in 0..<count {
                path.addLine(to: CGPoint(x: slot * CGFloat(column), y: yPosition(lane[column].maximum, y0: y0, height: laneHeight)))
            }
            path.addLine(to: CGPoint(x: slot * CGFloat(count), y: yPosition(lane[count - 1].maximum, y0: y0, height: laneHeight)))
            for column in stride(from: count - 1, through: 0, by: -1) {
                path.addLine(to: CGPoint(x: slot * CGFloat(column), y: yPosition(lane[column].minimum, y0: y0, height: laneHeight)))
            }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(color.withAlphaComponent(0.72).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            if amplitude == .linear {
                let mid = NSBezierPath()
                let y = y0 + laneHeight / 2
                mid.move(to: NSPoint(x: 0, y: y))
                mid.line(to: NSPoint(x: bounds.width, y: y))
                color.withAlphaComponent(0.22).setStroke()
                mid.stroke()
            }
        }
    }

    private func drawSpectrogram() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: revealClipWidth(total: spectrogramColumnCount), height: bounds.height))
        defer { ctx.restoreGState() }
        let gap: CGFloat = spectrogramImages.count > 1 ? 3 : 0
        let laneHeight = max(1, (bounds.height - gap * CGFloat(max(spectrogramImages.count - 1, 0))) / CGFloat(spectrogramImages.count))
        for (index, image) in spectrogramImages.enumerated() {
            let rect = CGRect(
                x: 0,
                y: CGFloat(index) * (laneHeight + gap),
                width: bounds.width,
                height: laneHeight
            )
            ctx.saveGState()
            ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .none
            let filled = CGFloat(image.width)
            let total = CGFloat(max(spectrogramColumnCount, Int(filled), 1))
            let drawWidth = bounds.width * filled / total
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: drawWidth, height: rect.height))
            ctx.restoreGState()
        }
    }

    private func drawFrequencyAxis() {
        guard showsFrequencyAxis, frequencyNyquist > FrequencyAxisTicks.audibleFloor else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: bounds)
        defer { ctx.restoreGState() }
        let images = spectrogramImages.isEmpty ? 1 : spectrogramImages.count
        let gap: CGFloat = images > 1 ? 3 : 0
        let laneHeight = max(1, (bounds.height - gap * CGFloat(max(images - 1, 0))) / CGFloat(images))
        var obstacles: [NSRect] = []
        var topLane = CGRect.zero
        var topTicks: [FrequencyAxisTicks.Tick] = []
        for index in 0..<images {
            let lane = CGRect(
                x: 0,
                y: CGFloat(index) * (laneHeight + gap),
                width: bounds.width,
                height: laneHeight
            )
            if index == 0 {
                topLane = lane
                topTicks = FrequencyAxisTicks.layout(height: lane.height, nyquist: frequencyNyquist)
            }
            let ticks = FrequencyAxisTicks.layout(height: lane.height, nyquist: frequencyNyquist)
            obstacles.append(contentsOf: ticks.map { FrequencyAxisTicks.labelFrame(for: $0, in: lane) })
            drawFrequencyLabels(in: lane)
        }
        let timeBand: CGFloat = showsTimeAxis && timeDuration > 0 ? 22 : 0
        if timeBand > 0 {
            obstacles.append(NSRect(x: 0, y: bounds.maxY - timeBand, width: bounds.width, height: timeBand))
        }
        if !topTicks.isEmpty, let unit = FrequencyAxisTicks.placedUnit(ticks: topTicks, in: topLane, avoiding: obstacles) {
            AxisLabelChrome.drawUnit(unit.text, frame: unit.frame, clip: bounds)
        }
    }

    private func drawFrequencyLabels(in lane: CGRect) {
        let ticks = FrequencyAxisTicks.layout(height: lane.height, nyquist: frequencyNyquist)
        guard !ticks.isEmpty else { return }
        let clip = bounds.intersection(lane)
        guard clip.width > 0, clip.height > 0 else { return }
        let timeBand: CGFloat = showsTimeAxis && timeDuration > 0 ? 22 : 0
        for tick in ticks {
            let center = lane.minY + tick.centerY
            if timeBand > 0, center > lane.maxY - timeBand {
                continue
            }
            let frame = FrequencyAxisTicks.labelFrame(for: tick, in: lane)
            AxisLabelChrome.drawLabel(tick.label, textOrigin: frame.origin, in: self, clip: clip)
            AxisLabelChrome.drawTick(
                from: NSPoint(x: lane.minX + 2, y: center),
                to: NSPoint(x: lane.minX + 2 + AxisLabelChrome.tickLength, y: center),
                clip: clip
            )
        }
    }

    private func drawTimeAxis() {
        guard showsTimeAxis, timeDuration > 0 else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: bounds)
        defer { ctx.restoreGState() }
        let ticks = TimeAxisTicks.layout(width: bounds.width, duration: timeDuration)
        guard !ticks.isEmpty else { return }
        let baseline = bounds.maxY - 2
        let tickTop = baseline - AxisLabelChrome.tickLength
        for tick in ticks {
            if let frame = TimeAxisTicks.labelFrame(for: tick, width: bounds.width, tickTop: tickTop) {
                AxisLabelChrome.drawLabel(tick.label, textOrigin: frame.origin, in: self, clip: bounds)
            }
            AxisLabelChrome.drawTick(
                from: NSPoint(x: tick.centerX, y: tickTop),
                to: NSPoint(x: tick.centerX, y: baseline),
                clip: bounds
            )
        }
        if let unit = TimeAxisTicks.placedUnit(ticks: ticks, duration: timeDuration, pane: bounds, tickTop: tickTop) {
            AxisLabelChrome.drawUnit(unit.text, frame: unit.frame, clip: bounds)
        }
    }

    func drawSpectrogramAxisChromeForTest(label: String, textOrigin: NSPoint, tickStart: NSPoint, tickEnd: NSPoint, clip: NSRect) {
        AxisLabelChrome.drawLabel(label, textOrigin: textOrigin, in: self, clip: clip)
        AxisLabelChrome.drawTick(from: tickStart, to: tickEnd, clip: clip)
    }

    override func mouseDown(with event: NSEvent) {
        guard bounds.width > 1 else { return }
        report(event, .began)
        window?.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event else { return }
            if event.type == .leftMouseUp {
                self.report(event, .ended)
                stop.pointee = true
                return
            }
            self.report(event, .moved)
        }
    }

    private func report(_ event: NSEvent, _ phase: ScrubPhase) {
        let local = convert(event.locationInWindow, from: nil)
        let fraction = min(1, max(0, Double(local.x / bounds.width)))
        onScrub?(fraction, phase)
    }

    private func yPosition(_ amplitudeValue: Float, y0: CGFloat, height: CGFloat) -> CGFloat {
        let unit: CGFloat
        switch amplitude {
        case .linear:
            let clamped = min(1, max(-1, amplitudeValue))
            unit = CGFloat((clamped + 1) * 0.5)
        case .decibels:
            unit = CGFloat(WaveformColumns.decibelUnit(amplitudeValue))
        }
        return y0 + (1 - unit) * height
    }

    func resolvedWaveformRGB(appearance: NSAppearance) -> (Double, Double, Double) {
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        appearance.performAsCurrentDrawingAppearance {
            let color = resolvedColor()
            let rgb = color.usingColorSpace(.sRGB) ?? color
            red = Double(rgb.redComponent)
            green = Double(rgb.greenComponent)
            blue = Double(rgb.blueComponent)
        }
        return (red, green, blue)
    }

    private func resolvedColor() -> NSColor {
        if waveformColor.usesSystemBlue {
            return .systemBlue
        }
        return NSColor(
            srgbRed: waveformColor.red,
            green: waveformColor.green,
            blue: waveformColor.blue,
            alpha: waveformColor.alpha
        )
    }
}

extension SlipContentView {
    @objc fileprivate func playPressed() {
        playClicks += 1
        onPlay()
    }

    @objc private func volumeChanged() {
        onVolume(volumeSlider.doubleValue)
    }

    @objc private func gearPressed() {
        onGear()
    }

    @objc private func loopPressed() {
        onLoop(loopButton.state == .on)
    }
}

enum SpectrogramImage {
    static func make(
        columns: [[[Float]]],
        type: SpectrogramType,
        nFFT: Int,
        sampleRate: Double,
        fmin: Double,
        fmax: Double,
        decibels: Bool,
        dbFloor: Double,
        dbRange: Double,
        colorMap: SpectrogramColorMap = .magma
    ) -> [CGImage] {
        guard let first = columns.first, let bins = first.first?.count, bins > 0 else { return [] }
        let width = first.count
        guard width > 0 else { return [] }
        var peak: Float = 0
        if !decibels {
            for lane in columns {
                for column in lane {
                    for value in column where value > peak {
                        peak = value
                    }
                }
            }
        }
        return columns.compactMap { lane in
            guard lane.count == width, lane.first?.count == bins else { return nil }
            return image(
                lane: lane,
                bins: bins,
                type: type,
                nFFT: nFFT,
                sampleRate: sampleRate,
                fmin: fmin,
                fmax: fmax,
                decibels: decibels,
                dbFloor: dbFloor,
                dbRange: dbRange,
                peak: peak,
                colorMap: colorMap
            )
        }
    }

    private static func image(
        lane: [[Float]],
        bins: Int,
        type: SpectrogramType,
        nFFT: Int,
        sampleRate: Double,
        fmin: Double,
        fmax: Double,
        decibels: Bool,
        dbFloor: Double,
        dbRange: Double,
        peak: Float,
        colorMap: SpectrogramColorMap
    ) -> CGImage? {
        let width = lane.count
        let height = min(bins, 256)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let bin = binIndex(
                rowFromTop: row,
                rows: height,
                bins: bins,
                type: type,
                nFFT: nFFT,
                sampleRate: sampleRate,
                fmin: fmin,
                fmax: fmax
            )
            for column in 0..<width {
                let power = bin < lane[column].count ? lane[column][bin] : 0
                let unit = unit(
                    power: power,
                    decibels: decibels,
                    dbFloor: dbFloor,
                    dbRange: dbRange,
                    peak: peak
                )
                let color = colorMap.components(unit)
                let offset = (row * width + column) * 4
                pixels[offset] = UInt8(color.0 * 255)
                pixels[offset + 1] = UInt8(color.1 * 255)
                pixels[offset + 2] = UInt8(color.2 * 255)
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func unit(power: Float, decibels: Bool, dbFloor: Double, dbRange: Double, peak: Float) -> CGFloat {
        if decibels {
            guard dbRange != 0 else { return 0 }
            let db = power > 0 ? 10 * log10(Double(power)) : dbFloor
            return CGFloat(min(1, max(0, (db - dbFloor) / dbRange)))
        }
        guard peak > 0 else { return 0 }
        return CGFloat(min(1, max(0, power / peak)))
    }

    private static func binIndex(
        rowFromTop row: Int,
        rows: Int,
        bins: Int,
        type: SpectrogramType,
        nFFT: Int,
        sampleRate: Double,
        fmin: Double,
        fmax: Double
    ) -> Int {
        if type == .logFrequency, sampleRate > 0, nFFT > 1, fmax > 0 {
            let fromBottom = 1 - (Double(row) + 0.5) / Double(max(rows, 1))
            let low = max(fmin, sampleRate / Double(nFFT))
            let high = max(fmax, low)
            guard low > 0, high > low else { return scaledBin(row, rows: rows, bins: bins) }
            let freq = exp(log(low) + (log(high) - log(low)) * fromBottom)
            let bin = Int((freq * Double(nFFT) / sampleRate).rounded())
            return min(bins - 1, max(0, bin))
        }
        return scaledBin(row, rows: rows, bins: bins)
    }

    private static func scaledBin(_ row: Int, rows: Int, bins: Int) -> Int {
        guard rows > 1, bins > 1 else { return 0 }
        let fromTop = Double(row) / Double(rows - 1)
        let bin = Int((Double(bins - 1) * (1 - fromTop)).rounded())
        return min(bins - 1, max(0, bin))
    }
}
