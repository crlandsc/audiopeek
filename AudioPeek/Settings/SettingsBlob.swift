import Foundation

enum WaveformAmplitude: String, Codable, Equatable, Sendable {
    case linear
    case decibels
}

enum SpectrogramType: String, Codable, Equatable, Sendable {
    case linear
    case logFrequency
    case mel
}

enum FFTWindow: String, Codable, Equatable, Sendable {
    case hann
    case hamming
    case blackman
}

struct WaveformColor: Codable, Equatable {
    var usesSystemBlue: Bool
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let systemBlue = WaveformColor(usesSystemBlue: true, red: 0, green: 0, blue: 1, alpha: 1)
}

struct StoredWindowFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct SpectrogramSettings: Codable, Equatable {
    var type: SpectrogramType
    var nFFT: Int
    var hop: Int
    var window: FFTWindow
    var nMels: Int
    var fmin: Double
    var fmax: Double?
    var decibelsEnabled: Bool
    var dbFloor: Double
    var dbRange: Double

    static let factory = SpectrogramSettings(
        type: .mel,
        nFFT: 2048,
        hop: 512,
        window: .hann,
        nMels: 128,
        fmin: 0,
        fmax: nil,
        decibelsEnabled: true,
        dbFloor: -80,
        dbRange: 80
    )
}

struct SettingsBlob: Equatable {
    var loginItemEnabled: Bool
    var didAttemptFirstLoginRegistration: Bool
    var showStatusItem: Bool
    var showDockIcon: Bool
    var hotkey: HotkeyCombo
    var showWaveform: Bool
    var showSpectrogram: Bool
    var waveformDual: Bool
    var spectrogramDual: Bool
    var waveformAmplitude: WaveformAmplitude
    var waveformColor: WaveformColor
    var splitFraction: Double
    var loopEnabled: Bool
    var staticOverview: Bool
    var spectrogram: SpectrogramSettings
    var windowFrame: StoredWindowFrame?

    static let factory = SettingsBlob(
        loginItemEnabled: false,
        didAttemptFirstLoginRegistration: false,
        showStatusItem: true,
        showDockIcon: false,
        hotkey: .optionSpace,
        showWaveform: true,
        showSpectrogram: true,
        waveformDual: true,
        spectrogramDual: false,
        waveformAmplitude: .linear,
        waveformColor: .systemBlue,
        splitFraction: 0.5,
        loopEnabled: false,
        staticOverview: false,
        spectrogram: .factory,
        windowFrame: nil
    )
}

extension SettingsBlob: Codable {
    private enum CodingKeys: String, CodingKey {
        case loginItemEnabled
        case didAttemptFirstLoginRegistration
        case showStatusItem
        case showDockIcon
        case hotkey
        case showWaveform
        case showSpectrogram
        case waveformDual
        case spectrogramDual
        case waveformAmplitude
        case waveformColor
        case splitFraction
        case loopEnabled
        case staticOverview
        case spectrogram
        case windowFrame
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        loginItemEnabled = try container.decode(Bool.self, forKey: .loginItemEnabled)
        didAttemptFirstLoginRegistration = try container.decode(Bool.self, forKey: .didAttemptFirstLoginRegistration)
        showStatusItem = try container.decode(Bool.self, forKey: .showStatusItem)
        showDockIcon = try container.decode(Bool.self, forKey: .showDockIcon)
        hotkey = try container.decode(HotkeyCombo.self, forKey: .hotkey)
        showWaveform = try container.decode(Bool.self, forKey: .showWaveform)
        showSpectrogram = try container.decode(Bool.self, forKey: .showSpectrogram)
        waveformDual = try container.decode(Bool.self, forKey: .waveformDual)
        spectrogramDual = try container.decode(Bool.self, forKey: .spectrogramDual)
        waveformAmplitude = try container.decode(WaveformAmplitude.self, forKey: .waveformAmplitude)
        waveformColor = try container.decode(WaveformColor.self, forKey: .waveformColor)
        splitFraction = try container.decode(Double.self, forKey: .splitFraction)
        loopEnabled = try container.decodeIfPresent(Bool.self, forKey: .loopEnabled) ?? false
        staticOverview = try container.decodeIfPresent(Bool.self, forKey: .staticOverview) ?? false
        spectrogram = try container.decode(SpectrogramSettings.self, forKey: .spectrogram)
        windowFrame = try container.decodeIfPresent(StoredWindowFrame.self, forKey: .windowFrame)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(loginItemEnabled, forKey: .loginItemEnabled)
        try container.encode(didAttemptFirstLoginRegistration, forKey: .didAttemptFirstLoginRegistration)
        try container.encode(showStatusItem, forKey: .showStatusItem)
        try container.encode(showDockIcon, forKey: .showDockIcon)
        try container.encode(hotkey, forKey: .hotkey)
        try container.encode(showWaveform, forKey: .showWaveform)
        try container.encode(showSpectrogram, forKey: .showSpectrogram)
        try container.encode(waveformDual, forKey: .waveformDual)
        try container.encode(spectrogramDual, forKey: .spectrogramDual)
        try container.encode(waveformAmplitude, forKey: .waveformAmplitude)
        try container.encode(waveformColor, forKey: .waveformColor)
        try container.encode(splitFraction, forKey: .splitFraction)
        try container.encode(loopEnabled, forKey: .loopEnabled)
        try container.encode(staticOverview, forKey: .staticOverview)
        try container.encode(spectrogram, forKey: .spectrogram)
        try container.encodeIfPresent(windowFrame, forKey: .windowFrame)
    }
}

enum SplitSnap {
    static func value(_ fraction: Double) -> Double {
        abs(fraction - 0.5) < 0.02 ? 0.5 : fraction
    }
}
