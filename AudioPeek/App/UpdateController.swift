import AppKit
import Combine
import Sparkle

/// An update found by a background check that the person hasn't acted on yet.
enum PendingUpdate: Equatable {
    /// Found by a daily check. Choosing it opens Sparkle's update window.
    case available(version: String)
    /// Downloaded by an automatic install and waiting for AudioPeek to quit or go idle.
    /// Choosing it installs now and relaunches.
    case readyToInstall(version: String)

    var version: String {
        switch self {
        case let .available(version), let .readyToInstall(version): version
        }
    }
}

/// The part of the updater the app talks to. Sparkle in a normal launch; a recording fake
/// in unit tests and `--test-config` runs, so tests never start an updater or reach the network.
@MainActor
protocol UpdaterDriver: AnyObject {
    var automaticallyChecks: Bool { get set }
    var automaticallyInstalls: Bool { get set }
    /// Opens the update window: checks now, or brings a found update into focus.
    func checkForUpdates()
    /// Installs a downloaded update now and relaunches. Only valid while one is ready.
    func installNow()
    /// Called with what's waiting, or nil once the person has seen it or it went away.
    var onPendingChange: (PendingUpdate?) -> Void { get set }
    /// Set by the app: true when nothing is on screen and nothing is playing, so a
    /// downloaded update can install and relaunch without interrupting anyone.
    var isIdle: () -> Bool { get set }
}

/// Owns the updater for the app: the menu item, the dot on the menu bar icon and the
/// Updates section in Settings all read from here.
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var pending: PendingUpdate?
    @Published private(set) var automaticallyChecks: Bool
    @Published private(set) var automaticallyInstalls: Bool
    private let driver: UpdaterDriver

    init(driver: UpdaterDriver) {
        self.driver = driver
        automaticallyChecks = driver.automaticallyChecks
        automaticallyInstalls = driver.automaticallyInstalls
        driver.onPendingChange = { [weak self] pending in
            self?.pending = pending
        }
    }

    /// The fake, when tests drive the app.
    var recorder: RecordingUpdaterDriver? { driver as? RecordingUpdaterDriver }

    var isIdle: () -> Bool {
        get { driver.isIdle }
        set { driver.isIdle = newValue }
    }

    /// Sparkle for a normal launch, the fake when tests drive the app.
    static func make(forTesting: Bool) -> UpdateController {
        UpdateController(driver: forTesting ? RecordingUpdaterDriver() : SparkleUpdaterDriver())
    }

    var menuTitle: String {
        menuTitle(for: pending)
    }

    /// `$pending` publishes before the property changes, so watchers pass the new value.
    func menuTitle(for pending: PendingUpdate?) -> String {
        switch pending {
        case nil: "Check for Updates…"
        case let .available(version): "Update to \(version)…"
        case let .readyToInstall(version): "Restart to Install \(version)"
        }
    }

    /// The line at the top of the Updates section in Settings.
    var settingsStatus: String {
        switch pending {
        case nil:
            let info = Bundle.main.infoDictionary ?? [:]
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            let build = info["CFBundleVersion"] as? String ?? "?"
            return "Version \(version) (\(build))"
        case let .available(version): return "AudioPeek \(version) is available."
        case let .readyToInstall(version): return "AudioPeek \(version) is ready to install."
        }
    }

    /// The button beside that line; it does the same as the menu item.
    var settingsButtonTitle: String {
        switch pending {
        case nil: "Check Now"
        case .available: "Update…"
        case .readyToInstall: "Restart Now"
        }
    }

    func setAutomaticallyChecks(_ on: Bool) {
        driver.automaticallyChecks = on
        automaticallyChecks = driver.automaticallyChecks
        automaticallyInstalls = driver.automaticallyInstalls
    }

    func setAutomaticallyInstalls(_ on: Bool) {
        guard automaticallyChecks else { return }
        driver.automaticallyInstalls = on
        automaticallyInstalls = driver.automaticallyInstalls
    }

    /// The menu item and the Settings button.
    func act() {
        if case .readyToInstall = pending {
            driver.installNow()
        } else {
            driver.checkForUpdates()
        }
    }
}

/// Sparkle's standard updater, with its scheduled-update window replaced by the quiet
/// indicator ("gentle reminders") and automatic installs held until the app is idle.
@MainActor
final class SparkleUpdaterDriver: NSObject, UpdaterDriver {
    /// How often to look for a moment to install a downloaded update.
    static let idleCheckInterval: TimeInterval = 60

    var onPendingChange: (PendingUpdate?) -> Void = { _ in }
    var isIdle: () -> Bool = { false }
    private var controller: SPUStandardUpdaterController!
    private var installHandler: (() -> Void)?
    private var idleTimer: Timer?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    private var updater: SPUUpdater { controller.updater }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyInstalls: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func installNow() {
        guard let installHandler else {
            checkForUpdates()
            return
        }
        installHandler()
    }

    private func holdForIdleInstall(_ handler: @escaping () -> Void, version: String) {
        installHandler = handler
        onPendingChange(.readyToInstall(version: version))
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let handler = self.installHandler, self.isIdle() else { return }
                handler()
            }
        }
    }
}

extension SparkleUpdaterDriver: SPUUpdaterDelegate {
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let version = item.displayVersionString
        nonisolated(unsafe) let handler = immediateInstallHandler
        MainActor.assumeIsolated {
            holdForIdleInstall(handler, version: version)
        }
        return true
    }
}

extension SparkleUpdaterDriver: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    // A scheduled check never opens a window by itself; the indicator shows it instead.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            onPendingChange(.available(version: version))
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            onPendingChange(nil)
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            onPendingChange(nil)
        }
    }
}

/// Stands in for Sparkle when tests drive the app. Records what was asked of it and lets a
/// test report an update.
@MainActor
final class RecordingUpdaterDriver: UpdaterDriver {
    var automaticallyChecks = true {
        didSet {
            if !automaticallyChecks { automaticallyInstalls = false }
        }
    }
    var automaticallyInstalls = false
    var onPendingChange: (PendingUpdate?) -> Void = { _ in }
    var isIdle: () -> Bool = { false }
    private(set) var checkCount = 0
    private(set) var installCount = 0

    func checkForUpdates() {
        checkCount += 1
    }

    func installNow() {
        installCount += 1
    }

    func report(_ pending: PendingUpdate?) {
        onPendingChange(pending)
    }
}
