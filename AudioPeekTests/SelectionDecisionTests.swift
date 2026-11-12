import XCTest
@testable import AudioPeek

final class SelectionDecisionTests: XCTestCase {
    func testExactlyOneLocalAudioFileOpens() {
        let url = URL(fileURLWithPath: "/tmp/one.wav")
        let decision = SelectionDecisionMaker.decide(facts: [localFile(url)])
        XCTAssertEqual(decision, .open(url))
    }

    func testEmptyMixedMultiAndNonAudioDismiss() {
        let wav = URL(fileURLWithPath: "/tmp/a.wav")
        let other = URL(fileURLWithPath: "/tmp/notes.txt")
        XCTAssertEqual(SelectionDecisionMaker.decide(facts: []), .dismiss)
        XCTAssertEqual(SelectionDecisionMaker.decide(facts: [localFile(wav), localFile(wav)]), .dismiss)
        XCTAssertEqual(SelectionDecisionMaker.decide(facts: [localFile(wav), localFile(other)]), .dismiss)
        XCTAssertEqual(SelectionDecisionMaker.decide(facts: [localFile(other)]), .dismiss)
    }

    func testFormatsCoreAudioCannotReadDismiss() {
        // .mkv, .webm and .wma need a bundled decoder. .oga opens but reports no length.
        for name in ["a.mkv", "a.webm", "a.wma", "a.oga"] {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            XCTAssertEqual(SelectionDecisionMaker.decide(facts: [localFile(url)]), .dismiss, name)
        }
    }

    func testHeaderLabelsForEverySupportedFormat() {
        for ext in AudioFileKind.extensions {
            let url = URL(fileURLWithPath: "/tmp/a.\(ext)")
            XCTAssertFalse(AudioFileKind.metadataLabel(for: url).isEmpty, ext)
        }
        XCTAssertEqual(AudioFileKind.metadataLabel(for: URL(fileURLWithPath: "/tmp/a.ogg")), "Ogg")
        XCTAssertEqual(AudioFileKind.metadataLabel(for: URL(fileURLWithPath: "/tmp/a.MOV")), "MOV")
        XCTAssertEqual(AudioFileKind.metadataLabel(for: URL(fileURLWithPath: "/tmp/a.aac")), "AAC")
        XCTAssertEqual(AudioFileKind.metadataLabel(for: URL(fileURLWithPath: "/tmp/a.caf")), "CAF")
    }

    func testDirectoryPackageAndRemoteDismiss() {
        let wav = URL(fileURLWithPath: "/tmp/folder.wav")
        XCTAssertEqual(
            SelectionDecisionMaker.decide(facts: [SelectionFacts(url: wav, exists: true, isDirectory: true, isPackage: false, isUbiquitous: false, isDownloaded: false)]),
            .dismiss
        )
        XCTAssertEqual(
            SelectionDecisionMaker.decide(facts: [SelectionFacts(url: wav, exists: true, isDirectory: false, isPackage: true, isUbiquitous: false, isDownloaded: false)]),
            .dismiss
        )
        XCTAssertEqual(
            SelectionDecisionMaker.decide(facts: [SelectionFacts(url: wav, exists: true, isDirectory: false, isPackage: false, isUbiquitous: true, isDownloaded: false)]),
            .dismiss
        )
    }

    func testSupportedExtensions() {
        for name in [
            "a.wav", "a.aif", "a.aiff", "a.mp3", "a.m4a", "a.mp4", "a.flac", "a.opus",
            "a.ogg", "a.mov", "a.aac", "a.caf", "a.OGG",
        ] {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            XCTAssertEqual(SelectionDecisionMaker.decide(facts: [localFile(url)]), .open(url), name)
        }
    }

    func testAppBundleDocumentTypesListSupportedExtensions() throws {
        let bundle = try XCTUnwrap(hostAppBundle(), "AudioPeek.app was not the test host")
        let types = try XCTUnwrap(bundle.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]])
        var extensions = Set<String>()
        for type in types {
            let listed = type["CFBundleTypeExtensions"] as? [String] ?? []
            extensions.formUnion(listed.map { $0.lowercased() })
        }
        XCTAssertEqual(extensions, AudioFileKind.extensions)
    }

    func testRealFileOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-selection-\(UUID().uuidString).wav")
        try Data([0]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(SelectionDecisionMaker.decide([url]), .open(url))
        let text = FileManager.default.temporaryDirectory.appendingPathComponent("audiopeek-selection-\(UUID().uuidString).txt")
        try Data([0]).write(to: text)
        defer { try? FileManager.default.removeItem(at: text) }
        XCTAssertEqual(SelectionDecisionMaker.decide([text]), .dismiss)
        XCTAssertEqual(SelectionDecisionMaker.decide([url, text]), .dismiss)
    }

    private func hostAppBundle() -> Bundle? {
        if Bundle.main.bundleIdentifier == "com.landschoot.audiopeek" {
            return Bundle.main
        }
        let appURL = Bundle(for: SelectionDecisionTests.self).bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard let bundle = Bundle(url: appURL), bundle.bundleIdentifier == "com.landschoot.audiopeek" else {
            return nil
        }
        return bundle
    }

    private func localFile(_ url: URL) -> SelectionFacts {
        SelectionFacts(
            url: url,
            exists: true,
            isDirectory: false,
            isPackage: false,
            isUbiquitous: false,
            isDownloaded: false
        )
    }
}
