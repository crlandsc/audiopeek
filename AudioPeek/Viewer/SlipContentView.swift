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
    let loopButton = NSButton()
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
    var onLoop: (Bool) -> Void = { _ in }
    var onSplit: (Double) -> Void = { _ in }
    var onSeek: (String, Double) -> Void = { _, _ in }
    var onScrub: (String, Double, ScrubPhase) -> Void = { _, _, _ in }
    var onResizeEnd: () -> Void = {}
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
        metadataLabel.alignment = .right
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
        waveformPlayhead.setAccessibilityIdentifier("slip.playhead.waveform")
        spectrogramPlayhead.setAccessibilityIdentifier("slip.playhead.spectrogram")
        progressFill.wantsLayer = true
        progressFill.isHidden = true
        progressFill.setAccessibilityIdentifier("slip.progress")

        for view in [playButton, filenameLabel, metadataLabel, volumeSlider, loopButton, gearButton, waveformPane, spectrogramPane, divider, progressFill] {
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
        loopButton.contentTintColor = enabled ? palette.head : palette.muted
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
        let loopX = gearX - gap - button
        loopButton.frame = NSRect(x: loopX, y: (headerHeight - button) / 2, width: button, height: button)
        let volumeX = loopX - gap - volumeWidth
        volumeSlider.frame = NSRect(x: volumeX, y: (headerHeight - button) / 2, width: volumeWidth, height: button)
        let nameX = pad + button + gap
        let available = max(0, volumeX - gap - nameX)
        let metaWidth = min(fieldWidth(metadataLabel), available)
        let metaX = volumeX - gap - metaWidth
        let nameWidth = max(0, metaX - gap - nameX)
        let labelHeight = headerHeight - 2
        filenameLabel.frame = NSRect(x: nameX, y: 0, width: nameWidth, height: labelHeight)
        metadataLabel.frame = NSRect(x: metaX, y: 0, width: metaWidth, height: labelHeight)
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
        if splitHit(local) || resizeEdges(local) != (false, false) || headerBackground(local) {
            return self
        }
        return super.hitTest(point)
    }

    func hitKind(at point: NSPoint) -> String {
        if headerBackground(point) { return "header" }
        if !waveformPane.isHidden, waveformPane.frame.contains(point) { return "waveform" }
        if !spectrogramPane.isHidden, spectrogramPane.frame.contains(point) { return "spectrogram" }
        return "other"
    }

    private func headerBackground(_ point: NSPoint) -> Bool {
        guard point.y >= 0, point.y < 34, bounds.contains(point) else { return false }
        let controls = [playButton, volumeSlider, loopButton, gearButton]
        return !controls.contains { $0.frame.contains(point) }
    }

    private func fieldWidth(_ field: NSTextField) -> CGFloat {
        guard !field.stringValue.isEmpty, let cell = field.cell else { return 0 }
        let fitted = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 40)).width
        return ceil(fitted)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let edges = resizeEdges(local)
        if edges.right || edges.bottom {
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
                self.onResizeEnd()
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
        let raw = min(max((local.y - top) / body, 0.08), 0.92)
        let fraction = SplitSnap.value(raw)
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
        loopButton.contentTintColor = loopButton.state == .on ? palette.head : palette.muted
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

    func advanceReveal() {
        waveformPane.advanceReveal()
        spectrogramPane.advanceReveal()
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
    var revealedColumnCount: CGFloat { revealedColumns }

    override var isFlipped: Bool { true }

    func setWaveform(snapshot: WaveformSnapshot, amplitude: WaveformAmplitude, color: WaveformColor) {
        lanes = snapshot.lanes
        columnCount = snapshot.columnCount
        self.amplitude = amplitude
        waveformColor = color
        setRevealTarget(snapshot.lanes.map(\.count).max() ?? 0)
        needsDisplay = true
    }

    func clearWaveform() {
        lanes = []
        columnCount = 0
        revealedColumns = 0
        targetColumns = 0
        needsDisplay = true
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
                self.needsDisplay = true
            }
        }
    }

    func clearSpectrogram() {
        spectrogramImages = []
        spectrogramColumnCount = 0
        _ = nextSpectrogramBuild()
        revealedColumns = 0
        targetColumns = 0
        needsDisplay = true
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
        let gap = targetColumns - revealedColumns
        if gap <= 0.35 {
            guard revealedColumns != targetColumns else { return }
            revealedColumns = targetColumns
            needsDisplay = true
            return
        }
        let step = max(gap * (1.0 / 60.0) / 0.12, 0.2)
        revealedColumns = min(targetColumns, revealedColumns + step)
        needsDisplay = true
    }

    private func setRevealTarget(_ count: Int) {
        let next = CGFloat(max(count, 0))
        if next + 1 < targetColumns {
            revealedColumns = 0
        }
        targetColumns = next
    }

    private func revealClipWidth(total: Int) -> CGFloat {
        let span = CGFloat(max(total, 1))
        return bounds.width * min(max(revealedColumns, 0), span) / span
    }

    override func draw(_ dirtyRect: NSRect) {
        if !spectrogramImages.isEmpty {
            drawSpectrogram()
            return
        }
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
