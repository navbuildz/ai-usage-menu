import AppKit
import SwiftUI
import QuartzCore

private final class UsageWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private let services = AppServices()
    private var welcome: NSWindow?
    private let store = UsageStore()
    let preferences = DisplayPreferences(defaults: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil ? .standard : UserDefaults(suiteName: "ai.aiusagemenu.tests.display")!)
    var statusItemCount: Int { items.count }
    private(set) var items: [String: NSStatusItem] = [:]
    let popover = NSPopover()
    private let panelNavigation = Navigation()
    private let windowNavigation = Navigation()
    private var sessionFrame: NSRect?
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    private var appearance: NSKeyValueObservation?
    private var eventMonitor: Any?
    private var rendered: DockSnapshot?
    private var panelID: String?

    static func main() {
        let application = NSApplication.shared
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            // One owner across Debug and Release, including simultaneous launches.
            let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AI Usage Menu")
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let lock = Darwin.open(support.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            if lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) != 0 {
                Darwin.close(lock)
                DistributedNotificationCenter.default().postNotificationName(.init("ai.aiusagemenu.reopen"), object: nil, userInfo: nil, deliverImmediately: true)
                return
            }
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        applyActivation()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenExisting), name: .init("ai.aiusagemenu.reopen"), object: nil)
        installMenus()
        popover.behavior = .transient
        popover.delegate = self
        appearance = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.preferences.objectWillChange.send()
                self.applyTheme()
                self.updateDisplays()
            }
        }
        preferences.changed = { [weak self] in self?.applyPreferences() }
        store.readingChanged = { [weak self] in self?.updateItems() }
        store.onChange = { [weak self] in self?.updateDisplays(); if let self { self.services.evaluate(self.store, health: self.preferences.options.thresholds) } }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        applyPreferences()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            services.start()
            store.start(minutes: preferences.options.refreshMinutes)
            if !UserDefaults.standard.bool(forKey: "onboardingComplete") { showWelcome() }
            else if preferences.options.placement == .hidden { showSettings() }
        }
    }

    private func showWelcome() {
        let view = Onboarding(store: store, services: services, preferences: preferences) { [weak self] in
            UserDefaults.standard.set(true, forKey: "onboardingComplete")
            self?.welcome?.close()
            self?.welcome = nil
            if self?.preferences.options.placement == .hidden { self?.showSettings() }
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Welcome to AI Usage Menu"
        w.styleMask = [.titled]
        w.appearance = preferences.options.theme.appearance
        w.isReleasedWhenClosed = false
        w.center()
        welcome = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func applyActivation() {
        let target: NSApplication.ActivationPolicy = preferences.options.placement.showsDock ? .regular : .accessory
        if NSApp.activationPolicy() != target { NSApp.setActivationPolicy(target) }
    }

    private func applyTheme() {
        let theme = preferences.options.theme.appearance
        popover.appearance = theme ?? NSApp.effectiveAppearance
        popover.contentViewController?.view.appearance = popover.appearance
        window?.appearance = theme
        settingsWindow?.appearance = theme
    }

    private func applyPreferences() {
        applyActivation()
        applyTheme()
        store.setInterval(minutes: preferences.options.refreshMinutes)
        store.setDisabled(preferences.options.disabled)
        if !preferences.options.placement.showsMenu { popover.performClose(nil) }
        updateDisplays()
    }

    private func updateDisplays() {
        updateItems()
        let options = preferences.options
        if !options.placement.showsDock {
            if rendered != nil { NSApp.dockTile.contentView = nil; rendered = nil }
            return
        }
        var snapshot = DockSnapshot.resolve(providers: store.displayProviders, snapshots: store.snapshots, options: options, now: .now)
        snapshot.light = (options.dockTheme.appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua,.darkAqua]) == .aqua
        let tile = NSApp.dockTile
        guard rendered != snapshot else { return }
        rendered = snapshot
        if snapshot.indicator == .absent && !snapshot.light { tile.contentView = nil }
        else {
            let view = NSImageView(frame: .init(origin: .zero, size: tile.size))
            view.imageScaling = .scaleProportionallyUpOrDown
            view.image = DockIconRenderer.image(for: snapshot, size: max(32, Int(tile.size.width * (NSScreen.main?.backingScaleFactor ?? 1))))
            tile.contentView = view
        }
        tile.display()
    }

    private func updateItems() {
        let options = preferences.options
        let separate = options.separateItems && !store.displayProviders.isEmpty
        let keys = !options.placement.showsMenu ? [] : (separate ? store.displayProviders.map(\.id) : ["auto"])
        // AppKit inserts new status items on the left. Recreate the group when
        // membership changes so enabling a provider restores the tab order.
        if Set(items.keys) != Set(keys) {
            if popover.isShown { popover.performClose(nil) }
            for item in items.values { NSStatusBar.system.removeStatusItem(item) }
            items.removeAll()
        }
        for key in keys.reversed() {
            let item = items[key] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            items[key] = item
            guard let button = item.button else { continue }
            button.target = self
            button.action = #selector(openPanel(_:))
            let provider = store.providers.first { $0.id == key }
            let value = store.menuValue(key, options: options)
            let pair = options.twoMenuNumbers && options.showPercent ? store.menuPair(key, options: options) : nil
            let visual = MenuItemVisual(value: value, pair: pair, provider: provider, options: options, appearance: button.effectiveAppearance)
            button.title = visual.title
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.image = visual.image
            button.contentTintColor = visual.iconTint
            button.imagePosition = visual.title.isEmpty ? .imageOnly : .imageLeading
            let description = (provider?.displayName ?? "AI Usage Menu") + ", " + (visual.usageDescription ?? (value.percent.map { $0.compactUsage + " percent used" } ?? "Usage unavailable"))
            let shownID = provider?.id ?? (value.percent != nil ? store.enabled.first { $0.glyph == { if case let .value(_, g) = value { return g }; return "" }() }?.id : nil)
            let stale = shownID.flatMap { id in store.snapshots[id].map { $0.isStale(providerID: id, at: .now) } } ?? false
            button.alphaValue = stale ? 0.55 : 1
            let staleNote = stale ? ", from the last Codex session" : ""
            button.setAccessibilityLabel(description + staleNote)
            button.toolTip = description + staleNote
            button.wantsLayer = true
            let pulse = key == "auto" ? !store.active.isEmpty : store.active.contains(key)
            if pulse && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                if button.layer?.animation(forKey: "reading") == nil {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = 1; fade.toValue = 0.65; fade.duration = 0.7; fade.autoreverses = true; fade.repeatCount = .infinity
                    button.layer?.add(fade, forKey: "reading")
                }
            } else { button.layer?.removeAnimation(forKey: "reading") }
        }
    }

    private func usage(_ navigation: Navigation) -> NSHostingController<UsageView> {
        let inPopover = navigation === panelNavigation
        let controller = NSHostingController(rootView: UsageView(store: store, preferences: preferences, navigation: navigation, settings: { [weak self] in self?.showSettings() }, close: { [weak self] in
            guard let self else { return }
            if navigation === panelNavigation { popover.performClose(nil) } else { window?.close() }
        }, fitsContent: inPopover))
        // The popover follows the view's size, so short tabs and messages leave no empty block.
        if inPopover { controller.sizingOptions = [.preferredContentSize] }
        return controller
    }

    @objc private func openPanel(_ sender: NSStatusBarButton) {
        let id = items.first { $0.value.button === sender }?.key ?? "auto"
        if popover.isShown {
            let same = panelID == id
            popover.performClose(nil)
            if same { return }
        }
        panelID = id
        if id != "auto" { panelNavigation.select(id) }
        else if case let .value(_, glyph) = store.menuValue("auto", options: preferences.options), let winner = store.enabled.first(where: { $0.glyph == glyph }) { panelNavigation.select(winner.id) }
        store.opened()
        popover.contentViewController = usage(panelNavigation)
        popover.contentViewController?.view.appearance = popover.appearance
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil; panelID = nil }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let welcome { welcome.makeKeyAndOrderFront(nil); return true }
        if !preferences.options.placement.showsDock { showSettings(); return true }
        store.opened()
        if window == nil {
            let w = UsageWindow(contentRect: .init(x: 0, y: 0, width: 390, height: 525), styleMask: [.borderless,.resizable], backing: .buffered, defer: false)
            w.minSize = .init(width: 380, height: 455)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.title = "AI Usage Menu"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.appearance = preferences.options.theme.appearance
            w.isRestorable = false
            window = w
        }
        if window?.contentViewController == nil { window?.contentViewController = usage(windowNavigation) }
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.cornerRadius = 18
        window?.contentView?.layer?.masksToBounds = true
        if let window, !window.isVisible {
            position(window, previous: sessionFrame)
        }
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        if let window, window.isVisible { position(window, previous: window.frame) }
    }

    private func position(_ window: NSWindow, previous: NSRect?) {
        let screens = NSScreen.screens
        guard let active = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let frame = Self.windowFrame(previous: previous, visibleFrames: screens.map(\.visibleFrame), active: active.visibleFrame)
        if window.frame != frame { window.setFrame(frame, display: true) }
    }

    static func windowFrame(previous: NSRect?, visibleFrames: [NSRect], active: NSRect) -> NSRect {
        let previousScreen = previous.flatMap { frame in
            visibleFrames.filter { $0.intersects(frame) }.max {
                $0.intersection(frame).area < $1.intersection(frame).area
            }
        }
        let area = previousScreen ?? active
        let size = previous?.size ?? NSSize(width: 390, height: 525)
        let width = min(size.width, area.width), height = min(size.height, area.height)
        let center = NSPoint(x: area.midX - width / 2, y: area.midY - height / 2)
        let origin = previousScreen == nil ? center : previous?.origin ?? center
        return NSRect(x: max(area.minX, min(origin.x, area.maxX - width)),
                      y: max(area.minY, min(origin.y, area.maxY - height)), width: width, height: height)
    }

    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w === window { sessionFrame = w.frame; w.contentViewController = nil }
    }

    @objc func showSettings() {
        if let welcome { welcome.makeKeyAndOrderFront(nil); return }
        services.syncLogin()
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: DisplaySettings(preferences: preferences, store: store, services: services)))
            w.appearance = preferences.options.theme.appearance
            w.titlebarAppearsTransparent = true
            w.backgroundColor = NSColor(named: "background")
            w.title = "AI Usage Menu Settings"
            w.styleMask = [.titled,.closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func handle(_ event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers {
            case "w":
                if popover.isShown { popover.performClose(nil) }
                else if let window, event.window === window { window.close() }
                else { return false }
            case "r": refresh()
            case ",": showSettings()
            case "q": NSApp.terminate(nil)
            default: return false
            }
            return true
        }
        let panel = popover.isShown && event.window === popover.contentViewController?.view.window
        guard panel || (window != nil && event.window === window) else { return false }
        let navigation = panel ? panelNavigation : windowNavigation
        switch event.keyCode {
        case 53:
            if panel { popover.performClose(nil) }
            else { window?.close() }
        case 123, 124:
            let ids = store.enabled.map(\.id)
            guard !ids.isEmpty else { return false }
            let i = ids.firstIndex(of: navigation.provider) ?? 0
            navigation.select(ids[(i + (event.keyCode == 124 ? 1 : ids.count - 1)) % ids.count])
        default: return false
        }
        return true
    }

    @objc private func reopenExisting() {
        NSApp.activate(ignoringOtherApps: true)
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
    }
    @objc func refresh() { store.refreshAll() }
    @objc func typeFire() { NSWorkspace.shared.open(URL(string: "https://typefire.app")!) }
    @objc private func pickDockProvider(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { preferences.options.dockProvider = id }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let available = store.displayProviders
        let selected = available.contains { $0.id == preferences.options.dockProvider } ? preferences.options.dockProvider : "auto"
        for (id, title) in [("auto", "Auto")] + available.map({ ($0.id, $0.displayName) }) {
            let item = menu.addItem(withTitle: title, action: #selector(pickDockProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = id == selected ? .on : .off
        }
        menu.addItem(.separator())
        for (name, action) in [("Refresh", #selector(refresh)), ("Settings…", #selector(showSettings)), ("Quit", #selector(NSApplication.terminate(_:)))] {
            menu.addItem(withTitle: name, action: action, keyEquivalent: "").target = name == "Quit" ? NSApp : self
        }
        return menu
    }
    private func installMenus() {
        let main = NSMenu()
        let menu = NSMenu(title: "AI Usage Menu")
        let root = NSMenuItem()
        root.submenu = menu
        main.addItem(root)
        menu.addItem(withTitle: "About AI Usage Menu", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "").target = NSApp
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "From the makers of TypeFire", action: #selector(typeFire), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AI Usage Menu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        // Standard Edit and Window menus so Cmd+C, Cmd+A and Cmd+W work in every window.
        // Their items have no target, so they go to whichever window or text view is focused.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

private extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }
