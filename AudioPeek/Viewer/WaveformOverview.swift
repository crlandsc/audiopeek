import AudioToolbox
import Foundation

struct WaveformColumn: Equatable, Sendable {
    var minimum: Float
    var maximum: Float
}

struct WaveformSnapshot: Equatable, Sendable {
    var passID: Int
    var lanes: [[WaveformColumn]]
    var columnCount: Int
    var filled: Int
    var running: Bool
    var paused: Bool
    var finished: Bool
    var peakPasses: Int
    var progress: Double
    var spectrogram: [[[Float]]]

    static let empty = WaveformSnapshot(
        passID: 0,
        lanes: [],
        columnCount: 0,
        filled: 0,
        running: false,
        paused: false,
        finished: false,
        peakPasses: 0,
        progress: 0,
        spectrogram: []
    )
}

enum WaveformColumns {
    static let laneCap = 8

    static func laneCount(channels: Int, dual: Bool) -> Int {
        guard channels > 0 else { return 1 }
        if dual { return min(channels, laneCap) }
        return 1
    }

    static func showing(channels: Int, dual: Bool) -> Int? {
        let lanes = laneCount(channels: channels, dual: dual)
        guard dual, channels > lanes else { return nil }
        return lanes
    }

    static func spectrogramShowing(channels: Int, dual: Bool) -> Int? {
        guard dual, channels > 2 else { return nil }
        return 2
    }

    static func decibelUnit(_ amplitude: Float) -> Float {
        let peak = abs(amplitude)
        if peak <= 1e-10 { return 0 }
        let db = 20 * log10(Double(peak))
        let clamped = min(0, max(-80, db))
        return Float((clamped + 80) / 80)
    }
}

struct WaveformAccumulator {
    let channels: Int
    let lanes: Int
    let dual: Bool
    let totalFrames: Int
    let columnCount: Int
    private(set) var framesSeen = 0
    private var minimums: [Float]
    private var maximums: [Float]
    private var seen: [Bool]

    init(channels: Int, totalFrames: Int, columnCount: Int, dual: Bool) {
        self.channels = max(channels, 1)
        self.dual = dual
        self.totalFrames = max(totalFrames, 1)
        self.columnCount = max(columnCount, 1)
        self.lanes = WaveformColumns.laneCount(channels: channels, dual: dual)
        let count = self.lanes * self.columnCount
        minimums = Array(repeating: 0, count: count)
        maximums = Array(repeating: 0, count: count)
        seen = Array(repeating: false, count: count)
    }

    var completedColumns: Int {
        if framesSeen >= totalFrames { return columnCount }
        var count = 0
        while count < columnCount {
            let end = (count + 1) * totalFrames / columnCount
            if end > framesSeen { break }
            count += 1
        }
        return count
    }

    var progress: Double {
        guard totalFrames > 0 else { return 0 }
        return min(1, Double(framesSeen) / Double(totalFrames))
    }

    mutating func skip(frames: Int) {
        let available = min(frames, max(0, totalFrames - framesSeen))
        framesSeen += available
    }

    mutating func ingest(base: UnsafePointer<Float>, frames: Int) {
        let available = min(frames, max(0, totalFrames - framesSeen))
        guard available > 0 else { return }
        let usedLanes = lanes
        for frame in 0..<available {
            let absolute = framesSeen + frame
            let column = min(columnCount - 1, absolute * columnCount / totalFrames)
            if dual {
                for lane in 0..<usedLanes {
                    include(lane: lane, column: column, value: base[frame * channels + lane])
                }
            } else {
                var sum: Float = 0
                let row = frame * channels
                for channel in 0..<channels {
                    sum += base[row + channel]
                }
                include(lane: 0, column: column, value: sum / Float(channels))
            }
        }
        framesSeen += available
    }

    func columns(through filled: Int) -> [[WaveformColumn]] {
        let count = min(max(filled, 0), columnCount)
        return (0..<lanes).map { lane in
            (0..<count).map { column in
                let slot = lane * columnCount + column
                return WaveformColumn(minimum: minimums[slot], maximum: maximums[slot])
            }
        }
    }

    func column(lane: Int, column: Int) -> WaveformColumn {
        let slot = lane * columnCount + column
        return WaveformColumn(minimum: minimums[slot], maximum: maximums[slot])
    }

    private mutating func include(lane: Int, column: Int, value: Float) {
        let slot = lane * columnCount + column
        if seen[slot] {
            minimums[slot] = min(minimums[slot], value)
            maximums[slot] = max(maximums[slot], value)
        } else {
            seen[slot] = true
            minimums[slot] = value
            maximums[slot] = value
        }
    }
}

enum WaveformReadPoint {
    case beforeOpen
    case afterOpen
    case betweenChunks
}

enum WaveformReadStop: Equatable {
    case finished
    case cancelled
    case failed
}

struct WaveformReadResult {
    var stop: WaveformReadStop
    var chunks: Int
    var opened: Bool
    var accumulator: WaveformAccumulator?
}

