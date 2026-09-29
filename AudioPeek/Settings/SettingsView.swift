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

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var onLoginToggle: (Bool) -> Void
    var onOpenLoginItems: () -> Void
    var onOpenAutomation: () -> Void
    var onReset: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !store.finderMessage.isEmpty {
                    GroupBox("Finder access") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(store.finderMessage)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("finder.automationMessage")
                            Button("Open Automation") {
                                onOpenAutomation()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)
                            .accessibilityIdentifier("finder.openAutomation")
                            .accessibilityLabel("Open Automation")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("Chrome") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Open at login", isOn: Binding(
                            get: { store.blob.loginItemEnabled },
                            set: { onLoginToggle($0) }
                        ))
                        if store.loginPresentation.offersLoginItems {
                            Text(store.loginPresentation.message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("login.manualMessage")
                            Button(store.loginPresentation.buttonTitle) {
                                onOpenLoginItems()
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Viewer") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show waveform", isOn: store.binding(\.showWaveform))
                        Toggle("Show spectrogram", isOn: store.binding(\.showSpectrogram))
                        Toggle("Waveform dual view", isOn: store.binding(\.waveformDual))
                        Toggle("Spectrogram dual view", isOn: store.binding(\.spectrogramDual))
                        Toggle("Full detail", isOn: store.binding(\.staticOverview))
                        Text("Full detail reads every sample. Leave it off and files longer than 30 seconds use a coarser picture.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Amplitude", selection: store.binding(\.waveformAmplitude)) {
                            Text("Linear").tag(WaveformAmplitude.linear)
                            Text("dB").tag(WaveformAmplitude.decibels)
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Toggle("System blue", isOn: Binding(
                                get: { store.blob.waveformColor.usesSystemBlue },
                                set: { store.setUsesSystemBlue($0) }
                            ))
                            Spacer()
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
                        .padding(.trailing, 12)
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Split") {
                                Slider(value: Binding(
                                    get: { store.blob.splitFraction },
                                    set: { newValue in
                                        let snapped = SplitSnap.value(newValue)
                                        store.update { $0.splitFraction = snapped }
                                    }
                                ), in: 0...1)
                                .overlay(alignment: .bottom) {
                                    Circle()
                                        .frame(width: 4, height: 4)
                                        .foregroundStyle(.secondary)
                                        .offset(y: 7)
                                        .accessibilityIdentifier("split.midpoint")
                                }
                            }
                            Text("Waveform on top, spectrogram below. The middle is 50/50.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Spectrogram") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Type", selection: store.binding(\.spectrogram.type)) {
                            Text("Linear").tag(SpectrogramType.linear)
                            Text("Log frequency").tag(SpectrogramType.logFrequency)
                            Text("Mel").tag(SpectrogramType.mel)
                        }
                        Toggle("Frequency axis", isOn: store.binding(\.showFrequencyAxis))
                            .accessibilityIdentifier("spectrogram.frequencyAxis")
                        Text("Frequencies along the left of the spectrogram, from 20 Hz up to Nyquist.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Colors", selection: store.binding(\.spectrogram.colorMap)) {
                            Text("Magma").tag(SpectrogramColorMap.magma)
                            Text("Inferno").tag(SpectrogramColorMap.inferno)
                            Text("Viridis").tag(SpectrogramColorMap.viridis)
                            Text("Gray").tag(SpectrogramColorMap.gray)
                        }
                        IntegerField(title: "n_fft", value: store.binding(\.spectrogram.nFFT))
                        IntegerField(title: "Hop", value: store.binding(\.spectrogram.hop))
                        Picker("Window", selection: store.binding(\.spectrogram.window)) {
                            Text("Hann").tag(FFTWindow.hann)
                            Text("Hamming").tag(FFTWindow.hamming)
                            Text("Blackman").tag(FFTWindow.blackman)
                        }
                        IntegerField(title: "n_mels", value: store.binding(\.spectrogram.nMels))
                        DoubleField(title: "fmin", value: store.binding(\.spectrogram.fmin))
                        HertzField(
                            title: "fmax",
                            placeholder: "Nyquist",
                            value: store.blob.spectrogram.fmax
                        ) { store.setFMax($0) }
                        Text("Blank fmax uses the file's Nyquist.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Toggle("dB", isOn: store.binding(\.spectrogram.decibelsEnabled))
                        DoubleField(title: "dB floor", value: store.binding(\.spectrogram.dbFloor))
                        DoubleField(title: "dB range", value: store.binding(\.spectrogram.dbRange))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Spacer()
                    Button("Reset") { onReset() }
                        .accessibilityIdentifier("settings.reset")
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct IntegerField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: $value, format: IntegerFormatStyle<Int>())
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }
}

private struct DoubleField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(title) {
            TextField(title, value: $value, format: FloatingPointFormatStyle<Double>())
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
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
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
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
