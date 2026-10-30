import AppKit
import SwiftUI

/// Holds the current pane pinned to the top, so a size change reveals or hides rows at the bottom.
private final class SettingsContainerView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let paneWidth: CGFloat = 500
    /// One resize animation for switching panes and opening or closing Advanced.
    static let resizeDuration: TimeInterval = 0.25

    private let store: SettingsStore
    private let onLoginToggle: (Bool) -> Void
    private let onOpenLoginItems: () -> Void
    private let onOpenAutomation: () -> Void
    private let onReset: () -> Void
    private var window: NSWindow?
    private var paneViews: [SettingsPane: NSHostingView<SettingsPaneView>] = [:]
    private var paneHeights: [SettingsPane: CGFloat] = [:]
    private(set) var currentPane: SettingsPane = .general
    let sections = SettingsSectionState()
    private var resizeLink: CADisplayLink?
    private var resizeFrom: CGFloat = 0
    private var resizeTo: CGFloat = 0
    private var resizeStart: CFTimeInterval = 0

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

    var frame: NSRect {
        window?.frame ?? .zero
    }

    // Labels from every pane, not just the visible one, so tests can find any control.
    func controlLabels() -> [String] {
        guard window != nil else { return [] }
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
        for pane in SettingsPane.allCases {
            if let view = paneViews[pane] {
                view.layoutSubtreeIfNeeded()
                walk(view)
            }
        }
        return labels
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if !store.finderMessage.isEmpty {
            select(.general, animate: false)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func select(_ pane: SettingsPane, animate: Bool = true) {
        let window = self.window ?? makeWindow()
        self.window = window
        currentPane = pane
        window.toolbar?.selectedItemIdentifier = pane.toolbarIdentifier
        window.title = pane.title
        if let container = window.contentView, let view = paneViews[pane] {
            container.subviews = [view]
            placePane(view, in: container)
        }
        fit(animate: animate && window.isVisible)
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
        if let window { return window }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.paneWidth, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        // Same level as the floating preview, so Settings opens in front of it instead of behind.
        window.level = .floating
        // No autosave names: a test instance would otherwise write them into the real app's defaults.
        let toolbar = NSToolbar(identifier: "AudioPeekSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        window.contentView = SettingsContainerView(frame: NSRect(x: 0, y: 0, width: Self.paneWidth, height: 400))
        let actions = SettingsActions(
            onLoginToggle: onLoginToggle,
            onOpenLoginItems: onOpenLoginItems,
            onOpenAutomation: onOpenAutomation,
            onReset: onReset
        )
        for pane in SettingsPane.allCases {
            let view = NSHostingView(rootView: SettingsPaneView(pane: pane, store: store, sections: sections, actions: actions) { [weak self] height in
                self?.paneHeightChanged(pane, to: height)
            })
            view.sizingOptions = []
            paneViews[pane] = view
        }
        self.window = window
        select(currentPane, animate: false)
        window.center()
        return window
    }

    private func paneHeightChanged(_ pane: SettingsPane, to height: CGFloat) {
        guard height > 1, paneHeights[pane] != height else { return }
        paneHeights[pane] = height
        if pane == currentPane, let view = paneViews[pane], let container = view.superview {
            placePane(view, in: container)
            fit(animate: window?.isVisible ?? false)
        }
    }

    /// The pane keeps its natural height, pinned to the top of the window.
    private func placePane(_ view: NSView, in container: NSView) {
        let height = paneHeights[currentPane] ?? max(container.bounds.height, view.fittingSize.height)
        view.frame = NSRect(x: 0, y: 0, width: container.bounds.width, height: height)
        view.autoresizingMask = [.width, .maxYMargin]
    }

    /// Test hook: open or close a pane's Advanced section the way a click does.
    func setAdvanced(_ pane: SettingsPane, expanded: Bool) {
        sections.setExpanded(pane, expanded)
    }

    // Size the window to the current pane, keeping its top edge fixed and staying on screen.
    private func fit(animate: Bool) {
        guard let window, let view = paneViews[currentPane] else { return }
        var height = paneHeights[currentPane] ?? 0
        if height <= 1 {
            view.layoutSubtreeIfNeeded()
            height = view.fittingSize.height
        }
        guard height > 1 else { return }
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let chrome = window.frame.height - window.contentLayoutRect.height
        if let visible {
            height = min(height, visible.height - chrome)
        }
        let content = NSSize(width: Self.paneWidth, height: ceil(height))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin.x = window.frame.minX
        frame.origin.y = window.frame.maxY - frame.height
        if let visible, frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        guard frame.size != window.frame.size || frame.origin != window.frame.origin else { return }
        guard animate else {
            resizeLink?.invalidate()
            resizeLink = nil
            window.setFrame(frame, display: true)
            return
        }
        animateHeight(to: frame.height)
    }

    // Our own resize animation: SwiftUI can correct a pane's height a frame after it changes,
    // and a second system window animation cuts the first one short. This one glides to the
    // new target from wherever it is, so switching panes and opening Advanced move the same way.
    private func animateHeight(to height: CGFloat) {
        guard let window else { return }
        resizeFrom = window.frame.height
        resizeTo = height
        resizeStart = CACurrentMediaTime()
        guard resizeLink == nil else { return }
        let link = window.displayLink(target: self, selector: #selector(resizeStep(_:)))
        link.add(to: .main, forMode: .common)
        resizeLink = link
    }

    @objc private func resizeStep(_ link: CADisplayLink) {
        guard let window else {
            link.invalidate()
            resizeLink = nil
            return
        }
        let t = min(1, (CACurrentMediaTime() - resizeStart) / Self.resizeDuration)
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        let height = resizeFrom + (resizeTo - resizeFrom) * CGFloat(eased)
        var frame = window.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        if let visible = window.screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = visible.minY
        }
        window.setFrame(frame, display: true)
        if t >= 1 {
            link.invalidate()
            resizeLink = nil
        }
    }

    // MARK: NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = SettingsPane.allCases.first(where: { $0.toolbarIdentifier == itemIdentifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(paneItemPressed(_:))
        return item
    }

    @objc private func paneItemPressed(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane.allCases.first(where: { $0.toolbarIdentifier == sender.itemIdentifier }) else { return }
        select(pane)
    }
}
