import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private let onSettings: () -> Void

    init(onSettings: @escaping () -> Void) {
        self.onSettings = onSettings
    }

    var isVisible: Bool { item != nil }

    var menuTitles: [String] {
        item?.menu?.items.map(\.title).filter { !$0.isEmpty } ?? []
    }

    func setVisible(_ visible: Bool) {
        if visible {
            installIfNeeded()
        } else {
            remove()
        }
    }

    private func installIfNeeded() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let button = item.button
        button?.title = "AudioPeek"
        if let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AudioPeek") {
            image.isTemplate = true
            button?.image = image
            button?.imagePosition = .imageLeading
        }
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings", action: #selector(openSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        self.item = item
    }

    private func remove() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    @objc private func openSettings(_ sender: Any?) {
        onSettings()
    }
}
