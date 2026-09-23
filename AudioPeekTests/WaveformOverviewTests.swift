import XCTest
@testable import AudioPeek

final class WaveformOverviewTests: XCTestCase {
    func testMixdownMinMaxMatchesTheSamples() {
        var accumulator = WaveformAccumulator(channels: 2, totalFrames: 4, columnCount: 2, dual: false)
        let samples: [Float] = [
            0.5, -0.25,
            -1, 0.25,
            0, 0.5,
            0.25, -0.5,
        ]
        samples.withUnsafeBufferPointer { buffer in
            accumulator.ingest(base: buffer.baseAddress!, frames: 4)
        }
        XCTAssertEqual(accumulator.completedColumns, 2)
        XCTAssertEqual(accumulator.column(lane: 0, column: 0).minimum, -0.375, accuracy: 0.0001)
        XCTAssertEqual(accumulator.column(lane: 0, column: 0).maximum, 0.125, accuracy: 0.0001)
        XCTAssertEqual(accumulator.column(lane: 0, column: 1).minimum, -0.125, accuracy: 0.0001)
        XCTAssertEqual(accumulator.column(lane: 0, column: 1).maximum, 0.25, accuracy: 0.0001)
    }

    func testDualKeepsTheFirstEightChannels() {
        var accumulator = WaveformAccumulator(channels: 10, totalFrames: 1, columnCount: 1, dual: true)
        var samples = Array(repeating: Float(0), count: 10)
        samples[0] = 0.25
        samples[7] = -0.5
        samples[9] = 1
        samples.withUnsafeBufferPointer { buffer in
            accumulator.ingest(base: buffer.baseAddress!, frames: 1)
        }
        XCTAssertEqual(accumulator.lanes, 8)
        XCTAssertEqual(accumulator.column(lane: 0, column: 0).maximum, 0.25, accuracy: 0.0001)
        XCTAssertEqual(accumulator.column(lane: 7, column: 0).minimum, -0.5, accuracy: 0.0001)
        XCTAssertNil(WaveformColumns.showing(channels: 8, dual: true))
        XCTAssertEqual(WaveformColumns.showing(channels: 10, dual: true), 8)
        XCTAssertNil(WaveformColumns.showing(channels: 10, dual: false))
    }

    func testHeaderUsesTheShowingPatternOnlyWhenALaneIsDropped() {
        let truncated = AudioFileKind.metadataLine(
            format: "WAV",
            sampleRate: 44100,
            channels: 16,
            duration: 1,
            waveformShowing: 8
        )
        XCTAssertEqual(truncated, "WAV · 44.1 kHz · 16 ch · showing 8 · 0:01")
        let mixed = AudioFileKind.metadataLine(
            format: "WAV",
            sampleRate: 44100,
            channels: 16,
            duration: 1
        )
        XCTAssertEqual(mixed, "WAV · 44.1 kHz · 16 ch · 0:01")
        let both = AudioFileKind.metadataLine(
            format: "WAV",
            sampleRate: 44100,
            channels: 16,
            duration: 1,
            waveformShowing: 8,
            spectrogramShowing: 2
        )
        XCTAssertEqual(both, "WAV · 44.1 kHz · 16 ch · showing 8 · 16 ch · showing 2 · 0:01")
    }

    func testDecibelScaleRunsFromTheFloorToFullScale() {
        XCTAssertEqual(WaveformColumns.decibelUnit(0), 0, accuracy: 0.0001)
        XCTAssertEqual(WaveformColumns.decibelUnit(1), 1, accuracy: 0.0001)
        XCTAssertEqual(WaveformColumns.decibelUnit(0.1), 0.75, accuracy: 0.0001)
        XCTAssertEqual(WaveformColumns.decibelUnit(-1), 1, accuracy: 0.0001)
    }

    func testColumnsPublishBeforeTheReadFinishes() throws {
        let url = try writeWav(frames: [0, 16384, -32768, 32767, 0, 0, 1000, -1000])
        defer { try? FileManager.default.removeItem(at: url) }
        var partials: [Int] = []
        let result = WaveformReader.read(
            url: url,
            columnCount: 4,
            dual: false,
            chunkFrames: 2,
            proceed: { _ in true },
            onChunk: { accumulator in
                if accumulator.completedColumns < accumulator.columnCount {
                    partials.append(accumulator.completedColumns)
                }
            }
        )
        XCTAssertEqual(result.stop, .finished)
        XCTAssertGreaterThan(result.chunks, 1)
        XCTAssertFalse(partials.isEmpty)
        let scale: Float = 32768
        let picture = try XCTUnwrap(result.accumulator)
        XCTAssertEqual(picture.column(lane: 0, column: 0).minimum, 0, accuracy: 0.002)
        XCTAssertEqual(picture.column(lane: 0, column: 0).maximum, 16384 / scale, accuracy: 0.002)
        XCTAssertEqual(picture.column(lane: 0, column: 1).minimum, -32768 / scale, accuracy: 0.002)
        XCTAssertEqual(picture.column(lane: 0, column: 1).maximum, 32767 / scale, accuracy: 0.002)
    }

