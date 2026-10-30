import AppKit
import Combine
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

/// Which panes have their Advanced section open. Every pane's Advanced starts collapsed.
/// Opening adds the rows at once and the growing window reveals them, like switching panes.
/// Closing turns the arrow at once, lets the window close over the rows, then removes them,
/// so nothing above the section ever moves.
@MainActor
final class SettingsSectionState: ObservableObject {
    /// The disclosure arrow.
    @Published private(set) var expanded: Set<SettingsPane> = []
    /// The section's rows.
    @Published private(set) var shown: Set<SettingsPane> = []
    /// Set by the window: shrink over the rows, then call the completion.
    var closeOver: (SettingsPane, @escaping () -> Void) -> Void = { _, done in done() }
    /// Set by the window: a section reopened before its rows were removed.
    var reopen: (SettingsPane) -> Void = { _ in }

    func isExpanded(_ pane: SettingsPane) -> Bool {
        expanded.contains(pane)
    }

    func isShown(_ pane: SettingsPane) -> Bool {
        shown.contains(pane)
    }

    func setExpanded(_ pane: SettingsPane, _ open: Bool) {
        guard isExpanded(pane) != open else { return }
        if open {
            expanded.insert(pane)
            if shown.contains(pane) {
                reopen(pane)
            } else {
                shown.insert(pane)
            }
        } else {
            expanded.remove(pane)
            closeOver(pane) { [weak self] in
                guard let self, !self.isExpanded(pane) else { return }
                self.shown.remove(pane)
            }
        }
    }

    func toggle(_ pane: SettingsPane) {
        setExpanded(pane, !isExpanded(pane))
    }
}

/// The "Advanced" section header with a disclosure arrow, like a system collapsible section.
private struct AdvancedHeader: View {
    let pane: SettingsPane
    @ObservedObject var sections: SettingsSectionState

    var body: some View {
        Button {
            sections.toggle(pane)
        } label: {
            // The title lines up with the other section titles; the arrow hangs in the margin.
            Text("Advanced")
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(sections.isExpanded(pane) ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: sections.isExpanded(pane))
                        .offset(x: -13)
                }
                .padding(.leading, 16)
                .contentShape(Rectangle())
                .padding(.leading, -16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sections.isExpanded(pane) ? "Hide Advanced" : "Show Advanced")
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
    @ObservedObject var sections: SettingsSectionState
    let actions: SettingsActions
    var onHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        Group {
            switch pane {
            case .general:
                GeneralPane(store: store, sections: sections, actions: actions)
            case .waveform:
                WaveformPane(store: store, sections: sections)
            case .spectrogram:
                SpectrogramPane(store: store, sections: sections)
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
        // Anchor to the top: while the window or a section animates, everything above the
        // change stays put and only what is below it opens or closes.
        .frame(maxHeight: .infinity, alignment: .top)
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
    @ObservedObject var sections: SettingsSectionState
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
                LoginItemsRow(presentation: store.loginPresentation) {
                    actions.onOpenLoginItems()
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

            Section {
                if sections.isShown(.general) {
                    Toggle(isOn: store.binding(\.staticOverview)) {
                        Text("Full detail")
                        Text("Reads every sample for the waveform and spectrogram. Leave it off and files longer than 30 seconds use a coarser picture.")
                    }
                    ResetRow(
                        title: "Reset All Settings",
                        detail: "Restores every setting on the General, Waveform and Spectrogram tabs to its default, including the hotkey and the login item. The volume and the preview's size and position stay as they are.",
                        identifier: "settings.reset"
                    ) {
                        actions.onReset()
                    }
                }
            } header: {
                AdvancedHeader(pane: .general, sections: sections)
            }
        }
    }
}

private struct WaveformPane: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var sections: SettingsSectionState

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

            Section {
                if sections.isShown(.waveform) {
                    ResetRow(
                        title: "Reset Waveform Settings",
                        detail: "Resets only the settings on this tab.",
                        identifier: "settings.resetWaveform"
                    ) {
                        store.resetWaveformSettings()
                    }
                }
            } header: {
                AdvancedHeader(pane: .waveform, sections: sections)
            }
        }
    }
}

private struct SpectrogramPane: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var sections: SettingsSectionState

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
                if sections.isShown(.spectrogram) {
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
                        caption: "Blank uses the file's Nyquist.",
                        placeholder: "Nyquist",
                        value: store.blob.spectrogram.fmax
                    ) { store.setFMax($0) }
                    Toggle("dB", isOn: store.binding(\.spectrogram.decibelsEnabled))
                    DoubleField(title: "dB floor", value: store.binding(\.spectrogram.dbFloor), range: -200...0, step: 5)
                    DoubleField(title: "dB range", value: store.binding(\.spectrogram.dbRange), range: 10...200, step: 5)
                    ResetRow(
                        title: "Reset Spectrogram Settings",
                        detail: "Resets only the settings on this tab.",
                        identifier: "settings.resetSpectrogram"
                    ) {
                        store.resetSpectrogramSettings()
                    }
                }
            } header: {
                AdvancedHeader(pane: .spectrogram, sections: sections)
            }
        }
    }
}

/// The login item's status and a shortcut to Login Items, in one row under the toggle.
private struct LoginItemsRow: View {
    let presentation: LoginPresentation
    let onOpen: () -> Void

    private var status: String {
        presentation.message.isEmpty ? "Manage it in System Settings, Login Items." : presentation.message
    }

    private var statusIdentifier: String {
        if presentation.offersLoginItems { return "login.manualMessage" }
        if presentation.showsRegistered { return "login.registered" }
        return "login.status"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(statusIdentifier)
            Spacer(minLength: 0)
            Button(presentation.buttonTitle.isEmpty ? "Open Login Items" : presentation.buttonTitle) {
                onOpen()
            }
            .accessibilityIdentifier("login.openButton")
        }
    }
}

/// A reset button with a line saying exactly what it restores.
private struct ResetRow: View {
    let title: String
    let detail: String
    let identifier: String
    let onReset: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(title) { onReset() }
                .accessibilityIdentifier(identifier)
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
    let caption: String
    let placeholder: String
    let value: Double?
    let onCommit: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent {
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
        } label: {
            Text(title)
            Text(caption)
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
