import Accelerate
import Foundation

struct SpectrogramJob: Equatable, Sendable {
    var dual: Bool
    var type: SpectrogramType
    var nFFT: Int
    var hop: Int
    var window: FFTWindow
    var nMels: Int
    var fmin: Double
    var fmax: Double?
    var decibels: Bool
    var dbFloor: Double
    var dbRange: Double

    func resolvedFMax(sampleRate: Double) -> Double {
        let nyquist = sampleRate / 2
        return min(fmax ?? nyquist, nyquist)
    }

    func isValid(sampleRate: Double) -> Bool {
        let high = resolvedFMax(sampleRate: sampleRate)
        return hop >= 1 && nFFT >= 2 && nMels >= 1 && fmin < high && sampleRate > 0
    }
}

enum OverviewDetail {
    static func inspectFrames(duration: TimeInterval, fullDetail: Bool, nFFT: Int) -> Int {
        if fullDetail || duration <= 30 { return 0 }
        return max(256, min(max(nFFT, 256), 2048))
    }
}

enum OverviewEstimate {
    static func seconds(
        duration: TimeInterval,
        sampleRate: Double,
        compressed: Bool,
        spectrogramDualVisible: Bool
    ) -> Double {
        guard duration > 0, sampleRate > 0 else { return 0 }
        var estimate = 6 * (duration / 3600) * (sampleRate / 44100)
        if compressed { estimate *= 2 }
        if spectrogramDualVisible { estimate *= 2 }
        return estimate
    }

    static func showsBar(_ estimate: Double) -> Bool {
        estimate > 1
    }

    static func isCompressed(url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "wav", "aif", "aiff":
            return false
        default:
            return true
        }
    }
}

enum SlaneyMel {
    struct Run {
        var startBin: Int
        var weights: [Float]
    }

    static func hzToMel(_ hz: Double) -> Double {
        let spacing = 200.0 / 3
        let minLogHz = 1000.0
        let minLogMel = minLogHz / spacing
        let logStep = log(6.4) / 27.0
        if hz >= minLogHz {
            return minLogMel + log(hz / minLogHz) / logStep
        }
        return hz / spacing
    }

    static func melToHz(_ mel: Double) -> Double {
        let spacing = 200.0 / 3
        let minLogHz = 1000.0
        let minLogMel = minLogHz / spacing
        let logStep = log(6.4) / 27.0
        if mel >= minLogMel {
            return minLogHz * exp(logStep * (mel - minLogMel))
        }
        return spacing * mel
    }

    static func weights(sampleRate: Double, nFFT: Int, nMels: Int, fmin: Double, fmax: Double) -> [Run] {
        let freqBins = nFFT / 2 + 1
        let melMin = hzToMel(fmin)
        let melMax = hzToMel(fmax)
        var melHz = [Double](repeating: 0, count: nMels + 2)
        for index in 0..<(nMels + 2) {
            let mel = melMin + (melMax - melMin) * Double(index) / Double(nMels + 1)
            melHz[index] = melToHz(mel)
        }
        var runs = [Run]()
        runs.reserveCapacity(nMels)
        for band in 0..<nMels {
            let rise = melHz[band + 1] - melHz[band]
            let fall = melHz[band + 2] - melHz[band + 1]
            var scaled = [Float](repeating: 0, count: freqBins)
            for bin in 0..<freqBins {
                let freq = Double(bin) * sampleRate / Double(nFFT)
                let lower = rise == 0 ? 0 : (freq - melHz[band]) / rise
                let upper = fall == 0 ? 0 : (melHz[band + 2] - freq) / fall
                scaled[bin] = Float(max(0, min(lower, upper)))
            }
            let width = melHz[band + 2] - melHz[band]
            guard width > 0 else {
                runs.append(Run(startBin: 0, weights: []))
                continue
            }
            let scale = Float(2 / width)
            var startBin: Int?
            var lastBin = 0
            for bin in 0..<freqBins {
                scaled[bin] *= scale
                if scaled[bin] > 0 {
                    if startBin == nil { startBin = bin }
                    lastBin = bin
                }
            }
            if let startBin {
                runs.append(Run(startBin: startBin, weights: Array(scaled[startBin...lastBin])))
            } else {
                runs.append(Run(startBin: 0, weights: []))
            }
        }
        return runs
    }

