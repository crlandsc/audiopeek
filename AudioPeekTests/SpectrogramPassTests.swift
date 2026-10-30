import XCTest
@testable import AudioPeek

final class SpectrogramPassTests: XCTestCase {
    func testEstimateHidesAShortFileAndShowsATwelveMinuteWav() {
        let short = OverviewEstimate.seconds(
            duration: 1,
            sampleRate: 44100,
            compressed: false,
            spectrogramDualVisible: false
        )
        XCTAssertEqual(short, 6.0 / 3600, accuracy: 1e-9)
        XCTAssertFalse(OverviewEstimate.showsBar(short))
        let long = OverviewEstimate.seconds(
            duration: 12 * 60,
            sampleRate: 44100,
            compressed: false,
            spectrogramDualVisible: false
        )
        XCTAssertEqual(long, 1.2, accuracy: 1e-9)
        XCTAssertTrue(OverviewEstimate.showsBar(long))
        let doubled = OverviewEstimate.seconds(
            duration: 12 * 60,
            sampleRate: 44100,
            compressed: true,
            spectrogramDualVisible: true
        )
        XCTAssertEqual(doubled, 4.8, accuracy: 1e-9)
        XCTAssertFalse(OverviewEstimate.isCompressed(url: URL(fileURLWithPath: "/tmp/a.wav")))
        XCTAssertFalse(OverviewEstimate.isCompressed(url: URL(fileURLWithPath: "/tmp/a.aiff")))
        XCTAssertTrue(OverviewEstimate.isCompressed(url: URL(fileURLWithPath: "/tmp/a.mp3")))
        XCTAssertTrue(OverviewEstimate.isCompressed(url: URL(fileURLWithPath: "/tmp/a.flac")))
    }

    func testLongFilesInspectACoarseWindowUnlessFullDetailIsOn() {
        XCTAssertEqual(OverviewDetail.inspectFrames(duration: 10, fullDetail: false, nFFT: 2048), 0)
        XCTAssertEqual(OverviewDetail.inspectFrames(duration: 60, fullDetail: true, nFFT: 2048), 0)
        XCTAssertEqual(OverviewDetail.inspectFrames(duration: 60, fullDetail: false, nFFT: 2048), 2048)
        XCTAssertEqual(OverviewDetail.inspectFrames(duration: 60, fullDetail: false, nFFT: 512), 512)
    }

