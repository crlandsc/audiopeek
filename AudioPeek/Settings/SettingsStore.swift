import Combine
import Foundation

struct LoginPresentation: Equatable {
    var showsRegistered: Bool
    var offersLoginItems: Bool
    var message: String
    var buttonTitle: String

    static let off = LoginPresentation(
        showsRegistered: false,
        offersLoginItems: false,
        message: "",
        buttonTitle: ""
    )

    static let registered = LoginPresentation(
        showsRegistered: true,
        offersLoginItems: false,
        message: "Registered",
        buttonTitle: ""
    )

    static let needsManual = LoginPresentation(
        showsRegistered: false,
        offersLoginItems: true,
        message: "AudioPeek could not register as a login item. Add AudioPeek under Login Items.",
        buttonTitle: "Open Login Items"
    )
}

@MainActor
final class SettingsStore: ObservableObject {
    static let blobKey = "settingsBlob"
    static let volumeKey = "volume"

    @Published private(set) var blob: SettingsBlob
    @Published private(set) var storedVolume: Double?
    @Published private(set) var loginPresentation: LoginPresentation
    @Published private(set) var lastLoginErrorCode: Int?
    @Published private(set) var finderMessage = ""

    let defaults: UserDefaults
    var onChange: (() -> Void)?

    var effectiveVolume: Double {
        min(max(storedVolume ?? 1, 0), 1)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.blob = .factory
        self.storedVolume = nil
        self.loginPresentation = .off
        self.lastLoginErrorCode = nil
        load()
    }

    func update(_ body: (inout SettingsBlob) -> Void) {
        var copy = blob
        body(&copy)
        blob = copy
        persistBlob()
        onChange?()
    }

    @discardableResult
    func setHotkey(_ combo: HotkeyCombo) -> Bool {
        if combo.isBareSpace {
            return false
        }
        update { $0.hotkey = combo }
        return true
    }

    func setUsesSystemBlue(_ uses: Bool) {
        update { blob in
            if uses {
                blob.waveformColor = .systemBlue
            } else {
                blob.waveformColor.usesSystemBlue = false
            }
        }
    }

    func setCustomWaveformColor(red: Double, green: Double, blue: Double, alpha: Double) {
        update {
            $0.waveformColor = WaveformColor(
                usesSystemBlue: false,
                red: red,
                green: green,
                blue: blue,
                alpha: alpha
            )
        }
    }

    func setFMax(_ value: Double?) {
        update { $0.spectrogram.fmax = value }
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        storedVolume = clamped
        defaults.set(clamped, forKey: Self.volumeKey)
    }

    func setFinderMessage(_ message: String) {
        finderMessage = message
    }

    func setLoginPresentation(_ presentation: LoginPresentation, errorCode: Int?) {
        loginPresentation = presentation
        lastLoginErrorCode = errorCode
    }

    /// Restores only the settings on the Waveform tab.
    func resetWaveformSettings() {
        let factory = SettingsBlob.factory
        update {
            $0.waveformDual = factory.waveformDual
            $0.waveformAmplitude = factory.waveformAmplitude
            $0.waveformColor = factory.waveformColor
        }
    }

    /// Restores only the settings on the Spectrogram tab.
    func resetSpectrogramSettings() {
        let factory = SettingsBlob.factory
        update {
            $0.spectrogramDual = factory.spectrogramDual
            $0.spectrogram = factory.spectrogram
            $0.showFrequencyAxis = factory.showFrequencyAxis
            $0.showTimeAxis = factory.showTimeAxis
        }
    }

    @discardableResult
    func resetKnobs() -> Bool {
        let wasEnabled = blob.loginItemEnabled
        let frame = blob.windowFrame
        let attempted = blob.didAttemptFirstLoginRegistration
        var next = SettingsBlob.factory
        next.windowFrame = frame
        next.didAttemptFirstLoginRegistration = attempted
        blob = next
        loginPresentation = .off
        lastLoginErrorCode = nil
        finderMessage = ""
        persistBlob()
        onChange?()
        return wasEnabled
    }

    private func load() {
        if let data = defaults.data(forKey: Self.blobKey) {
            if let decoded = try? JSONDecoder().decode(SettingsBlob.self, from: data) {
                blob = decoded
            } else {
                blob = .factory
                persistBlob()
            }
        }
        if defaults.object(forKey: Self.volumeKey) != nil {
            storedVolume = defaults.double(forKey: Self.volumeKey)
        }
    }

    private func persistBlob() {
        do {
            let data = try JSONEncoder().encode(blob)
            defaults.set(data, forKey: Self.blobKey)
        } catch {
            assertionFailure("Settings blob failed to encode: \(error)")
        }
    }
}
