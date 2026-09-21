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

    var onPlay: () -> Void = {}
    var onVolume: (Double) -> Void = { _ in }
    var onGear: () -> Void = {}
    var onSplit: (Double) -> Void = { _ in }
    var onSeek: (String, Double) -> Void = { _, _ in }
    private var playheadFraction = 0.0

    var showWaveform = true
    var showSpectrogram = true
    var splitFraction = 0.5
    private(set) var playClicks = 0
    private var draggingSplit = false
    private var palette = SlipPalette.current(NSApp.effectiveAppearance)

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
        waveformPane.onClick = { [weak self] fraction in
            self?.onSeek("waveform", fraction)
        }
        spectrogramPane.onClick = { [weak self] fraction in
            self?.onSeek("spectrogram", fraction)
        }
        waveformPlayhead.setAccessibilityIdentifier("slip.playhead.waveform")
        spectrogramPlayhead.setAccessibilityIdentifier("slip.playhead.spectrogram")

        for view in [playButton, filenameLabel, metadataLabel, volumeSlider, gearButton, waveformPane, spectrogramPane, divider] {
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
        filenameLabel.frame = NSRect(x: nameX, y: 0, width: nameWidth, height: headerHeight)
        metadataLabel.frame = NSRect(x: nameX + nameWidth + gap, y: 0, width: metaWidth, height: headerHeight)

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

    private func applyPalette() {
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
    }

}

final class SlipPaneView: NSView {
    var onClick: ((Double) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.width > 1 else { return }
        onClick?(Double(local.x / bounds.width))
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
