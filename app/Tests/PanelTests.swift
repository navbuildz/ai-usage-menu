import AppKit
import SwiftUI
import XCTest
@testable import AI_Usage_Menu

private struct FixtureProvider: Provider {
    let id: String
    let result: ProviderSnapshot
    var displayName: String { id == "claude" ? "Claude Code" : "Codex" }
    var glyph: String { id == "claude" ? "provider-claude-code" : "provider-codex" }
    func isAvailable() async -> Bool { result.state != .notInstalled }
    func read() async -> ProviderSnapshot { result }
}

final class PanelTests: XCTestCase {
    @MainActor func testPanelStatesInBothAppearances() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("handoff/screenshots/window")
        let record = ProcessInfo.processInfo.environment["RECORD_PANEL"] == "1"
        if record { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let siteCapture = ProcessInfo.processInfo.environment["RECORD_SITE"] == "1"
        let siteFolder = root.appendingPathComponent("handoff/screenshots/site-retina")
        if siteCapture { try FileManager.default.createDirectory(at: siteFolder, withIntermediateDirectories: true) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "subscription", withExtension: "txt"))
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let now = Date()
        var high = ClaudeParser.parse(text, now: now)
        high.limits = high.limits.enumerated().map { index, limit in
            .init(label: limit.label, usedPercent: limit.usedPercent, resetsAt: now.addingTimeInterval(index == 0 ? 6720 : 518400), windowMinutes: nil, source: limit.source)
        }
        high.details.append(.init(label:"Claude Code",value:"2.1.330"))
        var normal = high
        normal.limits = [.init(label:"Current session",usedPercent:30,resetsAt:now.addingTimeInterval(6720),windowMinutes:nil,source:"Claude Code"),
                         .init(label:"Current week (all models)",usedPercent:57,resetsAt:now.addingTimeInterval(518400),windowMinutes:nil,source:"Claude Code")]
        var stale = ProviderSnapshot(asOf:now.addingTimeInterval(-86400),state:.ready)
        stale.limits = [.init(label:"Session",usedPercent:94,resetsAt:now.addingTimeInterval(-3600),windowMinutes:300,source:"Last Codex activity")]
        var reached = stale
        reached.state = .limitReached("weekly")
        reached.limits = [.init(label:"Weekly",usedPercent:100,resetsAt:now.addingTimeInterval(7200),windowMinutes:10080,source:"Last Codex activity")]
        let missing = ProviderSnapshot(asOf:now,state:.notInstalled)
        var cases: [(String,String,ProviderSnapshot)] = [("normal","claude",normal),("high","claude",high),("breakdown","claude",high),("stale","codex",stale),("limit-reached","codex",reached),("missing","claude",missing)]
        for (name, id, state) in [("signed-out","claude",ProviderState.signedOut),("api-key","claude",.nonSubscription),("timeout","claude",.timedOut),("no-sessions","codex",.noSessions),("no-limits","codex",.noLimits),("unreadable","codex",.unreadable),("failed","claude",.failed("Fixture diagnostic"))] {
            cases.append((name,id,.init(asOf:now,state:state)))
        }
        var codex = ProviderSnapshot(asOf: now.addingTimeInterval(-10800), state: .ready)
        codex.details = [.init(label: "Plan", value: "Plus")]
        codex.limits = [
            .init(label: "Session", usedPercent: 72, resetsAt: now.addingTimeInterval(5400), windowMinutes: 300, source: "Last Codex activity"),
            .init(label: "Weekly", usedPercent: 57, resetsAt: now.addingTimeInterval(345600), windowMinutes: 10080, source: "Last Codex activity")
        ]
        cases.append(("codex-plan", "codex", codex))
        cases.append(("unknown","claude",.init(asOf:now,state:.unknownFormat,rawText:"Unrecognized fixture output")))
        let preferences = DisplayPreferences(defaults: UserDefaults(suiteName:"ai.aiusagemenu.tests.panel")!)
        for (name,id,snapshot) in cases {
            let providers = ["claude","codex"].map { FixtureProvider(id:$0,result:$0 == id ? snapshot : missing) }
            let store = UsageStore(providers:providers)
            let loaded = expectation(description:"Load fixtures")
            loaded.expectedFulfillmentCount = 2
            store.onChange = { loaded.fulfill() }
            store.refreshAll()
            await fulfillment(of:[loaded], timeout:3)
            store.onChange = nil
            let navigation = Navigation()
            navigation.select(id)
            for (suffix,theme) in [("dark",ColorScheme.dark),("light",ColorScheme.light)] {
                let view = UsageView(store:store,preferences:preferences,navigation:navigation,settings:{})
                    .environment(\.colorScheme,theme).frame(width:380,height:name == "breakdown" ? 1150 : 535)
                if siteCapture && ["normal", "breakdown", "codex-plan"].contains(name) {
                    try captureRetina(view, to: siteFolder.appendingPathComponent(name+"-"+suffix+"@2x.png"), theme: theme)
                    if name == "normal" {
                        let hero = UsageView(store: store, preferences: preferences, navigation: navigation, settings: {})
                            .environment(\.colorScheme, theme).frame(width: 550, height: 430)
                        try captureRetina(hero, to: siteFolder.appendingPathComponent("hero-"+suffix+"@2x.png"), theme: theme)
                    }
                }
                try capture(view, name:name+"-"+suffix, folder:folder, record:record, theme:theme)
                if name == "normal" {
                    if record {
                        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
                        let saved = delegate.preferences.options
                        defer { delegate.preferences.options = saved }
                        delegate.preferences.options.placement = .both
                        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
                        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "AI Usage Menu" && $0.isVisible })
                        let controller = try XCTUnwrap(window.contentViewController)
                        controller.view = NSHostingView(rootView: UsageView(store: store, preferences: preferences, navigation: navigation, settings: {}).environment(\.colorScheme, theme))
                        window.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
                        window.setContentSize(.init(width: 390, height: 525))
                        let content = controller.view
                        content.wantsLayer = true
                        content.layer?.cornerRadius = 18
                        content.layer?.masksToBounds = true
                        content.layoutSubtreeIfNeeded()
                        content.displayIfNeeded()
                        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                        content.cacheDisplay(in: content.bounds, to: bitmap)
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("hero-"+suffix+".png"))
                        window.close()
                    }
                    try capture(Onboarding(store: store, services: AppServices(), finish: {}).environment(\.colorScheme,theme), name:"onboarding-"+suffix, folder:folder, record:record, theme:theme)
                    for pane in SettingsPane.allCases {
                        let settings = DisplaySettings(preferences:preferences,store:store,pane:pane).environment(\.colorScheme,theme)
                        let prefix = pane == .general ? "settings" : "settings-" + String(describing: pane)
                        try capture(settings,name:prefix+"-"+suffix,folder:folder,record:record,theme:theme)
                    }
                }
            }
            store.stop()
        }
    }

    @MainActor func testMenuGaugeInBothMenuBarAppearances() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("handoff/screenshots/icon")
        let record = ProcessInfo.processInfo.environment["RECORD_PANEL"] == "1"
        if record { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for (theme, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            let appearance = try XCTUnwrap(NSAppearance(named: theme))
            for percent in [30, 72, 94] {
                let icon = MenuGauge.image(percent: Double(percent), thresholds: Thresholds(), appearance: appearance)
                XCTAssertEqual(icon.size, NSSize(width: 18, height: 18))
                if record {
                    let image = NSImage(size: NSSize(width: 32, height: 24), flipped: false) { rect in
                        (theme == .aqua ? NSColor.white : NSColor.black).setFill()
                        rect.fill()
                        icon.draw(in: NSRect(x: 7, y: 3, width: 18, height: 18))
                        return true
                    }
                    let data = try XCTUnwrap(image.tiffRepresentation)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("menu-\(percent)-\(name).png"))
                }
            }
        }
    }

    @MainActor private func captureRetina<V: View>(_ view: V, to url: URL, theme: ColorScheme) throws {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: .init(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.layoutIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    @MainActor private func capture<V: View>(_ root: V, name: String, folder: URL, record: Bool, theme: ColorScheme) throws {
        let host = NSHostingView(rootView:root)
        let size = host.fittingSize
        let window = NSWindow(contentRect:.init(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.appearance = NSAppearance(named:theme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.layoutIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:bitmap)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide,380)
        if record {
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:folder.appendingPathComponent(name+".png"))
        }
    }
    // [2026-11-25 Nav] The window opened on "Reading usage…" in a plain box and the Dock showed the plain
    // icon while the first read ran. Now: a loading card, last numbers restored at launch, Dock dots.
    @MainActor func testLoadingAndRestoredStatesDraw() throws {
        let look = ProcessInfo.processInfo.environment["LOOK_DIR"].map { URL(fileURLWithPath: $0) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "aum-restore-test"))
        defer { defaults.removePersistentDomain(forName: "aum-restore-test") }
        let now = Date()
        let reading = ProviderSnapshot(limits: [
            .init(label: "Current session", usedPercent: 5, resetsAt: now.addingTimeInterval(4 * 3600), windowMinutes: nil, source: "Claude Code"),
            .init(label: "Current week (all models)", usedPercent: 47, resetsAt: now.addingTimeInterval(3 * 86_400), windowMinutes: nil, source: "Claude Code")],
            details: [.init(label: "Plan", value: "Claude subscription")], asOf: now.addingTimeInterval(-600), state: .ready)
        SavedReading.save(["claude": reading, "codex": .init(asOf: now, state: .noSessions)], to: defaults)
        let restoredStore = UsageStore(providers: [ClaudeCodeProvider()], saved: defaults)
        let restored = try XCTUnwrap(restoredStore.snapshots["claude"])
        XCTAssertTrue(restored.restored)
        XCTAssertEqual(restored.limits.map(\.usedPercent), [5, 47])
        XCTAssertNil(restoredStore.snapshots["codex"], "only good readings are saved")
        let dock = DockSnapshot.resolve(providers: restoredStore.providers, snapshots: restoredStore.snapshots, options: DisplayOptions(), now: now)
        XCTAssertEqual(dock.indicator.percent, 5, "the Dock shows the restored number at launch")

        let emptyStore = UsageStore(providers: [ClaudeCodeProvider()])
        for (suffix, theme) in [("dark", ColorScheme.dark), ("light", ColorScheme.light)] {
            for (name, store) in [("loading", emptyStore), ("restored", restoredStore)] {
                let host = NSHostingView(rootView: UsageView(store: store, preferences: DisplayPreferences(defaults: UserDefaults(suiteName: "ai.aiusagemenu.tests.panel")!), navigation: Navigation(), settings: {})
                    .environment(\.colorScheme, theme).frame(width: 390, height: 525))
                let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 390, height: 525), styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
                window.contentView = host
                window.layoutIfNeeded(); host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let look { try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: look.appendingPathComponent("\(name)-\(suffix).png")) }
            }
            var loading = DockSnapshot(indicator: .absent, thresholds: Thresholds())
            loading.loading = true
            loading.light = suffix == "light"
            let image = DockIconRenderer.image(for: loading, size: 256)
            if let look, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: look.appendingPathComponent("dock-loading-\(suffix).png"))
            }
        }
    }
}
