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
        store.onChange = { [weak self] in self?.updateDisplays() }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        applyPreferences()
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { store.start(minutes: preferences.options.refreshMinutes) }
    }

    private func applyActivation() {
        let target: NSApplication.ActivationPolicy = preferences.options.placement == .menu ? .accessory : .regular
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
        if preferences.options.placement == .dock { popover.performClose(nil) }
        updateDisplays()
    }

    private func updateDisplays() {
        updateItems()
        let options = preferences.options
        if options.placement == .menu {
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
        let keys = options.placement == .dock ? [] : (separate ? store.displayProviders.map(\.id) : ["auto"])
        for key in Array(items.keys) where !keys.contains(key) {
            if panelID == key { popover.performClose(nil) }
            if let item = items.removeValue(forKey: key) { NSStatusBar.system.removeStatusItem(item) }
        }
        for key in keys {
            let item = items[key] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            items[key] = item
            guard let button = item.button else { continue }
            button.target = self
            button.action = #selector(openPanel(_:))
            let provider = store.providers.first { $0.id == key }
            let value = store.menuValue(key, options: options)
            let visual = MenuItemVisual(value: value, provider: provider, options: options, appearance: button.effectiveAppearance)
            button.attributedTitle = NSAttributedString(string: visual.title, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: visual.textColor])
            button.image = visual.image
            button.contentTintColor = visual.iconTint
            button.imagePosition = visual.title.isEmpty ? .imageOnly : .imageLeading
            let description = (provider?.displayName ?? "AI Usage Menu") + ", " + (value.percent.map { $0.usageNumber + " percent used" } ?? "Usage unavailable")
            button.setAccessibilityLabel(description)
            button.toolTip = description
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
        NSHostingController(rootView: UsageView(store: store, preferences: preferences, navigation: navigation, settings: { [weak self] in self?.showSettings() }, close: { [weak self] in
            guard let self else { return }
            if navigation === panelNavigation { popover.performClose(nil) } else { window?.close() }
        }))
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
        popover.contentSize = .init(width: 380, height: 535)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) { popover.contentViewController = nil; panelID = nil }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard preferences.options.placement != .menu else { return false }
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
            let screens = NSScreen.screens
            let active = screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let previousScreen = sessionFrame.flatMap { frame in
                screens.filter { $0.visibleFrame.intersects(frame) }.max {
                    $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area
                }
            }
            let screen = previousScreen ?? active
            if let area = screen?.visibleFrame {
                let size = sessionFrame?.size ?? NSSize(width: 390, height: 525)
                let width = min(size.width, area.width), height = min(size.height, area.height)
                let origin = sessionFrame?.origin ?? NSPoint(x: area.midX - width/2, y: area.midY - height/2)
                window.setFrame(.init(x: max(area.minX,min(origin.x,area.maxX-width)), y: max(area.minY,min(origin.y,area.maxY-height)), width: width,height: height), display: true)
            }
        }
        window?.makeKeyAndOrderFront(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        if let w = notification.object as? NSWindow, w === window { sessionFrame = w.frame; w.contentViewController = nil }
    }

    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: DisplaySettings(preferences: preferences, store: store)))
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
        if preferences.options.placement == .menu, let button = items.values.first?.button {
            if !popover.isShown { openPanel(button) }
        } else { _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false) }
    }
    @objc func refresh() { store.refreshAll() }
    @objc func typeFire() { NSWorkspace.shared.open(URL(string: "https://typefire.app")!) }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
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
        NSApp.mainMenu = main
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

@MainActor
enum MenuGauge {
    static func image(percent: Double, thresholds: Thresholds, appearance: NSAppearance) -> NSImage {
        let tier = thresholds.tier(percent)
        let ink = thresholds.color(percent)
        let light = appearance.bestMatch(from: [.darkAqua,.aqua]) == .aqua
        let rects = [CGRect(x: 8.9,y: 18.2,width: 4.8,height: 7.8), CGRect(x: 15,y: 14.5,width: 4.8,height: 11.5), CGRect(x: 21.1,y: 10.7,width: 4.8,height: 15.3)]
        return NSImage(size: .init(width: 18,height: 18), flipped: true) { bounds in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.saveGState()
            c.scaleBy(x: bounds.width / 32, y: bounds.height / 32)
            let template = NSImage(named: "UsageTemplate")!
            template.draw(in: .init(x: 0,y: 0,width: 32,height: 32), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            (light ? NSColor.black : NSColor.white).setFill()
            NSRect(x: 0,y: 0,width: 32,height: 32).fill(using: .sourceAtop)
            for (index, rect) in rects.enumerated() {
                let path = NSBezierPath(roundedRect: rect, xRadius: 1.8, yRadius: 1.8)
                (index < tier ? ink : (light ? NSColor.lightGray : NSColor.darkGray)).setFill()
                path.fill()
            }
            c.restoreGState()
            return true
        }
    }
}

private extension CGRect { var area: CGFloat { isNull ? 0 : width * height } }

extension UsageStore {
    func menuValue(_ key: String, options: DisplayOptions) -> Indicator {
        let choice = key == "auto" ? options.menuProvider : key
        let id = displayProviders.contains { $0.id == choice } ? choice : "auto"
        return Indicator.select(providers: displayProviders, snapshots: snapshots, providerID: id, window: options.menuWindow, at: .now)
    }
}

@MainActor
struct MenuItemVisual {
    let title: String
    let image: NSImage?
    let textColor: NSColor
    let iconTint: NSColor?

    init(value: Indicator, provider: (any Provider)?, options: DisplayOptions, appearance: NSAppearance) {
        title = value.percent.flatMap { options.showPercent ? $0.usageNumber + "%" : nil } ?? (value == .warning ? "⚠" : "")
        let ink = value.percent.map { options.thresholds.color($0) }
        textColor = provider != nil ? ink ?? .labelColor : .labelColor
        iconTint = provider != nil && !options.showPercent ? ink : nil
        if provider == nil, let percent = value.percent {
            image = MenuGauge.image(percent: percent, thresholds: options.thresholds, appearance: appearance)
        } else {
            image = NSImage(named: provider?.glyph ?? "UsageTemplate")?.copy() as? NSImage
            image?.size = .init(width: 18, height: 18)
            image?.isTemplate = true
        }
    }
}
