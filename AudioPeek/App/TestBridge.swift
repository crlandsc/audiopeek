import AppKit
import Foundation

struct InjectedLoad {
    var thermal: String
    var cpu: Double
}

struct TestLaunchConfig {
    var defaultsSuite: String
    var statePath: String
    var injection: InjectedLoginRegistrar.Mode?
    var finderScript: ScriptedFinderSelection.Script?
    var injectedLoad: InjectedLoad?
    var overviewStall: Bool

    func makeDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
            fputs("AudioPeek could not open the test defaults suite\n", stderr)
            exit(1)
        }
        return defaults
    }

    static func load(from arguments: [String]) -> TestLaunchConfig? {
        guard let flag = arguments.firstIndex(of: "--test-config") else {
            return nil
        }
        guard flag + 1 < arguments.count else {
            fputs("AudioPeek missing test config path\n", stderr)
            exit(1)
        }
        let url = URL(fileURLWithPath: arguments[flag + 1])
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let suite = json["defaultsSuite"] as? String,
              let statePath = json["statePath"] as? String else {
            fputs("AudioPeek could not read the test config\n", stderr)
            exit(1)
        }
        let injection: InjectedLoginRegistrar.Mode?
        if json["injectLoginFailure"] is NSNull || json["injectLoginFailure"] == nil {
            injection = nil
        } else if let name = json["injectLoginFailure"] as? String {
            switch name {
            case "invalid-signature":
                injection = .invalidSignature
            case "other":
                injection = .other
            case "succeeded":
                injection = .succeeded
            default:
                fputs("AudioPeek unknown login failure injection\n", stderr)
                exit(1)
            }
        } else {
            fputs("AudioPeek unknown login failure injection\n", stderr)
            exit(1)
        }
        return TestLaunchConfig(
            defaultsSuite: suite,
            statePath: statePath,
            injection: injection,
            finderScript: finderScript(from: json["finderSelection"]),
            injectedLoad: injectedLoad(from: json["machineLoad"]),
            overviewStall: json["overviewStall"] as? Bool ?? false
        )
    }

    private static func injectedLoad(from value: Any?) -> InjectedLoad? {
        guard let load = value as? [String: Any] else { return nil }
        let thermal = load["thermal"] as? String ?? "nominal"
        let cpu = (load["cpu"] as? NSNumber)?.doubleValue ?? 0
        return InjectedLoad(thermal: thermal, cpu: cpu)
    }

    private static func finderScript(from value: Any?) -> ScriptedFinderSelection.Script? {
        if value == nil || value is NSNull {
            return nil
        }
        if let mode = value as? String {
            switch mode {
            case "denied":
                return .denied
            case "failed":
                return .failed
            case "empty":
                return .urls([])
            default:
                return .urls([URL(fileURLWithPath: mode)])
            }
        }
        if let paths = value as? [String] {
            return .urls(paths.map { URL(fileURLWithPath: $0) })
        }
        fputs("AudioPeek unknown finder selection injection\n", stderr)
        exit(1)
    }
}

@MainActor
final class TestBridge: NSObject {
    let store: SettingsStore
    let login: LoginItemController
    let status: StatusItemController
    let settings: SettingsWindowController
    let slip: SlipPanelController
    let hotkey: HotkeyCenter
    let scriptedFinder: ScriptedFinderSelection?
    let app: AppDelegate
    let stateURL: URL
    var onOpenSettings: () -> Void = {}
    private var generation = 0
    private var probePoint = NSPoint(x: 80, y: 10)

    init(
        store: SettingsStore,
        login: LoginItemController,
        status: StatusItemController,
        settings: SettingsWindowController,
        slip: SlipPanelController,
        hotkey: HotkeyCenter,
        scriptedFinder: ScriptedFinderSelection?,
        app: AppDelegate,
        stateURL: URL
    ) {
        self.store = store
        self.login = login
        self.status = status
        self.settings = settings
        self.slip = slip
        self.hotkey = hotkey
        self.scriptedFinder = scriptedFinder
        self.app = app
        self.stateURL = stateURL
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handle(_:)),
            name: Notification.Name("com.landschoot.audiopeek.test"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        writeState()
    }

