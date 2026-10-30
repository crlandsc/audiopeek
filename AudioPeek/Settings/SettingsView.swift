import AppKit
import SwiftUI

extension SettingsStore {
    func binding<Value>(_ keyPath: WritableKeyPath<SettingsBlob, Value>) -> Binding<Value> {
        Binding(
            get: { self.blob[keyPath: keyPath] },
            set: { newValue in
                self.update { $0[keyPath: keyPath] = newValue }
            }
        )
    }
}

enum SettingsPane: String, CaseIterable {
    case general
    case waveform
    case spectrogram

    var title: String {
        switch self {
        case .general: "General"
        case .waveform: "Waveform"
        case .spectrogram: "Spectrogram"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .waveform: "waveform"
        case .spectrogram: "chart.bar.xaxis"
        }
    }

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("settings.pane.\(rawValue)")
    }
}

struct SettingsActions {
    var onLoginToggle: (Bool) -> Void
    var onOpenLoginItems: () -> Void
    var onOpenAutomation: () -> Void
    var onReset: () -> Void
}

// One Settings pane as a grouped form. It reports its natural height so the window can fit it.
struct SettingsPaneView: View {
    let pane: SettingsPane
    @ObservedObject var store: SettingsStore
    let actions: SettingsActions
    var onHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        Group {
            switch pane {
            case .general:
                GeneralPane(store: store, actions: actions)
            case .waveform:
                WaveformPane(store: store)
            case .spectrogram:
                SpectrogramPane(store: store)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollDisabled(true)
        .frame(width: SettingsWindowController.paneWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PaneHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(PaneHeightKey.self) { height in
            onHeight(height)
        }
    }
}

private struct PaneHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct GeneralPane: View {
    @ObservedObject var store: SettingsStore
    let actions: SettingsActions

    var body: some View {
        Form {
            if !store.finderMessage.isEmpty {
                Section("Finder access") {
                    Text(store.finderMessage)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("finder.automationMessage")
                    Button("Open Automation") {
                        actions.onOpenAutomation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .accessibilityIdentifier("finder.openAutomation")
                    .accessibilityLabel("Open Automation")
                }
            }

            Section("Startup and menu bar") {
                Toggle("Open at login", isOn: Binding(
                    get: { store.blob.loginItemEnabled },
                    set: { actions.onLoginToggle($0) }
                ))
                if store.loginPresentation.offersLoginItems {
                    Text(store.loginPresentation.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("login.manualMessage")
                    Button(store.loginPresentation.buttonTitle) {
                        actions.onOpenLoginItems()
                    }
                    .accessibilityIdentifier("login.openButton")
                }
                if store.loginPresentation.showsRegistered {
                    Text(store.loginPresentation.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("login.registered")
                }
                Toggle("Show menu bar icon", isOn: store.binding(\.showStatusItem))
                Toggle("Show Dock icon", isOn: store.binding(\.showDockIcon))
                HotkeyRecorder(combo: store.blob.hotkey) { combo in
                    store.setHotkey(combo)
                }
            }

            Section {
                Toggle("Show waveform", isOn: store.binding(\.showWaveform))
                Toggle("Show spectrogram", isOn: store.binding(\.showSpectrogram))
                LabeledContent("Split") {
                    Slider(value: Binding(
                        get: { store.blob.splitFraction },
                        set: { newValue in
                            let snapped = SplitSnap.value(newValue)
                            store.update { $0.splitFraction = snapped }
                        }
                    ), in: 0...1)
                    .labelsHidden()
                    .overlay(alignment: .bottom) {
                        Circle()
                            .frame(width: 4, height: 4)
                            .foregroundStyle(.secondary)
                            .offset(y: 7)
                            .accessibilityIdentifier("split.midpoint")
                    }
                }
            } header: {
                Text("Layout")
            } footer: {
                Text("Waveform on top, spectrogram below. The middle is 50/50.")
            }

            Section("Advanced") {
                Toggle(isOn: store.binding(\.staticOverview)) {
                    Text("Full detail")
                    Text("Reads every sample for the waveform and spectrogram. Leave it off and files longer than 30 seconds use a coarser picture.")
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { actions.onReset() }
                        .accessibilityIdentifier("settings.reset")
                }
            }
        }
    }
}

private struct WaveformPane: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Dual view", isOn: store.binding(\.waveformDual))
                Picker("Amplitude", selection: store.binding(\.waveformAmplitude)) {
                    Text("Linear").tag(WaveformAmplitude.linear)
                    Text("dB").tag(WaveformAmplitude.decibels)
                }
                .pickerStyle(.segmented)
                Toggle("System blue", isOn: Binding(
                    get: { store.blob.waveformColor.usesSystemBlue },
                    set: { store.setUsesSystemBlue($0) }
                ))
                LabeledContent("Color") {
                    WaveformColorWell(color: store.blob.waveformColor.nsColor) { color in
                        let rgb = color.usingColorSpace(.sRGB) ?? color
                        store.setCustomWaveformColor(
                            red: Double(rgb.redComponent),
                            green: Double(rgb.greenComponent),
                            blue: Double(rgb.blueComponent),
                            alpha: Double(rgb.alphaComponent)
                        )
                    }
                    .frame(width: 48, height: 24)
                    .accessibilityIdentifier("waveform.colorWell")
                }
            }
        }
    }
}

private struct SpectrogramPane: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Dual view", isOn: store.binding(\.spectrogramDual))
                Picker("Type", selection: store.binding(\.spectrogram.type)) {
                    Text("Linear").tag(SpectrogramType.linear)
                    Text("Log frequency").tag(SpectrogramType.logFrequency)
                    Text("Mel").tag(SpectrogramType.mel)
                }
                Picker("Colors", selection: store.binding(\.spectrogram.colorMap)) {
                    Text("Magma").tag(SpectrogramColorMap.magma)
                    Text("Inferno").tag(SpectrogramColorMap.inferno)
                    Text("Viridis").tag(SpectrogramColorMap.viridis)
                    Text("Gray").tag(SpectrogramColorMap.gray)
                }
                Toggle("Frequency axis", isOn: store.binding(\.showFrequencyAxis))
                    .accessibilityIdentifier("spectrogram.frequencyAxis")
                Toggle("Time axis", isOn: store.binding(\.showTimeAxis))
                    .accessibilityIdentifier("preview.timeAxis")
            } header: {
                Text("Display")
            } footer: {
                Text("Frequencies along the left of the spectrogram, from 20 up to Nyquist. Time runs along the bottom of the preview. Both start off.")
            }

            Section {
                IntegerField(title: "n_fft", value: store.binding(\.spectrogram.nFFT), range: 64...32768, doubles: true)
                IntegerField(title: "Hop", value: store.binding(\.spectrogram.hop), range: 16...8192, doubles: true)
                Picker("Window", selection: store.binding(\.spectrogram.window)) {
                    Text("Hann").tag(FFTWindow.hann)
                    Text("Hamming").tag(FFTWindow.hamming)
                    Text("Blackman").tag(FFTWindow.blackman)
                }
                IntegerField(title: "n_mels", value: store.binding(\.spectrogram.nMels), range: 8...512, step: 8)
                DoubleField(title: "fmin", value: store.binding(\.spectrogram.fmin), range: 0...20000, step: 10)
                HertzField(
                    title: "fmax",
                    placeholder: "Nyquist",
                    value: store.blob.spectrogram.fmax
                ) { store.setFMax($0) }
                Toggle("dB", isOn: store.binding(\.spectrogram.decibelsEnabled))
                DoubleField(title: "dB floor", value: store.binding(\.spectrogram.dbFloor), range: -200...0, step: 5)
                DoubleField(title: "dB range", value: store.binding(\.spectrogram.dbRange), range: 10...200, step: 5)
            } header: {
                Text("Analysis")
            } footer: {
                Text("Blank fmax uses the file's Nyquist.")
            }
        }
    }
}

// Number fields are bordered boxes with stepper arrows, so they read as editable.
private struct IntegerField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    /// Step by doubling and halving, for sizes that are powers of two.
    var doubles = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: IntegerFormatStyle<Int>())
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Stepper(title) {
                    value = min(range.upperBound, doubles ? value * 2 : value + step)
                } onDecrement: {
                    value = max(range.lowerBound, doubles ? value / 2 : value - step)
                }
                .labelsHidden()
            }
        }
    }
}

private struct DoubleField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: FloatingPointFormatStyle<Double>())
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

private struct HertzField: View {
    let title: String
    let placeholder: String
    let value: Double?
    let onCommit: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(placeholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                // Lines up with the stepped fields above and below.
                .padding(.trailing, 19)
                .focused($focused)
                .onAppear { text = Self.render(value) }
                .onSubmit { commit() }
                .onChange(of: text) { _, _ in commit() }
                .onChange(of: value) { _, newValue in
                    if !focused {
                        text = Self.render(newValue)
                    }
                }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if value != nil {
                onCommit(nil)
            }
            return
        }
        guard let number = Double(trimmed) else { return }
        if value != number {
            onCommit(number)
        }
    }

    private static func render(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }
}
