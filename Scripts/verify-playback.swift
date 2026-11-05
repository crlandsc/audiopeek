import AppKit
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

// Quitting can take a moment (the audio engine shuts down), so wait for it instead of sleeping.
func waitForQuit(timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline && !runningApps().isEmpty {
        Thread.sleep(forTimeInterval: 0.05)
    }
    return runningApps().isEmpty
}

func stopRunningApps() {
    for app in runningApps() { app.terminate() }
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline && !runningApps().isEmpty { Thread.sleep(forTimeInterval: 0.05) }
    for app in runningApps() { app.forceTerminate() }
}

func readState(at url: URL) -> JSONValue? {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
    return JSONValue(raw: object)
}

func waitUntil(at url: URL, timeout: TimeInterval = 4, _ match: (JSONValue) -> Bool) -> JSONValue? {
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
        notificationName, object: nil, userInfo: info, deliverImmediately: true
    )
}

func writeWav(to url: URL, seconds: Double, sampleRate: Int) {
    let frames = Int(seconds * Double(sampleRate))
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
    append32(UInt32(sampleRate))
    append32(UInt32(sampleRate * 2))
    append16(2)
    append16(16)
    data.append(contentsOf: "data".utf8)
    append32(UInt32(frames * 2))
    data.append(Data(count: frames * 2))
    try! data.write(to: url)
}

func systemVolume() -> String {
    run("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"]).1
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: verify-playback AudioPeek.app\n", stderr)
    exit(2)
}

let appPath = CommandLine.arguments[1]
stopRunningApps()
let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audiopeek-playback-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let tone = root.appendingPathComponent("tone.wav")
let broken = root.appendingPathComponent("broken.wav")
writeWav(to: tone, seconds: 1.2, sampleRate: 44100)
try! Data([0, 1, 2, 3]).write(to: broken)
defer {
    try? FileManager.default.removeItem(at: root)
    stopRunningApps()
}

let id = UUID().uuidString
let suite = "audiopeek.playback.\(id)"
let stateURL = URL(fileURLWithPath: "/tmp/audiopeek-playback-\(id).json")
let configURL = URL(fileURLWithPath: "/tmp/audiopeek-playback-\(id)-config.json")
let config: [String: Any] = [
    "defaultsSuite": suite,
    "statePath": stateURL.path,
    "injectLoginFailure": "succeeded",
    "finderSelection": "empty",
    "machineLoad": ["thermal": "nominal", "cpu": 0.2],
]
try! JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted]).write(to: configURL)
defer {
    _ = run("/usr/bin/defaults", ["delete", suite])
    try? FileManager.default.removeItem(at: stateURL)
    try? FileManager.default.removeItem(at: configURL)
}

func generation() -> Int { readState(at: stateURL)?["generation"]?.int ?? 0 }

func command(_ name: String, extra: [String: Any] = [:]) -> JSONValue {
    // Timers also write state, so wait for this command's own id, not just the next write.
    let id = UUID().uuidString
    post(name, extra: extra.merging(["commandID": id]) { current, _ in current })
    return waitUntil(at: stateURL) { $0["lastCommandID"]?.string == id } ?? JSONValue(raw: [:])
}

func openFile(_ path: String) -> JSONValue {
    _ = command("setFinder", extra: ["mode": "paths", "paths": [path]])
    let before = generation()
    post("dispatchViewerHotkey")
    return waitUntil(at: stateURL, timeout: 4) { value in
        let gen = value["generation"]?.int ?? 0
        let duration = value["durationSeconds"]?.double ?? 0
        return gen > before && value["slipVisible"]?.bool == true && duration > 0
    } ?? (readState(at: stateURL) ?? JSONValue(raw: [:]))
}

let volumeBefore = systemVolume()
let opened = run("/usr/bin/open", [appPath, "--args", "--test-config", configURL.path])
Check.expect(opened.0 == 0, "open launched the app")
guard waitUntil(at: stateURL, timeout: 6, { ($0["generation"]?.int ?? 0) > 0 }) != nil else {
    Check.expect(false, "app wrote launch state")
    print("PLAYBACK FAIL")
    exit(1)
}

let launchedPid = readState(at: stateURL)?["pid"]?.int ?? -1
let launchedPath = run("/bin/ps", ["-o", "comm=", "-p", String(launchedPid)]).1.trimmingCharacters(in: .whitespacesAndNewlines)
let expectedPath = URL(fileURLWithPath: appPath).resolvingSymlinksInPath().appendingPathComponent("Contents/MacOS").path
Check.expect(launchedPath.hasPrefix(expectedPath), "launched the app it was given: \(launchedPath)")

var state = openFile(tone.path)
Check.expect(state["slipVisible"]?.bool == true, "the file opens the panel")
Check.expect(state["playbackRunning"]?.bool == true, "autoplay starts on a clear sample")
Check.expect((state["playheadSeconds"]?.double ?? 1) < 0.2, "autoplay starts near 0, got \(state["playheadSeconds"]?.double ?? -1)")
Check.expect(abs((state["durationSeconds"]?.double ?? 0) - 1.2) < 0.05, "duration \(state["durationSeconds"]?.double ?? 0)")
Check.expect(state["slipMetadata"]?.string == "WAV · 44.1 kHz · 1 ch · 0:00 / 0:01", "metadata \(state["slipMetadata"]?.string ?? "")")
Check.expect(state["volumeKeyPresent"]?.bool == false, "autoplay does not create the volume key")