    func writeState() {
        generation += 1
        store.defaults.synchronize()
        let policy: String
        switch NSApp.activationPolicy() {
        case .regular:
            policy = "regular"
        case .accessory:
            policy = "accessory"
        case .prohibited:
            policy = "prohibited"
        @unknown default:
            policy = "unknown"
        }
        let state = TestState(
            generation: generation,
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            blob: store.blob,
            hotkeyDisplay: store.blob.hotkey.displayString,
            volumeKeyPresent: store.defaults.object(forKey: SettingsStore.volumeKey) != nil,
            storedVolume: store.storedVolume,
            activationPolicy: policy,
            statusItemVisible: status.isVisible,
            statusMenuTitles: status.menuTitles,
            settingsWindowVisible: settings.isVisible,
            loginShowsRegistered: store.loginPresentation.showsRegistered,
            loginOffersLoginItems: store.loginPresentation.offersLoginItems,
            loginMessage: store.loginPresentation.message,
            loginButtonTitle: store.loginPresentation.buttonTitle,
            loginItemEnabled: store.blob.loginItemEnabled,
            lastLoginErrorCode: store.lastLoginErrorCode,
            finderMessage: store.finderMessage,
            slipVisible: slip.isVisible,
            slipFilename: slip.filename,
            slipMetadata: slip.metadata,
            headerOrder: slip.headerOrder,
            finderPollScheduled: slip.pollScheduled,
            finderRequestCount: slip.requestCount,
            playbackRunning: slip.playbackRunning,
            audioEngineRunning: slip.audioEngineRunning,
            escapeHotkeyRegistered: hotkey.escapeRegistered,
            previewSpaceRegistered: hotkey.previewSpaceRegistered,
            viewerHotkeyStatus: Int(hotkey.viewerStatus),
            carbonDeliveries: hotkey.carbonDeliveries,
            panelCanBecomeKey: slip.canBecomeKey,
            panelIsKey: slip.isKeyWindow,
            hotkeyFactoryFellBack: app.hotkeyFactoryFellBack,
            lastProbeStatus: Int(hotkey.lastProbeStatus),
            playClicks: slip.playClicks,
            playheadSeconds: slip.playheadSeconds,
            durationSeconds: slip.durationSeconds,
            loadThermal: thermalName(slip.lastLoad.thermal),
            loadCPU: slip.lastLoad.cpuBusy,
            overviewFilled: slip.overviewFilled,
            overviewColumnCount: slip.overviewColumnCount,
            overviewLaneCount: slip.overviewLaneCount,
            overviewRunning: slip.overviewRunning,
            overviewPaused: slip.overviewPaused,
            overviewFinished: slip.overviewFinished,
            overviewPassID: slip.overviewPassID,
            overviewPeakPasses: slip.overviewPeakPasses,
            overviewFirstMaximum: slip.overviewFirstMaximum,
            progressVisible: slip.progressVisible,
            progressFraction: slip.progressFraction,
            estimateSeconds: slip.estimateSeconds,
            spectrogramLaneCount: slip.spectrogramLaneCount,
            spectrogramBinCount: slip.spectrogramBinCount,
            spectrogramPeak: slip.spectrogramPeak,
            slipAppearance: slip.slipAppearance,
            chromeRed: slip.chromeRed,
            chromeGreen: slip.chromeGreen,
            chromeBlue: slip.chromeBlue,
            playheadRed: slip.playheadRed,
            playheadGreen: slip.playheadGreen,
            playheadBlue: slip.playheadBlue,
            playheadWidth: slip.playheadWidth,
            waveformUsesSystemBlue: slip.waveformUsesSystemBlue,
            waveformRed: slip.waveformRed,
            waveformGreen: slip.waveformGreen,
            waveformBlue: slip.waveformBlue,
            settingsLabels: settings.controlLabels(),
            settingsPane: settings.currentPane.rawValue,
            settingsFrameWidth: settings.frame.width,
            settingsFrameHeight: settings.frame.height,
            settingsFrameMaxY: settings.frame.maxY,
            slipFrameX: slip.frame.origin.x,
            slipFrameY: slip.frame.origin.y,
            slipFrameWidth: slip.frame.width,
            slipFrameHeight: slip.frame.height,
            movableByBackground: slip.movableByBackground,
            filenameToolTip: slip.filenameToolTip,
            metadataToolTip: slip.metadataToolTip,
            metadataMaxX: slip.metadataMaxX,
            volumeMinX: slip.volumeMinX,
            loopMinX: slip.loopMinX,
            gearMinX: slip.gearMinX,
            filenameWidth: slip.filenameWidth,
            hitKind: slip.hitKind(at: probePoint)
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            fputs("AudioPeek could not write test state: \(error)\n", stderr)
        }
    }

