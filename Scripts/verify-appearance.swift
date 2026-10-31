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
    var strings: [String] {
        if let values = raw as? [String] { return values }
        if let values = raw as? [Any] { return values.compactMap { $0 as? String } }
        return []
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

func append32(_ value: UInt32, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}

func append16(_ value: UInt16, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}

func writeWav(to url: URL, frames: Int, sample: (Int) -> Int16) {
    var data = Data()
    data.append(contentsOf: "RIFF".utf8)
    append32(UInt32(36 + frames * 2), to: &data)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    append32(16, to: &data)
    append16(1, to: &data)
    append16(1, to: &data)
    append32(44100, to: &data)
    append32(44100 * 2, to: &data)
    append16(2, to: &data)
    append16(16, to: &data)
    data.append(contentsOf: "data".utf8)
    append32(UInt32(frames * 2), to: &data)
    for frame in 0..<frames {
        var little = sample(frame).littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    try! data.write(to: url)
}

func near(_ state: JSONValue, _ key: String, _ expected: Double, slack: Double = 0.03) -> Bool {
    guard let got = state[key]?.double else { return false }
    return abs(got - expected) <= slack
}

func blueDominant(_ state: JSONValue) -> Bool {
    let red = state["waveformRed"]?.double ?? 0
    let green = state["waveformGreen"]?.double ?? 0
    let blue = state["waveformBlue"]?.double ?? 0
    return blue > red + 0.2 && blue > green + 0.2
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: verify-appearance AudioPeek.app\n", stderr)
    exit(2)
}

let appPath = CommandLine.arguments[1]
stopRunningApps()
let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audiopeek-appearance-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let tone = root.appendingPathComponent("tone.wav")
writeWav(to: tone, frames: 44100 * 30) { frame in
    Int16(sin(2 * Double.pi * 440 * Double(frame) / 44100) * 16000)
}
defer {
    try? FileManager.default.removeItem(at: root)
    stopRunningApps()
}

let id = UUID().uuidString
let suite = "audiopeek.appearance.\(id)"
let stateURL = URL(fileURLWithPath: "/tmp/audiopeek-appearance-\(id).json")
let configURL = URL(fileURLWithPath: "/tmp/audiopeek-appearance-\(id)-config.json")
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

let opened = run("/usr/bin/open", [appPath, "--args", "--test-config", configURL.path])
Check.expect(opened.0 == 0, "open launched the app")
guard waitUntil(at: stateURL, timeout: 6, { ($0["generation"]?.int ?? 0) > 0 }) != nil else {
    Check.expect(false, "app wrote launch state")
    print("APPEARANCE FAIL")
    exit(1)
}

var state = openFile(tone.path)
_ = command("stepOverview")
state = waitUntil(at: stateURL, timeout: 4) { ($0["overviewFilled"]?.int ?? 0) > 0 } ?? state
let paintingPass = state["overviewPassID"]?.int ?? -1
Check.expect(state["playbackRunning"]?.bool == true, "playback is running before the appearance change")
Check.expect(state["waveformUsesSystemBlue"]?.bool == true, "waveform color starts as system blue")
Check.expect(blueDominant(state), "the starting waveform is blue, rgb \(state["waveformRed"]?.double ?? -1) \(state["waveformGreen"]?.double ?? -1) \(state["waveformBlue"]?.double ?? -1)")

state = command("setAppearance", extra: ["appearance": "dark"])
Check.expect(state["slipAppearance"]?.string == "dark", "forced dark, got \(state["slipAppearance"]?.string ?? "")")
// On macOS 26 and later the panel sits on Liquid Glass and draws no chrome color of its own,
// so the chrome checks below cover the solid fallback color the view keeps for macOS 15.
if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
    Check.expect(state["slipUsesGlass"]?.bool == true, "the panel uses Liquid Glass on this macOS")
}
Check.expect(near(state, "chromeRed", 0x2A / 255) && near(state, "chromeBlue", 0x2C / 255), "dark chrome \(state["chromeRed"]?.double ?? -1) \(state["chromeGreen"]?.double ?? -1) \(state["chromeBlue"]?.double ?? -1)")
Check.expect(near(state, "playheadRed", 1) && near(state, "playheadGreen", 0x45 / 255) && near(state, "playheadBlue", 0x3A / 255), "dark hairline \(state["playheadRed"]?.double ?? -1) \(state["playheadGreen"]?.double ?? -1) \(state["playheadBlue"]?.double ?? -1)")
Check.expect(abs((state["playheadWidth"]?.double ?? 0) - 1) < 0.1, "playhead stays a 1 px hairline, got \(state["playheadWidth"]?.double ?? -1)")
Check.expect(blueDominant(state), "dark system blue stays blue")
let darkWave = (
    state["waveformRed"]?.double ?? 0,
    state["waveformGreen"]?.double ?? 0,
    state["waveformBlue"]?.double ?? 0
)
Check.expect((state["overviewPassID"]?.int ?? -1) == paintingPass, "dark appearance keeps the pass")
Check.expect(state["playbackRunning"]?.bool == true, "playback continues in dark appearance")

state = command("setAppearance", extra: ["appearance": "light"])
Check.expect(state["slipAppearance"]?.string == "light", "forced light, got \(state["slipAppearance"]?.string ?? "")")
Check.expect(near(state, "chromeRed", 0xF3 / 255) && near(state, "chromeBlue", 0xF5 / 255), "light chrome \(state["chromeRed"]?.double ?? -1) \(state["chromeGreen"]?.double ?? -1) \(state["chromeBlue"]?.double ?? -1)")
Check.expect(near(state, "playheadRed", 1) && near(state, "playheadGreen", 0x3B / 255) && near(state, "playheadBlue", 0x30 / 255), "light hairline \(state["playheadRed"]?.double ?? -1) \(state["playheadGreen"]?.double ?? -1) \(state["playheadBlue"]?.double ?? -1)")
Check.expect(blueDominant(state), "light system blue stays blue")
let lightWave = (
    state["waveformRed"]?.double ?? 0,
    state["waveformGreen"]?.double ?? 0,
    state["waveformBlue"]?.double ?? 0
)
let waveGap = abs(lightWave.0 - darkWave.0) + abs(lightWave.1 - darkWave.1) + abs(lightWave.2 - darkWave.2)
Check.expect(waveGap > 0.02, "light and dark system blue differ, light \(lightWave) dark \(darkWave)")
Check.expect((state["overviewPassID"]?.int ?? -1) == paintingPass, "light appearance keeps the pass")
Check.expect(state["playbackRunning"]?.bool == true, "playback continues in light appearance")

state = command("setWaveformColor", extra: ["red": 1, "green": 0, "blue": 0, "alpha": 1])
Check.expect(state["waveformUsesSystemBlue"]?.bool == false, "the color well overrides system blue")
Check.expect(near(state, "waveformRed", 1, slack: 0.01) && near(state, "waveformGreen", 0, slack: 0.01) && near(state, "waveformBlue", 0, slack: 0.01), "custom waveform is red")
Check.expect((state["overviewPassID"]?.int ?? -1) == paintingPass, "a color change does not restart the pass")
Check.expect(state["playbackRunning"]?.bool == true, "playback continues through the color change")
let lanesBefore = state["overviewLaneCount"]?.int ?? -1
let binsBefore = state["spectrogramBinCount"]?.int ?? -1
state = command("setAmplitude", extra: ["amplitude": "decibels"])
Check.expect((state["overviewPassID"]?.int ?? -1) == paintingPass, "amplitude does not restart the pass")
Check.expect((state["spectrogramBinCount"]?.int ?? -1) == binsBefore, "amplitude keeps the spectrogram")
state = command("setDbFloor", extra: ["floor": -40])
Check.expect((state["overviewPassID"]?.int ?? -1) == paintingPass, "db floor does not restart the pass")
Check.expect((state["overviewLaneCount"]?.int ?? -1) == lanesBefore, "db floor keeps the waveform")

state = command("reset")
Check.expect(state["waveformUsesSystemBlue"]?.bool == true, "reset restores system blue")
Check.expect(blueDominant(state), "reset waveform is system blue again")
Check.expect((state["overviewPassID"]?.int ?? -1) == paintingPass, "reset keeps the pass")
Check.expect(state["playbackRunning"]?.bool == true, "playback continues through reset")

_ = command("openSettings")
Thread.sleep(forTimeInterval: 0.4)
state = command("dump")
let labels = state["settingsLabels"]?.strings ?? []
let joined = labels.joined(separator: "\n").lowercased()
Check.expect(labels.contains("waveform.colorWell"), "settings has the waveform color well, labels \(labels)")
Check.expect(!joined.contains("appearance") && !joined.contains("dark mode") && !joined.contains("light mode"), "settings has no appearance toggle")

_ = command("quit")
let quitDeadline = Date().addingTimeInterval(2)
while Date() < quitDeadline && !runningApps().isEmpty { Thread.sleep(forTimeInterval: 0.05) }
Check.expect(runningApps().isEmpty, "app quit")

if Check.failures.isEmpty {
    print("APPEARANCE PASS")
} else {
    print("APPEARANCE FAIL \(Check.failures.count)")
    exit(1)
}
