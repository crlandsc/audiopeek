import AppKit
import CoreGraphics
import Foundation

let bundleID = "com.landschoot.audiopeek"
let notificationName = Notification.Name("com.landschoot.audiopeek.test")
let settingsVolumeKey = "volume"

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
        guard let dict = raw as? [String: Any] else { return nil }
        guard let next = dict[key], !(next is NSNull) else { return nil }
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
    do {
        try process.run()
    } catch {
        return (1, "\(error)")
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func runningApps() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
}

func stopRunningApps() {
    let apps = runningApps()
    for app in apps {
        app.terminate()
    }
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline && !runningApps().isEmpty {
        Thread.sleep(forTimeInterval: 0.05)
    }
    for app in runningApps() {
        app.forceTerminate()
    }
    let forceDeadline = Date().addingTimeInterval(3)
    while Date() < forceDeadline && !runningApps().isEmpty {
        Thread.sleep(forTimeInterval: 0.05)
    }
}

func readState(at url: URL) -> JSONValue? {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) else {
        return nil
    }
    return JSONValue(raw: object)
}

func waitForState(at url: URL, above generation: Int, timeout: TimeInterval = 8) -> JSONValue? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let state = readState(at: url), let value = state["generation"]?.int, value > generation {
            return state
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return readState(at: url)
}

func post(_ command: String, extra: [String: Any] = [:]) {
    var info: [String: Any] = ["command": command]
    for (key, value) in extra {
        info[key] = value
    }
    DistributedNotificationCenter.default().postNotificationName(
        notificationName,
        object: nil,
        userInfo: info,
        deliverImmediately: true
    )
}

func defaultsValue(_ suite: String, _ key: String) -> (Bool, String) {
    let result = run("/usr/bin/defaults", ["read", suite, key])
    return (result.0 == 0, result.1.trimmingCharacters(in: .whitespacesAndNewlines))
}

func assertFactory(_ state: JSONValue, label: String) {
    let blob = state["blob"]
    Check.expect(blob?["loginItemEnabled"]?.bool == false, "\(label) login off")
    Check.expect(blob?["showStatusItem"]?.bool == true, "\(label) status item shown")
    Check.expect(blob?["showDockIcon"]?.bool == false, "\(label) dock hidden")
    Check.expect(blob?["hotkey"]?["keyCode"]?.int == 49, "\(label) hotkey key code")
    Check.expect(blob?["hotkey"]?["carbonModifiers"]?.int == 2048, "\(label) hotkey modifiers")
    Check.expect(state["hotkeyDisplay"]?.string == "Option-Space", "\(label) hotkey reads Option-Space")
    Check.expect(blob?["showWaveform"]?.bool == true, "\(label) waveform on")
    Check.expect(blob?["showSpectrogram"]?.bool == true, "\(label) spectrogram on")
    Check.expect(blob?["waveformDual"]?.bool == true, "\(label) waveform dual on")
    Check.expect(blob?["spectrogramDual"]?.bool == false, "\(label) spectrogram dual off")
    Check.expect(blob?["waveformAmplitude"]?.string == "linear", "\(label) amplitude linear")
    Check.expect(blob?["waveformColor"]?["usesSystemBlue"]?.bool == true, "\(label) system blue")
    Check.expect(abs((blob?["splitFraction"]?.double ?? -1) - 0.5) < 0.0001, "\(label) split 50/50")
    let spectrogram = blob?["spectrogram"]
    Check.expect(spectrogram?["type"]?.string == "mel", "\(label) mel")
    Check.expect(spectrogram?["nFFT"]?.int == 2048, "\(label) n_fft 2048")
    Check.expect(spectrogram?["hop"]?.int == 512, "\(label) hop 512")
    Check.expect(spectrogram?["window"]?.string == "hann", "\(label) Hann")
    Check.expect(spectrogram?["nMels"]?.int == 128, "\(label) 128 mels")
    Check.expect(spectrogram?["fmin"]?.double == 0, "\(label) fmin 0")
    Check.expect(blob?["spectrogram"]?["fmax"] == nil, "\(label) fmax is Nyquist")
    Check.expect(spectrogram?["decibelsEnabled"]?.bool == true, "\(label) dB on")
    Check.expect(spectrogram?["dbFloor"]?.double == -80, "\(label) floor -80")
    Check.expect(spectrogram?["dbRange"]?.double == 80, "\(label) range 80")
}

