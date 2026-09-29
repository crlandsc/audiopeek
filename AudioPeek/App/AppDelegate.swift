import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SettingsStore!
    private var statusItem: StatusItemController!
    private var login: LoginItemController!
    private var settingsWindow: SettingsWindowController!
    private var hotkeyCenter: HotkeyCenter!
    private var slip: SlipPanelController!
    private var pendingOpens: [[URL]] = []
    private var scriptedFinder: ScriptedFinderSelection?
    private var registeredCombo: HotkeyCombo?
    private(set) var hotkeyFactoryFellBack = false
    private var testBridge: TestBridge?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningTests {
            return
        }
        installMainMenu()
        let config = TestLaunchConfig.load(from: CommandLine.arguments)
        let defaults = config?.makeDefaults() ?? .standard
        store = SettingsStore(defaults: defaults)
        let registrar: LoginRegistrar = config?.injection.map { InjectedLoginRegistrar(mode: $0) }
            ?? SystemLoginRegistrar()
        login = LoginItemController(store: store, registrar: registrar)
        statusItem = StatusItemController { [weak self] in
            self?.openSettings()
        }
        settingsWindow = SettingsWindowController(
            store: store,
            onLoginToggle: { [weak self] enabled in
                self?.login.setEnabled(enabled)
            },
            onOpenLoginItems: { [weak self] in
                self?.login.openSystemSettings()
            },
            onOpenAutomation: {
                guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation") else {
                    return
                }
                NSWorkspace.shared.open(url)
            },
            onReset: { [weak self] in
                self?.login.reset()
            }
        )
        let finderSource = makeFinderSource(config?.finderScript)
        hotkeyCenter = HotkeyCenter()
        hotkeyCenter.installHandler()
        slip = SlipPanelController(
            store: store,
            finder: finderSource,
            hotkey: hotkeyCenter,
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )
        deliverPendingOpens()
        hotkeyCenter.onViewer = { [weak self] in
            self?.slip.viewerHotkey()
        }
        hotkeyCenter.onEscape = { [weak self] in
            self?.slip.escape()
        }
        hotkeyCenter.onPreviewSpace = { [weak self] in
            self?.slip.previewSpace()
        }
        slip.onFileOpened = { [weak self] in
            self?.login.noteFirstSuccessfulAudioOpen()
        }
        if let load = config?.injectedLoad {
            slip.setInjectedLoad(thermal: load.thermal, cpu: load.cpu, applyNow: false)
        }
        if config?.overviewStall == true {
            slip.setOverviewStall(true)
        }
        store.onChange = { [weak self] in
            self?.applyChrome()
            self?.slip.applySettings()
            self?.syncHotkey(allowFactoryFallback: false)
        }
        applyChrome()
        login.refreshFromSystem()
        syncHotkey(allowFactoryFallback: true)
        if let config {
            let bridge = TestBridge(
                store: store,
                login: login,
                status: statusItem,
                settings: settingsWindow,
                slip: slip,
                hotkey: hotkeyCenter,
                scriptedFinder: scriptedFinder,
                app: self,
                stateURL: URL(fileURLWithPath: config.statePath)
            )
            bridge.onOpenSettings = { [weak self] in
                self?.openSettings()
            }
            slip.onActivity = { [weak bridge] in
                bridge?.writeState()
            }
            bridge.start()
            testBridge = bridge
        }
    }

    private func makeFinderSource(_ script: ScriptedFinderSelection.Script?) -> FinderSelectionSource {
        guard let script else {
            return SystemFinderSelection()
        }
        let scripted = ScriptedFinderSelection(script: script)
        scriptedFinder = scripted
        return scripted
    }

    private func syncHotkey(allowFactoryFallback: Bool) {
        let desired = store.blob.hotkey
        if desired == registeredCombo { return }
        let status = hotkeyCenter.registerViewer(desired)
        if status == noErr {
            registeredCombo = desired
            return
        }
        if allowFactoryFallback, desired == .optionSpace {
            let fallback = HotkeyCombo.controlOptionSpace
            if hotkeyCenter.registerViewer(fallback) == noErr {
                hotkeyFactoryFellBack = true
                registeredCombo = fallback
                if store.blob.hotkey != fallback {
                    store.setHotkey(fallback)
                }
                return
            }
        }
        guard let registeredCombo, registeredCombo != desired else { return }
        if hotkeyCenter.registerViewer(registeredCombo) == noErr, store.blob.hotkey != registeredCombo {
            store.setHotkey(registeredCombo)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // A cold launch can deliver the open before slip exists.
        pendingOpens.append(urls)
        deliverPendingOpens()
    }

    private func deliverPendingOpens() {
        guard let slip else { return }
        while !pendingOpens.isEmpty {
            let urls = pendingOpens.removeFirst()
            slip.openFiles(urls)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard store != nil else { return false }
        openSettings()
        testBridge?.writeState()
        return false
    }

    private func openSettings() {
        settingsWindow.show()
        NSApp.activate()
        applyChrome()
    }

    private func applyChrome() {
        let policy: NSApplication.ActivationPolicy = store.blob.showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            _ = NSApp.setActivationPolicy(policy)
        }
        statusItem.setVisible(store.blob.showStatusItem)
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "AudioPeek")
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About AudioPeek",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "AudioPeek Settings", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit AudioPeek",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        NSApp.mainMenu = main
    }

    @objc private func showSettings(_ sender: Any?) {
        openSettings()
    }

    private static var isRunningTests: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return ProcessInfo.processInfo.arguments.contains { $0.contains("XCTest") }
    }
}
