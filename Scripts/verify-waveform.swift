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

func writeWav(to url: URL, frames: Int, channels: Int, sample: (Int, Int) -> Int16) {
    var data = Data()
    func append32(_ value: UInt32) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    func append16(_ value: UInt16) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    let block = channels * 2
    data.append(contentsOf: "RIFF".utf8)
    append32(UInt32(36 + frames * block))
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    append32(16)
    append16(1)
    append16(UInt16(channels))
    append32(44100)
    append32(UInt32(44100 * block))
    append16(UInt16(block))
    append16(16)
    data.append(contentsOf: "data".utf8)
    append32(UInt32(frames * block))
    for frame in 0..<frames {
        for channel in 0..<channels {
            var little = sample(frame, channel).littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
    }
    try! data.write(to: url)
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: verify-waveform AudioPeek.app\n", stderr)
    exit(2)
}

let appPath = CommandLine.arguments[1]
stopRunningApps()
let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audiopeek-waveform-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let tone = root.appendingPathComponent("tone.wav")
let other = root.appendingPathComponent("other.wav")
let wide = root.appendingPathComponent("wide.wav")
writeWav(to: tone, frames: 44100 * 30, channels: 1) { frame, _ in
    frame < 200 ? 32767 : 0
}
writeWav(to: other, frames: 44100, channels: 1) { frame, _ in
    frame < 200 ? 16000 : 0
}
writeWav(to: wide, frames: 12000, channels: 16) { frame, channel in
    channel == 0 && frame < 200 ? 32767 : 0
}
defer {
    try? FileManager.default.removeItem(at: root)
    stopRunningApps()
}

let id = UUID().uuidString
let suite = "audiopeek.waveform.\(id)"
let stateURL = URL(fileURLWithPath: "/tmp/audiopeek-waveform-\(id).json")
let configURL = URL(fileURLWithPath: "/tmp/audiopeek-waveform-\(id)-config.json")
let config: [String: Any] = [
    "defaultsSuite": suite,
    "statePath": stateURL.path,
    "injectLoginFailure": "succeeded",
    "finderSelection": "empty",
    "overviewStall": true,
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
    let before = generation()
    post(name, extra: extra)
    return waitUntil(at: stateURL) { ($0["generation"]?.int ?? 0) > before } ?? JSONValue(raw: [:])
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

func followFile(_ path: String, previousPass: Int, previousFilled: Int, grew: inout Bool) -> JSONValue {
    let name = URL(fileURLWithPath: path).lastPathComponent
    _ = command("setFinder", extra: ["mode": "paths", "paths": [path]])
    return waitUntil(at: stateURL, timeout: 4) { value in
        let pass = value["overviewPassID"]?.int ?? -1
        let count = value["overviewFilled"]?.int ?? 0
        if pass == previousPass && count > previousFilled { grew = true }
        return value["slipVisible"]?.bool == true
            && value["slipFilename"]?.string == name
            && (value["durationSeconds"]?.double ?? 0) > 0
            && pass != previousPass
            && value["overviewRunning"]?.bool == true
    } ?? (readState(at: stateURL) ?? JSONValue(raw: [:]))
}

func revealColumns(from state: JSONValue) -> JSONValue {
    if (state["overviewFilled"]?.int ?? 0) > 0 { return state }
    _ = command("stepOverview")
    return waitUntil(at: stateURL, timeout: 4) { ($0["overviewFilled"]?.int ?? 0) > 0 }
        ?? (readState(at: stateURL) ?? state)
}

let opened = run("/usr/bin/open", [appPath, "--args", "--test-config", configURL.path])
Check.expect(opened.0 == 0, "open launched the app")
guard waitUntil(at: stateURL, timeout: 6, { ($0["generation"]?.int ?? 0) > 0 }) != nil else {
    Check.expect(false, "app wrote launch state")
    print("WAVEFORM FAIL")
    exit(1)
}

var state = openFile(tone.path)
state = revealColumns(from: state)
let paintingPass = state["overviewPassID"]?.int ?? -1
let filled = state["overviewFilled"]?.int ?? 0
let columns = state["overviewColumnCount"]?.int ?? 0
Check.expect(state["overviewRunning"]?.bool == true, "the pass is still running")
Check.expect(state["overviewFinished"]?.bool == false, "columns appear before the pass finishes")
Check.expect(filled > 0 && filled < columns, "filled \(filled) of \(columns)")
Check.expect((state["overviewFirstMaximum"]?.double ?? 0) > 0.9, "the first column follows the samples, got \(state["overviewFirstMaximum"]?.double ?? -1)")
Check.expect(state["playbackRunning"]?.bool == true, "playback is running while the picture fills")
Check.expect((state["overviewPeakPasses"]?.int ?? 0) == 1, "one pass is in flight")

let frozen = filled
state = command("setLoad", extra: ["thermal": "serious", "cpu": 0.1])
state = waitUntil(at: stateURL) { $0["overviewPaused"]?.bool == true } ?? state
Check.expect(state["overviewPaused"]?.bool == true, "serious thermal state pauses the overview")
Check.expect(state["playbackRunning"]?.bool == true, "playback continues")
Check.expect((state["overviewFilled"]?.int ?? -1) == frozen, "painted columns stay, got \(state["overviewFilled"]?.int ?? -1)")
let pausedPass = state["overviewPassID"]?.int ?? -1
Check.expect(pausedPass == paintingPass, "pressure keeps pass \(pausedPass), started as \(paintingPass)")

state = command("setLoad", extra: ["thermal": "fair", "cpu": 0.75])
Thread.sleep(forTimeInterval: 0.6)
state = readState(at: stateURL) ?? state
Check.expect(state["overviewPaused"]?.bool == true, "a window above 70% leaves the overview paused")
Check.expect((state["overviewFilled"]?.int ?? -1) == frozen, "that window adds no columns")
Check.expect(state["playbackRunning"]?.bool == true, "playback still continues")

state = command("setLoad", extra: ["thermal": "nominal", "cpu": 0.7])
_ = command("stepOverview")
state = waitUntil(at: stateURL) { ($0["overviewFilled"]?.int ?? 0) > frozen && $0["overviewPaused"]?.bool == false } ?? state
Check.expect((state["overviewFilled"]?.int ?? 0) > frozen, "the same pass resumes, filled \(state["overviewFilled"]?.int ?? 0)")
Check.expect((state["overviewPassID"]?.int ?? -1) == pausedPass, "resume kept pass \(state["overviewPassID"]?.int ?? -1), paused pass \(pausedPass)")
Check.expect(state["playbackRunning"]?.bool == true, "playback continues after the window clears")
Check.expect(state["overviewFinished"]?.bool == false, "resume does not start a second pass")

let heldPass = state["overviewPassID"]?.int ?? -1
let heldFilled = state["overviewFilled"]?.int ?? 0
var sawOldGrow = false
let switched = followFile(other.path, previousPass: heldPass, previousFilled: heldFilled, grew: &sawOldGrow)
Check.expect(!sawOldGrow, "cancel after the painted columns publishes nothing further")
state = revealColumns(from: switched)
Check.expect((state["overviewPassID"]?.int ?? -1) != heldPass, "the next pass started")
Check.expect((state["overviewFilled"]?.int ?? 0) > 0, "the next pass is not blocked")
Check.expect((state["overviewPeakPasses"]?.int ?? 0) == 1, "a second pass does not run beside the first, peak \(state["overviewPeakPasses"]?.int ?? -1)")

var ignoredGrow = false
let widePassBefore = state["overviewPassID"]?.int ?? -1
state = followFile(wide.path, previousPass: widePassBefore, previousFilled: state["overviewFilled"]?.int ?? 0, grew: &ignoredGrow)
Check.expect(state["slipMetadata"]?.string?.contains("16 ch · showing 8") == true, "header \(state["slipMetadata"]?.string ?? "")")
state = revealColumns(from: state)
Check.expect((state["overviewLaneCount"]?.int ?? 0) == 8, "dual draws 8 lanes, got \(state["overviewLaneCount"]?.int ?? -1)")

let widePass = state["overviewPassID"]?.int ?? -1
state = command("setWaveformDual", extra: ["dual": false])
state = waitUntil(at: stateURL, timeout: 4) {
    $0["slipMetadata"]?.string?.contains("showing") != true && ($0["overviewPassID"]?.int ?? -1) != widePass
} ?? state
Check.expect(state["slipMetadata"]?.string?.contains("16 ch") == true, "mixdown header keeps the channel count, got \(state["slipMetadata"]?.string ?? "")")
Check.expect(state["slipMetadata"]?.string?.contains("showing") != true, "mixdown header has no showing count, got \(state["slipMetadata"]?.string ?? "")")
state = revealColumns(from: state)
Check.expect((state["overviewLaneCount"]?.int ?? 0) == 1, "mixdown draws one lane, got \(state["overviewLaneCount"]?.int ?? -1)")

let steadyPass = state["overviewPassID"]?.int ?? -1
let frameX = state["slipFrameX"]?.double ?? 0
let frameY = state["slipFrameY"]?.double ?? 0
let frameWidth = state["slipFrameWidth"]?.double ?? 860
let frameHeight = state["slipFrameHeight"]?.double ?? 500
_ = command("setWindowFrame", extra: ["x": frameX, "y": frameY, "width": frameWidth, "height": frameHeight + 40])
Thread.sleep(forTimeInterval: 0.6)
state = readState(at: stateURL) ?? state
Check.expect((state["overviewPassID"]?.int ?? -1) == steadyPass, "a height change keeps the pass")

_ = command("setWindowFrame", extra: ["x": frameX, "y": frameY, "width": 700, "height": frameHeight])
state = waitUntil(at: stateURL, timeout: 4) { ($0["overviewPassID"]?.int ?? -1) != steadyPass } ?? state
Check.expect((state["overviewPassID"]?.int ?? -1) != steadyPass, "a width change restarts the pass once")
Check.expect((state["overviewPeakPasses"]?.int ?? 0) == 1, "the restarted pass is still alone")
let restartedColumns = state["overviewColumnCount"]?.int ?? 0
// The panes sit inside a 12 pt glass rim on each side, so a 700 pt panel has 676 pt panes.
Check.expect(abs(restartedColumns - (700 - 2 * 12)) <= 4, "columns follow the pane width, got \(restartedColumns)")

_ = command("quit")
Thread.sleep(forTimeInterval: 0.3)
Check.expect(runningApps().isEmpty, "app quit")

if Check.failures.isEmpty {
    print("WAVEFORM PASS")
} else {
    print("WAVEFORM FAIL \(Check.failures.count)")
    exit(1)
}
