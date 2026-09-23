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
        computeWaveform: Bool = true,
        inspectPerColumn: Int = 0
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
        if inspectPerColumn > 0 {
            let totalFrames = accumulator.totalFrames
            let columns = max(columnCount, 1)
            var fileFrame = 0
            var decoderFrame = 0
            while fileFrame < totalFrames {
                if chunks > 0, !proceed(.betweenChunks) {
                    return WaveformReadResult(stop: .cancelled, chunks: chunks, opened: true, accumulator: accumulator)
                }
                let columnEnd = min(totalFrames, (min(columns - 1, fileFrame * columns / totalFrames) + 1) * totalFrames / columns)
                let take = min(inspectPerColumn, max(0, columnEnd - fileFrame))
                if take > 0 {
                    let gap = fileFrame - decoderFrame
                    if gap > 0, gap < 4 * inspectPerColumn {
                        var remaining = gap
                        while remaining > 0 {
                            var list = AudioBufferList(
                                mNumberBuffers: 1,
                                mBuffers: AudioBuffer(
                                    mNumberChannels: UInt32(channels),
                                    mDataByteSize: UInt32(sampleCapacity * MemoryLayout<Float>.size),
                                    mData: data
                                )
                            )
                            var frames = UInt32(min(remaining, Int(framesPerChunk)))
                            let status = ExtAudioFileRead(audioFile, &frames, &list)
                            if status != noErr || frames == 0 {
                                return WaveformReadResult(stop: .failed, chunks: chunks, opened: true, accumulator: accumulator)
                            }
                            remaining -= Int(frames)
                        }
                        decoderFrame = fileFrame
                    } else if gap >= 4 * inspectPerColumn {
                        var position = Int64(fileFrame)
                        if ExtAudioFileSeek(audioFile, position) != noErr {
                            return WaveformReadResult(stop: .failed, chunks: chunks, opened: true, accumulator: accumulator)
                        }
                        decoderFrame = fileFrame
                    }
                    var list = AudioBufferList(
                        mNumberBuffers: 1,
                        mBuffers: AudioBuffer(
                            mNumberChannels: UInt32(channels),
                            mDataByteSize: UInt32(sampleCapacity * MemoryLayout<Float>.size),
                            mData: data
                        )
                    )
                    var frames = UInt32(min(take, Int(framesPerChunk)))
                    let status = ExtAudioFileRead(audioFile, &frames, &list)
                    if status != noErr {
                        return WaveformReadResult(stop: .failed, chunks: chunks, opened: true, accumulator: accumulator)
                    }
                    if frames > 0 {
                        onSamples?(data, Int(frames), channels, description.sampleRate, totalFrames)
                        if computeWaveform {
                            accumulator.ingest(base: data, frames: Int(frames))
                        } else {
                            accumulator.skip(frames: Int(frames))
                        }
                    }
                    decoderFrame += Int(frames)
                }
                if accumulator.framesSeen < columnEnd {
                    accumulator.skip(frames: columnEnd - accumulator.framesSeen)
                }
                fileFrame = max(columnEnd, fileFrame + 1)
                chunks += 1
                onChunk(accumulator)
                if accumulator.framesSeen >= totalFrames { break }
            }
            return WaveformReadResult(stop: .finished, chunks: chunks, opened: true, accumulator: accumulator)
        }
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
    private var chunkDeliveredOnce = false
    private var deliverNextChunkNow = false
    private var lastChunkDeliveredAt = Date.distantPast
    private var coalescedFlush: DispatchWorkItem?
    private var deliveryQueued = false
    private var deliverySnapshot: WaveformSnapshot?
    private var deliveryToken = 0
    private let chunkPublishInterval: TimeInterval = 0.1

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
        let token: Int
        let published: WaveformSnapshot
        lock.lock()
        generation += 1
        token = generation
        liveEngine?.cancelled = true
        let peak = peakPasses
        snapshot = .empty
        snapshot.peakPasses = peak
        resetPublishWindowLocked()
        published = snapshot
        lock.unlock()
        wake.signal()
        deliver(published, token: token)
    }

    func start(url: URL, columnCount: Int, waveformDual: Bool, computeWaveform: Bool, spectrogram: SpectrogramJob?, inspectPerColumn: Int = 0) {
        let token: Int
        let published: WaveformSnapshot
        lock.lock()
        generation += 1
        liveEngine?.cancelled = true
        token = generation
        resetPublishWindowLocked()
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
                spectrogram: spectrogram,
                inspectPerColumn: inspectPerColumn
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
        spectrogram: SpectrogramJob?,
        inspectPerColumn: Int
    ) {
        enterPass()
        var trackedEngine: SpectrogramAccumulator?
        defer {
            forgetLiveEngine(trackedEngine)
            leavePass()
        }
        let box = SpectrogramBox()
        let result = WaveformReader.read(
            url: url,
            columnCount: columnCount,
            dual: waveformDual,
            chunkFrames: 8192,
            proceed: { [weak self] point in
                guard let self else { return false }
                switch point {
                case .beforeOpen:
                    return self.waitToContinue(token)
                case .betweenChunks:
                    box.engine?.cancelled = !self.isCurrent(token)
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
                    let pictured = inspectPerColumn > 0 ? columnCount * inspectPerColumn : totalFrames
                    box.engine = SpectrogramAccumulator(
                        job: spectrogram,
                        sampleRate: sampleRate,
                        channels: channels,
                        totalFrames: pictured,
                        columnCount: columnCount
                    )
                    trackedEngine = box.engine
                    self.rememberLiveEngine(box.engine)
                }
                box.engine?.ingest(base: base, frames: frames, channels: channels)
            },
            computeWaveform: computeWaveform,
            inspectPerColumn: inspectPerColumn
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
                if stall {
                    pendingSteps -= 1
                    deliverNextChunkNow = true
                }
                let wasPaused = snapshot.paused
                snapshot.paused = false
                lock.unlock()
                if wasPaused { deliverFresh(token) }
                return true
            }
            let wasPaused = snapshot.paused
            if !allowed { snapshot.paused = true }
            lock.unlock()
            if !allowed && !wasPaused { deliverFresh(token) }
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
        guard isCurrent(token) else { return }
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
        snapshot.running = !finished
        snapshot.paused = false
        snapshot.finished = finished
        snapshot.peakPasses = peakPasses
        let now = Date()
        let windowElapsed = now.timeIntervalSince(lastChunkDeliveredAt) >= chunkPublishInterval
        let deliverNow = finished || !chunkDeliveredOnce || deliverNextChunkNow || windowElapsed
        if !finished {
            chunkDeliveredOnce = true
        }
        if deliverNow {
            deliverNextChunkNow = false
            cancelFlushLocked()
            if !finished {
                lastChunkDeliveredAt = now
            }
            lock.unlock()
            emit(spectrogram, token: token)
            return
        }
        if coalescedFlush == nil {
            let delay = chunkPublishInterval - now.timeIntervalSince(lastChunkDeliveredAt)
            let work = DispatchWorkItem { [weak self] in
                self?.flushCoalesced(token)
            }
            coalescedFlush = work
            queue.asyncAfter(deadline: .now() + max(0, delay), execute: work)
        }
        lock.unlock()
    }

    private func flushCoalesced(_ token: Int) {
        let engine: SpectrogramAccumulator?
        lock.lock()
        coalescedFlush = nil
        guard token == generation else {
            lock.unlock()
            return
        }
        engine = liveEngine
        lastChunkDeliveredAt = Date()
        lock.unlock()
        emit(engine, token: token)
    }

    private func deliverFresh(_ token: Int) {
        let engine: SpectrogramAccumulator?
        lock.lock()
        guard token == generation else {
            lock.unlock()
            return
        }
        cancelFlushLocked()
        engine = liveEngine
        lock.unlock()
        emit(engine, token: token)
    }

    private func emit(_ engine: SpectrogramAccumulator?, token: Int) {
        let painted = engine?.paintedColumns() ?? []
        lock.lock()
        guard token == generation else {
            lock.unlock()
            return
        }
        snapshot.spectrogram = painted
        let copy = snapshot
        lock.unlock()
        deliver(copy, token: token)
    }

    private func deliver(_ snapshot: WaveformSnapshot, token: Int) {
        lock.lock()
        deliverySnapshot = snapshot
        deliveryToken = token
        let schedule = !deliveryQueued
        deliveryQueued = true
        lock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingDelivery()
        }
    }

    private func applyPendingDelivery() {
        lock.lock()
        let snapshot = deliverySnapshot
        let token = deliveryToken
        deliverySnapshot = nil
        deliveryQueued = false
        lock.unlock()
        guard let snapshot else { return }
        guard isCurrent(token) else { return }
        onSnapshot(snapshot)
    }

    private func resetPublishWindowLocked() {
        chunkDeliveredOnce = false
        deliverNextChunkNow = false
        lastChunkDeliveredAt = .distantPast
        cancelFlushLocked()
    }

    private func cancelFlushLocked() {
        coalescedFlush?.cancel()
        coalescedFlush = nil
    }

    private var liveEngine: SpectrogramAccumulator?

    private func rememberLiveEngine(_ engine: SpectrogramAccumulator?) {
        lock.lock()
        liveEngine = engine
        lock.unlock()
    }

    private func forgetLiveEngine(_ engine: SpectrogramAccumulator?) {
        lock.lock()
        if liveEngine === engine {
            liveEngine = nil
        }
        lock.unlock()
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
