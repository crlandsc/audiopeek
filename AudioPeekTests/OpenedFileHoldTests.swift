import AppKit
import Carbon
import XCTest
@testable import AudioPeek

/// A file opened with AudioPeek (Open With, a drop, `open -a`) stays on screen while Finder
/// still reports the selection it had at the open, and follows Finder again once that changes.
@MainActor
final class OpenedFileHoldTests: XCTestCase {
    private var files: [URL] = []
    private var suites: [String] = []

    override func tearDown() {
        for url in files {
            try? FileManager.default.removeItem(at: url)
        }
        for suite in suites {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        files = []
        suites = []
        super.tearDown()
    }

    func testOpenedFileStaysWhileFinderShowsAnotherFile() throws {
        let opened = try wav("opened")
        let selected = try wav("selected")
        let finder = StubFinder(.files([selected]))
        let slip = makeSlip(finder)
        slip.openFiles([opened])
        XCTAssertTrue(waitForReads(slip, count: 3))
        XCTAssertTrue(slip.isVisible)
        XCTAssertEqual(slip.filename, opened.lastPathComponent)
        slip.hide()
    }

    func testOpenedFileStaysWhileFinderHasNothingSelected() throws {
        let opened = try wav("opened")
        let finder = StubFinder(.files([]))
        let slip = makeSlip(finder)
        slip.openFiles([opened])
        XCTAssertTrue(waitForReads(slip, count: 3))
        XCTAssertTrue(slip.isVisible)
        XCTAssertEqual(slip.filename, opened.lastPathComponent)
        slip.hide()
    }

    func testPanelFollowsFinderOnceTheSelectionChanges() throws {
        let opened = try wav("opened")
        let selected = try wav("selected")
        let picked = try wav("picked")
        let finder = StubFinder(.files([selected]))
        let slip = makeSlip(finder)
        slip.openFiles([opened])
        XCTAssertTrue(waitForReads(slip, count: 2))
        XCTAssertEqual(slip.filename, opened.lastPathComponent)

        finder.read = .files([picked])
        XCTAssertTrue(runUntil { slip.filename == picked.lastPathComponent })
        XCTAssertTrue(slip.isVisible)

        // Back to normal following: an empty selection closes the panel, as it does after the hotkey.
        finder.read = .files([])
        XCTAssertTrue(runUntil { !slip.isVisible })
    }

    func testClearingTheFinderSelectionAfterAnOpenClosesThePanel() throws {
        let opened = try wav("opened")
        let selected = try wav("selected")
        let finder = StubFinder(.files([selected]))
        let slip = makeSlip(finder)
        slip.openFiles([opened])
        XCTAssertTrue(waitForReads(slip, count: 2))
        XCTAssertTrue(slip.isVisible)

        finder.read = .files([])
        XCTAssertTrue(runUntil { !slip.isVisible })
    }

    func testDeniedFinderReadKeepsTheOpenedFileAndStopsAskingQuietly() throws {
        let opened = try wav("opened")
        let finder = StubFinder(.failed(Int32(errAEEventNotPermitted)))
        var settingsOpened = 0
        let slip = makeSlip(finder, onOpenSettings: { settingsOpened += 1 })
        slip.openFiles([opened])
        XCTAssertTrue(waitForReads(slip, count: 1))
        // Once the poll is stopped, no further read can arrive to change anything.
        XCTAssertTrue(runUntil { !slip.pollScheduled })
        XCTAssertTrue(slip.isVisible)
        XCTAssertEqual(slip.filename, opened.lastPathComponent)
        XCTAssertEqual(settingsOpened, 0)
        XCTAssertEqual(slipStore?.finderMessage, "")
        slip.hide()
    }

    func testOtherFailedFinderReadsKeepTheOpenedFileAndKeepPolling() throws {
        let opened = try wav("opened")
        let picked = try wav("picked")
        let finder = StubFinder(.failed(-1712))
        var settingsOpened = 0
        let slip = makeSlip(finder, onOpenSettings: { settingsOpened += 1 })
        slip.openFiles([opened])
        XCTAssertTrue(waitForReads(slip, count: 3))
        XCTAssertTrue(slip.pollScheduled)
        XCTAssertTrue(slip.isVisible)
        XCTAssertEqual(slip.filename, opened.lastPathComponent)
        XCTAssertEqual(settingsOpened, 0)

        // Finder recovers. Its first answer stands for the selection it had at the open,
        // so the opened file stays, and the next change is followed.
        let selected = try wav("selected")
        finder.read = .files([selected])
        XCTAssertTrue(waitForReads(slip, count: 3))
        XCTAssertEqual(slip.filename, opened.lastPathComponent)
        finder.read = .files([picked])
        XCTAssertTrue(runUntil { slip.filename == picked.lastPathComponent })
        XCTAssertTrue(slip.isVisible)
        slip.hide()
    }

    func testViewerHotkeyAfterAnOpenFollowsFinderAsBefore() throws {
        let opened = try wav("opened")
        let selected = try wav("selected")
        let finder = StubFinder(.files([selected]))
        let slip = makeSlip(finder)
        slip.openFiles([opened])
        XCTAssertTrue(waitForReads(slip, count: 2))
        XCTAssertEqual(slip.filename, opened.lastPathComponent)

        slip.viewerHotkey()
        XCTAssertFalse(slip.isVisible)
        slip.viewerHotkey()
        XCTAssertTrue(runUntil { slip.isVisible && slip.filename == selected.lastPathComponent })
        // The hotkey path keeps following Finder: no hold carried over from the earlier open.
        finder.read = .files([])
        XCTAssertTrue(runUntil { !slip.isVisible })
    }

    func testSecondOpenTakesItsOwnBaseline() throws {
        let first = try wav("first")
        let second = try wav("second")
        let selected = try wav("selected")
        let picked = try wav("picked")
        let finder = StubFinder(.files([selected]))
        let slip = makeSlip(finder)
        slip.openFiles([first])
        XCTAssertTrue(waitForReads(slip, count: 2))
        // Release the first hold, so only a fresh hold from the second open can keep it up.
        finder.read = .files([picked])
        XCTAssertTrue(runUntil { slip.filename == picked.lastPathComponent })
        slip.openFiles([second])
        XCTAssertTrue(waitForReads(slip, count: 3))
        XCTAssertTrue(slip.isVisible)
        XCTAssertEqual(slip.filename, second.lastPathComponent)
        slip.hide()
    }

    func testOpenDuringAResizeDragIsHeldOnceTheDragEnds() throws {
        let first = try wav("first")
        let second = try wav("second")
        let selected = try wav("selected")
        let finder = StubFinder(.files([selected]))
        let slip = makeSlip(finder)
        slip.openFiles([first])
        XCTAssertTrue(waitForReads(slip, count: 2))

        slip.beginResizeInteraction()
        slip.openFiles([second])
        // Polling continues during a drag. Those replies must not replace the deferred open.
        XCTAssertTrue(waitForReads(slip, count: 2))
        slip.endResizeInteraction()
        XCTAssertEqual(slip.filename, second.lastPathComponent)
        XCTAssertTrue(waitForReads(slip, count: 3))
        XCTAssertTrue(slip.isVisible)
        XCTAssertEqual(slip.filename, second.lastPathComponent)
        slip.hide()
    }

    // MARK: - Helpers

    private var slipStore: SettingsStore?

    private func makeSlip(_ finder: StubFinder, onOpenSettings: @escaping () -> Void = {}) -> SlipPanelController {
        let suite = "audiopeek.hold.\(UUID().uuidString)"
        suites.append(suite)
        let store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
        slipStore = store
        let slip = SlipPanelController(
            store: store,
            finder: finder,
            hotkey: HotkeyCenter(),
            onOpenSettings: onOpenSettings
        )
        slip.setInjectedLoad(thermal: "nominal", cpu: 0.1, applyNow: false)
        return slip
    }

    /// Runs the main run loop until `count` more Finder replies have come back and none is in flight.
    private func waitForReads(_ slip: SlipPanelController, count: Int) -> Bool {
        let target = slip.readCount + count
        return runUntil { slip.readCount >= target && slip.readCount == slip.requestCount }
    }

    private func runUntil(timeout: TimeInterval = 4, _ done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !done() {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        return done()
    }

    private func wav(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiopeek-hold-\(name)-\(UUID().uuidString).wav")
        let frames = 44_100
        var data = Data()
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append32(UInt32(36 + frames * 2))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        append32(16)
        append16(1)
        append16(1)
        append32(44100)
        append32(44100 * 2)
        append16(2)
        append16(16)
        data.append(contentsOf: "data".utf8)
        append32(UInt32(frames * 2))
        data.append(Data(count: frames * 2))
        try data.write(to: url)
        files.append(url)
        return url
    }
}

/// Answers every Finder request with `read`, on the main queue like the real client.
private final class StubFinder: FinderSelectionSource {
    var read: FinderRead

    init(_ read: FinderRead) {
        self.read = read
    }

    func requestSelection(_ completion: @escaping (FinderRead) -> Void) {
        let read = self.read
        DispatchQueue.main.async {
            completion(read)
        }
    }
}
