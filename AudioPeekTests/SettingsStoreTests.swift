import XCTest
@testable import AudioPeek

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var box: DefaultsBox?

    override func tearDown() {
        box?.close()
        box = nil
        super.tearDown()
    }

    private func makeStore() -> SettingsStore {
        let box = DefaultsBox()
        self.box = box
        return SettingsStore(defaults: box.defaults)
    }

    func testFreshDefaultsMatchFactoryAndDoNotWriteVolume() {
        let store = makeStore()
        XCTAssertEqual(store.blob, .factory)
        XCTAssertEqual(store.blob.hotkey.displayString, "Option-Space")
        XCTAssertNil(store.blob.spectrogram.fmax)
        XCTAssertNil(store.storedVolume)
        XCTAssertEqual(store.effectiveVolume, 1)
        XCTAssertNil(box?.defaults.object(forKey: SettingsStore.volumeKey))
        XCTAssertNil(box?.defaults.data(forKey: SettingsStore.blobKey))
    }

    func testCorruptBlobUsesFactoryAndLeavesVolume() {
        let box = DefaultsBox()
        self.box = box
        box.defaults.set(Data("not json".utf8), forKey: SettingsStore.blobKey)
        box.defaults.set(0.4, forKey: SettingsStore.volumeKey)
        let store = SettingsStore(defaults: box.defaults)
        XCTAssertEqual(store.blob, .factory)
        XCTAssertEqual(store.storedVolume, 0.4)
        XCTAssertEqual(box.defaults.double(forKey: SettingsStore.volumeKey), 0.4)
        let rewritten = try? JSONDecoder().decode(
            SettingsBlob.self,
            from: box.defaults.data(forKey: SettingsStore.blobKey) ?? Data()
        )
        XCTAssertEqual(rewritten, .factory)
    }

    func testResetOnFreshDefaultsDoesNotCreateVolumeKey() {
        let store = makeStore()
        XCTAssertFalse(store.resetKnobs())
        XCTAssertEqual(store.blob, .factory)
        XCTAssertNil(box?.defaults.object(forKey: SettingsStore.volumeKey))
    }

    func testResetRestoresKnobsAndPreservesVolumeAndFrame() {
        let store = makeStore()
        store.setVolume(0.25)
        store.update {
            $0.windowFrame = StoredWindowFrame(x: 10, y: 20, width: 860, height: 500)
            $0.didAttemptFirstLoginRegistration = true
            $0.showWaveform = false
            $0.showSpectrogram = false
            $0.waveformDual = false
            $0.spectrogramDual = true
            $0.waveformAmplitude = .decibels
            $0.waveformColor = WaveformColor(usesSystemBlue: false, red: 1, green: 0, blue: 0, alpha: 1)
            $0.splitFraction = 0.25
            $0.hotkey = HotkeyCombo(keyCode: 40, carbonModifiers: HotkeyCombo.commandKey)
            $0.showDockIcon = true
            $0.showStatusItem = false
            $0.loginItemEnabled = true
            $0.spectrogram = SpectrogramSettings(
                type: .linear,
                nFFT: 1024,
                hop: 256,
                window: .hamming,
                nMels: 64,
                fmin: 20,
                fmax: 8000,
                decibelsEnabled: false,
                dbFloor: -60,
                dbRange: 40
            )
        }
        XCTAssertTrue(store.resetKnobs())
        var expected = SettingsBlob.factory
        expected.windowFrame = StoredWindowFrame(x: 10, y: 20, width: 860, height: 500)
        expected.didAttemptFirstLoginRegistration = true
        XCTAssertEqual(store.blob, expected)
        XCTAssertEqual(store.blob.hotkey.displayString, "Option-Space")
        XCTAssertEqual(store.storedVolume, 0.25)
        XCTAssertEqual(box?.defaults.double(forKey: SettingsStore.volumeKey), 0.25)
        XCTAssertEqual(store.loginPresentation, .off)
    }

    func testStoredVolumeAboveUnityIsCappedForPlaybackAndLeftAloneByReset() {
        let box = DefaultsBox()
        self.box = box
        box.defaults.set(2.0, forKey: SettingsStore.volumeKey)
        let store = SettingsStore(defaults: box.defaults)
        XCTAssertEqual(store.storedVolume, 2)
        XCTAssertEqual(store.effectiveVolume, 1)
        _ = store.resetKnobs()
        XCTAssertEqual(store.storedVolume, 2)
        XCTAssertEqual(box.defaults.double(forKey: SettingsStore.volumeKey), 2)
        store.setVolume(1.4)
        XCTAssertEqual(store.storedVolume, 1)
        store.setVolume(-0.2)
        XCTAssertEqual(store.storedVolume, 0)
    }

    func testBareSpaceIsRejected() {
        let store = makeStore()
        XCTAssertTrue(HotkeyCombo.optionSpace.isBareSpace == false)
        XCTAssertTrue(HotkeyCombo(keyCode: 49, carbonModifiers: 0).isBareSpace)
        XCTAssertFalse(store.setHotkey(HotkeyCombo(keyCode: 49, carbonModifiers: 0)))
        XCTAssertEqual(store.blob.hotkey, .optionSpace)
        let fallback = HotkeyCombo(
            keyCode: 49,
            carbonModifiers: HotkeyCombo.controlKey | HotkeyCombo.optionKey
        )
        XCTAssertEqual(fallback.displayString, "Control-Option-Space")
        XCTAssertTrue(store.setHotkey(fallback))
        XCTAssertEqual(store.blob.hotkey.displayString, "Control-Option-Space")
    }

    func testFactoryBlobRoundTrips() throws {
        let data = try JSONEncoder().encode(SettingsBlob.factory)
        let decoded = try JSONDecoder().decode(SettingsBlob.self, from: data)
        XCTAssertEqual(decoded, .factory)
        XCTAssertEqual(decoded.spectrogram.nFFT, 2048)
        XCTAssertEqual(decoded.spectrogram.hop, 512)
        XCTAssertEqual(decoded.spectrogram.window, .hann)
        XCTAssertEqual(decoded.spectrogram.nMels, 128)
        XCTAssertEqual(decoded.spectrogram.fmin, 0)
        XCTAssertNil(decoded.spectrogram.fmax)
        XCTAssertTrue(decoded.spectrogram.decibelsEnabled)
        XCTAssertEqual(decoded.spectrogram.dbFloor, -80)
        XCTAssertEqual(decoded.spectrogram.dbRange, 80)
        XCTAssertEqual(decoded.splitFraction, 0.5)
        XCTAssertTrue(decoded.waveformColor.usesSystemBlue)
        XCTAssertFalse(decoded.showDockIcon)
        XCTAssertTrue(decoded.showStatusItem)
    }
}

@MainActor
final class DefaultsBox {
    let name: String
    let defaults: UserDefaults

    init() {
        name = "audiopeek.unit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        self.defaults = defaults
    }

    func close() {
        defaults.removePersistentDomain(forName: name)
    }
}
