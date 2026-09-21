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
        XCTAssertEqual(
            SelectionDecisionMaker.decide(facts: [localFile(URL(fileURLWithPath: "/tmp/song.ogg"))]),
            .dismiss
        )
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
        for name in ["a.wav", "a.aif", "a.aiff", "a.mp3", "a.m4a", "a.mp4", "a.flac", "a.opus"] {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            XCTAssertEqual(SelectionDecisionMaker.decide(facts: [localFile(url)]), .open(url), name)
        }
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