enum WaveformReader {
    static func read(
        url: URL,
        columnCount: Int,
        dual: Bool,
        chunkFrames: Int,
        proceed: (WaveformReadPoint) -> Bool,
        onChunk: (WaveformAccumulator) -> Void,
        onSamples: ((UnsafePointer<Float>, Int, Int, Double, Int) -> Void)? = nil,
        computeWaveform: Bool = true
    ) -> WaveformReadResult {
        if !proceed(.beforeOpen) {
            return WaveformReadResult(stop: .cancelled, chunks: 0, opened: false, accumulator: nil)
        }
        var audioFile: ExtAudioFileRef?
        let openStatus = ExtAudioFileOpenURL(url as CFURL, &audioFile)
        guard openStatus == noErr, let audioFile else {
            return WaveformReadResult(stop: .failed, chunks: 0, opened: false, accumulator: nil)
        }
        defer { ExtAudioFileDispose(audioFile) }
        if !proceed(.afterOpen) {
            return WaveformReadResult(stop: .cancelled, chunks: 0, opened: true, accumulator: nil)
        }
        guard let description = clientFormat(of: audioFile) else {
            return WaveformReadResult(stop: .failed, chunks: 0, opened: true, accumulator: nil)
        }
        var total = Int64(0)
        var totalSize = UInt32(MemoryLayout<Int64>.size)
        let lengthStatus = ExtAudioFileGetProperty(
            audioFile,
            kExtAudioFileProperty_FileLengthFrames,
            &totalSize,
            &total
        )
        guard lengthStatus == noErr, total > 0 else {
            return WaveformReadResult(stop: .failed, chunks: 0, opened: true, accumulator: nil)
        }
        let channels = Int(description.channelCount)
        var accumulator = WaveformAccumulator(
            channels: channels,
            totalFrames: Int(total),
            columnCount: columnCount,
            dual: dual
        )
        let framesPerChunk = UInt32(max(chunkFrames, 1))
        let sampleCapacity = Int(framesPerChunk) * channels
        let data = UnsafeMutablePointer<Float>.allocate(capacity: sampleCapacity)
        defer { data.deallocate() }
        var chunks = 0
        while accumulator.framesSeen < accumulator.totalFrames {
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(channels),
                    mDataByteSize: UInt32(sampleCapacity * MemoryLayout<Float>.size),
                    mData: data
                )
            )
            var frames = framesPerChunk
            let status = ExtAudioFileRead(audioFile, &frames, &list)
            if status != noErr {
                return WaveformReadResult(stop: .failed, chunks: chunks, opened: true, accumulator: accumulator)
            }
            if frames == 0 { break }
            onSamples?(data, Int(frames), channels, description.sampleRate, Int(total))
            if computeWaveform {
                accumulator.ingest(base: data, frames: Int(frames))
            } else {
                accumulator.skip(frames: Int(frames))
            }
            chunks += 1
            onChunk(accumulator)
            if accumulator.framesSeen >= accumulator.totalFrames { break }
            if !proceed(.betweenChunks) {
                return WaveformReadResult(stop: .cancelled, chunks: chunks, opened: true, accumulator: accumulator)
            }
        }
        return WaveformReadResult(stop: .finished, chunks: chunks, opened: true, accumulator: accumulator)
    }

    private static func clientFormat(of audioFile: ExtAudioFileRef) -> (sampleRate: Double, channelCount: UInt32)? {
        var fileFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard ExtAudioFileGetProperty(audioFile, kExtAudioFileProperty_FileDataFormat, &size, &fileFormat) == noErr else {
            return nil
        }
        let channels = fileFormat.mChannelsPerFrame
        guard channels > 0, fileFormat.mSampleRate > 0 else { return nil }
        var client = AudioStreamBasicDescription(
            mSampleRate: fileFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: channels * 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: channels * 4,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, size, &client) == noErr else {
            return nil
        }
        return (fileFormat.mSampleRate, channels)
    }
}

