import AppKit
import Foundation

struct HotkeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let optionSpace = HotkeyCombo(keyCode: 49, carbonModifiers: optionKey)
    static let controlOptionSpace = HotkeyCombo(
        keyCode: 49,
        carbonModifiers: controlKey | optionKey
    )

    static let commandKey: UInt32 = 256
    static let shiftKey: UInt32 = 512
    static let optionKey: UInt32 = 2048
    static let controlKey: UInt32 = 4096

    var isBareSpace: Bool {
        keyCode == 49 && (carbonModifiers & Self.modifierMask) == 0
    }

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & Self.controlKey != 0 { parts.append("Control") }
        if carbonModifiers & Self.optionKey != 0 { parts.append("Option") }
        if carbonModifiers & Self.shiftKey != 0 { parts.append("Shift") }
        if carbonModifiers & Self.commandKey != 0 { parts.append("Command") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "-")
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers & Self.modifierMask
    }

    init(event: NSEvent) {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= Self.commandKey }
        if event.modifierFlags.contains(.shift) { modifiers |= Self.shiftKey }
        if event.modifierFlags.contains(.option) { modifiers |= Self.optionKey }
        if event.modifierFlags.contains(.control) { modifiers |= Self.controlKey }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
    }

    private static let modifierMask = commandKey | shiftKey | optionKey | controlKey

    private static func keyName(for keyCode: UInt32) -> String {
        if let name = namedKeys[keyCode] {
            return name
        }
        return "Key \(keyCode)"
    }

    private static let namedKeys: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
        36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
    ]
}
