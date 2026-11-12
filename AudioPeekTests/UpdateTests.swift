import AppKit
import XCTest
@testable import AudioPeek

/// The updater's locked-in settings and the indicator. Nothing here starts Sparkle or
/// reaches the network: the controller runs on the recording fake.
@MainActor
final class UpdateTests: XCTestCase {
    private var info: [String: Any] {
        Bundle(for: AppDelegate.self).infoDictionary ?? [:]
    }

    // MARK: Locked in by the first updater release

    func testFeedIsTheLockedInGitHubAddress() {
        // Changing this strands every installed copy on the old feed.
        XCTAssertEqual(
            info["SUFeedURL"] as? String,
            "https://github.com/crlandsc/audiopeek/releases/latest/download/appcast.xml"
        )
    }

    func testUpdateKeyIsARealEdDSAKeyAndNotTheSpikeKey() throws {
        let key = try XCTUnwrap(info["SUPublicEDKey"] as? String, "SUPublicEDKey missing from Info.plist")
        XCTAssertEqual(Data(base64Encoded: key)?.count, 32, "An EdDSA public key is 32 bytes")
        XCTAssertNotEqual(key, Self.spikePublicKey, "Info.plist still has the throwaway spike key")
    }

    func testChecksDailyByDefaultAndNeverInstallsUnasked() {
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual((info["SUScheduledCheckInterval"] as? NSNumber)?.intValue, 86400)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
    }

    func testTestsNeverGetSparkle() {
        XCTAssertNotNil(UpdateController.make(forTesting: true).recorder)
    }

    // MARK: Menu and indicator

    private func makeStatusItem() -> (StatusItemController, UpdateController, RecordingUpdaterDriver) {
        let driver = RecordingUpdaterDriver()
        let updates = UpdateController(driver: driver)
        let status = StatusItemController(updates: updates) {}
        status.setVisible(true)
        addTeardownBlock { status.setVisible(false) }
        return (status, updates, driver)
    }

    func testMenuOffersCheckForUpdatesBetweenSettingsAndQuit() {
        let (status, _, driver) = makeStatusItem()
        XCTAssertEqual(status.menuTitles, ["AudioPeek Settings", "Check for Updates…", "Quit"])
        XCTAssertFalse(status.showsUpdateDot)
        status.chooseUpdateItem()
        XCTAssertEqual(driver.checkCount, 1)
        XCTAssertEqual(driver.installCount, 0)
    }

    func testAFoundUpdateShowsTheDotAndNamesTheVersionUntilSeen() {
        let (status, updates, driver) = makeStatusItem()
        driver.report(.available(version: "2.7"))
        XCTAssertEqual(updates.pending, .available(version: "2.7"))
        XCTAssertEqual(status.menuTitles, ["AudioPeek Settings", "Update to 2.7…", "Quit"])
        XCTAssertTrue(status.showsUpdateDot)
        XCTAssertTrue(status.statusImageIsTemplate, "The dotted eye still follows the menu bar's appearance")
        status.chooseUpdateItem()
        XCTAssertEqual(driver.checkCount, 1, "Choosing it opens the update window")
        driver.report(nil)
        XCTAssertEqual(status.menuTitles, ["AudioPeek Settings", "Check for Updates…", "Quit"])
        XCTAssertFalse(status.showsUpdateDot)
    }

    func testADownloadedUpdateInstallsWhenChosen() {
        let (status, _, driver) = makeStatusItem()
        driver.report(.readyToInstall(version: "2.7"))
        XCTAssertEqual(status.menuTitles, ["AudioPeek Settings", "Restart to Install 2.7", "Quit"])
        XCTAssertTrue(status.showsUpdateDot)
        status.chooseUpdateItem()
        XCTAssertEqual(driver.installCount, 1)
        XCTAssertEqual(driver.checkCount, 0)
    }

    func testTheDotIsDrawnOnlyWhenAsked() throws {
        func ink(_ image: NSImage) throws -> Int {
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ))
            rep.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            // The top-right corner, where the dot sits.
            var count = 0
            for x in 30..<36 {
                for y in 0..<6 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                    count += 1
                }
            }
            return count
        }
        XCTAssertEqual(try ink(PlaywaveMark.menuBarImage()), 0)
        XCTAssertGreaterThan(try ink(PlaywaveMark.menuBarImage(updateDot: true)), 10)
    }

    // MARK: Settings switches

    func testInstallingAutomaticallyNeedsAutomaticChecks() {
        let driver = RecordingUpdaterDriver()
        let updates = UpdateController(driver: driver)
        XCTAssertTrue(updates.automaticallyChecks)
        XCTAssertFalse(updates.automaticallyInstalls)
        updates.setAutomaticallyInstalls(true)
        XCTAssertTrue(updates.automaticallyInstalls)
        XCTAssertTrue(driver.automaticallyInstalls)
        updates.setAutomaticallyChecks(false)
        XCTAssertFalse(updates.automaticallyChecks)
        XCTAssertFalse(updates.automaticallyInstalls, "Turning checks off turns installs off")
        updates.setAutomaticallyInstalls(true)
        XCTAssertFalse(updates.automaticallyInstalls, "Installs can't turn on while checks are off")
        XCTAssertFalse(driver.automaticallyInstalls)
    }

    func testSettingsNamesTheVersionAndWhatTheButtonDoes() {
        let driver = RecordingUpdaterDriver()
        let updates = UpdateController(driver: driver)
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        XCTAssertEqual(updates.settingsStatus, "Version \(version) (\(build))")
        XCTAssertEqual(updates.settingsButtonTitle, "Check Now")
        driver.report(.available(version: "2.7"))
        XCTAssertEqual(updates.settingsStatus, "AudioPeek 2.7 is available.")
        XCTAssertEqual(updates.settingsButtonTitle, "Update…")
        driver.report(.readyToInstall(version: "2.7"))
        XCTAssertEqual(updates.settingsStatus, "AudioPeek 2.7 is ready to install.")
        XCTAssertEqual(updates.settingsButtonTitle, "Restart Now")
        updates.act()
        XCTAssertEqual(driver.installCount, 1)
    }

    private static let spikePublicKey = "UsqGCXQNxd/XKqlTjZQR0ia0zwR6oSOBGEeQR3QodCI="
}
