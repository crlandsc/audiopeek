import AppKit
import SwiftUI

/// Holds the current pane from the top down. The pane is never shorter than its content, so while
/// the window is still growing it is clipped at the bottom instead of being centered, and while the
/// window shrinks it fills the window so closing rows can finish animating.
private final class SettingsContainerView: NSView {
    override var isFlipped: Bool { true }

    var paneHeight: CGFloat = 0 {
        didSet {
            if paneHeight != oldValue {
                layoutPane()
            }
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutPane()
    }

    func layoutPane() {
        for view in subviews {
            view.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(bounds.height, paneHeight))
        }
    }
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
    private(set) var window: NSWindow?
    private var paneViews: [SettingsPane: NSHostingView<SettingsPaneView>] = [:]
    private var paneHeights: [SettingsPane: CGFloat] = [:]
    private(set) var currentPane: SettingsPane = .general
    let sections = SettingsSectionState()
    private var resizeLink: CADisplayLink?
    private var resizeFrom = NSRect.zero
    private var resizeTo = NSRect.zero
    private var resizeStart: CFTimeInterval = 0
    private var resizeCompletion: (() -> Void)?
    /// Each pane's height with its Advanced section closed, so closing can shrink to it first.
    private var collapsedHeights: [SettingsPane: CGFloat] = [:]

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
        finishPendingClose()
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
            // While the window grows, the pane extends past its bottom edge. Without this, SwiftUI
            // treats that part as a safe area and nudges the whole form down mid-animation.
            view.safeAreaRegions = []
            paneViews[pane] = view
        }
        self.window = window
        sections.closeOver = { [weak self] pane, done in
            guard let self else { return done() }
            self.closeOver(pane, then: done)
        }
        sections.reopen = { [weak self] pane in
            guard let self, pane == self.currentPane else { return }
            self.resizeCompletion = nil
            self.fit(animate: true)
        }
        select(currentPane, animate: false)
        window.center()
        return window
    }

    private func paneHeightChanged(_ pane: SettingsPane, to height: CGFloat) {
        guard height > 1, paneHeights[pane] != height else { return }
        paneHeights[pane] = height
        if !sections.isShown(pane) {
            collapsedHeights[pane] = height
        }
        if pane == currentPane, let view = paneViews[pane], let container = view.superview {
            placePane(view, in: container)
            fit(animate: window?.isVisible ?? false)
        }
    }

    private func placePane(_ view: NSView, in container: NSView) {
        view.autoresizingMask = []
        if let container = container as? SettingsContainerView {
            container.paneHeight = paneHeights[currentPane] ?? view.fittingSize.height
            container.layoutPane()
        } else {
            view.frame = container.bounds
        }
    }

    /// Test hook: open or close a pane's Advanced section the way a click does.
    func setAdvanced(_ pane: SettingsPane, expanded: Bool) {
        sections.setExpanded(pane, expanded)
    }

    /// Closing Advanced: the window first shrinks over the rows, then they are removed, so the
    /// rows are covered from the bottom instead of vanishing.
    private func closeOver(_ pane: SettingsPane, then done: @escaping () -> Void) {
        guard let window, window.isVisible, pane == currentPane,
              let collapsed = collapsedHeights[pane],
              let frame = targetFrame(contentHeight: collapsed) else {
            done()
            return
        }
        animateFrame(to: frame, then: done)
    }

    private func finishPendingClose() {
        guard let done = resizeCompletion else { return }
        resizeCompletion = nil
        done()
    }

    // Size the window to the current pane, keeping its top edge fixed and staying on screen.
    private func fit(animate: Bool) {
        guard let window, let view = paneViews[currentPane] else { return }
        var height = paneHeights[currentPane] ?? 0
        if height <= 1 {
            view.layoutSubtreeIfNeeded()
            height = view.fittingSize.height
        }
        guard let frame = targetFrame(contentHeight: height) else { return }
        guard frame.size != window.frame.size || frame.origin != window.frame.origin else { return }
        guard animate else {
            resizeLink?.invalidate()
            resizeLink = nil
            window.setFrame(frame, display: true)
            return
        }
        animateFrame(to: frame)
    }

    private func targetFrame(contentHeight: CGFloat) -> NSRect? {
        guard let window, contentHeight > 1 else { return nil }
        var height = contentHeight
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
        return frame
    }

    // Our own resize animation: SwiftUI can correct a pane's height a frame after it changes,
    // and a second system window animation cuts the first one short. This one glides to the
    // new target from wherever it is, so switching panes and opening Advanced move the same way.
    private func animateFrame(to frame: NSRect, then completion: (() -> Void)? = nil) {
        guard let window else {
            completion?()
            return
        }
        resizeCompletion = completion
        resizeFrom = window.frame
        resizeTo = frame
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
        let eased = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)
        // Between two fixed frames: the top stays put unless the target had to move up to stay on screen.
        var frame = resizeTo
        frame.size.height = resizeFrom.height + (resizeTo.height - resizeFrom.height) * eased
        let top = resizeFrom.maxY + (resizeTo.maxY - resizeFrom.maxY) * eased
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true)
        if t >= 1 {
            link.invalidate()
            resizeLink = nil
            finishPendingClose()
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
