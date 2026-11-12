import Carbon
import Foundation

enum FinderRead: Equatable {
    case files([URL])
    case failed(Int32)

    /// AudioPeek is not allowed to control Finder (Privacy & Security > Automation).
    var isPermissionDenied: Bool {
        self == .failed(Int32(errAEEventNotPermitted))
    }
}

protocol FinderSelectionSource: AnyObject {
    func requestSelection(_ completion: @escaping (FinderRead) -> Void)
}

enum FinderSelectionEvent {
    static func make() -> NSAppleEventDescriptor {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kAECoreSuite),
            eventID: AEEventID(kAEGetData),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        var container = AEDesc()
        AECreateDesc(typeNull, nil, 0, &container)
        // typeType stores the host-endian OSType. A big-endian swap asks Finder for "eles".
        var code = OSType(0x73656C65)
        var keyData = AEDesc()
        withUnsafeBytes(of: &code) { raw in
            _ = AECreateDesc(typeType, raw.baseAddress, raw.count, &keyData)
        }
        var specifier = AEDesc()
        let created = CreateObjSpecifier(
            DescType(cProperty),
            &container,
            DescType(formPropertyID),
            &keyData,
            true,
            &specifier
        )
        if created != noErr {
            return event
        }
        let object = NSAppleEventDescriptor(aeDescNoCopy: &specifier)
        event.setParam(object, forKeyword: AEKeyword(keyDirectObject))
        event.setParam(typeCode(typeFileURL), forKeyword: AEKeyword(keyAERequestedType))
        return event
    }

    private static func typeCode(_ code: OSType) -> NSAppleEventDescriptor {
        var value = code
        let data = withUnsafeBytes(of: &value) { Data($0) }
        return NSAppleEventDescriptor(descriptorType: typeType, data: data) ?? NSAppleEventDescriptor(string: "")
    }
}

final class SystemFinderSelection: FinderSelectionSource {
    private let template: NSAppleEventDescriptor
    private let queue = DispatchQueue(label: "com.landschoot.audiopeek.finder")

    init(event: NSAppleEventDescriptor = FinderSelectionEvent.make()) {
        template = event
    }

    func requestSelection(_ completion: @escaping (FinderRead) -> Void) {
        let event = duplicate(template)
        queue.async {
            let result = Self.send(event)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func duplicate(_ event: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        guard let source = event.aeDesc else { return event }
        var copy = AEDesc()
        let status = AEDuplicateDesc(source, &copy)
        guard status == noErr else { return event }
        return NSAppleEventDescriptor(aeDescNoCopy: &copy)
    }

    private static func send(_ event: NSAppleEventDescriptor) -> FinderRead {
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 60)
        } catch {
            return .failed(Int32((error as NSError).code))
        }
        if let number = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, number != 0 {
            return .failed(number)
        }
        return .files(urls(from: reply))
    }

    private static func urls(from reply: NSAppleEventDescriptor) -> [URL] {
        let direct = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) ?? reply
        if let url = fileURL(from: direct) {
            return [url]
        }
        let count = direct.numberOfItems
        guard count > 0 else { return [] }
        var found: [URL] = []
        for index in 1...count {
            guard let item = direct.atIndex(index), let url = fileURL(from: item) else { continue }
            found.append(url)
        }
        return found
    }

    private static func fileURL(from descriptor: NSAppleEventDescriptor) -> URL? {
        if let url = descriptor.fileURLValue {
            return url
        }
        return descriptor.coerce(toDescriptorType: typeFileURL)?.fileURLValue
    }
}

final class ScriptedFinderSelection: FinderSelectionSource {
    enum Script: Equatable {
        case urls([URL])
        case denied
        case failed
    }

    var script: Script

    init(script: Script) {
        self.script = script
    }

    func requestSelection(_ completion: @escaping (FinderRead) -> Void) {
        let script = self.script
        DispatchQueue.global(qos: .userInitiated).async {
            let result: FinderRead
            switch script {
            case .urls(let urls):
                result = .files(urls)
            case .denied:
                result = .failed(Int32(errAEEventNotPermitted))
            case .failed:
                result = .failed(-1)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func set(mode: String, paths: [String]) {
        switch mode {
        case "denied":
            script = .denied
        case "failed":
            script = .failed
        default:
            script = .urls(paths.map { URL(fileURLWithPath: $0) })
        }
    }
}
