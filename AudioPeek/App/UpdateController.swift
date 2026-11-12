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
    /// False while the updater is busy (a background download, say) and a check would do nothing.
    var canCheckForUpdates: Bool { get }
    /// Called when the switches or `canCheckForUpdates` change underneath the app, for example
    /// from the checkbox in Sparkle's own update window.
    var onSettingsChange: () -> Void { get set }
}

/// Owns the updater for the app: the menu item, the dot on the menu bar icon and the
/// Updates section in Settings all read from here.
@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var pending: PendingUpdate?
    @Published private(set) var automaticallyChecks: Bool
    @Published private(set) var automaticallyInstalls: Bool
    @Published private(set) var canCheck: Bool
    private let driver: UpdaterDriver

    init(driver: UpdaterDriver) {
        self.driver = driver
        automaticallyChecks = driver.automaticallyChecks
        automaticallyInstalls = driver.automaticallyChecks && driver.automaticallyInstalls
        canCheck = driver.canCheckForUpdates
        driver.onPendingChange = { [weak self] pending in
            self?.pending = pending
        }
        driver.onSettingsChange = { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        automaticallyChecks = driver.automaticallyChecks
        automaticallyInstalls = driver.automaticallyChecks && driver.automaticallyInstalls
        canCheck = driver.canCheckForUpdates
    }

    /// Whether the menu item and the Settings button can do anything right now.
    var canAct: Bool {
        if case .readyToInstall = pending { return true }
        return canCheck
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

    /// Turning checks off also turns automatic installs off, so turning checks back on
    /// never quietly brings installs back.
    func setAutomaticallyChecks(_ on: Bool) {
        if !on {
            driver.automaticallyInstalls = false
        }
        driver.automaticallyChecks = on
        refresh()
    }

    func setAutomaticallyInstalls(_ on: Bool) {
        guard automaticallyChecks else { return }
        driver.automaticallyInstalls = on
        refresh()
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

/// Decides when a downloaded update may install by itself: after the app has stayed idle
/// for `delay`, judged from samples taken a few seconds apart. Any busy sample starts over.
struct IdleWait {
    let delay: TimeInterval
    private(set) var since: Date?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    /// Records one sample; true when the update should install now.
    mutating func sample(idle: Bool, now: Date) -> Bool {
        guard idle else {
            since = nil
            return false
        }
        let start = since ?? now
        since = start
        return now.timeIntervalSince(start) >= delay
    }

    mutating func reset() {
        since = nil
    }
}

/// Sparkle's standard updater, with its scheduled-update window replaced by the quiet
/// indicator ("gentle reminders") and automatic installs held until the app is idle.
@MainActor
final class SparkleUpdaterDriver: NSObject, UpdaterDriver {
    /// How long the app must stay idle before a downloaded update installs by itself.
    static let idleInstallDelay: TimeInterval = 60
    /// How often idleness is sampled while an update waits.
    static let idleSampleInterval: TimeInterval = 5

    var onPendingChange: (PendingUpdate?) -> Void = { _ in }
    var onSettingsChange: () -> Void = {}
    var isIdle: () -> Bool = { false }
    private var controller: SPUStandardUpdaterController!
    private var installHandler: (() -> Void)?
    private var readyVersion: String?
    private var idleTimer: Timer?
    private var idleWait = IdleWait(delay: SparkleUpdaterDriver.idleInstallDelay)
    private var observations: [NSKeyValueObservation] = []

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        // Sparkle's update window has its own "automatically download and install" checkbox,
        // and a background download blocks checks; follow both.
        let changed: @Sendable () -> Void = { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.settingsChanged()
                }
            }
        }
        observations = [
            updater.observe(\.automaticallyChecksForUpdates) { _, _ in changed() },
            updater.observe(\.automaticallyDownloadsUpdates) { _, _ in changed() },
            updater.observe(\.canCheckForUpdates) { _, _ in changed() },
        ]
    }

    private var updater: SPUUpdater { controller.updater }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyInstalls: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set {
            updater.automaticallyDownloadsUpdates = newValue
            settingsChanged()
        }
    }

    var canCheckForUpdates: Bool { updater.canCheckForUpdates }

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

    private func settingsChanged() {
        // Turned off with an update already downloaded: stop installing it by itself. It
        // still installs if chosen from the menu, or when the app quits (Sparkle's rule).
        if !updater.automaticallyDownloadsUpdates || !updater.automaticallyChecksForUpdates {
            stopIdleWatch()
        } else if installHandler != nil, idleTimer == nil {
            startIdleWatch()
        }
        onSettingsChange()
    }

    /// The pending state as the user driver sees it, but a downloaded update stays offered
    /// until it installs or fails.
    private func report(_ pending: PendingUpdate?) {
        if pending == nil, let readyVersion {
            onPendingChange(.readyToInstall(version: readyVersion))
        } else {
            onPendingChange(pending)
        }
    }

    private func holdForIdleInstall(_ handler: @escaping () -> Void, version: String) {
        installHandler = handler
        readyVersion = version
        onPendingChange(.readyToInstall(version: version))
        startIdleWatch()
    }

    private func startIdleWatch() {
        stopIdleWatch()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleSampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleIdle()
            }
        }
    }

    private func stopIdleWatch() {
        idleTimer?.invalidate()
        idleTimer = nil
        idleWait.reset()
    }

    private func sampleIdle() {
        guard let installHandler else { return }
        if idleWait.sample(idle: isIdle(), now: Date()) {
            stopIdleWatch()
            installHandler()
        }
    }

    private func installFailed() {
        stopIdleWatch()
        installHandler = nil
        readyVersion = nil
        onPendingChange(nil)
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

    // A failed download or install ends the cycle; clear what it left on screen.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        MainActor.assumeIsolated {
            installFailed()
        }
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
            report(.available(version: version))
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            report(nil)
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            report(nil)
        }
    }
}

/// Stands in for Sparkle when tests drive the app. Records what was asked of it and lets a
/// test report an update.
@MainActor
final class RecordingUpdaterDriver: UpdaterDriver {
    var automaticallyChecks = true
    var automaticallyInstalls = false
    var canCheckForUpdates = true
    var onPendingChange: (PendingUpdate?) -> Void = { _ in }
    var onSettingsChange: () -> Void = {}
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
