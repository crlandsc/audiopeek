import AVFAudio
import XCTest
@testable import AudioPeek

/// Each newly supported format decodes through both readers the app uses: the ExtAudioFile
/// read behind the waveform and spectrogram, and the AVAudioFile read behind playback.
/// The files are only read here, never played.
final class FormatDecodeTests: XCTestCase {
    private var written: [URL] = []

    override func tearDown() {
        for url in written {
            try? FileManager.default.removeItem(at: url)
        }
        written = []
        super.tearDown()
    }

    /// Ogg Vorbis, stereo 44.1 kHz, 1 s of a 440 Hz sine at -20 dBFS (made with ffmpeg).
    func testOggVorbisDecodes() throws {
        try assertDecodes(fixture("tone-vorbis", "ogg"), sampleRate: 44_100, channels: 2)
    }

    /// Opus inside `.ogg`, mono 48 kHz, 1 s of a 440 Hz sine at -20 dBFS (made with ffmpeg).
    func testOpusInOggDecodes() throws {
        try assertDecodes(fixture("tone-opus", "ogg"), sampleRate: 48_000, channels: 1)
    }

    /// A QuickTime movie with an MJPEG video track and a mono AAC track. Only the audio is read.
    func testMovWithVideoDecodesItsAudio() throws {
        try assertDecodes(fixture("tone-with-video", "mov"), sampleRate: 44_100, channels: 1)
    }

    func testCafDecodes() throws {
        let url = try writeTone(extension: "caf", settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ])
        try assertDecodes(url, sampleRate: 44_100, channels: 2)
    }

    func testAdtsAacDecodes() throws {
        let url = try writeTone(extension: "aac", settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
        ])
        // ADTS has no edit list, so the encoder's priming and padding (about 70 ms here)
        // count toward the length.
        try assertDecodes(url, sampleRate: 44_100, channels: 1, durationTolerance: 0.1)
    }

    /// The silent fixture that `verify-panel` opens and plays, so that check stays quiet.
    func testSilentOggFixtureIsSilent() throws {
        let url = try fixture("silence", "ogg")
        let read = try XCTUnwrap(PlaybackController.readFile(at: url))
        XCTAssertEqual(read.info.duration, 3, accuracy: 0.05)
        XCTAssertEqual(try peak(of: url), 0, accuracy: 1e-4)
    }

    // MARK: - Helpers

    private func assertDecodes(
        _ url: URL,
        sampleRate: Double,
        channels: Int,
        duration: TimeInterval = 1,
        durationTolerance: TimeInterval = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let read = try XCTUnwrap(PlaybackController.readFile(at: url), "playback could not open \(url.lastPathComponent)", file: file, line: line)
        XCTAssertEqual(read.info.sampleRate, sampleRate, file: file, line: line)
        XCTAssertEqual(read.info.channels, channels, file: file, line: line)
        // Lossy codecs can pad or trim a few milliseconds at the edges.
        XCTAssertEqual(read.info.duration, duration, accuracy: durationTolerance, file: file, line: line)

        // -20 dBFS is a peak of 0.1. Codec error and Gibbs overshoot stay well inside this band.
        let peak = try peak(of: url, file: file, line: line)
        XCTAssertGreaterThan(peak, 0.07, url.lastPathComponent, file: file, line: line)
        XCTAssertLessThan(peak, 0.14, url.lastPathComponent, file: file, line: line)
    }

    /// Reads the whole file through the waveform reader and returns the largest absolute sample.
    private func peak(of url: URL, file: StaticString = #filePath, line: UInt = #line) throws -> Float {
        let columns = 16
        let result = WaveformReader.read(
            url: url,
            columnCount: columns,
            dual: false,
            chunkFrames: 4096,
            proceed: { _ in true },
            onChunk: { _ in }
        )
        XCTAssertEqual(result.stop, .finished, url.lastPathComponent, file: file, line: line)
        let accumulator = try XCTUnwrap(result.accumulator, file: file, line: line)
        XCTAssertEqual(accumulator.completedColumns, columns, file: file, line: line)
        var peak: Float = 0
        for column in 0..<columns {
            let value = accumulator.column(lane: 0, column: column)
            peak = max(peak, abs(value.minimum), abs(value.maximum))
        }
        return peak
    }

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        let bundle = Bundle(for: FormatDecodeTests.self)
        let url = bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        return try XCTUnwrap(url, "missing test fixture \(name).\(ext)")
    }

    /// Writes 1 s of a 440 Hz sine at -20 dBFS with Core Audio's own encoder.
    private func writeTone(extension ext: String, settings: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiopeek-format-\(UUID().uuidString).\(ext)")
        written.append(url)
        let rate = settings[AVSampleRateKey] as? Double ?? 44_100
        let channels = AVAudioChannelCount(settings[AVNumberOfChannelsKey] as? Int ?? 1)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels))
        let frames = AVAudioFrameCount(rate)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let samples = try XCTUnwrap(buffer.floatChannelData?[channel])
            for frame in 0..<Int(frames) {
                samples[frame] = Float(0.1 * sin(2 * Double.pi * 440 * Double(frame) / rate))
            }
        }
        // The file closes when it goes out of scope, which finishes the encode.
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            try file.write(from: buffer)
        }
        return url
    }
}
