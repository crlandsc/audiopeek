import AppKit
import AVFAudio

final class SlipWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// The panel's content, held directly: on macOS 26 it sits inside a glass view,
    /// so it is not the window's contentView.
    weak var slipContent: SlipContentView?

    // A borderless resizable panel starts AppKit's own live-resize session on
    // an edge mouse-down. That session keeps a cached frame (and the shadow
    // window keeps the old shape) while the content view also setFrames this
    // panel, so one drag shows two windows. Handle the edge here and do not
    // let that session start.
    override func sendEvent(_ event: NSEvent) {
        if !acceptsMouseMovedEvents {
            acceptsMouseMovedEvents = true
        }
        if event.type == .leftMouseDown,
           let content = slipContent,
           !content.isResizeDrag {
            let local = content.convert(event.locationInWindow, from: nil)
            if content.resizeEdges(at: local).isActive {
                content.mouseDown(with: event)
                return
            }
        }
        super.sendEvent(event)
        if event.type == .mouseExited {
            NSCursor.arrow.set()
        } else if event.type == .mouseMoved || event.type == .mouseEntered || event.type == .cursorUpdate,
                  let content = slipContent {
            content.updateHoverCursor(with: event)
        }
    }
}

/// What arrived during a resize drag, replayed when the drag ends. The last one wins.
private enum DeferredDuringResize {
    case finderRead(FinderRead)
    case openedFile(URL)
}

/// A file opened with AudioPeek stays up while Finder still reports the selection it had
/// at the open. The first Finder reply after the open becomes that baseline.
private enum OpenedFileHold: Equatable {
    case awaitingBaseline
    case baseline(FinderRead)
}

