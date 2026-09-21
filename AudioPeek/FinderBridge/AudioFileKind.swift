import Foundation

enum AudioFileKind {
    static let extensions: Set<String> = ["wav", "aif", "aiff", "mp3", "m4a", "mp4", "flac", "opus"]

    static func isSupportedExtension(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func metadataLabel(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav":
            return "WAV"
        case "aif", "aiff":
            return "AIFF"
        case "mp3":
            return "MP3"
        case "m4a":
            return "M4A"
        case "mp4":
            return "MP4"
        case "flac":
            return "FLAC"
        case "opus":
            return "Opus"
        default:
            return ""
        }
    }

    static func metadataLine(format: String, sampleRate: Double, channels: Int, duration: TimeInterval) -> String {
        let khz = sampleRate / 1000
        let rate: String
        if abs(khz.rounded() - khz) < 0.05 {
            rate = "\(Int(khz.rounded())) kHz"
        } else {
            rate = String(format: "%.1f kHz", khz)
        }
        let whole = max(0, Int(duration.rounded(.down)))
        let clock = "\(whole / 60):" + String(format: "%02d", whole % 60)
        return "\(format) · \(rate) · \(channels) ch · \(clock)"
    }
}