func settingsWindowID() -> CGWindowID? {
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
    guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    for window in info {
        let owner = window[kCGWindowOwnerName as String] as? String ?? ""
        let title = window[kCGWindowName as String] as? String ?? ""
        if owner == "AudioPeek" && title == "AudioPeek Settings" {
            return window[kCGWindowNumber as String] as? CGWindowID
        }
    }
    return nil
}

func waitForSettingsWindow(timeout: TimeInterval = 5) -> CGWindowID? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let windowID = settingsWindowID() {
            return windowID
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return nil
}

func lsappinfoType() -> String {
    let result = run("/usr/bin/lsappinfo", ["info", bundleID])
    if result.0 != 0 {
        let byName = run("/usr/bin/lsappinfo", ["info", "AudioPeek"])
        return byName.1
    }
    return result.1
}

func launch(appPath: String, configPath: String) {
    let result = run("/usr/bin/open", [appPath, "--args", "--test-config", configPath])
    Check.expect(result.0 == 0, "open launched the app (\(result.1))")
}

struct Session {
    let suite: String
    let stateURL: URL
    let configURL: URL

    func cleanup() {
        _ = run("/usr/bin/defaults", ["delete", suite])
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: configURL)
    }
}

func makeSession(inject: String?) -> Session {
    let id = UUID().uuidString
    let suite = "audiopeek.phase1.\(id)"
    let stateURL = URL(fileURLWithPath: "/tmp/audiopeek-phase1-\(id).json")
    let configURL = URL(fileURLWithPath: "/tmp/audiopeek-phase1-\(id)-config.json")
    var config: [String: Any] = [
        "defaultsSuite": suite,
        "statePath": stateURL.path,
    ]
    if let inject {
        config["injectLoginFailure"] = inject
    } else {
        config["injectLoginFailure"] = NSNull()
    }
    let data = try! JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
    try! data.write(to: configURL)
    _ = run("/usr/bin/defaults", ["delete", suite])
    return Session(suite: suite, stateURL: stateURL, configURL: configURL)
}

func assertLoginFailure(_ state: JSONValue, code: Int, label: String) {
    Check.expect(state["loginItemEnabled"]?.bool == true, "\(label) toggle stays on")
    Check.expect(state["loginShowsRegistered"]?.bool == false, "\(label) does not show registered")
    Check.expect(state["loginOffersLoginItems"]?.bool == true, "\(label) offers Login Items")
    Check.expect(state["loginButtonTitle"]?.string == "Open Login Items", "\(label) button title")
    let message = state["loginMessage"]?.string ?? ""
    Check.expect(message.contains("Login Items"), "\(label) message mentions Login Items")
    Check.expect(!message.contains("Registered"), "\(label) message does not say Registered")
    Check.expect(state["lastLoginErrorCode"]?.int == code, "\(label) error code \(code), got \(state["lastLoginErrorCode"]?.int ?? -1)")
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
    let frames = 4410
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

func snapshot(stateURL: URL, generation: Int, path: String) -> JSONValue? {
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    post("snapshot", extra: ["path": path])
    return waitForState(at: stateURL, above: generation)
}

guard CommandLine.arguments.count > 1 else {
    fputs("usage: verify-phase1 AudioPeek.app\n", stderr)
    exit(2)
}

let appPath = CommandLine.arguments[1]
let app = URL(fileURLWithPath: appPath)
let info = app.appendingPathComponent("Contents/Info.plist")
stopRunningApps()

let identifier = run("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleIdentifier", info.path])
Check.expect(identifier.0 == 0 && identifier.1.trimmingCharacters(in: .whitespacesAndNewlines) == bundleID, "bundle id \(identifier.1)")
let name = run("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleName", info.path])
Check.expect(name.1.trimmingCharacters(in: .whitespacesAndNewlines) == "AudioPeek", "bundle name \(name.1)")
let uiElement = run("/usr/libexec/PlistBuddy", ["-c", "Print :LSUIElement", info.path])
Check.expect(uiElement.1.trimmingCharacters(in: .whitespacesAndNewlines) == "true", "LSUIElement \(uiElement.1)")

