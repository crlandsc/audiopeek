import AppKit
import CoreGraphics
import Foundation

let bundleID = "com.landschoot.audiopeek"
let notificationName = Notification.Name("com.landschoot.audiopeek.test")

struct Check {
    static var failures: [String] = []
    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            print("PASS: \(message)")
        } else {
            print("FAIL: \(message)")
            failures.append(message)
        }
    }
}

struct JSONValue {
    let raw: Any
    subscript(_ key: String) -> JSONValue? {
        guard let dict = raw as? [String: Any], let next = dict[key], !(next is NSNull) else { return nil }
        return JSONValue(raw: next)
    }
    var string: String? { raw as? String }
    var bool: Bool? { raw as? Bool }
    var int: Int? { (raw as? NSNumber)?.intValue }
    var double: Double? { (raw as? NSNumber)?.doubleValue }
    var strings: [String]? {
        if let values = raw as? [String] { return values }
        if let values = raw as? [Any] { return values.compactMap { $0 as? String } }
        return nil
    }
}

@discardableResult
func run(_ path: String, _ args: [String]) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (1, "\(error)") }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func runningApps() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
}

func stopRunningApps() {
    for app in runningApps() { app.terminate() }
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline && !runningApps().isEmpty {
        Thread.sleep(forTimeInterval: 0.05)
    }
    for app in runningApps() { app.forceTerminate() }
}

func readState(at url: URL) -> JSONValue? {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
    return JSONValue(raw: object)
}

func waitForState(at url: URL, above generation: Int, timeout: TimeInterval = 4) -> JSONValue? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let state = readState(at: url), let value = state["generation"]?.int, value > generation {
            return state
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return readState(at: url)
}

