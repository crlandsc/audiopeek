import AppKit
import Foundation

struct TestLaunchConfig {
    var defaultsSuite: String
    var statePath: String
    var injection: InjectedLoginRegistrar.Mode?

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
            default:
                fputs("AudioPeek unknown login failure injection\n", stderr)
                exit(1)
            }
        } else {
            fputs("AudioPeek unknown login failure injection\n", stderr)
            exit(1)
        }
        return TestLaunchConfig(defaultsSuite: suite, statePath: statePath, injection: injection)
    }
}

@MainActor
final class TestBridge: NSObject {
    let store: SettingsStore
    let login: LoginItemController
    let status: StatusItemController
    let settings: SettingsWindowController
    let stateURL: URL
    var onOpenSettings: () -> Void = {}
    private var generation = 0

    init(
        store: SettingsStore,
        login: LoginItemController,
        status: StatusItemController,
        settings: SettingsWindowController,
        stateURL: URL
    ) {
        self.store = store
        self.login = login
        self.status = status
        self.settings = settings
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
            lastLoginErrorCode: store.lastLoginErrorCode
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
        case "openSettings":
            onOpenSettings()
        case "snapshot":
            if let path = userInfo["path"] as? String {
                _ = settings.writePNG(to: URL(fileURLWithPath: path))
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
}