    func testCancelBeforeOpenPublishesNothing() throws {
        let url = try writeWav(frames: [0, 1000, 2000, 3000])
        defer { try? FileManager.default.removeItem(at: url) }
        var chunks = 0
        let result = WaveformReader.read(
            url: url,
            columnCount: 2,
            dual: false,
            chunkFrames: 2,
            proceed: { _ in false },
            onChunk: { _ in chunks += 1 }
        )
        XCTAssertEqual(result.stop, .cancelled)
        XCTAssertFalse(result.opened)
        XCTAssertEqual(result.chunks, 0)
        XCTAssertEqual(chunks, 0)
    }

    func testCancelAfterOpenDoesNotRead() throws {
        let url = try writeWav(frames: [0, 1000, 2000, 3000])
        defer { try? FileManager.default.removeItem(at: url) }
        var chunks = 0
        let result = WaveformReader.read(
            url: url,
            columnCount: 2,
            dual: false,
            chunkFrames: 2,
            proceed: { $0 == .beforeOpen },
            onChunk: { _ in chunks += 1 }
        )
        XCTAssertEqual(result.stop, .cancelled)
        XCTAssertTrue(result.opened)
        XCTAssertEqual(result.chunks, 0)
        XCTAssertEqual(chunks, 0)
    }

    func testCancelAfterTheFirstChunkPublishesNothingFurther() throws {
        let url = try writeWav(frames: [100, 200, 300, 400, 500, 600, 700, 800])
        defer { try? FileManager.default.removeItem(at: url) }
        var published: [Int] = []
        let result = WaveformReader.read(
            url: url,
            columnCount: 4,
            dual: true,
            chunkFrames: 2,
            proceed: { $0 != .betweenChunks },
            onChunk: { published.append($0.completedColumns) }
        )
        XCTAssertEqual(result.stop, .cancelled)
        XCTAssertEqual(result.chunks, 1)
        XCTAssertEqual(published.count, 1)
        XCTAssertLessThan(published[0], 4)
    }

    func testCoarseReadKeepsTheQuietHeadWhenTheColumnRunsPastTheWindow() throws {
        let inspectPerColumn = 512
        let span = inspectPerColumn + 400
        let columns = 3
        let quiet: Int16 = 1600
        let loud: Int16 = 28000
        var samples = [Int16](repeating: loud, count: span * columns)
        for column in 0..<columns {
            let start = column * span
            for frame in start..<(start + inspectPerColumn) {
                samples[frame] = quiet
            }
        }
        let url = try writeWav(frames: samples)
        defer { try? FileManager.default.removeItem(at: url) }
        var chunks = 0
        let result = WaveformReader.read(
            url: url,
            columnCount: columns,
            dual: false,
            chunkFrames: 8192,
            proceed: { _ in true },
            onChunk: { _ in chunks += 1 },
            inspectPerColumn: inspectPerColumn
        )
        XCTAssertEqual(result.stop, .finished)
        XCTAssertEqual(result.chunks, columns)
        XCTAssertEqual(chunks, columns)
        let picture = try XCTUnwrap(result.accumulator)
        let scale: Float = 32768
        let quietPeak = Float(quiet) / scale
        for column in 0..<columns {
            let peak = picture.column(lane: 0, column: column)
            XCTAssertEqual(peak.minimum, quietPeak, accuracy: 0.002)
            XCTAssertEqual(peak.maximum, quietPeak, accuracy: 0.002)
        }
    }

    func testCoarseReadMatchesTheHeadWhenTheColumnFitsTheWindow() throws {
        let span = 100
        let columns = 3
        var samples = [Int16](repeating: 0, count: span * columns)
        for column in 0..<columns {
            let start = column * span
            samples[start] = Int16(-(column + 1) * 1000)
            samples[start + span / 2] = Int16((column + 1) * 1500)
            samples[start + span - 1] = Int16((column + 1) * 800)
        }
        let url = try writeWav(frames: samples)
        defer { try? FileManager.default.removeItem(at: url) }
        let scale: Float = 32768
        for inspectPerColumn in [span, span + 80] {
            var chunks = 0
            let result = WaveformReader.read(
                url: url,
                columnCount: columns,
                dual: false,
                chunkFrames: 8192,
                proceed: { _ in true },
                onChunk: { _ in chunks += 1 },
                inspectPerColumn: inspectPerColumn
            )
            XCTAssertEqual(result.stop, .finished)
            XCTAssertEqual(result.chunks, columns)
            XCTAssertEqual(chunks, columns)
            let picture = try XCTUnwrap(result.accumulator)
            for column in 0..<columns {
                let start = column * span
                let head = samples[start..<(start + span)]
                let low = try XCTUnwrap(head.min())
                let high = try XCTUnwrap(head.max())
                let peak = picture.column(lane: 0, column: column)
                XCTAssertEqual(peak.minimum, Float(low) / scale, accuracy: 0.002)
                XCTAssertEqual(peak.maximum, Float(high) / scale, accuracy: 0.002)
            }
        }
    }

    private func writeWav(frames: [Int16]) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audiopeek-wave-\(UUID().uuidString).wav")
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
        return url
    }
}