final class WaveformOverview: @unchecked Sendable {
    var onSnapshot: (WaveformSnapshot) -> Void = { _ in }
    private let queue = DispatchQueue(label: "com.landschoot.audiopeek.overview")
    private let lock = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private var generation = 0
    private var workAllowed = true
    private var stallBetweenChunks = false
    private var pendingSteps = 0
    private var inFlight = 0
    private var peakPasses = 0
    private var snapshot = WaveformSnapshot.empty

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.running && !snapshot.finished
    }

    func setStallBetweenChunks(_ enabled: Bool) {
        lock.lock()
        stallBetweenChunks = enabled
        lock.unlock()
        wake.signal()
    }

    func setWorkAllowed(_ allowed: Bool) {
        lock.lock()
        workAllowed = allowed
        lock.unlock()
        wake.signal()
    }

    func step() {
        lock.lock()
        pendingSteps += 1
        lock.unlock()
        wake.signal()
    }

    func cancel() {
        let published: WaveformSnapshot
        lock.lock()
        generation += 1
        let peak = peakPasses
        snapshot = .empty
        snapshot.peakPasses = peak
        published = snapshot
        lock.unlock()
        wake.signal()
        DispatchQueue.main.async { [weak self] in
            self?.onSnapshot(published)
        }
    }

    func start(url: URL, columnCount: Int, waveformDual: Bool, computeWaveform: Bool, spectrogram: SpectrogramJob?) {
        let token: Int
        let published: WaveformSnapshot
        lock.lock()
        generation += 1
        token = generation
        snapshot = WaveformSnapshot(
            passID: token,
            lanes: [],
            columnCount: max(columnCount, 1),
            filled: 0,
            running: true,
            paused: false,
            finished: false,
            peakPasses: peakPasses,
            progress: 0,
            spectrogram: []
        )
        published = snapshot
        lock.unlock()
        wake.signal()
        deliver(published, token: token)
        queue.async { [weak self] in
            self?.run(
                token: token,
                url: url,
                columnCount: max(columnCount, 1),
                waveformDual: waveformDual,
                computeWaveform: computeWaveform,
                spectrogram: spectrogram
            )
        }
    }

    private final class SpectrogramBox {
        var engine: SpectrogramAccumulator?
    }

    private func run(
        token: Int,
        url: URL,
        columnCount: Int,
        waveformDual: Bool,
        computeWaveform: Bool,
        spectrogram: SpectrogramJob?
    ) {
        enterPass()
        defer { leavePass() }
        let box = SpectrogramBox()
        let result = WaveformReader.read(
            url: url,
            columnCount: columnCount,
            dual: waveformDual,
            chunkFrames: 8192,
            proceed: { [weak self] point in
                guard let self else { return false }
                switch point {
                case .beforeOpen, .betweenChunks:
                    return self.waitToContinue(token)
                case .afterOpen:
                    return self.isCurrent(token)
                }
            },
            onChunk: { [weak self] accumulator in
                self?.publish(
                    accumulator,
                    spectrogram: box.engine,
                    token: token,
                    finished: false,
                    includeWaveform: computeWaveform
                )
            },
            onSamples: { base, frames, channels, sampleRate, totalFrames in
                if box.engine == nil, let spectrogram {
                    box.engine = SpectrogramAccumulator(
                        job: spectrogram,
                        sampleRate: sampleRate,
                        channels: channels,
                        totalFrames: totalFrames,
                        columnCount: columnCount
                    )
                }
                box.engine?.ingest(base: base, frames: frames, channels: channels)
            },
            computeWaveform: computeWaveform
        )
        guard isCurrent(token) else { return }
        if result.stop == .finished {
            box.engine?.finish()
        }
        switch result.stop {
        case .finished:
            publish(result.accumulator, spectrogram: box.engine, token: token, finished: true, includeWaveform: computeWaveform)
        case .failed:
            publish(nil, spectrogram: box.engine, token: token, finished: true, includeWaveform: computeWaveform)
        case .cancelled:
            break
        }
    }

    private func waitToContinue(_ token: Int) -> Bool {
        while true {
            lock.lock()
            if token != generation {
                lock.unlock()
                return false
            }
            let allowed = workAllowed
            let stall = stallBetweenChunks
            let ready = pendingSteps > 0
            if allowed && (!stall || ready) {
                if stall { pendingSteps -= 1 }
                let wasPaused = snapshot.paused
                snapshot.paused = false
                let copy = snapshot
                lock.unlock()
                if wasPaused { deliver(copy, token: token) }
                return true
            }
            let wasPaused = snapshot.paused
            if !allowed { snapshot.paused = true }
            let copy = snapshot
            lock.unlock()
            if !allowed && !wasPaused { deliver(copy, token: token) }
            _ = wake.wait(timeout: .now() + 0.2)
        }
    }

    private func publish(
        _ accumulator: WaveformAccumulator?,
        spectrogram: SpectrogramAccumulator?,
        token: Int,
        finished: Bool,
        includeWaveform: Bool
    ) {
        let painted = spectrogram?.paintedColumns() ?? []
        let progress = accumulator?.progress ?? (finished ? 1 : 0)
        lock.lock()
        guard token == generation else {
            lock.unlock()
            return
        }
        let filled = accumulator?.completedColumns ?? snapshot.filled
        snapshot.passID = token
        if let accumulator, includeWaveform {
            snapshot.lanes = accumulator.columns(through: filled)
            snapshot.columnCount = accumulator.columnCount
            snapshot.filled = filled
        } else if !includeWaveform {
            snapshot.lanes = []
            snapshot.filled = 0
        }
        snapshot.progress = progress
        snapshot.spectrogram = painted
        snapshot.running = !finished
        snapshot.paused = false
        snapshot.finished = finished
        snapshot.peakPasses = peakPasses
        let copy = snapshot
        lock.unlock()
        deliver(copy, token: token)
    }

    private func deliver(_ snapshot: WaveformSnapshot, token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isCurrent(token) else { return }
            self.onSnapshot(snapshot)
        }
    }

    private func isCurrent(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token == generation
    }

    private func enterPass() {
        lock.lock()
        inFlight += 1
        if inFlight > peakPasses { peakPasses = inFlight }
        lock.unlock()
    }

    private func leavePass() {
        lock.lock()
        inFlight = max(0, inFlight - 1)
        lock.unlock()
    }
}
