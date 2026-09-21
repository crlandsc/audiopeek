import Foundation
import ServiceManagement

enum LoginServiceCode {
    static let internalFailure = 2
    static let invalidSignature = 3
    static let alreadyRegistered = 12
}

@MainActor
protocol LoginRegistrar: AnyObject {
    func register() throws
    func unregister() throws
    var status: SMAppService.Status { get }
    func openSystemSettingsLoginItems()
}

@MainActor
final class SystemLoginRegistrar: LoginRegistrar {
    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class InjectedLoginRegistrar: LoginRegistrar {
    enum Mode: Equatable {
        case invalidSignature
        case other
    }

    let mode: Mode
    private(set) var openCount = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func register() throws {
        let code = mode == .invalidSignature
            ? LoginServiceCode.invalidSignature
            : LoginServiceCode.internalFailure
        throw NSError(
            domain: SMAppServiceErrorDomain as String,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "injected"]
        )
    }

    func unregister() throws {}

    var status: SMAppService.Status { .notRegistered }

    func openSystemSettingsLoginItems() {
        openCount += 1
    }
}

@MainActor
final class LoginItemController {
    private let store: SettingsStore
    private let registrar: LoginRegistrar

    init(store: SettingsStore, registrar: LoginRegistrar) {
        self.store = store
        self.registrar = registrar
    }

    func refreshFromSystem() {
        guard store.blob.loginItemEnabled else {
            store.setLoginPresentation(.off, errorCode: nil)
            return
        }
        applyStatus(errorCode: nil)
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled {
            store.update { $0.loginItemEnabled = false }
            store.setLoginPresentation(.off, errorCode: nil)
            try? registrar.unregister()
            return
        }
        store.update { $0.loginItemEnabled = true }
        do {
            try registrar.register()
            applyStatus(errorCode: nil)
        } catch {
            let code = (error as NSError).code
            if registrar.status == .enabled {
                store.setLoginPresentation(.registered, errorCode: nil)
            } else {
                store.setLoginPresentation(.needsManual, errorCode: code)
            }
        }
    }

    func openSystemSettings() {
        registrar.openSystemSettingsLoginItems()
    }

    func noteFirstSuccessfulAudioOpen() {
        guard !store.blob.didAttemptFirstLoginRegistration else { return }
        store.update { $0.didAttemptFirstLoginRegistration = true }
        setEnabled(true)
    }

    func reset() {
        let shouldUnregister = store.resetKnobs()
        if shouldUnregister {
            try? registrar.unregister()
        }
    }

    private func applyStatus(errorCode: Int?) {
        if registrar.status == .enabled {
            store.setLoginPresentation(.registered, errorCode: nil)
        } else {
            store.setLoginPresentation(.needsManual, errorCode: errorCode)
        }
    }
}