@MainActor
final class SlipPanelController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let finder: FinderSelectionSource
    private let hotkey: HotkeyCenter
    private let onOpenSettings: () -> Void
    private let content = SlipContentView(frame: NSRect(x: 0, y: 0, width: 860, height: 500))
    /// Test hook: draw the macOS 15 solid panel even where Liquid Glass is available.
    var forceSolidChrome = false
    var usesGlass: Bool { content.usesGlass }
    private let playback = PlaybackController()
    private let gate = MachineLoadGate()
    private let overview = WaveformOverview()
    private var overviewSnapshot = WaveformSnapshot.empty
    private var appliedBlob = SettingsBlob.factory
    private var activeWave: WavePictureKey?
    private var activeSpec: SpecPictureKey?
    private var activeColumns = 0
    private var retainedLanes: [[WaveformColumn]] = []
    private var retainedSpectrogram: [[[Float]]] = []
    private var restartOverview: DispatchWorkItem?
    private var panel: SlipWindow?
    private var pollTimer: Timer?
    private var gateTimer: Timer?
    private var playheadTimer: Timer?
    private var playToggleOpen = true
    private var frameSave: DispatchWorkItem?
    private var isResizeDrag = false
    private var resizeNeedsOverview = false
    private var deferredDuringResize: DeferredDuringResize?
    /// Set while a file opened with AudioPeek (Open With, a drop, `open -a`) is up.
    /// It keeps Finder's existing selection from replacing that file.
    private var openedFileHold: OpenedFileHold?
    private(set) var panelsMade = 0
    private var epoch = 0
    private var inFlight = false
    private var currentURL: URL?
    private var openGeneration = 0
    private var forcedPanelUp: Bool?
    private var orderedOut = false
    private var appliedPreviewSpace = false
    private var injectedFrontBundleID: String?
    private(set) var requestCount = 0
    /// Finder replies that have come back, stale ones included. Equal to `requestCount` when none is in flight.
    private(set) var readCount = 0
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
        content.onScrub = { [weak self] _, fraction, phase in
            guard let self else { return }
            switch phase {
            case .began:
                self.playback.beginScrub(toFraction: fraction)
            case .moved:
                self.playback.moveScrub(toFraction: fraction)
            case .ended:
                self.playback.endScrub(toFraction: fraction)
                if self.playback.isPlaying {
                    self.ensurePlayheadTimer()
                }
            }
            self.syncPlayhead()
        }
        playback.onChange = { [weak self] in
            self?.syncPlayhead()
            self?.onActivity()
        }
        playback.setGain(store.effectiveVolume)
        playback.loopIsOn = { [weak self] in
            self?.store.blob.loopEnabled ?? false
        }
        playback.playbackAllowed = { [weak self] in
            guard let self else { return false }
            return self.gate.allowsPlayback(self.gate.sample())
        }
        content.onLoop = { [weak self] enabled in
            self?.store.update { $0.loopEnabled = enabled }
            self?.content.setLoop(enabled)
        }
        content.onGear = { [weak self] in
            self?.onOpenSettings()
        }
        content.onSplit = { [weak self] fraction in
            self?.store.update { $0.splitFraction = fraction }
        }
        content.onResizeBegan = { [weak self] in
            self?.beginResizeInteraction()
        }
        content.onResizeEnded = { [weak self] in
            self?.endResizeInteraction()
        }
        overview.onSnapshot = { [weak self] snapshot in
            self?.applyOverview(snapshot)
        }
        content.onAppearance = { [weak self] in
            self?.onActivity()
        }
        content.onRevealTargetRaised = { [weak self] in
            self?.ensurePlayheadTimer()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontApplicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        applySettings()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    var isVisible: Bool {
        if let forcedPanelUp { return forcedPanelUp }
        if orderedOut { return false }
        return panel?.isVisible ?? false
    }

    var pollScheduled: Bool { pollTimer?.isValid == true }

    var filename: String { content.filenameLabel.stringValue }

    var metadata: String { content.metadataLabel.stringValue }

    var headerOrder: [String] { content.headerOrder }

    var movableByBackground: Bool { panel?.isMovableByWindowBackground ?? false }

    var filenameToolTip: String { content.filenameLabel.toolTip ?? "" }

    var metadataToolTip: String { content.metadataLabel.toolTip ?? "" }

    var metadataMaxX: Double { Double(content.metadataLabel.frame.maxX) }

    var volumeMinX: Double { Double(content.volumeSlider.frame.minX) }

    var loopMinX: Double { Double(content.loopButton.frame.minX) }

    var gearMinX: Double { Double(content.gearButton.frame.minX) }

    var filenameWidth: Double { Double(content.filenameLabel.frame.width) }

    func hitKind(at point: NSPoint) -> String {
        content.hitKind(at: point)
    }

    var playClicks: Int { content.playClicks }

    var playbackRunning: Bool { playback.isPlaying }

    var audioEngineRunning: Bool { playback.engine.isRunning }

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

    private(set) var overviewStartCount = 0

    var playbackStartCount: Int { playback.playStartCount }

    var frequencyTickLabels: [String] { content.spectrogramPane.frequencyTickLabels }

    var timeTickLabels: [String] {
        if content.spectrogramPane.showsTimeAxis {
            return content.spectrogramPane.timeTickLabels
        }
        return content.waveformPane.timeTickLabels
    }

    var splitFraction: Double { content.splitFraction }

    var panesAreStretching: Bool {
        content.waveformPane.isStretching && content.spectrogramPane.isStretching
    }

    var panesHoldStretchSnapshot: Bool {
        content.waveformPane.hasStretchSnapshot && content.spectrogramPane.hasStretchSnapshot
    }

    func applySplitDragForTest(rawFraction: Double) {
        content.applySplitDrag(rawFraction: rawFraction)
    }

    @discardableResult
    func dividerClickForTest(clickCount: Int) -> Bool {
        if panel == nil {
            panel = makePanel()
        }
        content.layoutSubtreeIfNeeded()
        let local = NSPoint(x: content.bounds.midX, y: content.divider.frame.midY)
        let windowPoint = content.convert(local, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: content.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: clickCount,
            pressure: 1
        ) else { return false }
        content.mouseDown(with: event)
        return true
    }

    func applyScrubForTest(fraction: Double, phase: ScrubPhase) {
        content.onScrub("waveform", fraction, phase)
    }

    var overviewFirstMaximum: Double {
        guard let column = overviewSnapshot.lanes.first?.first else { return 0 }
        return Double(column.maximum)
    }

    var estimateSeconds: Double { currentEstimate }

    var progressVisible: Bool {
        OverviewEstimate.showsBar(currentEstimate) && overviewSnapshot.running && !overviewSnapshot.finished
    }

    var progressFraction: Double { overviewSnapshot.progress }

    var spectrogramLaneCount: Int { overviewSnapshot.spectrogram.count }

    var spectrogramBinCount: Int { overviewSnapshot.spectrogram.first?.first?.count ?? 0 }

    var spectrogramPeak: Double {
        var peak: Float = 0
        for lane in overviewSnapshot.spectrogram {
            for column in lane {
                for value in column where value > peak {
                    peak = value
                }
            }
        }
        return Double(peak)
    }

    var canBecomeKey: Bool { panel?.canBecomeKey ?? false }

    var isKeyWindow: Bool { panel?.isKeyWindow ?? false }

    func pressPlay() {
        content.playButton.performClick(nil)
    }

    func previewSpace() {
        guard isVisible else { return }
        togglePlay()
    }

    var frame: NSRect { panel?.frame ?? .zero }

    func viewerHotkey() {
        // Discarded. Stores the first host_statistics tick. The gate decides on a later sample.
        _ = gate.sample()
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
        content.setLoop(next.loopEnabled)
        playback.setGain(store.effectiveVolume)
        if isResizeDrag {
            if pictureChanged(appliedBlob, next) {
                resizeNeedsOverview = true
            }
            appliedBlob = next
            return
        }
        // Move the panel only when the stored frame itself changed. A resize or a
        // move saves its frame a moment later, so any other setting written in
        // between would otherwise put the panel back to the old frame.
        if let panel, let stored = next.windowFrame, stored != previous.windowFrame {
            let rect = NSRect(x: stored.x, y: stored.y, width: stored.width, height: stored.height)
            if abs(panel.frame.origin.x - rect.origin.x) > 0.5
                || abs(panel.frame.origin.y - rect.origin.y) > 0.5
                || abs(panel.frame.width - rect.width) > 0.5
                || abs(panel.frame.height - rect.height) > 0.5 {
                panel.setFrame(rect, display: true)
            }
        }
        content.layoutSubtreeIfNeeded()
        refreshPicture()
        appliedBlob = next
        refreshMetadata()
        guard isVisible, currentURL != nil else { return }
        if pictureChanged(previous, next) || abs(paneColumnCount() - activeColumns) > 4 {
            scheduleOverviewRestart()
        }
    }

    private func restartIfColumnsMoved() {
        guard isVisible, currentURL != nil else { return }
        let columns = paneColumnCount()
        if abs(columns - activeColumns) > 4 {
            scheduleOverviewRestart()
        }
    }

    func setHoverOverride(_ point: NSPoint?) {
        content.hoverOverride = point
        if let point {
            content.updateResizeHighlight(at: point, panelHit: true)
        } else {
            content.updateResizeHighlight(at: .zero, panelHit: false)
        }
    }

    var highlightEdges: SlipResizeEdges { content.resizeHighlight.edges }

    func setForcedAppearance(_ name: String) {
        let appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
        NSApp.appearance = appearance
        panel?.appearance = appearance
        content.apply(appearance: name)
    }

    var slipAppearance: String { content.appearanceName }

    var chromeRed: Double { content.chromeRGB.0 }
    var chromeGreen: Double { content.chromeRGB.1 }
    var chromeBlue: Double { content.chromeRGB.2 }
    var playheadRed: Double { content.playheadRGB.0 }
    var playheadGreen: Double { content.playheadRGB.1 }
    var playheadBlue: Double { content.playheadRGB.2 }
    var playheadWidth: Double { content.playheadWidth }
    var waveformUsesSystemBlue: Bool { store.blob.waveformColor.usesSystemBlue }
    var waveformRed: Double { content.waveformRGB().0 }
    var waveformGreen: Double { content.waveformRGB().1 }
    var waveformBlue: Double { content.waveformRGB().2 }

    func setOverviewStall(_ enabled: Bool) {
        overview.setStallBetweenChunks(enabled)
    }

    func stepOverview() {
        overview.step()
    }

    func hide() {
        openedFileHold = nil
        orderedOut = true
        openGeneration += 1
        epoch += 1
        inFlight = false
        stopPoll()
        stopPlayback()
        cancelOverview()
        retirePlayheadTimerIfIdle()
        hotkey.setEscapeEnabled(false)
        if let panel {
            panel.orderOut(nil)
        }
        applyPreviewSpacePolicy()
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
        // Snapshot our own view: offscreen captures of the glass come back blank.
        guard panel != nil else { return false }
        let view: NSView = content
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
            defer {
                self.readCount += 1
                self.onActivity()
            }
            guard token == self.epoch else { return }
            self.inFlight = false
            self.apply(read)
        }
    }

    private func apply(_ read: FinderRead) {
        if isResizeDrag {
            // A file opened during the drag outranks the poll replies that keep arriving.
            if case .openedFile = deferredDuringResize { return }
            deferredDuringResize = .finderRead(read)
            return
        }
        if case .files = read, !store.finderMessage.isEmpty {
            store.setFinderMessage("")
        }
        if holdsOpenedFile(against: read) {
            return
        }
        switch read {
        case .failed:
            stopPoll()
            store.setFinderMessage("AudioPeek could not read the Finder selection. Enable AudioPeek for Finder in System Settings > Privacy & Security > Automation, then press the hotkey again.")
            onOpenSettings()
            onActivity()
        case .files(let urls):
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

    /// True when `read` should be ignored because an opened file is up and Finder has not
    /// moved off the selection it had at the open. Any other selection ends the hold.
    private func holdsOpenedFile(against read: FinderRead) -> Bool {
        guard let hold = openedFileHold else { return false }
        if case .failed = read {
            // Someone who opened a file did not ask to follow Finder, so a failed read
            // never opens Settings here. Without the Automation grant, stop asking.
            // Any other failure (a slow Finder, a timeout) keeps polling.
            if read.isPermissionDenied {
                stopPoll()
            }
            return true
        }
        switch hold {
        case .awaitingBaseline:
            openedFileHold = .baseline(read)
            return true
        case .baseline(let baseline):
            if read == baseline { return true }
            openedFileHold = nil
            return false
        }
    }

    func openFiles(_ urls: [URL]) {
        guard case .open(let url) = SelectionDecisionMaker.decide(urls) else {
            return
        }
        if isResizeDrag {
            deferredDuringResize = .openedFile(url)
            return
        }
        show(url)
        openedFileHold = .awaitingBaseline
    }

    /// Callers defer during a resize drag, so this always runs outside one.
    private func show(_ url: URL) {
        orderedOut = false
        let window = panel ?? makePanel()
        panel = window
        let changed = currentURL != url
        currentURL = url
        if !window.isVisible {
            window.orderFrontRegardless()
            hotkey.setEscapeEnabled(true)
            startPoll()
            applyPreviewSpacePolicy()
        }
        if changed || playback.duration == 0 {
            beginOpen(url)
        }
        content.needsLayout = true
        onActivity()
    }

    nonisolated static func shouldConnectOpen(
        generation: Int,
        currentGeneration: Int,
        url: URL,
        currentURL: URL?,
        panelUp: Bool
    ) -> Bool {
        generation == currentGeneration && currentURL == url && panelUp
    }

    nonisolated static func shouldRegisterPreviewSpace(panelVisible: Bool, frontBundleID: String?) -> Bool {
        panelVisible && frontBundleID == "com.apple.finder"
    }

    func setInjectedFrontBundleID(_ bundleID: String?) {
        injectedFrontBundleID = bundleID
        applyPreviewSpacePolicy()
    }

    @objc private func frontApplicationActivated(_: Notification) {
        applyPreviewSpacePolicy()
    }

    private func applyPreviewSpacePolicy() {
        let enabled = Self.shouldRegisterPreviewSpace(
            panelVisible: panel?.isVisible ?? false,
            frontBundleID: frontBundleID()
        )
        guard enabled != appliedPreviewSpace else { return }
        appliedPreviewSpace = enabled
        hotkey.setPreviewSpaceEnabled(enabled)
    }

    private func frontBundleID() -> String? {
        if let injectedFrontBundleID {
            return injectedFrontBundleID
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func beginOpen(_ url: URL) {
        content.filenameLabel.stringValue = url.lastPathComponent
        openGeneration += 1
        let generation = openGeneration
        playback.unload()
        DispatchQueue.global(qos: .userInitiated).async {
            let read = PlaybackController.readFile(at: url)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.finishOpen(url: url, generation: generation, read: read)
                }
            }
        }
    }

    func stageOpenForTest(url: URL, generation: Int, panelUp: Bool) {
        currentURL = url
        openGeneration = generation
        forcedPanelUp = panelUp
    }

    func deliverOpenForTest(url: URL, generation: Int, read: ReadAudio?) {
        finishOpen(url: url, generation: generation, read: read)
    }

    private func finishOpen(url: URL, generation: Int, read: ReadAudio?) {
        guard Self.shouldConnectOpen(
            generation: generation,
            currentGeneration: openGeneration,
            url: url,
            currentURL: currentURL,
            panelUp: isVisible
        ) else {
            return
        }
        guard let read else {
            hide()
            return
        }
        playback.install(read)
        refreshMetadata()
        syncAxes()
        playback.setGain(store.effectiveVolume)
        onFileOpened()
        startGate()
        evaluateGate()
        startOverviewNow()
    }

    private func togglePlay() {
        // Stopping the engine drains the run loop, so one click can arrive twice.
        // The second pass would see a pause and start playback again.
        guard playToggleOpen else { return }
        playToggleOpen = false
        playback.toggle()
        if playback.isPlaying {
            ensurePlayheadTimer()
        }
        evaluateGate()
        syncPlayhead()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.playToggleOpen = true
            }
        }
    }

    private func evaluateGate(pauseIfPlaying: Bool? = nil) {
        if isResizeDrag { return }
        let sample = gate.sample()
        lastLoad = sample
        let allows = gate.allowsPlayback(sample)
        overview.setWorkAllowed(allows)
        let pausePlayback = pauseIfPlaying ?? !overview.isActive
        playback.applyGate(allows: allows && isVisible, pauseIfPlaying: pausePlayback)
        syncPlayhead()
    }

    private func syncPlayhead() {
        playback.refreshPosition()
        let fraction = playback.duration > 0 ? playback.position / playback.duration : 0
        content.setPlayhead(fraction: fraction)
        content.setPlaying(playback.isPlaying)
        refreshMetadata()
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
        ensurePlayheadTimer()
    }

    private func ensurePlayheadTimer() {
        if playheadTimer != nil { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.content.advanceReveal()
                if self.playback.isPlaying {
                    self.syncPlayhead()
                }
                self.retirePlayheadTimerIfIdle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playheadTimer = timer
    }

    private func retirePlayheadTimerIfIdle() {
        guard !playback.isPlaying, !playback.isScrubbing, content.revealCaughtUp else { return }
        playheadTimer?.invalidate()
        playheadTimer = nil
    }

    private func stopPlayback() {
        openGeneration += 1
        gateTimer?.invalidate()
        gateTimer = nil
        playback.stopKeepingEngineWarm()
        content.setPlaying(false)
        content.setPlayhead(fraction: 0)
    }

    private func makePanel() -> SlipWindow {
        if let panel {
            return panel
        }
        let rect = storedFrame() ?? defaultFrame()
        let window = SlipWindow(
            contentRect: rect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isMovableByWindowBackground = false
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
        window.slipContent = content
        if #available(macOS 26, *), !forceSolidChrome {
            // Liquid Glass behind the whole panel; our view goes inside it so AppKit keeps it legible.
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: rect.size))
            glass.style = .regular
            glass.cornerRadius = SlipLayout.cornerRadius
            content.frame = glass.bounds
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            window.contentView = glass
            content.usesGlass = true
        } else {
            window.contentView = content
            content.usesGlass = false
        }
        window.delegate = self
        window.acceptsMouseMovedEvents = true
        panelsMade += 1
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
        // A new Finder selection shows up within a quarter second. A read still
        // in flight skips the next tick, so a slow Finder cannot pile reads up.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
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
        if isResizeDrag { return }
        scheduleFrameSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if isResizeDrag { return }
        scheduleFrameSave()
        restartIfColumnsMoved()
    }

    func beginResizeInteraction() {
        guard !isResizeDrag else { return }
        isResizeDrag = true
        if restartOverview != nil {
            restartOverview?.cancel()
            restartOverview = nil
            resizeNeedsOverview = true
        }
        frameSave?.cancel()
        panel?.hasShadow = false
        content.beginResizeStretch()
    }

    func resizePanelForTest(_ rect: NSRect) {
        guard isResizeDrag, let panel else { return }
        panel.setFrame(rect, display: false)
        content.layoutSubtreeIfNeeded()
    }

    func endResizeInteraction() {
        guard isResizeDrag else { return }
        let widthChanged = abs(paneColumnCount() - activeColumns) > 4
        let needsPass = widthChanged || resizeNeedsOverview
        resizeNeedsOverview = false
        let deferred = deferredDuringResize
        deferredDuringResize = nil
        content.endResizeStretch()
        isResizeDrag = false
        if let panel {
            panel.hasShadow = true
            panel.invalidateShadow()
        }
        switch deferred {
        case .finderRead(let read):
            apply(read)
        case .openedFile(let url):
            openFiles([url])
        case nil:
            break
        }
        if needsPass {
            startOverviewNow()
        } else {
            syncFrequencyAxis()
            content.redisplayPicture()
        }
        scheduleFrameSave()
        evaluateGate(pauseIfPlaying: needsPass ? false : nil)
    }

    func sampleGateForTest() {
        evaluateGate()
    }

    private func applyOverview(_ snapshot: WaveformSnapshot) {
        var merged = snapshot
        if merged.lanes.isEmpty {
            merged.lanes = retainedLanes
        } else {
            retainedLanes = merged.lanes
        }
        if merged.spectrogram.isEmpty {
            merged.spectrogram = retainedSpectrogram
        } else {
            retainedSpectrogram = merged.spectrogram
        }
        overviewSnapshot = merged
        if isResizeDrag {
            return
        }
        let waveformBefore = content.waveformPane.revealTarget
        let spectrogramBefore = content.spectrogramPane.revealTarget
        content.setWaveform(
            snapshot: merged,
            amplitude: store.blob.waveformAmplitude,
            color: store.blob.waveformColor
        )
        let paintsSpectrogram = shouldRefreshSpectrogram(merged)
        if paintsSpectrogram {
            paintSpectrogram()
        }
        let spectrogramColumns = CGFloat(merged.spectrogram.first?.count ?? 0)
        if content.waveformPane.revealTarget > waveformBefore
            || (paintsSpectrogram && spectrogramColumns > spectrogramBefore) {
            ensurePlayheadTimer()
        }
        content.setProgress(visible: progressVisible, fraction: merged.progress)
        onActivity()
    }

    private var lastSpectrogramPaint = Date.distantPast
    private var lastSpectrogramColumns = -1

    private func shouldRefreshSpectrogram(_ snapshot: WaveformSnapshot) -> Bool {
        let count = snapshot.spectrogram.first?.count ?? 0
        if snapshot.finished || count != lastSpectrogramColumns {
            let elapsed = Date().timeIntervalSince(lastSpectrogramPaint)
            if snapshot.finished || elapsed >= 0.1 || lastSpectrogramColumns < 0 {
                lastSpectrogramColumns = count
                lastSpectrogramPaint = Date()
                return true
            }
        }
        return false
    }

    private func paintSpectrogram() {
        syncFrequencyAxis()
        let settings = store.blob.spectrogram
        let rate = playback.info?.sampleRate ?? 0
        let nyquist = rate / 2
        content.setSpectrogram(
            columns: overviewSnapshot.spectrogram,
            totalColumns: max(overviewSnapshot.columnCount, overviewSnapshot.spectrogram.first?.count ?? 0),
            type: settings.type,
            nFFT: settings.nFFT,
            sampleRate: rate,
            fmin: settings.fmin,
            fmax: min(settings.fmax ?? nyquist, nyquist),
            decibels: settings.decibelsEnabled,
            dbFloor: settings.dbFloor,
            dbRange: settings.dbRange,
            colorMap: settings.colorMap
        )
    }

    private func refreshPicture() {
        syncFrequencyAxis()
        content.setWaveform(
            snapshot: overviewSnapshot,
            amplitude: store.blob.waveformAmplitude,
            color: store.blob.waveformColor
        )
        let settings = store.blob.spectrogram
        let rate = playback.info?.sampleRate ?? 0
        let nyquist = rate / 2
        content.setSpectrogram(
            columns: overviewSnapshot.spectrogram,
            totalColumns: max(overviewSnapshot.columnCount, overviewSnapshot.spectrogram.first?.count ?? 0),
            type: settings.type,
            nFFT: settings.nFFT,
            sampleRate: rate,
            fmin: settings.fmin,
            fmax: min(settings.fmax ?? nyquist, nyquist),
            decibels: settings.decibelsEnabled,
            dbFloor: settings.dbFloor,
            dbRange: settings.dbRange,
            colorMap: settings.colorMap
        )
        content.setProgress(visible: progressVisible, fraction: overviewSnapshot.progress)
    }

    private func syncFrequencyAxis() {
        syncAxes()
    }

    private func syncAxes() {
        content.setFrequencyAxis(shown: store.blob.showFrequencyAxis, sampleRate: playback.info?.sampleRate ?? 0)
        content.setTimeAxis(shown: store.blob.showTimeAxis, duration: playback.duration)
    }

    private var currentEstimate: Double {
        guard let info = playback.info, let url = currentURL else { return 0 }
        return OverviewEstimate.seconds(
            duration: info.duration,
            sampleRate: info.sampleRate,
            compressed: OverviewEstimate.isCompressed(url: url),
            spectrogramDualVisible: store.blob.showSpectrogram && store.blob.spectrogramDual
        )
    }

    private func refreshMetadata() {
        guard let info = playback.info, let url = currentURL else { return }
        let waveformShowing = WaveformColumns.showing(
            channels: info.channels,
            dual: store.blob.waveformDual && store.blob.showWaveform
        )
        let spectrogramShowing = WaveformColumns.spectrogramShowing(
            channels: info.channels,
            dual: store.blob.spectrogramDual && store.blob.showSpectrogram
        )
        let line = AudioFileKind.metadataLine(
            format: AudioFileKind.metadataLabel(for: url),
            sampleRate: info.sampleRate,
            channels: info.channels,
            duration: info.duration,
            waveformShowing: waveformShowing,
            spectrogramShowing: spectrogramShowing,
            position: playback.position
        )
        guard content.metadataLabel.stringValue != line else { return }
        content.metadataLabel.stringValue = line
        content.metadataLabel.toolTip = line
        content.needsLayout = true
    }

    private func paneColumnCount() -> Int {
        content.layoutSubtreeIfNeeded()
        let width = store.blob.showWaveform ? content.waveformPane.bounds.width : content.spectrogramPane.bounds.width
        return max(1, Int(width.rounded(.down)))
    }

    private func pictureChanged(_ old: SettingsBlob, _ new: SettingsBlob) -> Bool {
        waveKey(for: old, columns: 0) != waveKey(for: new, columns: 0)
            || specKey(for: old, columns: 0) != specKey(for: new, columns: 0)
    }

    private func waveKey(for blob: SettingsBlob, columns: Int) -> WavePictureKey {
        WavePictureKey(
            path: currentURL?.path ?? "",
            columns: columns,
        dual: blob.waveformDual,
        shown: blob.showWaveform,
        fullDetail: blob.staticOverview
    )
    }

    private func specKey(for blob: SettingsBlob, columns: Int) -> SpecPictureKey {
        let settings = blob.spectrogram
        return SpecPictureKey(
            path: currentURL?.path ?? "",
            columns: columns,
            dual: blob.spectrogramDual,
            shown: blob.showSpectrogram,
            type: settings.type,
            nFFT: settings.nFFT,
            hop: settings.hop,
            window: settings.window,
            nMels: settings.nMels,
            fmin: settings.fmin,
            fmax: settings.fmax,
            fullDetail: blob.staticOverview
        )
    }

    private func spectrogramJob() -> SpectrogramJob? {
        guard store.blob.showSpectrogram else { return nil }
        let settings = store.blob.spectrogram
        return SpectrogramJob(
            dual: store.blob.spectrogramDual,
            type: settings.type,
            nFFT: settings.nFFT,
            hop: settings.hop,
            window: settings.window,
            nMels: settings.nMels,
            fmin: settings.fmin,
            fmax: settings.fmax,
            decibels: settings.decibelsEnabled,
            dbFloor: settings.dbFloor,
            dbRange: settings.dbRange
        )
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

    func startOverviewNow() {
        restartOverview?.cancel()
        restartOverview = nil
        if isResizeDrag {
            resizeNeedsOverview = true
            return
        }
        // The file is not connected yet. Leave whatever picture is up.
        guard playback.info != nil else { return }
        guard isVisible, let url = currentURL else {
            cancelOverview()
            return
        }
        let showWaveform = store.blob.showWaveform
        let showSpectrogram = store.blob.showSpectrogram
        guard showWaveform || showSpectrogram else {
            cancelOverview()
            return
        }
        let job = spectrogramJob()
        if showSpectrogram {
            guard let job, let rate = playback.info?.sampleRate, job.isValid(sampleRate: rate) else {
                cancelOverview()
                return
            }
        }
        let columns = paneColumnCount()
        let wave = waveKey(for: store.blob, columns: columns)
        let spec = specKey(for: store.blob, columns: columns)
        if wave.path != activeWave?.path {
            retainedLanes = []
            retainedSpectrogram = []
        }
        let waveDirty = showWaveform && wave != activeWave
        let specDirty = showSpectrogram && spec != activeSpec
        activeWave = wave
        activeSpec = spec
        activeColumns = columns
        if !waveDirty && !specDirty { return }
        overviewStartCount += 1
        if waveDirty { retainedLanes = [] }
        if specDirty { retainedSpectrogram = [] }
        let inspect = OverviewDetail.inspectFrames(
            duration: playback.duration,
            fullDetail: store.blob.staticOverview,
            nFFT: store.blob.spectrogram.nFFT
        )
        var pictured = specDirty ? job : nil
        if inspect > 0, var editable = pictured {
            editable.hop = min(editable.nFFT, max(editable.hop, inspect))
            pictured = editable
        }
        overview.start(
            url: url,
            columnCount: columns,
            waveformDual: store.blob.waveformDual,
            computeWaveform: waveDirty,
            spectrogram: pictured,
            inspectPerColumn: inspect
        )
    }

    private func cancelOverview() {
        restartOverview?.cancel()
        activeWave = nil
        activeSpec = nil
        activeColumns = 0
        retainedLanes = []
        retainedSpectrogram = []
        overview.cancel()
        overviewSnapshot = .empty
        content.clearWaveform()
        content.clearSpectrogram()
        content.setProgress(visible: false, fraction: 0)
    }
}

private struct WavePictureKey: Equatable {
    var path: String
    var columns: Int
    var dual: Bool
    var shown: Bool
    var fullDetail: Bool
}

private struct SpecPictureKey: Equatable {
    var path: String
    var columns: Int
    var dual: Bool
    var shown: Bool
    var type: SpectrogramType
    var nFFT: Int
    var hop: Int
    var window: FFTWindow
    var nMels: Int
    var fmin: Double
    var fmax: Double?
    var fullDetail: Bool
}