    @objc private func handle(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        let command = userInfo["command"] as? String ?? ""
        switch command {
        case "dump":
            break
        case "open":
            let paths = strings("paths", in: userInfo)
            app.application(NSApp, open: paths.map { URL(fileURLWithPath: $0) })
        case "openSettings":
            onOpenSettings()
        case "selectSettingsPane":
            if let name = userInfo["pane"] as? String, let pane = SettingsPane(rawValue: name) {
                settings.select(pane)
            }
        case "snapshot":
            if let path = userInfo["path"] as? String {
                _ = settings.writePNG(to: URL(fileURLWithPath: path))
            }
        case "snapshotSlip":
            if let path = userInfo["path"] as? String {
                _ = slip.writePNG(to: URL(fileURLWithPath: path))
            }
        case "pressViewerHotkey":
            slip.viewerHotkey()
        case "dispatchViewerHotkey":
            hotkey.postViewerEvent()
        case "dispatchEscape":
            hotkey.postEscapeEvent()
        case "dispatchPreviewSpace":
            hotkey.postPreviewSpaceEvent()
        case "probeHotkey":
            let keyCode = UInt32(number("keyCode", in: userInfo) ?? 0)
            let modifiers = UInt32(number("modifiers", in: userInfo) ?? 0)
            _ = hotkey.probe(HotkeyCombo(keyCode: keyCode, carbonModifiers: modifiers))
        case "setHotkey":
            let keyCode = UInt32(number("keyCode", in: userInfo) ?? 0)
            let modifiers = UInt32(number("modifiers", in: userInfo) ?? 0)
            _ = store.setHotkey(HotkeyCombo(keyCode: keyCode, carbonModifiers: modifiers))
        case "setFinder":
            let mode = userInfo["mode"] as? String ?? "paths"
            let paths = strings("paths", in: userInfo)
            scriptedFinder?.set(mode: mode, paths: paths)
        case "setFrontApp":
            slip.setInjectedFrontBundleID(userInfo["bundleID"] as? String)
        case "pressPlay":
            slip.pressPlay()
        case "setLoad":
            let thermal = userInfo["thermal"] as? String ?? "nominal"
            let cpu = number("cpu", in: userInfo) ?? 0
            slip.setInjectedLoad(thermal: thermal, cpu: cpu, applyNow: true)
        case "seek":
            let pane = userInfo["pane"] as? String ?? "waveform"
            let fraction = number("fraction", in: userInfo) ?? 0
            slip.seek(pane: pane, fraction: fraction)
        case "setPanes":
            slip.setPanes(
                waveform: bool("waveform", in: userInfo) ?? true,
                spectrogram: bool("spectrogram", in: userInfo) ?? true
            )
        case "stepOverview":
            slip.stepOverview()
        case "setWaveformDual":
            let dual = bool("dual", in: userInfo) ?? true
            store.update { $0.waveformDual = dual }
        case "setSpectrogramDual":
            let dual = bool("dual", in: userInfo) ?? false
            store.update { $0.spectrogramDual = dual }
        case "setSpectrogramNFFT":
            let count = Int(number("nFFT", in: userInfo) ?? 2048)
            store.update { $0.spectrogram.nFFT = count }
        case "setAmplitude":
            let name = userInfo["amplitude"] as? String ?? "linear"
            store.update { $0.waveformAmplitude = name == "decibels" ? .decibels : .linear }
        case "setDbFloor":
            store.update { $0.spectrogram.dbFloor = number("floor", in: userInfo) ?? -40 }
        case "setAppearance":
            slip.setForcedAppearance(userInfo["appearance"] as? String ?? "light")
        case "setWaveformColor":
            store.setCustomWaveformColor(
                red: number("red", in: userInfo) ?? 1,
                green: number("green", in: userInfo) ?? 0,
                blue: number("blue", in: userInfo) ?? 0,
                alpha: number("alpha", in: userInfo) ?? 1
            )
        case "setSlipVolume":
            if let volume = number("volume", in: userInfo) {
                store.setVolume(volume)
                slip.applySettings()
            }
        case "hideStatusItem":
            store.update { $0.showStatusItem = false }
        case "showStatusItem":
            store.update { $0.showStatusItem = true }
        case "setDockIcon":
            let show = bool("dock", in: userInfo) ?? false
            store.update { $0.showDockIcon = show }
        case "setVolume":
            if let volume = number("volume", in: userInfo) {
                store.setVolume(volume)
            }
        case "setLoop":
            let enabled = bool("enabled", in: userInfo) ?? false
            store.update { $0.loopEnabled = enabled }
        case "probeHit":
            let x = number("x", in: userInfo) ?? 80
            let y = number("y", in: userInfo) ?? 10
            probePoint = NSPoint(x: x, y: y)
        case "setWindowFrame":
            guard let x = number("x", in: userInfo),
                  let y = number("y", in: userInfo),
                  let width = number("width", in: userInfo),
                  let height = number("height", in: userInfo) else { break }
            store.update {
                $0.windowFrame = StoredWindowFrame(x: x, y: y, width: width, height: height)
            }
        case "mutateKnobs":
            store.update { blob in
                blob.showWaveform = false
                blob.showSpectrogram = false
                blob.waveformDual = false
                blob.spectrogramDual = true
                blob.waveformAmplitude = .decibels
                blob.waveformColor = WaveformColor(usesSystemBlue: false, red: 1, green: 0, blue: 0, alpha: 1)
                blob.splitFraction = 0.25
                blob.hotkey = HotkeyCombo(keyCode: 40, carbonModifiers: HotkeyCombo.commandKey)
                blob.showDockIcon = true
                blob.showStatusItem = false
                blob.spectrogram.type = .linear
                blob.spectrogram.nFFT = 1024
                blob.spectrogram.hop = 256
                blob.spectrogram.window = .hamming
                blob.spectrogram.nMels = 64
                blob.spectrogram.fmin = 20
                blob.spectrogram.fmax = 8000
                blob.spectrogram.decibelsEnabled = false
                blob.spectrogram.dbFloor = -60
                blob.spectrogram.dbRange = 40
            }
        case "reset":
            login.reset()
        case "setLoginEnabled":
            login.setEnabled(bool("enabled", in: userInfo) ?? false)
        case "quit":
            writeState()
            NSApp.terminate(nil)
            return
        default:
            break
        }
        writeState()
    }

