import ServiceManagement
import XCTest
@testable import AudioPeek

@MainActor
final class FakeLoginRegistrar: LoginRegistrar {
    var status: SMAppService.Status = .notRegistered
    var registerError: NSError?
    var statusAfterRegister: SMAppService.Status = .enabled
    var registerCount = 0
    var unregisterCount = 0
    var openCount = 0

    func register() throws {
        registerCount += 1
        if let registerError {
            throw registerError
        }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openCount += 1
    }
}

@MainActor
final class LoginItemTests: XCTestCase {
    private var box: DefaultsBox?

    override func tearDown() {
        box?.close()
        box = nil
        super.tearDown()
    }

    private func makePair(registrar: FakeLoginRegistrar) -> (SettingsStore, LoginItemController) {
        let box = DefaultsBox()
        self.box = box
        let store = SettingsStore(defaults: box.defaults)
        return (store, LoginItemController(store: store, registrar: registrar))
    }

    func testInvalidSignatureOffersLoginItemsAndDoesNotShowRegistered() {
        let registrar = FakeLoginRegistrar()
        registrar.registerError = NSError(domain: SMAppServiceErrorDomain as String, code: LoginServiceCode.invalidSignature)
        let (store, login) = makePair(registrar: registrar)
        login.setEnabled(true)
        XCTAssertTrue(store.blob.loginItemEnabled)
        XCTAssertEqual(store.loginPresentation, .needsManual)
        XCTAssertFalse(store.loginPresentation.showsRegistered)
        XCTAssertTrue(store.loginPresentation.offersLoginItems)
        XCTAssertEqual(store.loginPresentation.buttonTitle, "Open Login Items")
        XCTAssertFalse(store.loginPresentation.message.contains("Registered"))
        XCTAssertTrue(store.loginPresentation.message.contains("Login Items"))
        XCTAssertEqual(store.lastLoginErrorCode, LoginServiceCode.invalidSignature)
        login.openSystemSettings()
        XCTAssertEqual(registrar.openCount, 1)
    }

    func testOtherFailureUsesTheSameLoginItemsPath() {
        let registrar = FakeLoginRegistrar()
        registrar.registerError = NSError(domain: SMAppServiceErrorDomain as String, code: LoginServiceCode.internalFailure)
        let (store, login) = makePair(registrar: registrar)
        login.setEnabled(true)
        XCTAssertTrue(store.blob.loginItemEnabled)
        XCTAssertEqual(store.loginPresentation, .needsManual)
        XCTAssertFalse(store.loginPresentation.showsRegistered)
        XCTAssertEqual(store.lastLoginErrorCode, LoginServiceCode.internalFailure)
        login.openSystemSettings()
        XCTAssertEqual(registrar.openCount, 1)
    }

    func testRequiresApprovalDoesNotShowRegistered() {
        let registrar = FakeLoginRegistrar()
        registrar.statusAfterRegister = .requiresApproval
        let (store, login) = makePair(registrar: registrar)
        login.setEnabled(true)
        XCTAssertEqual(store.loginPresentation, .needsManual)
        XCTAssertFalse(store.loginPresentation.showsRegistered)
        XCTAssertTrue(store.loginPresentation.offersLoginItems)
    }

    func testSuccessfulRegistrationShowsRegistered() {
        let registrar = FakeLoginRegistrar()
        let (store, login) = makePair(registrar: registrar)
        login.setEnabled(true)
        XCTAssertEqual(store.loginPresentation, .registered)
        XCTAssertTrue(store.loginPresentation.showsRegistered)
        XCTAssertFalse(store.loginPresentation.offersLoginItems)
        XCTAssertEqual(registrar.registerCount, 1)
        XCTAssertEqual(registrar.status, .enabled)
    }

    func testAlreadyRegisteredShowsRegistered() {
        let registrar = FakeLoginRegistrar()
        registrar.status = .enabled
        registrar.registerError = NSError(domain: SMAppServiceErrorDomain as String, code: LoginServiceCode.alreadyRegistered)
        let (store, login) = makePair(registrar: registrar)
        login.setEnabled(true)
        XCTAssertEqual(store.loginPresentation, .registered)
        XCTAssertNil(store.lastLoginErrorCode)
    }

    func testTurningLoginOffUnregisters() {
        let registrar = FakeLoginRegistrar()
        let (store, login) = makePair(registrar: registrar)
        login.setEnabled(true)
        login.setEnabled(false)
        XCTAssertFalse(store.blob.loginItemEnabled)
        XCTAssertEqual(store.loginPresentation, .off)
        XCTAssertEqual(registrar.unregisterCount, 1)
    }

    func testFirstSuccessfulOpenAttemptsRegistrationOnce() {
        let registrar = FakeLoginRegistrar()
        registrar.registerError = NSError(domain: SMAppServiceErrorDomain as String, code: LoginServiceCode.invalidSignature)
        let (store, login) = makePair(registrar: registrar)
        login.noteFirstSuccessfulAudioOpen()
        XCTAssertTrue(store.blob.didAttemptFirstLoginRegistration)
        XCTAssertTrue(store.blob.loginItemEnabled)
        XCTAssertEqual(store.loginPresentation, .needsManual)
        XCTAssertEqual(registrar.registerCount, 1)
        login.noteFirstSuccessfulAudioOpen()
        XCTAssertEqual(registrar.registerCount, 1)
    }

    func testResetTurnsLoginOffAndUnregisters() {
        let registrar = FakeLoginRegistrar()
        let (store, login) = makePair(registrar: registrar)
        login.setEnabled(true)
        store.setVolume(0.3)
        login.reset()
        XCTAssertFalse(store.blob.loginItemEnabled)
        XCTAssertEqual(store.loginPresentation, .off)
        XCTAssertEqual(registrar.unregisterCount, 1)
        XCTAssertEqual(store.storedVolume, 0.3)
        XCTAssertEqual(store.blob.hotkey.displayString, "Option-Space")
    }

}