func waitUntil(at url: URL, timeout: TimeInterval = 3, _ match: (JSONValue) -> Bool) -> JSONValue? {
    let deadline = Date().addingTimeInterval(timeout)
    var latest: JSONValue?
    while Date() < deadline {
        if let state = readState(at: url) {
            latest = state
            if match(state) { return state }
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return latest
}

func post(_ command: String, extra: [String: Any] = [:]) {
    var info: [String: Any] = ["command": command]
    for (key, value) in extra { info[key] = value }
    DistributedNotificationCenter.default().postNotificationName(
        notificationName,
        object: nil,
        userInfo: info,
        deliverImmediately: true
    )
}

func writeWav(to url: URL) {
    var data = Data()
    func append32(_ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    func append16(_ value: UInt16) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    let frames = 44100 * 8
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
    try! data.write(to: url)
}

func sourceHits(_ pattern: String) -> String {
    run("/usr/bin/grep", ["-R", "-n", "-E", pattern, "AudioPeek", "--include=*.swift"]).1
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: verify-panel AudioPeek.app\n", stderr)
    exit(2)
}

let appPath = CommandLine.arguments[1]
let info = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
stopRunningApps()

let usage = run("/usr/libexec/PlistBuddy", ["-c", "Print :NSAppleEventsUsageDescription", info.path])
let usageText = usage.1.trimmingCharacters(in: .whitespacesAndNewlines)
Check.expect(usage.0 == 0 && usageText.contains("Finder"), "usage string mentions Finder: \(usageText)")

let forbidden = sourceHits("addGlobalMonitorForEvents|AXUIElement|NSAppleScript|CGEvent\\.tapCreate")
Check.expect(forbidden.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "no global monitor, event tap, Accessibility, or AppleScript (\(forbidden))")

let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audiopeek-panel-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let wavA = root.appendingPathComponent("tone.wav")
let wavB = root.appendingPathComponent("other.wav")
let text = root.appendingPathComponent("notes.txt")
let ogg = root.appendingPathComponent("song.ogg")
let folder = root.appendingPathComponent("Folder", isDirectory: true)
writeWav(to: wavA)
writeWav(to: wavB)
try! Data("hello".utf8).write(to: text)
try! Data("ogg".utf8).write(to: ogg)
try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

let id = UUID().uuidString
let suite = "audiopeek.panel.\(id)"
let stateURL = URL(fileURLWithPath: "/tmp/audiopeek-panel-\(id).json")
let configURL = URL(fileURLWithPath: "/tmp/audiopeek-panel-\(id)-config.json")
let config: [String: Any] = [
    "defaultsSuite": suite,
    "statePath": stateURL.path,
    "injectLoginFailure": "succeeded",
    "machineLoad": ["thermal": "nominal", "cpu": 0.2],
    "finderSelection": "empty",
]
try! JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted]).write(to: configURL)
defer {
    _ = run("/usr/bin/defaults", ["delete", suite])
    try? FileManager.default.removeItem(at: stateURL)
    try? FileManager.default.removeItem(at: configURL)
    stopRunningApps()
}

let opened = run("/usr/bin/open", [appPath, "--args", "--test-config", configURL.path])
Check.expect(opened.0 == 0, "open launched the app")
guard var state = waitForState(at: stateURL, above: 0) else {
    Check.expect(false, "app wrote launch state")
    print("PANEL FAIL")
    exit(1)
}

let launchedPid = readState(at: stateURL)?["pid"]?.int ?? -1
let launchedPath = run("/bin/ps", ["-o", "comm=", "-p", String(launchedPid)]).1.trimmingCharacters(in: .whitespacesAndNewlines)
let expectedPath = URL(fileURLWithPath: appPath).resolvingSymlinksInPath().appendingPathComponent("Contents/MacOS").path
Check.expect(launchedPath.hasPrefix(expectedPath), "launched the app it was given: \(launchedPath)")

if state["hotkeyFactoryFellBack"]?.bool == true {
    print("FACTORY FALLBACK \(state["hotkeyDisplay"]?.string ?? "") status \(state["viewerHotkeyStatus"]?.int ?? -1)")
}
Check.expect(state["viewerHotkeyStatus"]?.int == 0, "viewer hotkey registered, status \(state["viewerHotkeyStatus"]?.int ?? -1)")
Check.expect(state["hotkeyDisplay"]?.string == "Option-Space", "factory hotkey \(state["hotkeyDisplay"]?.string ?? "")")
Check.expect(state["slipVisible"]?.bool == false, "launch leaves the panel closed")
Check.expect(state["finderPollScheduled"]?.bool == false, "hidden panel has no Finder timer")
Check.expect(state["playbackRunning"]?.bool == false, "nothing is playing")
Check.expect(state["panelCanBecomeKey"]?.bool == false, "panel does not become key")

func generation() -> Int { readState(at: stateURL)?["generation"]?.int ?? 0 }

func command(_ name: String, extra: [String: Any] = [:], settle: Bool = false) -> JSONValue {
    let before = generation()
    let requests = readState(at: stateURL)?["finderRequestCount"]?.int ?? 0
    post(name, extra: extra)
    if settle {
        let deadline = Date().addingTimeInterval(2)
        var latest = state
        while Date() < deadline {
            if let value = readState(at: stateURL) {
                latest = value
                let count = value["finderRequestCount"]?.int ?? 0
                let gen = value["generation"]?.int ?? 0
                if count > requests && gen > before + 1 {
                    return value
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return readState(at: stateURL) ?? latest
    }
    return waitForState(at: stateURL, above: before) ?? state
}

state = command("probeHotkey", extra: ["keyCode": 49, "modifiers": 2048])
Check.expect(state["lastProbeStatus"]?.int == -9878, "live Option-Space cannot be registered twice, got \(state["lastProbeStatus"]?.int ?? 0)")

state = command("probeHotkey", extra: ["keyCode": 49, "modifiers": 0])
Check.expect(state["lastProbeStatus"]?.int == -50, "bare space is rejected, got \(state["lastProbeStatus"]?.int ?? 0)")

state = command("probeHotkey", extra: ["keyCode": 123, "modifiers": 0])
Check.expect(state["lastProbeStatus"]?.int == -50, "unmodified left arrow is rejected, got \(state["lastProbeStatus"]?.int ?? 0)")
for code in [124, 125, 126] {
    state = command("probeHotkey", extra: ["keyCode": code, "modifiers": 0])
    Check.expect(state["lastProbeStatus"]?.int == -50, "unmodified arrow \(code) is rejected")
}

let beforeCarbon = state["carbonDeliveries"]?.int ?? 0
state = command("dispatchViewerHotkey", settle: true)
Check.expect((state["carbonDeliveries"]?.int ?? 0) > beforeCarbon, "carbon handler ran")
Check.expect(state["slipVisible"]?.bool == false, "empty selection leaves the panel closed")
Check.expect(state["finderPollScheduled"]?.bool == false, "empty selection does not schedule the Finder timer")

state = command("setFinder", extra: ["mode": "paths", "paths": [wavA.path, wavB.path]])
state = command("dispatchViewerHotkey", settle: true)
Check.expect(state["slipVisible"]?.bool == false, "two audio files leave the panel closed")

state = command("setFinder", extra: ["mode": "paths", "paths": [wavA.path, text.path]])
state = command("dispatchViewerHotkey", settle: true)
Check.expect(state["slipVisible"]?.bool == false, "a mixed selection leaves the panel closed")

state = command("setFinder", extra: ["mode": "paths", "paths": [text.path]])
state = command("dispatchViewerHotkey", settle: true)
Check.expect(state["slipVisible"]?.bool == false, "a non-audio file leaves the panel closed")

state = command("setFinder", extra: ["mode": "paths", "paths": [ogg.path]])
state = command("dispatchViewerHotkey", settle: true)
Check.expect(state["slipVisible"]?.bool == false, "an ogg file leaves the panel closed")

state = command("setFinder", extra: ["mode": "paths", "paths": [folder.path]])
state = command("dispatchViewerHotkey", settle: true)
Check.expect(state["slipVisible"]?.bool == false, "a folder leaves the panel closed")

state = command("setFinder", extra: ["mode": "paths", "paths": [wavA.path]])
state = command("dispatchViewerHotkey", settle: true)
state = waitUntil(at: stateURL) { $0["slipVisible"]?.bool == true && $0["playbackRunning"]?.bool == true } ?? state
let openedPlaying = state["playbackRunning"]?.bool == true
Check.expect(state["slipVisible"]?.bool == true, "one audio file opens the panel")
Check.expect(state["slipFilename"]?.string == "tone.wav", "filename \(state["slipFilename"]?.string ?? "")")
let openedMetadata = state["slipMetadata"]?.string ?? ""
Check.expect(
    openedMetadata.hasPrefix("WAV · 44.1 kHz · 1 ch · ") && openedMetadata.hasSuffix(" / 0:08"),
    "metadata \(openedMetadata)"
)
Check.expect(state["headerOrder"]?.strings == ["play", "filename", "metadata", "volume", "loop", "settings"], "header order \(state["headerOrder"]?.strings ?? [])")
Check.expect(state["movableByBackground"]?.bool == false, "the window does not drag from the background")
Check.expect((state["metadataMaxX"]?.double ?? 9999) <= (state["volumeMinX"]?.double ?? 0) + 0.5, "metadata stays left of the volume control")
Check.expect((state["loopMinX"]?.double ?? 0) + 20 < (state["gearMinX"]?.double ?? 0), "loop sits left of settings")
Check.expect(state["filenameToolTip"]?.string == "tone.wav", "filename help tag")
Check.expect(state["metadataToolTip"]?.string == openedMetadata, "metadata help tag")
Check.expect(state["blob"]?["loopEnabled"]?.bool == false, "loop defaults off")
state = command("probeHit", extra: ["x": 80, "y": 10])
Check.expect(state["hitKind"]?.string == "header", "header drag region \(state["hitKind"]?.string ?? "")")
state = command("probeHit", extra: ["x": 80, "y": 120])
Check.expect(state["hitKind"]?.string == "waveform", "waveform scrub region \(state["hitKind"]?.string ?? "")")
Check.expect(state["finderPollScheduled"]?.bool == true, "visible panel schedules the Finder timer")
Check.expect(state["escapeHotkeyRegistered"]?.bool == true, "escape is registered while the panel is visible")
Check.expect(openedPlaying, "opening the panel starts playback")
Check.expect(state["panelCanBecomeKey"]?.bool == false, "the open panel does not become key")
Check.expect(state["panelIsKey"]?.bool == false, "Finder keeps the key window")
state = command("setFrontApp", extra: ["bundleID": "com.apple.finder"])
Check.expect(state["previewSpaceRegistered"]?.bool == true, "space toggles play while the panel is visible and Finder is front")
state = command("dispatchPreviewSpace")
state = waitUntil(at: stateURL, timeout: 2) { $0["playbackRunning"]?.bool == false } ?? state
Check.expect(state["playbackRunning"]?.bool == false, "space pauses playback")
Check.expect(state["audioEngineRunning"]?.bool == true, "space keeps the audio engine warm while paused")
state = command("dispatchPreviewSpace")
state = waitUntil(at: stateURL, timeout: 2) { $0["playbackRunning"]?.bool == true } ?? state
Check.expect(state["audioEngineRunning"]?.bool == true, "space resumes on the warm audio engine")
Check.expect(state["playbackRunning"]?.bool == true, "space resumes playback")

state = command("setFrontApp", extra: ["bundleID": "com.apple.Safari"])
Check.expect(state["slipVisible"]?.bool == true, "the panel stays up when Finder is not front")
Check.expect(state["previewSpaceRegistered"]?.bool == false, "space is unregistered when Finder is not front")
Check.expect(state["escapeHotkeyRegistered"]?.bool == true, "escape stays registered when Finder is not front")
state = command("setFrontApp", extra: ["bundleID": "com.apple.finder"])
Check.expect(state["slipVisible"]?.bool == true, "the panel stays up when Finder is front again")
Check.expect(state["previewSpaceRegistered"]?.bool == true, "space is registered again when Finder is front")
state = command("dispatchPreviewSpace")
state = waitUntil(at: stateURL, timeout: 2) { $0["playbackRunning"]?.bool == false } ?? state
Check.expect(state["playbackRunning"]?.bool == false, "space pauses playback again")
Check.expect(state["audioEngineRunning"]?.bool == true, "space keeps the audio engine warm while paused again")
state = command("dispatchPreviewSpace")
state = waitUntil(at: stateURL, timeout: 2) { $0["playbackRunning"]?.bool == true } ?? state
Check.expect(state["audioEngineRunning"]?.bool == true, "space resumes on the warm audio engine again")
Check.expect(state["playbackRunning"]?.bool == true, "space resumes playback again")

Check.expect(abs((state["slipFrameWidth"]?.double ?? 0) - 860) < 1, "first width 860, got \(state["slipFrameWidth"]?.double ?? 0)")
Check.expect(abs((state["slipFrameHeight"]?.double ?? 0) - 500) < 1, "first height 500, got \(state["slipFrameHeight"]?.double ?? 0)")

let slipPNG = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/panel-slip.png").path
_ = command("snapshotSlip", extra: ["path": slipPNG])
Check.expect(FileManager.default.fileExists(atPath: slipPNG), "slip snapshot")

let requestsAtOpen = state["finderRequestCount"]?.int ?? 0
let polled = waitUntil(at: stateURL, timeout: 2.5) { ($0["finderRequestCount"]?.int ?? 0) > requestsAtOpen }
Check.expect((polled?["finderRequestCount"]?.int ?? 0) > requestsAtOpen, "the Finder timer sends another read")

let volumeBefore = run("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"])
state = command("pressPlay")
state = waitUntil(at: stateURL, timeout: 2) {
    ($0["playClicks"]?.int ?? 0) >= 1 && $0["playbackRunning"]?.bool == false
} ?? state
Check.expect((state["playClicks"]?.int ?? 0) >= 1, "play control is visible")
Check.expect(state["playbackRunning"]?.bool == false, "play pauses the autoplay")
state = command("seek", extra: ["pane": "waveform", "fraction": 0.25])
state = waitUntil(at: stateURL, timeout: 2) { abs(($0["playheadSeconds"]?.double ?? -1) - 2.0) < 0.2 } ?? state
state = command("seek", extra: ["pane": "waveform", "fraction": 0.5])
state = waitUntil(at: stateURL, timeout: 2) { abs(($0["playheadSeconds"]?.double ?? -1) - 4.0) < 0.25 } ?? state
Check.expect(abs((state["playheadSeconds"]?.double ?? -1) - 4.0) < 0.25, "a second seek moves the playhead, got \(state["playheadSeconds"]?.double ?? -1)")
state = command("setSlipVolume", extra: ["volume": 0.4])
state = waitUntil(at: stateURL, timeout: 2) { abs(($0["storedVolume"]?.double ?? -1) - 0.4) < 0.001 } ?? state
Check.expect(abs((state["storedVolume"]?.double ?? -1) - 0.4) < 0.001, "slider stores 0.4, got \(state["storedVolume"]?.double ?? -1)")
let volumeAfter = run("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"])
Check.expect(volumeBefore.1 == volumeAfter.1, "system volume unchanged (\(volumeBefore.1.trimmingCharacters(in: .whitespacesAndNewlines)) vs \(volumeAfter.1.trimmingCharacters(in: .whitespacesAndNewlines)))")

if let screen = NSScreen.screens.first {
    let point = CGPoint(x: 8, y: screen.frame.height - 8)
    if let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
       let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
Thread.sleep(forTimeInterval: 0.3)
state = readState(at: stateURL) ?? state
Check.expect(state["slipVisible"]?.bool == true, "a click outside leaves the panel up")

state = command("setFinder", extra: ["mode": "paths", "paths": [wavB.path]])
let followed = waitUntil(at: stateURL, timeout: 2.5) { $0["slipFilename"]?.string == "other.wav" }
Check.expect(followed?["slipFilename"]?.string == "other.wav", "the poll follows a new audio file")
let followedMetadata = followed?["slipMetadata"]?.string ?? ""
Check.expect(
    followedMetadata.hasPrefix("WAV · 44.1 kHz · 1 ch · ") && followedMetadata.hasSuffix(" / 0:08"),
    "the new file's metadata is \(followedMetadata)"
)

state = command("setFinder", extra: ["mode": "paths", "paths": []])
let closed = waitUntil(at: stateURL, timeout: 2.5) { $0["slipVisible"]?.bool == false }
Check.expect(closed?["slipVisible"]?.bool == false, "an empty selection closes the open panel")
Check.expect(closed?["finderPollScheduled"]?.bool == false, "closing the panel unschedules the Finder timer")
let quietCount = closed?["finderRequestCount"]?.int ?? 0
Thread.sleep(forTimeInterval: 1.3)
state = readState(at: stateURL) ?? state
Check.expect(state["finderRequestCount"]?.int == quietCount, "a hidden panel does not keep reading Finder")

state = command("setFinder", extra: ["mode": "paths", "paths": [wavA.path]])
state = command("dispatchViewerHotkey", settle: true)
state = waitUntil(at: stateURL) { $0["slipVisible"]?.bool == true } ?? state
Check.expect(state["slipVisible"]?.bool == true, "the hotkey opens the panel again")
let carbonBeforeEscape = state["carbonDeliveries"]?.int ?? 0
state = command("dispatchEscape")
state = waitUntil(at: stateURL, timeout: 2) {
    ($0["carbonDeliveries"]?.int ?? 0) > carbonBeforeEscape && $0["slipVisible"]?.bool == false
} ?? state
Check.expect((state["carbonDeliveries"]?.int ?? 0) > carbonBeforeEscape, "escape went through the carbon handler")
Check.expect(state["slipVisible"]?.bool == false, "escape closes the panel")
Check.expect(state["escapeHotkeyRegistered"]?.bool == false, "escape is not registered once the panel is closed")
Check.expect(state["previewSpaceRegistered"]?.bool == false, "space is not taken once the panel is closed")
Check.expect(state["finderPollScheduled"]?.bool == false, "escape unschedules the Finder timer")
Check.expect(state["panelIsKey"]?.bool != true, "escape does not leave the panel key")

state = command("setHotkey", extra: ["keyCode": 40, "modifiers": 6144])
Check.expect(state["hotkeyDisplay"]?.string == "Control-Option-K", "rebind display \(state["hotkeyDisplay"]?.string ?? "")")
state = command("probeHotkey", extra: ["keyCode": 49, "modifiers": 2048])
Check.expect(state["lastProbeStatus"]?.int == 0, "Option-Space is free after rebind, got \(state["lastProbeStatus"]?.int ?? -1)")
state = command("probeHotkey", extra: ["keyCode": 40, "modifiers": 6144])
Check.expect(state["lastProbeStatus"]?.int == -9878, "the new combo is the registered one")

state = command("setHotkey", extra: ["keyCode": 49, "modifiers": 0])
Check.expect(state["hotkeyDisplay"]?.string == "Control-Option-K", "bare space does not replace the hotkey")

state = command("setFinder", extra: ["mode": "paths", "paths": [wavA.path]])
state = command("dispatchViewerHotkey", settle: true)
state = waitUntil(at: stateURL) { $0["slipVisible"]?.bool == true } ?? state
Check.expect(state["slipVisible"]?.bool == true, "the rebound hotkey still toggles the panel")
state = command("dispatchViewerHotkey", settle: true)
Check.expect(state["slipVisible"]?.bool == false, "the hotkey toggles the panel closed")

state = command("setFinder", extra: ["mode": "denied"])
let beforeDenied = state["carbonDeliveries"]?.int ?? 0
state = command("dispatchViewerHotkey", settle: true)
Check.expect((state["carbonDeliveries"]?.int ?? 0) > beforeDenied, "denied selection still reaches the handler")
Check.expect(state["slipVisible"]?.bool == false, "an automation denial leaves the panel closed")
let message = state["finderMessage"]?.string ?? ""
Check.expect(message.contains("Enable AudioPeek for Finder"), "denial message: \(message)")
Check.expect(!message.contains("Registered"), "denial message does not say Registered")
Check.expect(state["settingsWindowVisible"]?.bool == true, "the denial is shown in settings")
Check.expect(state["finderPollScheduled"]?.bool == false, "a denial does not start the Finder timer")

state = command("quit")
Thread.sleep(forTimeInterval: 0.4)
Check.expect(runningApps().isEmpty, "app quit")

if Check.failures.isEmpty {
    print("PANEL PASS")
} else {
    print("PANEL FAIL \(Check.failures.count)")
    exit(1)
}