    func testCoarseReadStillFinishesALongFile() throws {
        let frames = 44_100 * 2
        let url = URL(fileURLWithPath: "/tmp/audiopeek-coarse-\(UUID().uuidString).wav")
        try writeSilent(frames: frames, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = WaveformReader.read(
            url: url,
            columnCount: 16,
            dual: false,
            chunkFrames: 8192,
            proceed: { _ in true },
            onChunk: { _ in },
            computeWaveform: true,
            inspectPerColumn: 512
        )
        XCTAssertEqual(result.stop, .finished)
        XCTAssertGreaterThan(result.accumulator?.completedColumns ?? 0, 0)
    }

    func testACancelledPassStopsBeforePaintingColumns() throws {
        let engine = try XCTUnwrap(
            SpectrogramAccumulator(job: factoryJob(), sampleRate: 44100, channels: 1, totalFrames: 8192, columnCount: 8)
        )
        engine.cancelled = true
        let samples = [Float](repeating: 0.2, count: 4096)
        samples.withUnsafeBufferPointer { buffer in
            engine.ingest(base: buffer.baseAddress!, frames: 4096, channels: 1)
        }
        XCTAssertEqual(engine.filledColumns, 0)
    }

    func testColorMapsStayDistinctAndGrayRunsFromBlackToWhite() {
        let black = SpectrogramColorMap.gray.components(0)
        let white = SpectrogramColorMap.gray.components(1)
        XCTAssertEqual(Double(black.0), 0, accuracy: 0.001)
        XCTAssertEqual(Double(white.0), 1, accuracy: 0.001)
        let magma = SpectrogramColorMap.magma.components(0.4)
        let viridis = SpectrogramColorMap.viridis.components(0.4)
        XCTAssertGreaterThan(abs(Double(magma.0 - viridis.0)), 0.05)
        XCTAssertEqual(SettingsBlob.factory.spectrogram.colorMap, .magma)
    }

    func testInvalidKnobsDoNotBuildAndDualKeepsTwoLanes() {
        let invalid = factoryJob(hop: 0)
        XCTAssertFalse(invalid.isValid(sampleRate: 44100))
        XCTAssertNil(SpectrogramAccumulator(job: invalid, sampleRate: 44100, channels: 1, totalFrames: 100, columnCount: 8))
        let dual = factoryJob(dual: true)
        let engine = SpectrogramAccumulator(job: dual, sampleRate: 44100, channels: 16, totalFrames: 100, columnCount: 8)
        XCTAssertEqual(engine?.lanes, 2)
        XCTAssertEqual(WaveformColumns.spectrogramShowing(channels: 16, dual: true), 2)
        XCTAssertNil(WaveformColumns.spectrogramShowing(channels: 16, dual: false))
        XCTAssertNil(WaveformColumns.spectrogramShowing(channels: 2, dual: true))
    }

    private func writeSilent(frames: Int, to url: URL) throws {
        var samples = [Int16](repeating: 0, count: frames)
        try writeWav(frames: samples, to: url)
    }

    func testMelMatchesPinnedLibrosa() throws {
        let frames = 44100
        let columnCount = 32
        var samples = [Int16](repeating: 0, count: frames)
        var state: UInt32 = 0xC0FFEE
        for frame in 0..<frames {
            state = state &* 1664525 &+ 1013904223
            let noise = (Float(state % 10000) / 10000 - 0.5) * 0.25
            let tone = sin(2 * Float.pi * 440 * Float(frame) / 44100) * 0.45
            let mixed = min(0.95, max(-0.95, noise + tone))
            samples[frame] = Int16(mixed * 32767)
        }
        let wav = URL(fileURLWithPath: "/tmp/audiopeek-mel-check.wav")
        let columns = URL(fileURLWithPath: "/tmp/audiopeek-mel-check.json")
        try writeWav(frames: samples, to: wav)
        let job = factoryJob()
        let engine = try XCTUnwrap(
            SpectrogramAccumulator(job: job, sampleRate: 44100, channels: 1, totalFrames: frames, columnCount: columnCount)
        )
        let gate = MachineLoadGate()
        gate.setInjected(thermal: .nominal, cpu: 0.2)
        var gateAllowed = true
        let result = WaveformReader.read(
            url: wav,
            columnCount: columnCount,
            dual: false,
            chunkFrames: 8192,
            proceed: { _ in
                let allowed = gate.allowsPlayback(gate.sample())
                if !allowed { gateAllowed = false }
                return allowed
            },
            onChunk: { _ in },
            onSamples: { base, count, channels, _, _ in
                engine.ingest(base: base, frames: count, channels: channels)
            }
        )
        XCTAssertTrue(gateAllowed)
        XCTAssertEqual(result.stop, .finished)
        engine.finish()
        let waveform = try XCTUnwrap(result.accumulator)
        XCTAssertEqual(waveform.completedColumns, columnCount)
        var minima = [Double]()
        var maxima = [Double]()
        for column in 0..<columnCount {
            let value = waveform.column(lane: 0, column: column)
            minima.append(Double(value.minimum))
            maxima.append(Double(value.maximum))
        }
        let mel = engine.allColumns()[0].map { column in column.map { Double($0) } }
        let payload: [String: Any] = [
            "sample_rate": 44100,
            "n_fft": 2048,
            "hop": 512,
            "n_mels": 128,
            "column_count": columnCount,
            "waveform_min": minima,
            "waveform_max": maxima,
            "mel": mel,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: columns)
        XCTAssertEqual(mel.count, columnCount)
        XCTAssertEqual(mel.first?.count, 128)
    }

    func testSparseMelDotMatchesDenseWhenTheFootIsFractional() {
        let sampleRate = 8000.0
        let nFFT = 512
        let nMels = 128
        let fmin = 1000.0
        let fmax = 4000.0
        let freqBins = nFFT / 2 + 1
        let runs = SlaneyMel.weights(
            sampleRate: sampleRate,
            nFFT: nFFT,
            nMels: nMels,
            fmin: fmin,
            fmax: fmax
        )
        let dense = denseSlaneyWeights(
            sampleRate: sampleRate,
            nFFT: nFFT,
            nMels: nMels,
            fmin: fmin,
            fmax: fmax
        )
        let melMin = SlaneyMel.hzToMel(fmin)
        let melMax = SlaneyMel.hzToMel(fmax)
        var melHz = [Double](repeating: 0, count: nMels + 2)
        for index in 0..<(nMels + 2) {
            let mel = melMin + (melMax - melMin) * Double(index) / Double(nMels + 1)
            melHz[index] = SlaneyMel.melToHz(mel)
        }
        var power = [Float](repeating: 0, count: freqBins)
        for bin in 0..<freqBins {
            power[bin] = 1 + Float(bin % 5) * 0.25
        }
        let sparse = SlaneyMel.dot(power: power, runs: runs)
        var sawFractionalFoot = false
        XCTAssertEqual(runs.count, nMels)
        XCTAssertEqual(sparse.count, nMels)
        for band in 0..<nMels {
            let left = melHz[band] * Double(nFFT) / sampleRate
            let right = melHz[band + 2] * Double(nFFT) / sampleRate
            let footIsFractional = abs(left - left.rounded()) > 0.05 || abs(right - right.rounded()) > 0.05
            let run = runs[band]
            var denseSum: Float = 0
            for bin in 0..<freqBins {
                let weight = dense[band * freqBins + bin]
                denseSum += weight * power[bin]
                if weight > 0 {
                    let offset = bin - run.startBin
                    XCTAssertGreaterThanOrEqual(offset, 0)
                    XCTAssertLessThan(offset, run.weights.count)
                    XCTAssertEqual(run.weights[offset], weight)
                    if footIsFractional, weight < 1 {
                        sawFractionalFoot = true
                    }
                }
            }
            XCTAssertEqual(sparse[band], denseSum, accuracy: 1e-5)
        }
        XCTAssertTrue(sawFractionalFoot)
        let zeroWidth = SlaneyMel.weights(
            sampleRate: sampleRate,
            nFFT: 32,
            nMels: 3,
            fmin: 1000,
            fmax: 1000
        )
        XCTAssertEqual(zeroWidth.count, 3)
        XCTAssertTrue(zeroWidth.allSatisfy { $0.weights.isEmpty })
    }

    func testAPaneWiderThanTheHopCountHasNoEmptyColumns() throws {
        let hops = 100
        let frames = hops * 512
        let columns = 160
        let engine = try XCTUnwrap(
            SpectrogramAccumulator(job: factoryJob(), sampleRate: 44100, channels: 1, totalFrames: frames, columnCount: columns)
        )
        var seed: UInt32 = 1
        let samples = (0..<frames).map { _ -> Float in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.5
        }
        samples.withUnsafeBufferPointer { buffer in
            engine.ingest(base: buffer.baseAddress!, frames: frames, channels: 1)
        }
        engine.finish()
        for picture in [engine.paintedColumns()[0], engine.allColumns()[0]] {
            XCTAssertEqual(picture.count, columns)
            let empty = picture.indices.filter { index in picture[index].allSatisfy { $0 == 0 } }
            XCTAssertEqual(empty, [])
        }
    }

    func testDualDrainOfDifferentSamplesDoesNotComeOutEqual() throws {
        let frames = 4096
        let engine = try XCTUnwrap(
            SpectrogramAccumulator(
                job: factoryJob(dual: true),
                sampleRate: 44100,
                channels: 2,
                totalFrames: frames,
                columnCount: 8
            )
        )
        var samples = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            samples[frame * 2] = sin(2 * Float.pi * 440 * Float(frame) / 44100)
            samples[frame * 2 + 1] = sin(2 * Float.pi * 1760 * Float(frame) / 44100) * 0.25
        }
        samples.withUnsafeBufferPointer { buffer in
            engine.ingest(base: buffer.baseAddress!, frames: frames, channels: 2)
        }
        engine.finish()
        let columns = engine.allColumns()
        XCTAssertEqual(columns.count, 2)
        XCTAssertGreaterThan(columns[0].joined().reduce(Float(0), +), 0)
        XCTAssertGreaterThan(columns[1].joined().reduce(Float(0), +), 0)
        XCTAssertNotEqual(columns[0], columns[1])
    }

