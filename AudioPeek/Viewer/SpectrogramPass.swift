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
        return hop >= 1 && nFFT >= max(hop, 2) && nMels >= 1 && fmin < high && sampleRate > 0
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

    static func weights(sampleRate: Double, nFFT: Int, nMels: Int, fmin: Double, fmax: Double) -> [Float] {
        let freqBins = nFFT / 2 + 1
        let melMin = hzToMel(fmin)
        let melMax = hzToMel(fmax)
        var melHz = [Double](repeating: 0, count: nMels + 2)
        for index in 0..<(nMels + 2) {
            let mel = melMin + (melMax - melMin) * Double(index) / Double(nMels + 1)
            melHz[index] = melToHz(mel)
        }
        var bank = [Float](repeating: 0, count: nMels * freqBins)
        for band in 0..<nMels {
            let rise = melHz[band + 1] - melHz[band]
            let fall = melHz[band + 2] - melHz[band + 1]
            for bin in 0..<freqBins {
                let freq = Double(bin) * sampleRate / Double(nFFT)
                let lower = rise == 0 ? 0 : (freq - melHz[band]) / rise
                let upper = fall == 0 ? 0 : (melHz[band + 2] - freq) / fall
                bank[band * freqBins + bin] = Float(max(0, min(lower, upper)))
            }
            let width = melHz[band + 2] - melHz[band]
            guard width > 0 else { continue }
            let scale = Float(2 / width)
            for bin in 0..<freqBins {
                bank[band * freqBins + bin] *= scale
            }
        }
        return bank
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
    private let weights: [Float]?
    private let setup: FFTSetup?
    private let log2n: vDSP_Length
    private var pending: [[Float]]
    private var head: [Int]
    private var hopIndex = 0
    private var powers: [Float]
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
            weights = SlaneyMel.weights(
                sampleRate: sampleRate,
                nFFT: nFFT,
                nMels: job.nMels,
                fmin: job.fmin,
                fmax: high
            )
            binCount = job.nMels
        } else {
            weights = nil
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
            let center = hopIndex * hop
            let column = min(columnCount - 1, center * columnCount / totalFrames)
            for lane in 0..<lanes {
                var frame = [Float](repeating: 0, count: nFFT)
                let start = head[lane]
                for index in 0..<nFFT {
                    frame[index] = pending[lane][start + index] * window[index]
                }
                let power = fftPower(frame)
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
        guard let weights else { return power }
        var bands = [Float](repeating: 0, count: binCount)
        for band in 0..<binCount {
            var sum: Float = 0
            let row = band * frequencyBins
            for bin in 0..<frequencyBins {
                sum += weights[row + bin] * power[bin]
            }
            bands[band] = sum
        }
        return bands
    }

    private func fftPower(_ frame: [Float]) -> [Float] {
        if let setup {
            return packedPower(frame, setup: setup)
        }
        return directPower(frame)
    }

    private func packedPower(_ frame: [Float], setup: FFTSetup) -> [Float] {
        let half = nFFT / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        for index in 0..<half {
            real[index] = frame[index * 2]
            imag[index] = frame[index * 2 + 1]
        }
        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        var power = [Float](repeating: 0, count: half + 1)
        power[0] = real[0] * real[0]
        power[half] = imag[0] * imag[0]
        if half > 1 {
            for index in 1..<half {
                let re = real[index] * 0.5
                let im = imag[index] * 0.5
                power[index] = re * re + im * im
            }
        }
        return power
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
