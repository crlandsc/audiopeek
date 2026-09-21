import AppKit

final class SlipWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SlipPanelController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let finder: FinderSelectionSource
    private let hotkey: HotkeyCenter
    private let onOpenSettings: () -> Void
    private let content = SlipContentView(frame: NSRect(x: 0, y: 0, width: 860, height: 500))
    private let playback = PlaybackController()
    private let gate = MachineLoadGate()
    private let overview = WaveformOverview()
    private var overviewSnapshot = WaveformSnapshot.empty
    private var appliedBlob = SettingsBlob.factory
    private var activeOverview: OverviewKey?
    private var activeColumns = 0
    private var restartOverview: DispatchWorkItem?
    private var panel: SlipWindow?
    private var pollTimer: Timer?
    private var gateTimer: Timer?
    private var playheadTimer: Timer?
    private var frameSave: DispatchWorkItem?
    private var epoch = 0
    private var inFlight = false
    private var currentURL: URL?
    private(set) var requestCount = 0
    private(set) var lastLoad = LoadSample(thermal: .nominal, cpuBusy: nil)
    var onActivity: () -> Void = {}
    var onFileOpened: () -> Void = {}

    init(store: SettingsStore, finder: FinderSelectionSource, hotkey: HotkeyCenter, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.finder = finder
        self.hotkey = hotkey
        self.onOpenSettings = onOpenSettings
        super.init()
        content.onPlay = { [weak self] in
            self?.togglePlay()
        }
        content.onVolume = { [weak self] value in
            self?.store.setVolume(value)
            self?.playback.setGain(self?.store.effectiveVolume ?? value)
        }
        content.onSeek = { [weak self] _, fraction in
            self?.playback.seek(toFraction: fraction)
            self?.syncPlayhead()
        }
        playback.onChange = { [weak self] in
            self?.syncPlayhead()
            self?.onActivity()
        }
        playback.setGain(store.effectiveVolume)
        content.onGear = { [weak self] in
            self?.onOpenSettings()
        }
        content.onSplit = { [weak self] fraction in
            self?.store.update { $0.splitFraction = fraction }
        }
        overview.onSnapshot = { [weak self] snapshot in
            self?.applyOverview(snapshot)
        }
        applySettings()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    var pollScheduled: Bool { pollTimer?.isValid == true }

    var filename: String { content.filenameLabel.stringValue }

    var metadata: String { content.metadataLabel.stringValue }

    var headerOrder: [String] { content.headerOrder }

    var playClicks: Int { content.playClicks }

    var playbackRunning: Bool { playback.isPlaying }

    var playheadSeconds: TimeInterval { playback.position }

    var durationSeconds: TimeInterval { playback.duration }

    var overviewFilled: Int { overviewSnapshot.filled }

    var overviewColumnCount: Int { overviewSnapshot.columnCount }

    var overviewLaneCount: Int { overviewSnapshot.lanes.count }

    var overviewRunning: Bool { overviewSnapshot.running }

    var overviewPaused: Bool { overviewSnapshot.paused }

    var overviewFinished: Bool { overviewSnapshot.finished }

    var overviewPassID: Int { overviewSnapshot.passID }

    var overviewPeakPasses: Int { overviewSnapshot.peakPasses }

    var overviewFirstMaximum: Double {
        guard let column = overviewSnapshot.lanes.first?.first else { return 0 }
        return Double(column.maximum)
    }

    var canBecomeKey: Bool { panel?.canBecomeKey ?? false }

    var isKeyWindow: Bool { panel?.isKeyWindow ?? false }

    func pressPlay() {
        content.playButton.performClick(nil)
    }

    var frame: NSRect { panel?.frame ?? .zero }

    func viewerHotkey() {
        if isVisible {
            hide()
            return
        }
        requestSelection()
    }

    func escape() {
        guard isVisible else { return }
        hide()
    }

    func applySettings() {
        let previous = appliedBlob
        let next = store.blob
        content.apply(
            showWaveform: next.showWaveform,
            showSpectrogram: next.showSpectrogram,
            split: next.splitFraction,
            volume: store.effectiveVolume
        )
        playback.setGain(store.effectiveVolume)
        if let panel, let stored = next.windowFrame {
            let rect = NSRect(x: stored.x, y: stored.y, width: stored.width, height: stored.height)
            if abs(panel.frame.origin.x - rect.origin.x) > 0.5
                || abs(panel.frame.origin.y - rect.origin.y) > 0.5
                || abs(panel.frame.width - rect.width) > 0.5
                || abs(panel.frame.height - rect.height) > 0.5 {
                panel.setFrame(rect, display: true)
            }
        }
        content.layoutSubtreeIfNeeded()
        content.setWaveform(
            snapshot: overviewSnapshot,
            amplitude: next.waveformAmplitude,
            color: next.waveformColor
        )
        appliedBlob = next
        refreshMetadata()
        guard isVisible, currentURL != nil else { return }
        let columns = waveformColumnCount()
        if overviewInputsChanged(previous, next) || columns != activeColumns {
            scheduleOverviewRestart()
        }
    }

    func setOverviewStall(_ enabled: Bool) {
        overview.setStallBetweenChunks(enabled)
    }

    func stepOverview() {
        overview.step()
    }

    func hide() {
        epoch += 1
        inFlight = false
        stopPoll()
        stopPlayback()
        cancelOverview()
        hotkey.setEscapeEnabled(false)
        panel?.orderOut(nil)
        onActivity()
    }

    func setInjectedLoad(thermal: String, cpu: Double, applyNow: Bool) {
        let state: ProcessInfo.ThermalState
        switch thermal {
        case "fair":
            state = .fair
        case "serious":
            state = .serious
        case "critical":
            state = .critical
        default:
            state = .nominal
        }
        gate.setInjected(thermal: state, cpu: cpu)
        if applyNow {
            evaluateGate()
        }
    }

    func seek(pane: String, fraction: Double) {
        let visible: Bool
        switch pane {
        case "waveform":
            visible = store.blob.showWaveform
        case "spectrogram":
            visible = store.blob.showSpectrogram
        default:
            return
        }
        guard visible else { return }
        playback.seek(toFraction: fraction)
        syncPlayhead()
    }

    func setPanes(waveform: Bool, spectrogram: Bool) {
        store.update {
            $0.showWaveform = waveform
            $0.showSpectrogram = spectrogram
        }
    }

    func writePNG(to url: URL) -> Bool {
        guard let view = panel?.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private func requestSelection() {
        if inFlight { return }
        inFlight = true
        requestCount += 1
        let token = epoch
        finder.requestSelection { [weak self] read in
            guard let self else { return }
            guard token == self.epoch else { return }
            self.inFlight = false
            self.apply(read)
        }
    }

    private func apply(_ read: FinderRead) {
        switch read {
        case .failed:
            stopPoll()
            store.setFinderMessage("AudioPeek could not read the Finder selection. Enable AudioPeek for Finder.")
            onOpenSettings()
            onActivity()
        case .files(let urls):
            if !store.finderMessage.isEmpty {
                store.setFinderMessage("")
            }
            switch SelectionDecisionMaker.decide(urls) {
            case .open(let url):
                show(url)
            case .dismiss:
                if isVisible {
                    hide()
                } else {
                    onActivity()
                }
            }
        }
    }

    private func show(_ url: URL) {
        let window = panel ?? makePanel()
        panel = window
        let changed = currentURL != url
        currentURL = url
        if !window.isVisible {
            window.orderFrontRegardless()
            hotkey.setEscapeEnabled(true)
            startPoll()
        }
        if changed || playback.duration == 0 {
            beginOpen(url)
        }
        content.needsLayout = true
        onActivity()
    }

    private func beginOpen(_ url: URL) {
        content.filenameLabel.stringValue = url.lastPathComponent
        guard playback.open(url: url) != nil else {
            hide()
            return
        }
        refreshMetadata()
        playback.setGain(store.effectiveVolume)
        onFileOpened()
        startGate()
        evaluateGate()
        startOverviewNow()
    }

    private func togglePlay() {
        playback.toggle()
        evaluateGate()
        syncPlayhead()
    }

    private func evaluateGate() {
        let sample = gate.sample()
        lastLoad = sample
        let allows = gate.allowsPlayback(sample)
        overview.setWorkAllowed(allows)
        let pausePlayback = !overview.isActive
        playback.applyGate(allows: allows && isVisible, pauseIfPlaying: pausePlayback)
        syncPlayhead()
    }

    private func syncPlayhead() {
        playback.refreshPosition()
        let fraction = playback.duration > 0 ? playback.position / playback.duration : 0
        content.setPlayhead(fraction: fraction)
        content.setPlaying(playback.isPlaying)
    }

    private func startGate() {
        if gateTimer == nil {
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.evaluateGate()
                    self?.onActivity()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            gateTimer = timer
        }
        if playheadTimer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.playback.isPlaying else { return }
                    self.syncPlayhead()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            playheadTimer = timer
        }
    }

    private func stopPlayback() {
        gateTimer?.invalidate()
        gateTimer = nil
        playheadTimer?.invalidate()
        playheadTimer = nil
        playback.stop()
        content.setPlaying(false)
        content.setPlayhead(fraction: 0)
    }

    private func makePanel() -> SlipWindow {
        let rect = storedFrame() ?? defaultFrame()
        let window = SlipWindow(
            contentRect: rect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.becomesKeyOnlyIfNeeded = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 420, height: 280)
        window.contentView = content
        window.delegate = self
        if store.blob.windowFrame == nil {
            remember(window.frame)
        }
        return window
    }

    private func storedFrame() -> NSRect? {
        guard let frame = store.blob.windowFrame else { return nil }
        return NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private func defaultFrame() -> NSRect {
        let size = NSSize(width: 860, height: 500)
        let screen = finderScreen() ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func finderScreen() -> NSScreen? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let globalHeight = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        for window in info {
            guard (window[kCGWindowOwnerName as String] as? String) == "Finder" else { continue }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else { continue }
            let x = cgFloat(bounds["X"])
            let y = cgFloat(bounds["Y"])
            let width = cgFloat(bounds["Width"])
            let height = cgFloat(bounds["Height"])
            let appKit = NSRect(x: x, y: globalHeight - y - height, width: width, height: height)
            if let screen = NSScreen.screens.first(where: { $0.frame.intersects(appKit) }) {
                return screen
            }
        }
        return nil
    }

    private func cgFloat(_ value: Any?) -> CGFloat {
        if let number = value as? NSNumber { return CGFloat(number.doubleValue) }
        if let number = value as? CGFloat { return number }
        return 0
    }

    private func startPoll() {
        stopPoll()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPoll() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func poll() {
        guard isVisible else { return }
        requestSelection()
    }

    private func remember(_ rect: NSRect) {
        let next = StoredWindowFrame(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
        if store.blob.windowFrame == next { return }
        store.update { $0.windowFrame = next }
    }

    private func scheduleFrameSave() {
        frameSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.remember(panel.frame)
        }
        frameSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    func windowDidMove(_ notification: Notification) {
        scheduleFrameSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        scheduleFrameSave()
        scheduleOverviewRestart()
    }

    private func applyOverview(_ snapshot: WaveformSnapshot) {
        overviewSnapshot = snapshot
        content.setWaveform(
            snapshot: snapshot,
            amplitude: store.blob.waveformAmplitude,
            color: store.blob.waveformColor
        )
        onActivity()
    }

    private func refreshMetadata() {
        guard let info = playback.info, let url = currentURL else { return }
        let showing = WaveformColumns.showing(
            channels: info.channels,
            dual: store.blob.waveformDual && store.blob.showWaveform
        )
        content.metadataLabel.stringValue = AudioFileKind.metadataLine(
            format: AudioFileKind.metadataLabel(for: url),
            sampleRate: info.sampleRate,
            channels: info.channels,
            duration: info.duration,
            waveformShowing: showing
        )
    }

    private func waveformColumnCount() -> Int {
        content.layoutSubtreeIfNeeded()
        return max(1, Int(content.waveformPane.bounds.width.rounded(.down)))
    }

    private func overviewInputsChanged(_ old: SettingsBlob, _ new: SettingsBlob) -> Bool {
        old.showWaveform != new.showWaveform
            || old.showSpectrogram != new.showSpectrogram
            || old.waveformDual != new.waveformDual
            || old.waveformAmplitude != new.waveformAmplitude
            || old.spectrogram != new.spectrogram
    }

    private func scheduleOverviewRestart() {
        guard isVisible, currentURL != nil else { return }
        restartOverview?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.startOverviewNow()
        }
        restartOverview = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func startOverviewNow() {
        restartOverview?.cancel()
        guard isVisible, let url = currentURL, store.blob.showWaveform else {
            cancelOverview()
            return
        }
        let columns = waveformColumnCount()
        let key = OverviewKey(
            path: url.path,
            columns: columns,
            dual: store.blob.waveformDual,
            amplitude: store.blob.waveformAmplitude,
            showSpectrogram: store.blob.showSpectrogram,
            spectrogram: store.blob.spectrogram
        )
        if key == activeOverview, overview.isActive { return }
        activeOverview = key
        activeColumns = columns
        overview.start(url: url, columnCount: columns, dual: store.blob.waveformDual)
    }

    private func cancelOverview() {
        restartOverview?.cancel()
        activeOverview = nil
        activeColumns = 0
        overview.cancel()
        overviewSnapshot = .empty
        content.clearWaveform()
    }
}

private struct OverviewKey: Equatable {
    var path: String
    var columns: Int
    var dual: Bool
    var amplitude: WaveformAmplitude
    var showSpectrogram: Bool
    var spectrogram: SpectrogramSettings
}
