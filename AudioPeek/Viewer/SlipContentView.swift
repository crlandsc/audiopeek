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

final class SlipContentView: NSView {
    let playButton = NSButton()
    let filenameLabel = NSTextField(labelWithString: "")
    let metadataLabel = NSTextField(labelWithString: "")
    let volumeSlider = NSSlider()
    let gearButton = NSButton()
    let waveformPane = SlipPaneView()
    let spectrogramPane = SlipPaneView()
    let divider = NSView()
    let waveformPlayhead = NSView()
    let spectrogramPlayhead = NSView()
    let progressFill = NSView()

    var onPlay: () -> Void = {}
    var onVolume: (Double) -> Void = { _ in }
    var onGear: () -> Void = {}
    var onSplit: (Double) -> Void = { _ in }
    var onSeek: (String, Double) -> Void = { _, _ in }
    var onAppearance: () -> Void = {}
    private var playheadFraction = 0.0

    var showWaveform = true
    var showSpectrogram = true
    var splitFraction = 0.5
    private(set) var playClicks = 0
    private var draggingSplit = false
    private var palette = SlipPalette.current(NSApp.effectiveAppearance)
    private var showProgress = false
    private var progressFraction = 0.0

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

        filenameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        filenameLabel.lineBreakMode = .byTruncatingTail
        filenameLabel.setAccessibilityIdentifier("slip.filename")
        metadataLabel.font = .systemFont(ofSize: 11)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.setAccessibilityIdentifier("slip.metadata")

        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.doubleValue = 1
        volumeSlider.isContinuous = true
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeSlider.setAccessibilityIdentifier("slip.volume")
        volumeSlider.setAccessibilityLabel("Volume")

        configurePlay(gearButton)
        gearButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Open settings")
        gearButton.action = #selector(gearPressed)
        gearButton.setAccessibilityIdentifier("slip.settings")
        gearButton.setAccessibilityLabel("Open settings")

        waveformPane.setAccessibilityIdentifier("slip.waveform")
        spectrogramPane.setAccessibilityIdentifier("slip.spectrogram")
        waveformPane.layerContentsRedrawPolicy = .onSetNeedsDisplay
        waveformPane.onClick = { [weak self] fraction in
            self?.onSeek("waveform", fraction)
        }
        spectrogramPane.onClick = { [weak self] fraction in
            self?.onSeek("spectrogram", fraction)
        }
        waveformPlayhead.setAccessibilityIdentifier("slip.playhead.waveform")
        spectrogramPlayhead.setAccessibilityIdentifier("slip.playhead.spectrogram")
        progressFill.wantsLayer = true
        progressFill.isHidden = true
        progressFill.setAccessibilityIdentifier("slip.progress")

