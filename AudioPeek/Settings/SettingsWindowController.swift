import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let onLoginToggle: (Bool) -> Void
    private let onOpenLoginItems: () -> Void
    private let onOpenAutomation: () -> Void
    private let onReset: () -> Void
    private var window: NSWindow?

    init(
        store: SettingsStore,
        onLoginToggle: @escaping (Bool) -> Void,
        onOpenLoginItems: @escaping () -> Void,
        onOpenAutomation: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.store = store
        self.onLoginToggle = onLoginToggle
        self.onOpenLoginItems = onOpenLoginItems
        self.onOpenAutomation = onOpenAutomation
        self.onReset = onReset
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func controlLabels() -> [String] {
        guard let view = window?.contentView else { return [] }
        view.layoutSubtreeIfNeeded()
        var labels: [String] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: AnyObject) {
            let token = ObjectIdentifier(object)
            if seen.contains(token) { return }
            seen.insert(token)
            if let identifier = object.accessibilityIdentifier(), !identifier.isEmpty {
                labels.append(identifier)
            }
            if let label = object.accessibilityLabel(), !label.isEmpty {
                labels.append(label)
            }
            if let button = object as? NSButton, !button.title.isEmpty {
                labels.append(button.title)
            }
            if let field = object as? NSTextField, !field.stringValue.isEmpty {
                labels.append(field.stringValue)
            }
            if let view = object as? NSView {
                for child in view.subviews {
                    walk(child)
                }
            }
            for child in object.accessibilityChildren() ?? [] {
                walk(child as AnyObject)
            }
        }
        walk(view)
        return labels
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func writePNG(to url: URL) -> Bool {
        show()
        guard let view = window?.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 420, height: 480)
        let root = SettingsView(
            store: store,
            onLoginToggle: onLoginToggle,
            onOpenLoginItems: onOpenLoginItems,
            onOpenAutomation: onOpenAutomation,
            onReset: onReset
        )
        window.contentViewController = NSHostingController(rootView: root)
        window.center()
        return window
    }
}
