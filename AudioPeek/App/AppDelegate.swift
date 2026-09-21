import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: SettingsStore!
    private var statusItem: StatusItemController!
    private var login: LoginItemController!
    private var settingsWindow: SettingsWindowController!
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
            onReset: { [weak self] in
                self?.login.reset()
            }
        )
        store.onChange = { [weak self] in
            self?.applyChrome()
        }
        applyChrome()
        login.refreshFromSystem()
        if let config {
            let bridge = TestBridge(
                store: store,
                login: login,
                status: statusItem,
                settings: settingsWindow,
                stateURL: URL(fileURLWithPath: config.statePath)
            )
            bridge.onOpenSettings = { [weak self] in
                self?.openSettings()
            }
            bridge.start()
            testBridge = bridge
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
        let settings = NSMenuItem(title: "Settings", action: #selector(showSettings(_:)), keyEquivalent: ",")
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