        for view in [playButton, filenameLabel, metadataLabel, volumeSlider, gearButton, waveformPane, spectrogramPane, divider, progressFill] {
            addSubview(view)
        }
        waveformPane.addSubview(waveformPlayhead)
        spectrogramPane.addSubview(spectrogramPlayhead)
        applyPalette()
    }

    required init?(coder: NSCoder) {
        nil
    }

    var headerOrder: [String] {
        ["play", "filename", "metadata", "volume", "settings"]
    }

    func setPlaying(_ playing: Bool) {
        let name = playing ? "pause.fill" : "play.fill"
        playButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Play or pause")
    }

    func setPlayhead(fraction: Double) {
        playheadFraction = min(max(fraction, 0), 1)
        needsLayout = true
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
        let headerHeight: CGFloat = 34
        let pad: CGFloat = 10
        let gap: CGFloat = 8
        let button: CGFloat = 24
        let volumeWidth: CGFloat = 72
        playButton.frame = NSRect(x: pad, y: (headerHeight - button) / 2, width: button, height: button)
        let gearX = bounds.width - pad - button
        gearButton.frame = NSRect(x: gearX, y: (headerHeight - button) / 2, width: button, height: button)
        let volumeX = gearX - gap - volumeWidth
        volumeSlider.frame = NSRect(x: volumeX, y: (headerHeight - button) / 2, width: volumeWidth, height: button)
        let metaWidth = min(metadataLabel.intrinsicContentSize.width, max(0, volumeX - pad - button - gap * 3 - 80))
        let nameX = pad + button + gap
        let nameWidth = max(40, volumeX - gap - metaWidth - gap - nameX)
        let labelHeight = headerHeight - 2
        filenameLabel.frame = NSRect(x: nameX, y: 0, width: nameWidth, height: labelHeight)
        metadataLabel.frame = NSRect(x: nameX + nameWidth + gap, y: 0, width: metaWidth, height: labelHeight)
        progressFill.isHidden = !showProgress
        progressFill.frame = NSRect(
            x: 0,
            y: headerHeight - 2,
            width: bounds.width * progressFraction,
            height: 2
        )

        waveformPane.isHidden = !showWaveform
        spectrogramPane.isHidden = !showSpectrogram
        let both = showWaveform && showSpectrogram
        divider.isHidden = !both
        let top = headerHeight + 1
        let body = max(0, bounds.height - top)
        if both {
            let dividerHeight: CGFloat = 1
            let available = max(0, body - dividerHeight)
            let waveHeight = min(max(available * splitFraction, 48), max(48, available - 48))
            waveformPane.frame = NSRect(x: 0, y: top, width: bounds.width, height: waveHeight)
            divider.frame = NSRect(x: 0, y: top + waveHeight, width: bounds.width, height: dividerHeight)
            let specY = top + waveHeight + dividerHeight
            spectrogramPane.frame = NSRect(x: 0, y: specY, width: bounds.width, height: max(0, bounds.height - specY))
        } else if showWaveform {
            waveformPane.frame = NSRect(x: 0, y: top, width: bounds.width, height: body)
        } else if showSpectrogram {
            spectrogramPane.frame = NSRect(x: 0, y: top, width: bounds.width, height: body)
        }
        placePlayhead(waveformPlayhead, in: waveformPane)
        placePlayhead(spectrogramPlayhead, in: spectrogramPane)
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

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if splitHit(local) || resizeEdges(local) != (false, false) {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let edges = resizeEdges(local)
        if edges.right || edges.bottom {
            resizeWindow(from: event, edges: edges)
            return
        }
        guard splitHit(local) else {
            super.mouseDown(with: event)
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

    private func resizeEdges(_ point: NSPoint) -> (right: Bool, bottom: Bool) {
        let margin: CGFloat = 8
        return (point.x >= bounds.width - margin, point.y >= bounds.height - margin)
    }

    private func resizeWindow(from event: NSEvent, edges: (right: Bool, bottom: Bool)) {
        guard let window else { return }
        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
            guard let event else { return }
            if event.type == .leftMouseUp {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            var frame = startFrame
            if edges.right {
                frame.size.width = max(window.minSize.width, startFrame.width + mouse.x - startMouse.x)
            }
            if edges.bottom {
                let delta = mouse.y - startMouse.y
                frame.origin.y = startFrame.origin.y + delta
                frame.size.height = max(window.minSize.height, startFrame.height - delta)
            }
            window.setFrame(frame, display: true)
        }
    }

    private func updateSplit(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let top: CGFloat = 35
        let body = max(1, bounds.height - top)
        let fraction = min(max((local.y - top) / body, 0.08), 0.92)
        splitFraction = fraction
        onSplit(fraction)
        needsLayout = true
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
        button.target = self
    }

    func applyPalette() {
        palette = SlipPalette.current(effectiveAppearance)
        layer?.backgroundColor = palette.background.cgColor
        layer?.borderColor = palette.line.cgColor
        filenameLabel.textColor = palette.ink
        metadataLabel.textColor = palette.muted
        playButton.contentTintColor = palette.ink
        gearButton.contentTintColor = palette.muted
        volumeSlider.trackFillColor = palette.head
        waveformPane.wantsLayer = true
        spectrogramPane.wantsLayer = true
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

    func setWaveform(snapshot: WaveformSnapshot, amplitude: WaveformAmplitude, color: WaveformColor) {
        waveformPane.setWaveform(snapshot: snapshot, amplitude: amplitude, color: color)
    }

    func clearWaveform() {
        waveformPane.clearWaveform()
    }

    func setSpectrogram(
        columns: [[[Float]]],
        type: SpectrogramType,
        nFFT: Int,
        sampleRate: Double,
        fmin: Double,
        fmax: Double,
        decibels: Bool,
        dbFloor: Double,
        dbRange: Double
    ) {
        spectrogramPane.setSpectrogram(
            columns: columns,
            type: type,
            nFFT: nFFT,
            sampleRate: sampleRate,
            fmin: fmin,
            fmax: fmax,
            decibels: decibels,
            dbFloor: dbFloor,
            dbRange: dbRange
        )
    }

    func clearSpectrogram() {
        spectrogramPane.clearSpectrogram()
    }

}

final class SlipPaneView: NSView {
    var onClick: ((Double) -> Void)?
    private var lanes: [[WaveformColumn]] = []
    private var columnCount = 0
    private var amplitude = WaveformAmplitude.linear
    private var waveformColor = WaveformColor.systemBlue
    private var spectrogramImages: [CGImage] = []

    override var isFlipped: Bool { true }

    func setWaveform(snapshot: WaveformSnapshot, amplitude: WaveformAmplitude, color: WaveformColor) {
        lanes = snapshot.lanes
        columnCount = snapshot.columnCount
        self.amplitude = amplitude
        waveformColor = color
        needsDisplay = true
    }

    func clearWaveform() {
        lanes = []
        columnCount = 0
        needsDisplay = true
    }

    func setSpectrogram(
        columns: [[[Float]]],
        type: SpectrogramType,
        nFFT: Int,
        sampleRate: Double,
        fmin: Double,
        fmax: Double,
        decibels: Bool,
        dbFloor: Double,
        dbRange: Double
    ) {
        spectrogramImages = SpectrogramImage.make(
            columns: columns,
            type: type,
            nFFT: nFFT,
            sampleRate: sampleRate,
            fmin: fmin,
            fmax: fmax,
            decibels: decibels,
            dbFloor: dbFloor,
            dbRange: dbRange
        )
        needsDisplay = true
    }

    func clearSpectrogram() {
        spectrogramImages = []
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if !spectrogramImages.isEmpty {
            drawSpectrogram()
            return
        }
        guard columnCount > 0, let lane = lanes.first, !lane.isEmpty else { return }
        let color = resolvedColor()
        let gap: CGFloat = lanes.count > 1 ? 3 : 0
        let laneHeight = max(1, (bounds.height - gap * CGFloat(max(lanes.count - 1, 0))) / CGFloat(lanes.count))
        let slot = bounds.width / CGFloat(columnCount)
        for (index, lane) in lanes.enumerated() {
            let count = min(lane.count, columnCount)
            guard count > 0 else { continue }
            let y0 = CGFloat(index) * (laneHeight + gap)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: yPosition(lane[0].maximum, y0: y0, height: laneHeight)))
            for column in 0..<count {
                path.line(to: NSPoint(x: slot * CGFloat(column), y: yPosition(lane[column].maximum, y0: y0, height: laneHeight)))
            }
            path.line(to: NSPoint(x: slot * CGFloat(count), y: yPosition(lane[count - 1].maximum, y0: y0, height: laneHeight)))
            for column in stride(from: count - 1, through: 0, by: -1) {
                path.line(to: NSPoint(x: slot * CGFloat(column), y: yPosition(lane[column].minimum, y0: y0, height: laneHeight)))
            }
            path.close()
            color.withAlphaComponent(0.72).setFill()
            path.fill()
            color.setStroke()
            path.lineWidth = 1
            path.stroke()
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
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            ctx.restoreGState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.width > 1 else { return }
        onClick?(Double(local.x / bounds.width))
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
}

enum MagmaColor {
    private static let stops: [(CGFloat, CGFloat, CGFloat)] = [
        (0.00146, 0.00047, 0.01387),
        (0.02815, 0.02115, 0.13640),
        (0.11300, 0.04180, 0.31400),
        (0.23200, 0.05900, 0.46800),
        (0.37000, 0.08200, 0.54100),
        (0.51600, 0.10500, 0.52800),
        (0.66500, 0.15400, 0.48600),
        (0.79600, 0.23400, 0.42600),
        (0.89200, 0.34600, 0.35600),
        (0.95200, 0.48200, 0.31800),
        (0.98200, 0.62200, 0.35200),
        (0.99400, 0.76400, 0.46800),
        (0.99100, 0.89200, 0.64600),
        (0.98705, 0.99144, 0.74950),
    ]

    static func components(_ unit: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let clamped = min(1, max(0, unit))
        let scaled = clamped * CGFloat(stops.count - 1)
        let index = min(stops.count - 2, Int(scaled))
        let fraction = scaled - CGFloat(index)
        let start = stops[index]
        let end = stops[index + 1]
        return (
            start.0 + (end.0 - start.0) * fraction,
            start.1 + (end.1 - start.1) * fraction,
            start.2 + (end.2 - start.2) * fraction
        )
    }
}

private enum SpectrogramImage {
    static func make(
        columns: [[[Float]]],
        type: SpectrogramType,
        nFFT: Int,
        sampleRate: Double,
        fmin: Double,
        fmax: Double,
        decibels: Bool,
        dbFloor: Double,
        dbRange: Double
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
                peak: peak
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
        peak: Float
    ) -> CGImage? {
        let width = lane.count
        let height = bins
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
                let color = MagmaColor.components(unit)
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
            guard low > 0, high > low else { return min(bins - 1, max(0, bins - 1 - row)) }
            let freq = exp(log(low) + (log(high) - log(low)) * fromBottom)
            let bin = Int((freq * Double(nFFT) / sampleRate).rounded())
            return min(bins - 1, max(0, bin))
        }
        return min(bins - 1, max(0, bins - 1 - row))
    }
}