let described = run("/usr/bin/codesign", ["-dv", "--verbose=4", appPath])
print(described.1)
let signature = described.1.lowercased()
Check.expect(signature.contains("adhoc") || signature.contains("signature=adhoc"), "ad-hoc signature")
let verified = run("/usr/bin/codesign", ["--verify", "--verbose=2", appPath])
Check.expect(verified.0 == 0, "codesign verify \(verified.1)")

let fresh = makeSession(inject: nil)
defer { fresh.cleanup() }
launch(appPath: appPath, configPath: fresh.configURL.path)
guard var state = waitForState(at: fresh.stateURL, above: 0) else {
    Check.expect(false, "app wrote launch state")
    print("PHASE1 FAIL")
    exit(1)
}
let pid = state["pid"]?.int
Check.expect(pid != nil, "app pid")
Check.expect(runningApps().count == 1, "one running instance")
assertFactory(state, label: "fresh")
Check.expect(state["volumeKeyPresent"]?.bool == false, "fresh volume key absent in app")
let freshVolume = defaultsValue(fresh.suite, settingsVolumeKey)
Check.expect(freshVolume.0 == false, "fresh volume key absent in defaults")
let freshBlob = defaultsValue(fresh.suite, "settingsBlob")
Check.expect(freshBlob.0 == false, "fresh blob not written yet")
Check.expect(state["activationPolicy"]?.string == "accessory", "fresh activation accessory")
Check.expect(state["statusItemVisible"]?.bool == true, "fresh status item visible")
Check.expect(state["statusMenuTitles"]?.strings == ["AudioPeek Settings", "Quit"], "status menu \(state["statusMenuTitles"]?.strings ?? [])")
Check.expect(state["settingsWindowVisible"]?.bool == false, "first launch does not open settings")
let freshType = lsappinfoType()
print("lsappinfo fresh:\n\(freshType)")
Check.expect(freshType.contains("UIElement"), "fresh lsappinfo is a UI element")

