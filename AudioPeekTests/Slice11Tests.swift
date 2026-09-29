import AppKit
import AudioToolbox
import AVFoundation
import XCTest
@testable import AudioPeek

@MainActor
final class Slice11Tests: XCTestCase {
    func testMetadataStaysClearOfTheControls() {
        let view = SlipContentView(frame: NSRect(x: 0, y: 0, width: 860, height: 500))
        view.filenameLabel.stringValue = "tone.wav"
        view.metadataLabel.stringValue = "WAV · 44.1 kHz · 16 ch · showing 8 · 16 ch · showing 2 · 0:00 / 0:00"
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(view.metadataLabel.frame.maxX, view.volumeSlider.frame.minX + 0.5)
        XCTAssertLessThan(view.loopButton.frame.maxX, view.gearButton.frame.minX)
        XCTAssertEqual(view.filenameLabel.toolTip, "tone.wav")
        XCTAssertEqual(view.metadataLabel.toolTip, view.metadataLabel.stringValue)
        XCTAssertGreaterThan(view.filenameLabel.frame.width, 12)

        view.setFrameSize(NSSize(width: 420, height: 280))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(view.metadataLabel.frame.maxX, view.volumeSlider.frame.minX + 0.5)
        XCTAssertFalse(view.metadataLabel.frame.intersects(view.volumeSlider.frame))
        XCTAssertFalse(view.metadataLabel.frame.intersects(view.loopButton.frame))
        XCTAssertFalse(view.metadataLabel.frame.intersects(view.gearButton.frame))
        XCTAssertEqual(view.headerOrder, ["play", "filename", "metadata", "volume", "loop", "settings"])
    }

    func testScreenshotMetadataFitsWhileTheFilenameCanTruncate() throws {
        let filename = "Piano Lullabies - Piano Music for Sleeping and Relaxation.mp3"
        let metadata = "MP3 · 44.1 kHz · 2 ch · 0:00 / 84:22"
        let wavMetadata = "WAV · 44.1 kHz · 2 ch · 0:00 / 0:10"
        for (width, line) in [(512.0, metadata), (860.0, metadata), (1024.0, metadata), (860.0, wavMetadata)] {
            let view = SlipContentView(frame: NSRect(x: 0, y: 0, width: width, height: 80))
            view.filenameLabel.stringValue = filename
            view.metadataLabel.stringValue = line
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            let needed = try XCTUnwrap(view.metadataLabel.cell).cellSize(
                forBounds: NSRect(x: 0, y: 0, width: 10_000, height: 40)
            ).width
            XCTAssertGreaterThanOrEqual(
                view.metadataLabel.frame.width + 0.5,
                needed,
                "\(line) truncates at width \(width): field \(view.metadataLabel.frame.width) needed \(needed)"
            )
            XCTAssertLessThanOrEqual(view.metadataLabel.frame.maxX, view.volumeSlider.frame.minX - 7)
            XCTAssertFalse(view.metadataLabel.frame.intersects(view.volumeSlider.frame))
        }
        let wide = SlipContentView(frame: NSRect(x: 0, y: 0, width: 1024, height: 42))
        wide.filenameLabel.stringValue = filename
        wide.metadataLabel.stringValue = metadata
        wide.needsLayout = true
        wide.layoutSubtreeIfNeeded()
        try render(wide.metadataLabel, named: "header-metadata")
    }

    func testRevealUncoversABlockWithoutJumpingToTheEnd() {
        let pane = SlipPaneView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        let columns = (0..<40).map { _ in WaveformColumn(minimum: -0.2, maximum: 0.2) }
        pane.setWaveform(
            snapshot: WaveformSnapshot(
                passID: 1,
                lanes: [columns],
                columnCount: 200,
                filled: 40,
                running: true,
                paused: false,
                finished: false,
                peakPasses: 1,
                progress: 0.2,
                spectrogram: []
            ),
            amplitude: .linear,
            color: .systemBlue
        )
        XCTAssertEqual(pane.revealedColumnCount, 0)
        pane.advanceReveal()
        let first = pane.revealedColumnCount
        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThan(first, 40)
        for _ in 0..<40 {
            pane.advanceReveal()
        }
        XCTAssertEqual(pane.revealedColumnCount, 40)
        pane.setWaveform(
            snapshot: WaveformSnapshot(
                passID: 2,
                lanes: [[WaveformColumn(minimum: -0.1, maximum: 0.1)]],
                columnCount: 200,
                filled: 1,
                running: true,
                paused: false,
                finished: false,
                peakPasses: 1,
                progress: 0,
                spectrogram: []
            ),
            amplitude: .linear,
            color: .systemBlue
        )
        XCTAssertEqual(pane.revealedColumnCount, 0)
    }