    private func number(_ key: String, in userInfo: [AnyHashable: Any]) -> Double? {
        if let value = userInfo[key] as? Double { return value }
        if let value = userInfo[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    private func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    private func strings(_ key: String, in userInfo: [AnyHashable: Any]) -> [String] {
        if let values = userInfo[key] as? [String] { return values }
        if let values = userInfo[key] as? [Any] {
            return values.compactMap { $0 as? String }
        }
        return []
    }

    private func bool(_ key: String, in userInfo: [AnyHashable: Any]) -> Bool? {
        if let value = userInfo[key] as? Bool { return value }
        if let value = userInfo[key] as? NSNumber { return value.boolValue }
        return nil
    }
}

private struct TestState: Encodable {
    var generation: Int
    var pid: Int
    var blob: SettingsBlob
    var hotkeyDisplay: String
    var volumeKeyPresent: Bool
    var storedVolume: Double?
    var activationPolicy: String
    var statusItemVisible: Bool
    var statusMenuTitles: [String]
    var settingsWindowVisible: Bool
    var loginShowsRegistered: Bool
    var loginOffersLoginItems: Bool
    var loginMessage: String
    var loginButtonTitle: String
    var loginItemEnabled: Bool
    var lastLoginErrorCode: Int?
    var finderMessage: String
    var slipVisible: Bool
    var slipFilename: String
    var slipMetadata: String
    var headerOrder: [String]
    var finderPollScheduled: Bool
    var finderRequestCount: Int
    var playbackRunning: Bool
    var audioEngineRunning: Bool
    var escapeHotkeyRegistered: Bool
    var previewSpaceRegistered: Bool
    var viewerHotkeyStatus: Int
    var carbonDeliveries: Int
    var panelCanBecomeKey: Bool
    var panelIsKey: Bool
    var hotkeyFactoryFellBack: Bool
    var lastProbeStatus: Int
    var playClicks: Int
    var playheadSeconds: Double
    var durationSeconds: Double
    var loadThermal: String
    var loadCPU: Double?
    var overviewFilled: Int
    var overviewColumnCount: Int
    var overviewLaneCount: Int
    var overviewRunning: Bool
    var overviewPaused: Bool
    var overviewFinished: Bool
    var overviewPassID: Int
    var overviewPeakPasses: Int
    var overviewFirstMaximum: Double
    var progressVisible: Bool
    var progressFraction: Double
    var estimateSeconds: Double
    var spectrogramLaneCount: Int
    var spectrogramBinCount: Int
    var spectrogramPeak: Double
    var slipAppearance: String
    var chromeRed: Double
    var chromeGreen: Double
    var chromeBlue: Double
    var playheadRed: Double
    var playheadGreen: Double
    var playheadBlue: Double
    var playheadWidth: Double
    var waveformUsesSystemBlue: Bool
    var waveformRed: Double
    var waveformGreen: Double
    var waveformBlue: Double
    var settingsLabels: [String]
    var settingsPane: String
    var settingsFrameWidth: Double
    var settingsFrameHeight: Double
    var settingsFrameMaxY: Double
    var slipFrameX: Double
    var slipFrameY: Double
    var slipFrameWidth: Double
    var slipFrameHeight: Double
    var movableByBackground: Bool
    var filenameToolTip: String
    var metadataToolTip: String
    var metadataMaxX: Double
    var volumeMinX: Double
    var loopMinX: Double
    var gearMinX: Double
    var filenameWidth: Double
    var hitKind: String
}
