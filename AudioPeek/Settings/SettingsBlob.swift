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

enum SpectrogramColorMap: String, Codable, Equatable, Sendable {
    case magma
    case inferno
    case viridis
    case gray

    func components(_ unit: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        let stops = self.stops
        let clamped = min(1, max(0, unit))
        let scaled = clamped * CGFloat(stops.count - 1)
        let index = min(stops.count - 2, max(0, Int(scaled)))
        let fraction = scaled - CGFloat(index)
        let start = stops[index]
        let end = stops[index + 1]
        return (
            start.0 + (end.0 - start.0) * fraction,
            start.1 + (end.1 - start.1) * fraction,
            start.2 + (end.2 - start.2) * fraction
        )
    }

    private var stops: [(CGFloat, CGFloat, CGFloat)] {
        switch self {
        case .magma:
            return Self.magmaStops
        case .inferno:
            return Self.infernoStops
        case .viridis:
            return Self.viridisStops
        case .gray:
            return [(0, 0, 0), (1, 1, 1)]
        }
    }

    private static let magmaStops: [(CGFloat, CGFloat, CGFloat)] = [
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

    private static let infernoStops: [(CGFloat, CGFloat, CGFloat)] = [
        (0.001, 0.000, 0.014),
        (0.122, 0.047, 0.282),
        (0.341, 0.062, 0.429),
        (0.563, 0.107, 0.436),
        (0.762, 0.197, 0.343),
        (0.928, 0.353, 0.125),
        (0.988, 0.645, 0.040),
        (0.988, 0.998, 0.645),
    ]

    private static let viridisStops: [(CGFloat, CGFloat, CGFloat)] = [
        (0.267, 0.005, 0.329),
        (0.283, 0.141, 0.458),
        (0.254, 0.265, 0.530),
        (0.207, 0.372, 0.553),
        (0.164, 0.471, 0.558),
        (0.128, 0.567, 0.551),
        (0.135, 0.659, 0.518),
        (0.267, 0.749, 0.441),
        (0.478, 0.821, 0.318),
        (0.741, 0.873, 0.150),
        (0.993, 0.906, 0.144),
    ]
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

struct SpectrogramSettings: Equatable {
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
    var colorMap: SpectrogramColorMap

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
        dbRange: 80,
        colorMap: .magma
    )
}

extension SpectrogramSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case nFFT
        case hop
        case window
        case nMels
        case fmin
        case fmax
        case decibelsEnabled
        case dbFloor
        case dbRange
        case colorMap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(SpectrogramType.self, forKey: .type)
        nFFT = try container.decode(Int.self, forKey: .nFFT)
        hop = try container.decode(Int.self, forKey: .hop)
        window = try container.decode(FFTWindow.self, forKey: .window)
        nMels = try container.decode(Int.self, forKey: .nMels)
        fmin = try container.decode(Double.self, forKey: .fmin)
        fmax = try container.decodeIfPresent(Double.self, forKey: .fmax)
        decibelsEnabled = try container.decode(Bool.self, forKey: .decibelsEnabled)
        dbFloor = try container.decode(Double.self, forKey: .dbFloor)
        dbRange = try container.decode(Double.self, forKey: .dbRange)
        colorMap = try container.decodeIfPresent(SpectrogramColorMap.self, forKey: .colorMap) ?? .magma
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(nFFT, forKey: .nFFT)
        try container.encode(hop, forKey: .hop)
        try container.encode(window, forKey: .window)
        try container.encode(nMels, forKey: .nMels)
        try container.encode(fmin, forKey: .fmin)
        try container.encodeIfPresent(fmax, forKey: .fmax)
        try container.encode(decibelsEnabled, forKey: .decibelsEnabled)
        try container.encode(dbFloor, forKey: .dbFloor)
        try container.encode(dbRange, forKey: .dbRange)
        try container.encode(colorMap, forKey: .colorMap)
    }
}

struct SettingsBlob: Equatable {
    var loginItemEnabled: Bool
    var didAttemptFirstLoginRegistration: Bool
    var showStatusItem: Bool
    var showDockIcon: Bool
    var hotkey: HotkeyCombo
    var showWaveform: Bool
    var showSpectrogram: Bool
    var showFrequencyAxis: Bool
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
        showFrequencyAxis: false,
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
        case showFrequencyAxis
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
        showFrequencyAxis = try container.decodeIfPresent(Bool.self, forKey: .showFrequencyAxis) ?? false
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
        try container.encode(showFrequencyAxis, forKey: .showFrequencyAxis)
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
