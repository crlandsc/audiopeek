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

struct SettingsBlob: Codable, Equatable {
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
        spectrogram: .factory,
        windowFrame: nil
    )
}
