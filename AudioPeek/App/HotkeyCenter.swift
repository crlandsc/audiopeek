import Carbon
import Foundation

final class HotkeyCenter {
    var onViewer: () -> Void = {}
    var onEscape: () -> Void = {}

    private(set) var carbonDeliveries = 0
    private(set) var viewerStatus: OSStatus = 1
    private(set) var escapeRegistered = false
    private(set) var viewerCombo: HotkeyCombo?
    private(set) var lastProbeStatus: OSStatus = 0
    private var viewerRef: EventHotKeyRef?
    private var escapeRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var installed = false

    private let viewerID = EventHotKeyID(signature: HotkeyCenter.four("APk1"), id: 1)
    private let escapeID = EventHotKeyID(signature: HotkeyCenter.four("APk2"), id: 2)

    func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                center.noteFromCarbon(id: hotKeyID.id)
                return noErr
            },
            1,
            &spec,
            pointer,
            &handlerRef
        )
    }

    @discardableResult
    func registerViewer(_ combo: HotkeyCombo) -> OSStatus {
        if let viewerRef {
            UnregisterEventHotKey(viewerRef)
            self.viewerRef = nil
            viewerCombo = nil
        }
        if combo.isBareSpace || Self.isUnmodifiedArrow(combo) {
            viewerStatus = OSStatus(paramErr)
            return OSStatus(paramErr)
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            viewerID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        viewerStatus = status
        if status == noErr {
            viewerRef = ref
            viewerCombo = combo
        }
        return status
    }

    func unregisterViewer() {
        if let viewerRef {
            UnregisterEventHotKey(viewerRef)
            self.viewerRef = nil
        }
        viewerCombo = nil
        viewerStatus = 1
    }

    func setEscapeEnabled(_ enabled: Bool) {
        if enabled {
            guard escapeRef == nil else {
                escapeRegistered = true
                return
            }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(53, 0, escapeID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr {
                escapeRef = ref
                escapeRegistered = true
            } else {
                escapeRegistered = false
            }
            return
        }
        if let escapeRef {
            UnregisterEventHotKey(escapeRef)
            self.escapeRef = nil
        }
        escapeRegistered = false
    }

    func probe(_ combo: HotkeyCombo) -> OSStatus {
        if combo.isBareSpace || Self.isUnmodifiedArrow(combo) {
            lastProbeStatus = OSStatus(paramErr)
            return OSStatus(paramErr)
        }
        var ref: EventHotKeyRef?
        let probeID = EventHotKeyID(signature: Self.four("APk9"), id: 9)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            probeID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            UnregisterEventHotKey(ref)
        }
        lastProbeStatus = status
        return status
    }

    func postViewerEvent() {
        post(id: viewerID)
    }

    func postEscapeEvent() {
        post(id: escapeID)
    }

    private func post(id: EventHotKeyID) {
        var event: EventRef?
        let created = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            UInt32(kEventHotKeyPressed),
            0,
            EventAttributes(kEventAttributeNone),
            &event
        )
        guard created == noErr, let event else { return }
        var hotKeyID = id
        SetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size,
            &hotKeyID
        )
        SendEventToEventTarget(event, GetApplicationEventTarget())
        ReleaseEvent(event)
    }

    private func noteFromCarbon(id: UInt32) {
        carbonDeliveries += 1
        let deliver = {
            if id == self.escapeID.id {
                self.onEscape()
            } else if id == self.viewerID.id {
                self.onViewer()
            }
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }

    private static func isUnmodifiedArrow(_ combo: HotkeyCombo) -> Bool {
        guard combo.carbonModifiers == 0 else { return false }
        return combo.keyCode == 123 || combo.keyCode == 124 || combo.keyCode == 125 || combo.keyCode == 126
    }

    private static func four(_ text: String) -> OSType {
        var value: OSType = 0
        for byte in text.utf8.prefix(4) {
            value = (value << 8) | OSType(byte)
        }
        return value
    }
}
