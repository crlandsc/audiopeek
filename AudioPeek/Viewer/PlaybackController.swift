import AVFoundation
import Foundation

struct OpenedAudio: Equatable {
    var sampleRate: Double
    var channels: Int
    var duration: TimeInterval
}

struct ReadAudio {
    var file: AVAudioFile
    var info: OpenedAudio
}

@MainActor
final class PlaybackController {
    let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var origin: TimeInterval = 0
    private var userPaused = false
    private var playGeneration = 0
    private var renderQueued = false
    private var scrubbing = false
    private var playAfterScrub = false
    private var clockAnchorSample: AVAudioFramePosition?
    private var clockAnchorUptime: TimeInterval?
    private(set) var isPlaying = false
    private(set) var playStartCount = 0
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var info: OpenedAudio?
    var onChange: () -> Void = {}
    var loopIsOn: () -> Bool = { false }
    var playbackAllowed: () -> Bool = { true }

    init() {
        engine.attach(node)
    }

    nonisolated static func readFile(at url: URL) -> ReadAudio? {
        do {
            let file = try AVAudioFile(forReading: url)
            let rate = file.processingFormat.sampleRate
            guard rate > 0, file.length > 0 else { return nil }
            let duration = Double(file.length) / rate
            return ReadAudio(
                file: file,
                info: OpenedAudio(
                    sampleRate: rate,
                    channels: Int(file.processingFormat.channelCount),
                    duration: duration
                )
            )
        } catch {
            return nil
        }
    }

    func open(url: URL) -> OpenedAudio? {
        stop()
        guard let read = Self.readFile(at: url) else { return nil }
        install(read)
        return info
    }

    func install(_ read: ReadAudio) {
        stop()
        file = read.file
        duration = read.info.duration
        position = 0
        origin = 0
        info = read.info
        connect(read.file)
    }

    func setGain(_ value: Double) {
        let gain = Float(min(max(value, 0), 1))
        engine.mainMixerNode.outputVolume = gain
    }

    func toggle() {
        if isPlaying {
            userPaused = true
            pauseEngine()
            return
        }
        if position >= duration - 0.01 {
            position = 0
            origin = 0
        }
        userPaused = false
        playFromCurrent()
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        position = clamped(fraction) * duration
        origin = position
        if isPlaying {
            playFromCurrent()
        } else {
            onChange()
        }
    }

    func beginScrub(toFraction fraction: Double) {
        guard duration > 0 else { return }
        playAfterScrub = isPlaying
        scrubbing = true
        if isPlaying {
            userPaused = true
            pauseEngine()
        }
        placeScrub(fraction)
    }

    func moveScrub(toFraction fraction: Double) {
        guard scrubbing else { return }
        placeScrub(fraction)
    }

    func endScrub(toFraction fraction: Double) {
        guard duration > 0 else { return }
        placeScrub(fraction)
        let resume = playAfterScrub
        scrubbing = false
        playAfterScrub = false
        if resume {
            userPaused = false
            playFromCurrent()
        } else {
            onChange()
        }
    }

    func applyGate(allows: Bool, pauseIfPlaying: Bool = true) {
        if !allows {
            if pauseIfPlaying, isPlaying {
                pauseEngine()
            }
            return
        }
        guard !userPaused, file != nil else { return }
        if !isPlaying {
            playFromCurrent()
        }
    }

    func stop() {
        if node.isPlaying {
            node.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
        playGeneration += 1
        renderQueued = false
        scrubbing = false
        playAfterScrub = false
        clearClockAnchor()
        isPlaying = false
        userPaused = false
        file = nil
        info = nil
        position = 0
        origin = 0
        duration = 0
    }

    func renderedSampleTime() -> Int64? {
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return nil }
        return playerTime.sampleTime
    }

    var clockDescription: String {
        guard let file else { return "no-file pos=\(position) dur=\(duration) playing=\(isPlaying)" }
        let fileRate = file.processingFormat.sampleRate
        guard let nodeTime = node.lastRenderTime, let playerTime = node.playerTime(forNodeTime: nodeTime) else {
            return "pos=\(position) dur=\(duration) playing=\(isPlaying) fileRate=\(fileRate) nodePlaying=\(node.isPlaying) no-player-time"
        }
        return "pos=\(position) dur=\(duration) playing=\(isPlaying) sampleTime=\(playerTime.sampleTime) playerRate=\(playerTime.sampleRate) fileRate=\(fileRate) nodePlaying=\(node.isPlaying)"
    }

    func refreshPosition() {
        guard isPlaying, !scrubbing, let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return }
        let sample = playerTime.sampleTime
        let rate = playerTime.sampleRate
        let now = ProcessInfo.processInfo.systemUptime
        if let anchor = clockAnchorSample, let anchorTime = clockAnchorUptime {
            let elapsed = Double(sample - anchor) / rate
            let wall = now - anchorTime
            if sample < anchor || abs(elapsed - wall) > 0.35 {
                clockAnchorSample = sample
                clockAnchorUptime = now
            } else {
                position = min(duration, max(0, origin + elapsed))
            }
        } else {
            clockAnchorSample = sample
            clockAnchorUptime = now
        }
        guard renderQueued, position >= duration - 0.01 else { return }
        renderQueued = false
        if loopIsOn(), !userPaused, playbackAllowed() {
            position = 0
            origin = 0
            playFromCurrent()
            return
        }
        position = duration
        isPlaying = false
        userPaused = true
        if node.isPlaying {
            node.stop()
        }
        clearClockAnchor()
        onChange()
    }

    private func connect(_ file: AVAudioFile) {
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
    }

    private func playFromCurrent() {
        guard let file else { return }
        let rate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, position) * rate)
        let remaining = file.length - startFrame
        guard remaining > 0 else {
            position = duration
            isPlaying = false
            onChange()
            return
        }
        // pause() keeps the old segment queued. Stop clears it so play starts at this position.
        node.stop()
        renderQueued = false
        clearClockAnchor()
        origin = Double(startFrame) / rate
        playGeneration += 1
        let generation = playGeneration
        do {
            if !engine.isRunning {
                try engine.start()
            }
            node.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.playGeneration == generation else { return }
                    self.renderQueued = true
                    self.refreshPosition()
                    self.watchRenderTail()
                }
            }
            node.play()
            playStartCount += 1
            isPlaying = true
            onChange()
        } catch {
            isPlaying = false
            onChange()
        }
    }

    private func watchRenderTail() {
        guard renderQueued, isPlaying else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.renderQueued, self.isPlaying else { return }
            self.refreshPosition()
            self.watchRenderTail()
        }
    }

    private func placeScrub(_ fraction: Double) {
        guard duration > 0 else { return }
        position = clamped(fraction) * duration
        origin = position
        onChange()
    }

    private func clamped(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }

    private func clearClockAnchor() {
        clockAnchorSample = nil
        clockAnchorUptime = nil
    }

    private func pauseEngine() {
        renderQueued = false
        refreshPosition()
        playGeneration += 1
        if node.isPlaying {
            node.pause()
        }
        isPlaying = false
        if engine.isRunning {
            engine.stop()
        }
        onChange()
    }
}
