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

func append32(_ value: UInt32, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}

func append16(_ value: UInt16, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}

func wavHeader(frames: Int, channels: Int) -> Data {
    var data = Data()
    let block = channels * 2
    data.append(contentsOf: "RIFF".utf8)
    append32(UInt32(36 + frames * block), to: &data)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    append32(16, to: &data)
    append16(1, to: &data)
    append16(UInt16(channels), to: &data)
    append32(44100, to: &data)
    append32(UInt32(44100 * block), to: &data)
    append16(UInt16(block), to: &data)
    append16(16, to: &data)
    data.append(contentsOf: "data".utf8)
    append32(UInt32(frames * block), to: &data)
    return data
}

func writeWav(to url: URL, frames: Int, channels: Int, sample: (Int, Int) -> Int16) {
    var data = wavHeader(frames: frames, channels: channels)
    for frame in 0..<frames {
        for channel in 0..<channels {
            var little = sample(frame, channel).littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
    }
    try! data.write(to: url)
}

func writeSilentWav(to url: URL, frames: Int, channels: Int) {
    var data = wavHeader(frames: frames, channels: channels)
    data.append(Data(count: frames * channels * 2))
    try! data.write(to: url)
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: verify-spectrogram AudioPeek.app\n", stderr)
    exit(2)
}

let appPath = CommandLine.arguments[1]
let repo = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let mel = run(
    repo.appendingPathComponent("build/mel-check/bin/python").path,
    [
        repo.appendingPathComponent("Scripts/check_mel.py").path,
        "/tmp/audiopeek-mel-check.wav",
        "/tmp/audiopeek-mel-check.json",
    ]
)
print(mel.1)
Check.expect(mel.0 == 0, "shipping columns stay within 1 dB of pinned librosa")
if mel.0 != 0 {
    print("SPECTROGRAM FAIL")
    exit(1)
}

stopRunningApps()
let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audiopeek-spectrogram-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let tone = root.appendingPathComponent("tone.wav")
let long = root.appendingPathComponent("long.wav")
let wide = root.appendingPathComponent("wide.wav")
writeWav(to: tone, frames: 44100 * 30, channels: 1) { frame, _ in
    Int16(sin(2 * Double.pi * 440 * Double(frame) / 44100) * 16000)
}
writeSilentWav(to: long, frames: 44100 * 60 * 12, channels: 1)
writeWav(to: wide, frames: 12000, channels: 16) { frame, channel in
    (channel == 0 || channel == 1) && frame < 400 ? 20000 : 0
}
defer {
    try? FileManager.default.removeItem(at: root)
    stopRunningApps()
}

let id = UUID().uuidString
let suite = "audiopeek.spectrogram.\(id)"
let stateURL = URL(fileURLWithPath: "/tmp/audiopeek-spectrogram-\(id).json")
let configURL = URL(fileURLWithPath: "/tmp/audiopeek-spectrogram-\(id)-config.json")
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

func followFile(_ path: String) -> JSONValue {
    let name = URL(fileURLWithPath: path).lastPathComponent
    let previous = readState(at: stateURL)?["overviewPassID"]?.int ?? -1
    _ = command("setFinder", extra: ["mode": "paths", "paths": [path]])
    return waitUntil(at: stateURL, timeout: 4) { value in
        value["slipVisible"]?.bool == true
            && value["slipFilename"]?.string == name
            && (value["durationSeconds"]?.double ?? 0) > 0
            && (value["overviewPassID"]?.int ?? -1) != previous
            && value["overviewRunning"]?.bool == true
    } ?? (readState(at: stateURL) ?? JSONValue(raw: [:]))
}

let opened = run("/usr/bin/open", [appPath, "--args", "--test-config", configURL.path])
Check.expect(opened.0 == 0, "open launched the app")
guard waitUntil(at: stateURL, timeout: 6, { ($0["generation"]?.int ?? 0) > 0 }) != nil else {
    Check.expect(false, "app wrote launch state")
    print("SPECTROGRAM FAIL")
    exit(1)
}

var state = openFile(tone.path)
_ = command("stepOverview")
state = waitUntil(at: stateURL, timeout: 4) {
    ($0["spectrogramBinCount"]?.int ?? 0) == 128 && ($0["spectrogramPeak"]?.double ?? 0) > 0
} ?? state
Check.expect((state["spectrogramBinCount"]?.int ?? 0) == 128, "mel uses 128 bins, got \(state["spectrogramBinCount"]?.int ?? -1)")
Check.expect((state["spectrogramLaneCount"]?.int ?? 0) == 1, "mixdown draws one spectrogram lane, got \(state["spectrogramLaneCount"]?.int ?? -1)")
Check.expect(state["overviewRunning"]?.bool == true, "the pass is still running")
Check.expect(state["overviewFinished"]?.bool == false, "the short file is stalled after one chunk")
Check.expect(state["progressVisible"]?.bool == false, "a 30 s wav hides the percent bar")
Check.expect((state["estimateSeconds"]?.double ?? 1) < 1, "short estimate \(state["estimateSeconds"]?.double ?? -1)")
Check.expect((state["spectrogramPeak"]?.double ?? 0) > 0, "the sine has spectrogram energy")
Check.expect(state["playbackRunning"]?.bool == true, "playback is running while the short picture fills")

state = followFile(long.path)
Check.expect(state["progressVisible"]?.bool == true, "a 12 min wav shows the percent bar")
Check.expect((state["estimateSeconds"]?.double ?? 0) > 1, "long estimate \(state["estimateSeconds"]?.double ?? -1)")
let longPass = state["overviewPassID"]?.int ?? -1
_ = command("stepOverview")
state = waitUntil(at: stateURL, timeout: 4) {
    let fraction = $0["progressFraction"]?.double ?? 0
    return fraction > 0 && fraction < 0.02 && $0["playbackRunning"]?.bool == true
} ?? state
let fraction = state["progressFraction"]?.double ?? -1
Check.expect(fraction > 0 && fraction < 0.02, "the bar tracks the fill, got \(fraction)")
Check.expect(state["playbackRunning"]?.bool == true, "playback continues on the long file")
Check.expect((state["overviewPassID"]?.int ?? -1) == longPass, "one chunk stays on the long pass")

state = command("setSpectrogramNFFT", extra: ["nFFT": 1024])
state = waitUntil(at: stateURL, timeout: 4) { ($0["overviewPassID"]?.int ?? -1) != longPass } ?? state
Check.expect((state["overviewPassID"]?.int ?? -1) != longPass, "n_fft restarts the pass during playback")
Check.expect(state["playbackRunning"]?.bool == true, "playback continues through the knob change")
Check.expect((state["overviewPeakPasses"]?.int ?? 0) == 1, "the restarted pass is still alone")

state = followFile(wide.path)
let widePass = state["overviewPassID"]?.int ?? -1
state = command("setSpectrogramDual", extra: ["dual": true])
let header = state["slipMetadata"]?.string ?? ""
Check.expect(header.contains("16 ch · showing 8"), "waveform cap stays in the header, got \(header)")
Check.expect(header.contains("16 ch · showing 2"), "spectrogram cap uses the header pattern, got \(header)")
state = waitUntil(at: stateURL, timeout: 4) { ($0["overviewPassID"]?.int ?? -1) != widePass } ?? state
_ = command("stepOverview")
state = waitUntil(at: stateURL, timeout: 4) { ($0["spectrogramLaneCount"]?.int ?? 0) == 2 } ?? state
Check.expect((state["spectrogramLaneCount"]?.int ?? 0) == 2, "dual draws the first 2 channels, got \(state["spectrogramLaneCount"]?.int ?? -1)")

_ = command("quit")
Check.expect(waitForQuit(), "app quit")

if Check.failures.isEmpty {
    print("SPECTROGRAM PASS")
} else {
    print("SPECTROGRAM FAIL \(Check.failures.count)")
    exit(1)
}
