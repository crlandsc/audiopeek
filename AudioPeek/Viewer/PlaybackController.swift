import AVFoundation
import Foundation

struct OpenedAudio: Equatable {
    var sampleRate: Double
    var channels: Int
    var duration: TimeInterval
}

@MainActor
final class PlaybackController {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var origin: TimeInterval = 0
    private var userPaused = false
    private var playGeneration = 0
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var info: OpenedAudio?
    var onChange: () -> Void = {}

    init() {
        engine.attach(node)
    }

    func open(url: URL) -> OpenedAudio? {
        stop()
        do {
            let file = try AVAudioFile(forReading: url)
            let rate = file.processingFormat.sampleRate
            guard rate > 0, file.length > 0 else { return nil }
            self.file = file
            duration = Double(file.length) / rate
            position = 0
            origin = 0
            info = OpenedAudio(
                sampleRate: rate,
                channels: Int(file.processingFormat.channelCount),
                duration: duration
            )
            connect(file)
            return info
        } catch {
            file = nil
            info = nil
            duration = 0
            return nil
        }
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
        let clamped = min(max(fraction, 0), 1)
        position = clamped * duration
        origin = position
        if isPlaying {
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
        isPlaying = false
        userPaused = false
        file = nil
        info = nil
        position = 0
        origin = 0
        duration = 0
    }

    func refreshPosition() {
        guard isPlaying, let file, let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return }
        let rate = file.processingFormat.sampleRate
        guard rate > 0 else { return }
        let played = Double(playerTime.sampleTime) / rate
        position = min(duration, max(0, origin + played))
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
        if node.isPlaying {
            node.stop()
        }
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
                    self.finished()
                }
            }
            node.play()
            isPlaying = true
            onChange()
        } catch {
            isPlaying = false
            onChange()
        }
    }

    private func pauseEngine() {
        refreshPosition()
        if node.isPlaying {
            node.pause()
        }
        isPlaying = false
        onChange()
    }

    private func finished() {
        guard isPlaying else { return }
        position = duration
        isPlaying = false
        userPaused = true
        if node.isPlaying {
            node.stop()
        }
        onChange()
    }
}