    static func dot(power: [Float], runs: [Run]) -> [Float] {
        var bands = [Float](repeating: 0, count: runs.count)
        power.withUnsafeBufferPointer { powerPointer in
            guard let powerBase = powerPointer.baseAddress else { return }
            for (band, run) in runs.enumerated() {
                let count = run.weights.count
                guard count > 0 else { continue }
                var sum: Float = 0
                run.weights.withUnsafeBufferPointer { weightPointer in
                    guard let weightBase = weightPointer.baseAddress else { return }
                    vDSP_dotpr(weightBase, 1, powerBase + run.startBin, 1, &sum, vDSP_Length(count))
                }
                bands[band] = sum
            }
        }
        return bands
    }
}

final class SpectrogramAccumulator {
    let lanes: Int
    let binCount: Int
    let columnCount: Int
    let frequencyBins: Int
    private let channels: Int
    private let dual: Bool
    private let totalFrames: Int
    private let nFFT: Int
    private let hop: Int
    private let window: [Float]
    private let melRuns: [SlaneyMel.Run]?
    private let setup: FFTSetup?
    private let log2n: vDSP_Length
    private var pending: [[Float]]
    private var head: [Int]
    private let cancelLock = NSLock()
    private var cancelFlag = false
    var cancelled: Bool {
        get {
            cancelLock.lock()
            defer { cancelLock.unlock() }
            return cancelFlag
        }
        set {
            cancelLock.lock()
            cancelFlag = newValue
            cancelLock.unlock()
        }
    }
    private var hopIndex = 0
    private var powers: [Float]
    private var windowed: [Float]
    private var splitReal: [Float]
    private var splitImag: [Float]
    private var spectrum: [Float]
    private var highestColumn = -1

    init?(job: SpectrogramJob, sampleRate: Double, channels: Int, totalFrames: Int, columnCount: Int) {
        guard job.isValid(sampleRate: sampleRate), channels > 0, totalFrames > 0, columnCount > 0 else { return nil }
        self.channels = channels
        dual = job.dual
        lanes = job.dual ? min(channels, 2) : 1
        self.totalFrames = totalFrames
        self.columnCount = columnCount
        nFFT = job.nFFT
        hop = job.hop
        frequencyBins = nFFT / 2 + 1
        if job.type == .mel {
            let high = job.resolvedFMax(sampleRate: sampleRate)
            melRuns = SlaneyMel.weights(
                sampleRate: sampleRate,
                nFFT: nFFT,
                nMels: job.nMels,
                fmin: job.fmin,
                fmax: high
            )
            binCount = job.nMels
        } else {
            melRuns = nil
            binCount = frequencyBins
        }
        var built = [Float](repeating: 0, count: nFFT)
        let length = Float(nFFT)
        for index in 0..<nFFT {
            let phase = 2 * Float.pi * Float(index) / length
            switch job.window {
            case .hann:
                built[index] = 0.5 - 0.5 * cos(phase)
            case .hamming:
                built[index] = 0.54 - 0.46 * cos(phase)
            case .blackman:
                built[index] = 0.42 - 0.5 * cos(phase) + 0.08 * cos(phase * 2)
            }
        }
        window = built
        if nFFT > 1, nFFT & (nFFT - 1) == 0 {
            log2n = vDSP_Length(nFFT.trailingZeroBitCount)
            setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        } else {
            log2n = 0
            setup = nil
        }
        let pad = nFFT / 2
        pending = Array(repeating: Array(repeating: 0, count: pad), count: lanes)
        head = Array(repeating: 0, count: lanes)
        powers = Array(repeating: 0, count: lanes * columnCount * binCount)
        windowed = [Float](repeating: 0, count: nFFT)
        splitReal = [Float](repeating: 0, count: nFFT / 2)
        splitImag = [Float](repeating: 0, count: nFFT / 2)
        spectrum = [Float](repeating: 0, count: frequencyBins)
    }

