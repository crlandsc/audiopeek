import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private var updateItem: NSMenuItem?
    private let updates: UpdateController
    private let onSettings: () -> Void
    private var pendingWatch: AnyCancellable?

    init(updates: UpdateController, onSettings: @escaping () -> Void) {
        self.updates = updates
        self.onSettings = onSettings
        super.init()
        pendingWatch = updates.$pending.sink { [weak self] pending in
            self?.refresh(pending)
        }
    }

    var isVisible: Bool { item != nil }

    var menuTitles: [String] {
        item?.menu?.items.map(\.title).filter { !$0.isEmpty } ?? []
    }

    var statusImageIsTemplate: Bool {
        item?.button?.image?.isTemplate == true
    }

    var statusImageSize: NSSize {
        item?.button?.image?.size ?? .zero
    }

    var statusButtonTitle: String {
        item?.button?.title ?? ""
    }

    /// True while the menu bar eye carries the update dot.
    private(set) var showsUpdateDot = false

    func setVisible(_ visible: Bool) {
        if visible {
            installIfNeeded()
        } else {
            remove()
        }
    }

    private func installIfNeeded() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        let settings = NSMenuItem(title: "AudioPeek Settings", action: #selector(openSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let update = NSMenuItem(title: updates.menuTitle, action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        self.item = item
        updateItem = update
        refresh(updates.pending)
    }

    private func refresh(_ pending: PendingUpdate?) {
        showsUpdateDot = pending != nil
        updateItem?.title = updates.menuTitle(for: pending)
        item?.button?.image = PlaywaveMark.menuBarImage(updateDot: showsUpdateDot)
    }

    private func remove() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
        updateItem = nil
    }

    @objc private func openSettings(_ sender: Any?) {
        onSettings()
    }

    /// Chooses the update item as a click would, for tests.
    func chooseUpdateItem() {
        guard let updateItem else { return }
        checkForUpdates(updateItem)
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updates.act()
    }
}