state = command("pressPlay")
Check.expect(state["playbackRunning"]?.bool == false, "pause stops playback")
let pausedAt = state["playheadSeconds"]?.double ?? 0
state = command("pressPlay")
state = waitUntil(at: stateURL, timeout: 2) { $0["playbackRunning"]?.bool == true } ?? state
Check.expect(state["playbackRunning"]?.bool == true, "resume continues playback")
Check.expect(abs((state["playheadSeconds"]?.double ?? 0) - pausedAt) < 0.15, "resume keeps the playhead, got \(state["playheadSeconds"]?.double ?? -1)")
state = command("pressPlay")

state = command("seek", extra: ["pane": "waveform", "fraction": 0.25])
state = waitUntil(at: stateURL, timeout: 2) { abs(($0["playheadSeconds"]?.double ?? 0) - 0.3) < 0.08 } ?? state
Check.expect(abs((state["playheadSeconds"]?.double ?? 0) - 0.3) < 0.08, "waveform seek \(state["playheadSeconds"]?.double ?? -1)")
state = command("seek", extra: ["pane": "spectrogram", "fraction": 0.5])
state = waitUntil(at: stateURL, timeout: 2) { abs(($0["playheadSeconds"]?.double ?? 0) - 0.6) < 0.08 } ?? state
Check.expect(abs((state["playheadSeconds"]?.double ?? 0) - 0.6) < 0.08, "spectrogram seek \(state["playheadSeconds"]?.double ?? -1)")

state = command("setPanes", extra: ["waveform": false, "spectrogram": false])
let held = state["playheadSeconds"]?.double ?? 0
state = command("seek", extra: ["pane": "waveform", "fraction": 0.1])
Check.expect(abs((state["playheadSeconds"]?.double ?? 0) - held) < 0.05, "seek does nothing when both panes are hidden")
state = command("setPanes", extra: ["waveform": true, "spectrogram": true])

state = command("dispatchViewerHotkey")
state = waitUntil(at: stateURL) { $0["slipVisible"]?.bool == false } ?? state
Check.expect(state["playbackRunning"]?.bool == false, "hiding the panel stops playback")

state = command("setLoad", extra: ["thermal": "serious", "cpu": 0.1])
state = openFile(tone.path)
Check.expect(state["slipVisible"]?.bool == true, "a blocked sample still shows the file")
Check.expect(state["playbackRunning"]?.bool == false, "serious thermal state does not start playback")
state = command("setLoad", extra: ["thermal": "nominal", "cpu": 0.9])
Check.expect(state["playbackRunning"]?.bool == false, "CPU at or above 85% does not start playback")
state = command("setLoad", extra: ["thermal": "fair", "cpu": 0.75])
Check.expect(state["playbackRunning"]?.bool == false, "a window above 70% does not clear the gate")
state = command("setLoad", extra: ["thermal": "nominal", "cpu": 0.7])
state = waitUntil(at: stateURL) { $0["playbackRunning"]?.bool == true } ?? state
Check.expect(state["playbackRunning"]?.bool == true, "playback starts after one clear window")

state = command("setSlipVolume", extra: ["volume": 0.3])
Check.expect(abs((state["storedVolume"]?.double ?? -1) - 0.3) < 0.001, "volume 0.3 stored")
state = command("setSlipVolume", extra: ["volume": 2])
Check.expect(abs((state["storedVolume"]?.double ?? -1) - 1) < 0.001, "volume above unity clamps to 1")
state = command("setSlipVolume", extra: ["volume": 0.3])
let volumeDuring = systemVolume()
Check.expect(volumeBefore == volumeDuring, "system volume unchanged during playback")

let firstPid = state["pid"]?.int
_ = command("quit")
Check.expect(waitForQuit(), "app quit before relaunch")
let reopened = run("/usr/bin/open", [appPath, "--args", "--test-config", configURL.path])
Check.expect(reopened.0 == 0, "relaunch")
state = waitUntil(at: stateURL, timeout: 6) {
    $0["pid"]?.int != firstPid && abs(($0["storedVolume"]?.double ?? -1) - 0.3) < 0.001
} ?? JSONValue(raw: [:])
Check.expect(state["pid"]?.int != firstPid, "relaunch is a new process")
Check.expect(abs((state["storedVolume"]?.double ?? -1) - 0.3) < 0.001, "volume survives relaunch, got \(state["storedVolume"]?.double ?? -1)")

state = command("setFinder", extra: ["mode": "paths", "paths": [broken.path]])
let beforeBroken = state["generation"]?.int ?? 0
post("dispatchViewerHotkey")
state = waitUntil(at: stateURL, timeout: 4) { ($0["generation"]?.int ?? 0) > beforeBroken && $0["slipVisible"]?.bool == false } ?? state
Check.expect(state["slipVisible"]?.bool == false, "a file that fails to open leaves the panel closed")
Check.expect(state["playbackRunning"]?.bool == false, "a failed open does not play")

_ = command("quit")
Check.expect(waitForQuit(), "app quit")

if Check.failures.isEmpty {
    print("PLAYBACK PASS")
} else {
    print("PLAYBACK FAIL \(Check.failures.count)")
    exit(1)
}
