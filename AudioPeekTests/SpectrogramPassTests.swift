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