    private func factoryJob(hop: Int = 512, dual: Bool = false) -> SpectrogramJob {
        SpectrogramJob(
            dual: dual,
            type: .mel,
            nFFT: 2048,
            hop: hop,
            window: .hann,
            nMels: 128,
            fmin: 0,
            fmax: nil,
            decibels: true,
            dbFloor: -80,
            dbRange: 80
        )
    }

    private func denseSlaneyWeights(
        sampleRate: Double,
        nFFT: Int,
        nMels: Int,
        fmin: Double,
        fmax: Double
    ) -> [Float] {
        let freqBins = nFFT / 2 + 1
        let melMin = SlaneyMel.hzToMel(fmin)
        let melMax = SlaneyMel.hzToMel(fmax)
        var melHz = [Double](repeating: 0, count: nMels + 2)
        for index in 0..<(nMels + 2) {
            let mel = melMin + (melMax - melMin) * Double(index) / Double(nMels + 1)
            melHz[index] = SlaneyMel.melToHz(mel)
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

    private func writeWav(frames: [Int16], to url: URL) throws {
        var data = Data()
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let byteCount = frames.count * 2
        data.append(contentsOf: "RIFF".utf8)
        append32(UInt32(36 + byteCount))
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
        append32(UInt32(byteCount))
        for frame in frames {
            var little = frame.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        try data.write(to: url)
    }
}