    deinit {
        if let setup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    var filledColumns: Int { highestColumn + 1 }

    func ingest(base: UnsafePointer<Float>, frames: Int, channels: Int) {
        let used = min(channels, self.channels)
        guard used > 0 else { return }
        for frame in 0..<frames {
            let row = frame * channels
            if dual {
                for lane in 0..<lanes {
                    pending[lane].append(base[row + lane])
                }
            } else {
                var sum: Float = 0
                for channel in 0..<used {
                    sum += base[row + channel]
                }
                pending[0].append(sum / Float(used))
            }
        }
        drain()
    }

    func finish() {
        let pad = nFFT / 2
        for lane in 0..<lanes {
            pending[lane].append(contentsOf: Array(repeating: 0, count: pad))
        }
        drain()
    }

    func allColumns() -> [[[Float]]] {
        (0..<lanes).map { lane in
            (0..<columnCount).map { column in
                (0..<binCount).map { bin in
                    powers[((lane * columnCount) + column) * binCount + bin]
                }
            }
        }
    }

    func paintedColumns() -> [[[Float]]] {
        let count = filledColumns
        return (0..<lanes).map { lane in
            (0..<count).map { column in
                (0..<binCount).map { bin in
                    powers[((lane * columnCount) + column) * binCount + bin]
                }
            }
        }
    }

    private func drain() {
        while pending[0].count - head[0] >= nFFT {
            if cancelled { return }
            let center = hopIndex * hop
            let column = min(columnCount - 1, center * columnCount / totalFrames)
            for lane in 0..<lanes {
                let start = head[lane]
                for index in 0..<nFFT {
                    windowed[index] = pending[lane][start + index] * window[index]
                }
                let power = fftPower()
                let values = project(power)
                for bin in 0..<binCount {
                    let slot = ((lane * columnCount) + column) * binCount + bin
                    powers[slot] = max(powers[slot], values[bin])
                }
            }
            highestColumn = max(highestColumn, column)
            hopIndex += 1
            for lane in 0..<lanes {
                head[lane] += hop
            }
            if head[0] > nFFT * 4 {
                for lane in 0..<lanes {
                    pending[lane].removeFirst(head[lane])
                    head[lane] = 0
                }
            }
        }
    }

    private func project(_ power: [Float]) -> [Float] {
        guard let melRuns else { return power }
        return SlaneyMel.dot(power: power, runs: melRuns)
    }

    private func fftPower() -> [Float] {
        if let setup {
            packedPower(setup: setup)
            return spectrum
        }
        let frame = windowed
        return directPower(frame)
    }

    private func packedPower(setup: FFTSetup) {
        let half = nFFT / 2
        for index in 0..<half {
            splitReal[index] = windowed[index * 2]
            splitImag[index] = windowed[index * 2 + 1]
        }
        splitReal.withUnsafeMutableBufferPointer { realPointer in
            splitImag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        spectrum[0] = splitReal[0] * splitReal[0]
        spectrum[half] = splitImag[0] * splitImag[0]
        if half > 1 {
            for index in 1..<half {
                let re = splitReal[index] * 0.5
                let im = splitImag[index] * 0.5
                spectrum[index] = re * re + im * im
            }
        }
    }

    private func directPower(_ frame: [Float]) -> [Float] {
        let bins = nFFT / 2 + 1
        var power = [Float](repeating: 0, count: bins)
        let length = Float(nFFT)
        for bin in 0..<bins {
            var real: Float = 0
            var imag: Float = 0
            let step = -2 * Float.pi * Float(bin) / length
            for time in 0..<nFFT {
                let phase = step * Float(time)
                real += frame[time] * cos(phase)
                imag += frame[time] * sin(phase)
            }
            power[bin] = real * real + imag * imag
        }
        return power
    }
}