let generationBeforeReset = state["generation"]?.int ?? 0
post("reset")
guard let resetState = waitForState(at: fresh.stateURL, above: generationBeforeReset) else {
    Check.expect(false, "reset state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
state = resetState
assertFactory(state, label: "reset on fresh")
Check.expect(state["volumeKeyPresent"]?.bool == false, "reset does not create the volume key")
Check.expect(defaultsValue(fresh.suite, settingsVolumeKey).0 == false, "defaults still has no volume key after reset")

let generationBeforeHide = state["generation"]?.int ?? 0
post("hideStatusItem")
guard let hidden = waitForState(at: fresh.stateURL, above: generationBeforeHide) else {
    Check.expect(false, "hide status item")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
state = hidden
Check.expect(state["statusItemVisible"]?.bool == false, "status item hidden")
Check.expect(state["blob"]?["showStatusItem"]?.bool == false, "status preference hidden")
Check.expect(state["blob"]?["showDockIcon"]?.bool == false, "hiding the status item leaves the dock off")

let generationBeforeReopen = state["generation"]?.int ?? 0
let reopen = run("/usr/bin/open", [appPath])
Check.expect(reopen.0 == 0, "second launch open")
guard let reopened = waitForState(at: fresh.stateURL, above: generationBeforeReopen) else {
    Check.expect(false, "second launch state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
state = reopened
Check.expect(state["pid"]?.int == pid, "second launch is the same process")
Check.expect(runningApps().count == 1, "still one instance after second launch")
Check.expect(state["settingsWindowVisible"]?.bool == true, "second launch opens settings")
Check.expect(state["statusItemVisible"]?.bool == false, "second launch leaves the status item hidden")
Check.expect(state["blob"]?["showDockIcon"]?.bool == false, "second launch does not change the dock preference")
Check.expect(state["blob"]?["showStatusItem"]?.bool == false, "second launch does not change the menu bar preference")
let windowID = waitForSettingsWindow()
Check.expect(windowID != nil, "Settings window is on screen")
let settingsPNG = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/phase1-settings.png").path
if let shot = snapshot(stateURL: fresh.stateURL, generation: state["generation"]?.int ?? 0, path: settingsPNG) {
    state = shot
}
Check.expect(FileManager.default.fileExists(atPath: settingsPNG), "settings window snapshot")

let openRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audiopeek-phase1-\(UUID().uuidString)", isDirectory: true)
try! FileManager.default.createDirectory(at: openRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: openRoot) }
let wav = openRoot.appendingPathComponent("tone.wav")
let other = openRoot.appendingPathComponent("other.wav")
writeWav(to: wav)
writeWav(to: other)

let generationBeforeOpen = state["generation"]?.int ?? 0
post("open", extra: ["paths": [wav.path]])
guard let opened = waitForState(at: fresh.stateURL, above: generationBeforeOpen) else {
    Check.expect(false, "one local wav state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
state = opened
Check.expect(state["slipVisible"]?.bool == true, "one local wav opens the panel")
Check.expect(state["slipFilename"]?.string == "tone.wav", "one local wav shows the filename")

let generationBeforePanelHide = state["generation"]?.int ?? 0
post("pressViewerHotkey")
guard let panelHidden = waitForState(at: fresh.stateURL, above: generationBeforePanelHide) else {
    Check.expect(false, "panel hide state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
state = panelHidden
Check.expect(state["slipVisible"]?.bool == false, "panel is closed before two URLs")

let generationBeforeTwo = state["generation"]?.int ?? 0
post("open", extra: ["paths": [wav.path, other.path]])
guard let two = waitForState(at: fresh.stateURL, above: generationBeforeTwo) else {
    Check.expect(false, "two URL state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
state = two
Check.expect(state["slipVisible"]?.bool == false, "two URLs leave the panel closed")

let generationBeforeDock = state["generation"]?.int ?? 0
post("setDockIcon", extra: ["dock": true])
guard let dockOn = waitForState(at: fresh.stateURL, above: generationBeforeDock) else {
    Check.expect(false, "dock on state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
state = dockOn
Check.expect(state["activationPolicy"]?.string == "regular", "dock toggle sets regular policy")
Check.expect(state["blob"]?["showDockIcon"]?.bool == true, "dock preference on")
let dockOnType = lsappinfoType()
print("lsappinfo dock on:\n\(dockOnType)")
Check.expect(dockOnType.contains("Foreground") || dockOnType.contains("Background"), "dock on is not a UI element: \(dockOnType)")

let generationBeforeDockOff = state["generation"]?.int ?? 0
post("setDockIcon", extra: ["dock": false])
guard let dockOff = waitForState(at: fresh.stateURL, above: generationBeforeDockOff) else {
    Check.expect(false, "dock off state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
state = dockOff
Check.expect(state["activationPolicy"]?.string == "accessory", "dock toggle restores accessory")
Check.expect(state["blob"]?["showDockIcon"]?.bool == false, "dock preference off")

let generationBeforeVolume = state["generation"]?.int ?? 0
post("setVolume", extra: ["volume": 0.25])
guard let volumeState = waitForState(at: fresh.stateURL, above: generationBeforeVolume) else {
    Check.expect(false, "volume state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
let generationBeforeFrame = volumeState["generation"]?.int ?? 0
post("setWindowFrame", extra: ["x": 10, "y": 20, "width": 860, "height": 500])
guard let frameState = waitForState(at: fresh.stateURL, above: generationBeforeFrame) else {
    Check.expect(false, "frame state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
let generationBeforeMutate = frameState["generation"]?.int ?? 0
post("mutateKnobs")
guard let mutated = waitForState(at: fresh.stateURL, above: generationBeforeMutate) else {
    Check.expect(false, "mutate state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
Check.expect(mutated["blob"]?["showWaveform"]?.bool == false, "mutate changes a knob")
Check.expect(mutated["hotkeyDisplay"]?.string == "Command-K", "mutate changes the hotkey")
let generationBeforeFinalReset = mutated["generation"]?.int ?? 0
post("reset")
guard let restored = waitForState(at: fresh.stateURL, above: generationBeforeFinalReset) else {
    Check.expect(false, "final reset state")
    print("PHASE1 FAIL")
    stopRunningApps()
    exit(1)
}
assertFactory(restored, label: "reset")
Check.expect(restored["volumeKeyPresent"]?.bool == true, "reset leaves the volume key in place")
Check.expect(abs((restored["storedVolume"]?.double ?? -1) - 0.25) < 0.0001, "reset leaves volume at 0.25")
let volumeRead = defaultsValue(fresh.suite, settingsVolumeKey)
Check.expect(volumeRead.0, "defaults volume key still exists")
if let number = Double(volumeRead.1) {
    Check.expect(abs(number - 0.25) < 0.0001, "defaults volume is 0.25, got \(volumeRead.1)")
} else {
    Check.expect(false, "defaults volume parses, got \(volumeRead.1)")
}
Check.expect(restored["blob"]?["windowFrame"]?["width"]?.double == 860, "reset keeps the window frame width")
Check.expect(restored["blob"]?["windowFrame"]?["height"]?.double == 500, "reset keeps the window frame height")
Check.expect(restored["blob"]?["windowFrame"]?["x"]?.double == 10, "reset keeps the window frame x")
Check.expect(restored["blob"]?["windowFrame"]?["y"]?.double == 20, "reset keeps the window frame y")

let quitGeneration = restored["generation"]?.int ?? 0
post("quit")
_ = waitForState(at: fresh.stateURL, above: quitGeneration, timeout: 3)
let quitDeadline = Date().addingTimeInterval(5)
while Date() < quitDeadline && !runningApps().isEmpty {
    Thread.sleep(forTimeInterval: 0.05)
}
Check.expect(runningApps().isEmpty, "app quit")

func runInjection(_ mode: String, code: Int, capture: Bool) {
    stopRunningApps()
    let session = makeSession(inject: mode)
    defer { session.cleanup() }
    launch(appPath: appPath, configPath: session.configURL.path)
    guard let launched = waitForState(at: session.stateURL, above: 0) else {
        Check.expect(false, "\(mode) launched")
        return
    }
    let generation = launched["generation"]?.int ?? 0
    post("openSettings")
    guard let opened = waitForState(at: session.stateURL, above: generation) else {
        Check.expect(false, "\(mode) settings opened")
        return
    }
    Check.expect(opened["settingsWindowVisible"]?.bool == true, "\(mode) settings visible")
    let beforeLogin = opened["generation"]?.int ?? 0
    post("setLoginEnabled", extra: ["enabled": true])
    guard let failed = waitForState(at: session.stateURL, above: beforeLogin) else {
        Check.expect(false, "\(mode) login state")
        return
    }
    assertLoginFailure(failed, code: code, label: mode)
    if capture {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/phase1-login-failure.png").path
        _ = snapshot(stateURL: session.stateURL, generation: failed["generation"]?.int ?? 0, path: path)
        Check.expect(FileManager.default.fileExists(atPath: path), "login failure snapshot")
    }
    post("quit")
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline && !runningApps().isEmpty {
        Thread.sleep(forTimeInterval: 0.05)
    }
}

runInjection("invalid-signature", code: 3, capture: true)
runInjection("other", code: 2, capture: false)
stopRunningApps()

if Check.failures.isEmpty {
    print("PHASE1 PASS")
    exit(0)
} else {
    print("PHASE1 FAIL")
    for failure in Check.failures {
        print(" - \(failure)")
    }
    exit(1)
}