    func testHeaderHitLeavesThePanesForScrubbing() {
        let view = SlipContentView(frame: NSRect(x: 0, y: 0, width: 860, height: 500))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.hitKind(at: NSPoint(x: 80, y: 10)), "header")
        XCTAssertEqual(view.hitKind(at: NSPoint(x: 80, y: 120)), "waveform")
    }

    func testSplitSnapsNearTheMiddle() {
        XCTAssertEqual(SplitSnap.value(0.49), 0.5)
        XCTAssertEqual(SplitSnap.value(0.51), 0.5)
        XCTAssertEqual(SplitSnap.value(0.2), 0.2)
    }

    func testMissingLoopKeyDecodesOff() throws {
        let data = try JSONEncoder().encode(SettingsBlob.factory)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "loopEnabled")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SettingsBlob.self, from: stripped)
        XCTAssertFalse(decoded.loopEnabled)
        XCTAssertFalse(SettingsBlob.factory.loopEnabled)
    }

    func testMissingColorMapDecodesAsMagma() throws {
        let data = try JSONEncoder().encode(SettingsBlob.factory)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var spectrogram = object["spectrogram"] as! [String: Any]
        spectrogram.removeValue(forKey: "colorMap")
        object["spectrogram"] = spectrogram
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SettingsBlob.self, from: stripped)
        XCTAssertEqual(decoded.spectrogram.colorMap, .magma)
    }

    func testLoopRestartsAtTheEndAndAPauseStaysPaused() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-loop-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 8_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        playback.loopIsOn = { true }
        playback.playbackAllowed = { true }
        XCTAssertNotNil(playback.open(url: url))
        playback.toggle()
        let started = Date()
        var advanced = false
        var looped = false
        while Date().timeIntervalSince(started) < 1.5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            playback.refreshPosition()
            if playback.position > 0.08 {
                advanced = true
            }
            if advanced, playback.isPlaying, playback.position < 0.04 {
                looped = true
                break
            }
        }
        XCTAssertTrue(looped, "loop did not restart near the start, \(playback.clockDescription)")
        playback.toggle()
        XCTAssertFalse(playback.isPlaying)
        let stayed = expectation(description: "stayed paused")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if playback.isPlaying == false {
                stayed.fulfill()
            }
        }
        wait(for: [stayed], timeout: 1.5)
        playback.stop()
    }

    func testLoopDoesNotRestartWhenTheGateDenies() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-loop-gate-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 8_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        playback.loopIsOn = { true }
        playback.playbackAllowed = { false }
        XCTAssertNotNil(playback.open(url: url))
        playback.toggle()
        let stopped = expectation(description: "stopped")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if playback.isPlaying == false {
                stopped.fulfill()
            }
        }
        wait(for: [stopped], timeout: 2)
        playback.stop()
    }

    func testPlayheadReachesTheEndAndALateSeekStillPlays() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-end-\(UUID().uuidString).wav")
        let frames = 44_100 * 3
        try writeWav(to: url, frames: frames)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        playback.setGain(0)
        let info = try XCTUnwrap(playback.open(url: url))
        XCTAssertEqual(info.duration, 3, accuracy: 0.02)
        playback.toggle()
        var sawLate = false
        let started = Date()
        while Date().timeIntervalSince(started) < 5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            playback.refreshPosition()
            if playback.isPlaying, playback.position > 2.4 {
                sawLate = true
            }
            if !playback.isPlaying, Date().timeIntervalSince(started) > 0.4 { break }
        }
        XCTAssertTrue(sawLate, "playback stopped before the last half second: \(playback.clockDescription)")
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, info.duration, accuracy: 0.05)
        playback.toggle()
        let seekStart = Date()
        while playback.isPlaying, playback.position < 0.4, Date().timeIntervalSince(seekStart) < 2 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            playback.refreshPosition()
        }
        playback.seek(toFraction: 0.85)
        XCTAssertTrue(playback.isPlaying, "scrubbing into the last part stopped playback: \(playback.clockDescription)")
        XCTAssertGreaterThan(playback.position, 2.4)
        while playback.isPlaying, Date().timeIntervalSince(seekStart) < 4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            playback.refreshPosition()
        }
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, info.duration, accuracy: 0.05)
        playback.stop()

        let real = URL(fileURLWithPath: "/Users/chris/Music/dad_mode_intro_test.wav")
        guard FileManager.default.fileExists(atPath: real.path) else { return }
        let file = try AVAudioFile(forReading: real)
        var audioFile: ExtAudioFileRef?
        XCTAssertEqual(ExtAudioFileOpenURL(real as CFURL, &audioFile), noErr)
        defer { if let audioFile { ExtAudioFileDispose(audioFile) } }
        var extFrames = Int64(0)
        var size = UInt32(MemoryLayout<Int64>.size)
        if let audioFile {
            ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileLengthFrames, &size, &extFrames)
        }
        print("REAL av=\(file.length) ext=\(extFrames) rate=\(file.processingFormat.sampleRate)")
        XCTAssertEqual(extFrames, file.length)
        let realPlayback = PlaybackController()
        realPlayback.setGain(0)
        XCTAssertNotNil(realPlayback.open(url: real))
        let realStart = Date()
        realPlayback.toggle()
        var furthest = 0.0
        while Date().timeIntervalSince(realStart) < 13 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            realPlayback.refreshPosition()
            furthest = max(furthest, realPlayback.position)
            if !realPlayback.isPlaying, Date().timeIntervalSince(realStart) > 0.5 { break }
        }
        XCTAssertEqual(realPlayback.position, realPlayback.duration, accuracy: 0.05, realPlayback.clockDescription)
        XCTAssertGreaterThan(furthest, realPlayback.duration * 0.98)
        realPlayback.stop()
    }

    func testPlayheadDoesNotJumpAfterASeekAndAPause() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-clock-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 44_100 * 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        playback.setGain(0)
        let info = try XCTUnwrap(playback.open(url: url))
        playback.toggle()
        let started = Date()
        while playback.position < 0.4, Date().timeIntervalSince(started) < 2 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            playback.refreshPosition()
        }
        playback.seek(toFraction: 0.5)
        let seekPoint = playback.position
        XCTAssertEqual(seekPoint, info.duration * 0.5, accuracy: 0.05)
        var previous = seekPoint
        let afterSeek = Date()
        while Date().timeIntervalSince(afterSeek) < 0.8 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            playback.refreshPosition()
            XCTAssertGreaterThan(playback.position, seekPoint - 0.05, playback.clockDescription)
            XCTAssertLessThan(playback.position, seekPoint + 1.3, playback.clockDescription)
            XCTAssertGreaterThan(playback.position, previous - 0.08, playback.clockDescription)
            previous = playback.position
        }
        let beforePause = playback.position
        playback.toggle()
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, beforePause, accuracy: 0.15, playback.clockDescription)
        playback.toggle()
        XCTAssertTrue(playback.isPlaying)
        let resumed = playback.position
        let resumedAt = Date()
        while Date().timeIntervalSince(resumedAt) < 0.45 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            playback.refreshPosition()
            XCTAssertGreaterThan(playback.position, resumed - 0.08, playback.clockDescription)
            XCTAssertLessThan(playback.position, resumed + 0.9, playback.clockDescription)
        }
        playback.stop()
    }

    func testPauseStopsTheEngineAndPlayContinuesFromThere() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-engine-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 44_100 * 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        playback.setGain(0)
        XCTAssertNotNil(playback.open(url: url))
        playback.toggle()
        let started = Date()
        while playback.position < 0.35, Date().timeIntervalSince(started) < 2 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            playback.refreshPosition()
        }
        XCTAssertTrue(playback.engine.isRunning)
        let pausedAt = playback.position
        XCTAssertGreaterThan(pausedAt, 0.2, playback.clockDescription)
        playback.toggle()
        XCTAssertFalse(playback.isPlaying)
        XCTAssertFalse(playback.engine.isRunning)
        XCTAssertEqual(playback.position, pausedAt, accuracy: 0.15, playback.clockDescription)
        playback.toggle()
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.engine.isRunning)
        XCTAssertEqual(playback.position, pausedAt, accuracy: 0.15, playback.clockDescription)
        let resumed = playback.position
        let resumedAt = Date()
        while Date().timeIntervalSince(resumedAt) < 0.35 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            playback.refreshPosition()
        }
        XCTAssertGreaterThan(playback.position, resumed + 0.05, playback.clockDescription)
        playback.stop()
    }

    func testScrubStaysSilentUntilTheMouseIsReleased() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-scrub-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 44_100 * 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let playback = PlaybackController()
        playback.setGain(0)
        let info = try XCTUnwrap(playback.open(url: url))
        playback.toggle()
        let started = Date()
        while playback.position < 1.0, Date().timeIntervalSince(started) < 3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            playback.refreshPosition()
        }
        let beforeScrub = playback.renderedSampleTime() ?? 0
        XCTAssertGreaterThan(beforeScrub, 20_000)
        playback.beginScrub(toFraction: 0.3)
        XCTAssertFalse(playback.isPlaying)
        playback.moveScrub(toFraction: 0.8)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, info.duration * 0.8, accuracy: 0.02)
        playback.endScrub(toFraction: 0.8)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.position, info.duration * 0.8, accuracy: 0.15)
        let afterRelease = Date()
        var restarted = false
        while Date().timeIntervalSince(afterRelease) < 0.6 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            playback.refreshPosition()
            if let sample = playback.renderedSampleTime(), sample < beforeScrub / 2 {
                restarted = true
                break
            }
        }
        XCTAssertTrue(restarted, "scrub resumed the paused audio instead of the new point, \(playback.clockDescription)")
        XCTAssertEqual(playback.position, info.duration * 0.8, accuracy: 0.4)
        playback.toggle()
        XCTAssertFalse(playback.isPlaying)
        playback.beginScrub(toFraction: 0.25)
        playback.moveScrub(toFraction: 0.4)
        playback.endScrub(toFraction: 0.4)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.position, info.duration * 0.4, accuracy: 0.02)
        playback.stop()
    }

    func testReadFileSucceedsOnABackgroundQueue() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-read-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 44_100)
        defer { try? FileManager.default.removeItem(at: url) }
        let done = expectation(description: "read")
        let box = ReadResult()
        DispatchQueue.global(qos: .userInitiated).async {
            box.offMain = !Thread.isMainThread
            box.info = PlaybackController.readFile(at: url)?.info
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(box.offMain)
        let info = try XCTUnwrap(box.info)
        XCTAssertEqual(info.sampleRate, 44_100, accuracy: 0.1)
        XCTAssertEqual(info.channels, 1)
        XCTAssertEqual(info.duration, 1, accuracy: 0.02)
    }

    func testStaleGenerationDoesNotConnectOrStartTheOverview() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-stale-\(UUID().uuidString).wav")
        try writeWav(to: url, frames: 8_000)
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try XCTUnwrap(PlaybackController.readFile(at: url))
        let other = URL(fileURLWithPath: "/tmp/audiopeek-other.wav")
        XCTAssertFalse(SlipPanelController.shouldConnectOpen(
            generation: 1,
            currentGeneration: 2,
            url: url,
            currentURL: url,
            panelUp: true
        ))
        XCTAssertFalse(SlipPanelController.shouldConnectOpen(
            generation: 2,
            currentGeneration: 2,
            url: other,
            currentURL: url,
            panelUp: true
        ))
        XCTAssertFalse(SlipPanelController.shouldConnectOpen(
            generation: 2,
            currentGeneration: 2,
            url: url,
            currentURL: url,
            panelUp: false
        ))
        let suite = "audiopeek.s5-stale-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let slip = SlipPanelController(
            store: SettingsStore(defaults: defaults),
            finder: IdleFinder(),
            hotkey: HotkeyCenter(),
            onOpenSettings: {}
        )
        slip.stageOpenForTest(url: url, generation: 2, panelUp: true)
        var activity = 0
        slip.onActivity = { activity += 1 }
        slip.deliverOpenForTest(url: url, generation: 1, read: read)
        let pumped = expectation(description: "stale open dropped")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pumped.fulfill()
        }
        wait(for: [pumped], timeout: 1)
        XCTAssertEqual(activity, 0)
        XCTAssertEqual(slip.durationSeconds, 0)
        XCTAssertFalse(slip.playbackRunning)
        XCTAssertFalse(slip.overviewRunning)
        XCTAssertEqual(slip.overviewFilled, 0)
    }

    func testNilInfoLeavesTheOverviewAlone() {
        let suite = "audiopeek.s5-nil-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let slip = SlipPanelController(
            store: SettingsStore(defaults: defaults),
            finder: IdleFinder(),
            hotkey: HotkeyCenter(),
            onOpenSettings: {}
        )
        var activity = 0
        slip.onActivity = { activity += 1 }
        slip.startOverviewNow()
        let pumped = expectation(description: "overview stayed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pumped.fulfill()
        }
        wait(for: [pumped], timeout: 1)
        XCTAssertEqual(activity, 0)
        XCTAssertFalse(slip.overviewRunning)
        XCTAssertEqual(slip.overviewFilled, 0)
        XCTAssertEqual(slip.durationSeconds, 0)
    }

    private func render(_ field: NSTextField, named name: String) throws {
        let width = max(field.frame.width, 1)
        let height: CGFloat = 24
        let scale: CGFloat = 2
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale),
            pixelsHigh: Int(height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let cell = NSTextFieldCell(textCell: field.stringValue)
        cell.font = field.font
        cell.alignment = field.alignment
        cell.lineBreakMode = .byTruncatingTail
        cell.drawsBackground = false
        cell.isBordered = false
        cell.draw(withFrame: NSRect(x: 0, y: 0, width: width, height: height), in: field)
        NSGraphicsContext.restoreGraphicsState()
        let url = URL(fileURLWithPath: "/Users/chris/Desktop/Code/audiopeek/build/\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    private func writeWav(to url: URL, frames: Int) throws {
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
    }
}

private final class ReadResult {
    var info: OpenedAudio?
    var offMain = false
}

private final class IdleFinder: FinderSelectionSource {
    func requestSelection(_ completion: @escaping (FinderRead) -> Void) {}
}
