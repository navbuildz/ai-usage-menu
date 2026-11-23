import AppKit
import SwiftUI
import XCTest
@testable import AI_Usage_Menu

final class DisplayTests: XCTestCase {
    @MainActor func testWindowAcrossDisplaysAndAfterDisconnect() {
        let main = NSRect(x: 0, y: 50, width: 1500, height: 900)
        let left = NSRect(x: -1200, y: -200, width: 1200, height: 880)
        let screens = [main, left]
        let first = AppDelegate.windowFrame(previous: nil, visibleFrames: screens, active: left)
        XCTAssertEqual(first.midX, left.midX)
        XCTAssertEqual(first.midY, left.midY)
        let moved = first.offsetBy(dx: -100, dy: 65)
        XCTAssertEqual(AppDelegate.windowFrame(previous: moved, visibleFrames: screens, active: main), moved)
        let recovered = AppDelegate.windowFrame(previous: moved, visibleFrames: [main], active: main)
        XCTAssertEqual(recovered.midX, main.midX)
        XCTAssertEqual(recovered.midY, main.midY)
        let spanning = NSRect(x: -280, y: 10, width: 400, height: 600)
        XCTAssertTrue(left.contains(AppDelegate.windowFrame(previous: spanning, visibleFrames: screens, active: main)))
    }

    private let now = Date(timeIntervalSince1970: 1800000000)
    private let providers: [any Provider] = [ClaudeCodeProvider(), CodexProvider()]
    private var screenshotFolder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("handoff/screenshots/dock")
    }
    private func snapshot(_ session: Double, _ weekly: Double, stale: Bool = false) -> ProviderSnapshot {
        let date = now.addingTimeInterval(stale ? -1 : 300)
        return .init(limits: [
            .init(label: "Current session", usedPercent: session, resetsAt: date, windowMinutes: nil, source: "Fixture"),
            .init(label: "Weekly", usedPercent: weekly, resetsAt: date, windowMinutes: 10080, source: "Fixture")
        ], asOf: now, state: .ready)
    }

    func testIndependentProviderAndWindowSelection() {
        let readings = ["claude":snapshot(30,57),"codex":snapshot(94,12)]
        func chosen(_ provider: String, _ window: WindowChoice) -> Indicator {
            Indicator.select(providers: providers, snapshots: readings, providerID: provider, window: window, at: now)
        }
        XCTAssertEqual(chosen("auto",.highest),.value(94,"provider-codex"))
        XCTAssertEqual(chosen("claude",.session),.value(30,"provider-claude-code"))
        XCTAssertEqual(chosen("auto",.weekly),.value(57,"provider-claude-code"))
        XCTAssertEqual(chosen("codex",.weekly),.value(12,"provider-codex"))
        XCTAssertEqual(Indicator.select(providers: [providers[0]], snapshots: readings, at: now).percent,57)
        XCTAssertEqual(Indicator.select(providers: [], snapshots: readings, at: now),.absent)
    }

    @MainActor func testDockMenuProviderSelectionAndMenuNumberPreferences() throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let prefs = delegate.preferences
        let saved = prefs.options
        defer { prefs.options = saved }
        prefs.options.disabled = []
        prefs.options.dockProvider = "auto"
        let menu = try XCTUnwrap(delegate.applicationDockMenu(NSApp))
        XCTAssertEqual(menu.item(withTitle: "Auto")?.state, .on)
        let codex = try XCTUnwrap(menu.item(withTitle: "Codex"))
        menu.performActionForItem(at: menu.index(of: codex))
        XCTAssertEqual(prefs.options.dockProvider, "codex")
        XCTAssertEqual(delegate.applicationDockMenu(NSApp)?.item(withTitle: "Codex")?.state, .on)
        var options = DisplayOptions()
        options.twoMenuNumbers = true
        let decoded = try JSONDecoder().decode(DisplayOptions.self, from: JSONEncoder().encode(options))
        XCTAssertTrue(decoded.twoMenuNumbers)
        XCTAssertFalse(decoded.twoDockNumbers)
        let pair = DockSnapshot(indicator: .value(72, "provider-codex"), thresholds: options.thresholds, session: 13, weekly: 72)
        let visual = MenuItemVisual(value: pair.indicator, pair: pair, provider: nil, options: options, appearance: NSAppearance(named: .aqua)!)
        XCTAssertEqual(visual.usageDescription, "5-hour 13%, weekly 72%")
        XCTAssertEqual(visual.image?.size.height, 22)
    }

    @MainActor func testDockSnapshots() throws {
        let record = ProcessInfo.processInfo.environment["RECORD_DOCK"] == "1"
        if record { try FileManager.default.createDirectory(at: screenshotFolder, withIntermediateDirectories: true) }
        func resolved(_ readings: [String: ProviderSnapshot], colors: Thresholds = .init()) -> DockSnapshot {
            var options = DisplayOptions()
            options.thresholds = colors
            return DockSnapshot.resolve(providers: providers, snapshots: readings, options: options, now: now)
        }
        var samples: [(String, DockSnapshot)] = [0,12,30,57,72,94,100].map {
            ("usage-\($0)", resolved(["claude":snapshot(Double($0), 57)]))
        }
        if ProcessInfo.processInfo.environment["RECORD_SITE"] == "1" {
            let folder = screenshotFolder.deletingLastPathComponent().appendingPathComponent("site-retina")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for frame in 0...18 {
                let value = Double(frame) / 18
                let state = resolved(["claude": snapshot(72 * value, 57 * value)])
                let image = DockIconRenderer.image(for: state, size: 192)
                let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("dock-frame-\(frame).png"))
            }
        }
        let custom = Thresholds(amber: 50, red: 70)
        samples += [
            ("custom-57",resolved(["claude":snapshot(57,78)],colors:custom)),
            ("custom-78",resolved(["claude":snapshot(78,57)],colors:custom)),
            ("codex-stale",resolved(["codex":snapshot(94,100,stale:true)])),
            ("error",resolved(["claude":.init(asOf:now,state:.timedOut)])),
            ("no-providers",resolved(["codex":.init(asOf:now,state:.notInstalled)])),
            ("auto-both",resolved(["claude":snapshot(12,30),"codex":snapshot(72,57)]))
        ]
        var light = resolved(["claude":snapshot(37,72)])
        light.light = true
        samples.append(("light-37", light))
        var twoOptions = DisplayOptions()
        twoOptions.twoDockNumbers = true
        var dual = DockSnapshot.resolve(providers: providers, snapshots: ["claude": snapshot(9, 71)], options: twoOptions, now: now)
        XCTAssertTrue(dual.twoNumbers)
        XCTAssertEqual(dual.session, 9)
        XCTAssertEqual(dual.weekly, 71)
        samples.append(("two-numbers-dark", dual))
        dual.light = true
        samples.append(("two-numbers-light", dual))
        for (name, snapshot) in samples {
            for size in [32,128,1024] {
                let image = DockIconRenderer.image(for: snapshot, size: size)
                let bitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let url = screenshotFolder.appendingPathComponent("\(name)-\(size).png")
                if record { try png.write(to: url) }
                let actual = try XCTUnwrap(NSBitmapImageRep(data: png))
                let golden = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
                XCTAssertEqual(golden.pixelsWide, size)
                XCTAssertEqual(golden.pixelsHigh, size)
                // Sample the whole tile on a 32-square grid. Tolerate color-profile rounding.
                var mismatches = 0
                for x in stride(from: 0, to: size, by: size/32) {
                    for y in stride(from: 0, to: size, by: size/32) {
                        let a = actual.colorAt(x: x,y: y)!.usingColorSpace(.sRGB)!
                        let b = golden.colorAt(x: x,y: y)!.usingColorSpace(.sRGB)!
                        if abs(a.alphaComponent - b.alphaComponent) > 0.04 ||
                            (a.alphaComponent > 0.1 && max(abs(a.redComponent-b.redComponent),abs(a.greenComponent-b.greenComponent),abs(a.blueComponent-b.blueComponent)) > 0.07) { mismatches += 1 }
                    }
                }
                XCTAssertLessThan(mismatches, 12, "\(name) at \(size)")
            }
        }
        for size in [64,512] { XCTAssertEqual(DockIconRenderer.image(for: .init(indicator:.value(72,"provider-codex"),thresholds:.init()),size:size).size.width,CGFloat(size)) }
    }

    func testSplitRingProviderAndCenterStayIndependent() throws {
        var options = DisplayOptions()
        var claude = snapshot(12, 57)
        claude.limits.append(.init(label:"Current week (Fable)",usedPercent:99,resetsAt:nil,windowMinutes:nil,source:"Claude Code"))
        let readings = ["claude":claude, "codex":snapshot(30, 72)]
        func resolve() -> DockSnapshot {
            DockSnapshot.resolve(providers: providers, snapshots: readings, options: options, now: now)
        }
        XCTAssertEqual(resolve().indicator,.value(30,"provider-codex"))
        options.dockWindow = .weekly
        XCTAssertEqual(resolve().indicator,.value(72,"provider-codex"))
        XCTAssertEqual(resolve().session,30)
        XCTAssertEqual(resolve().weekly,72)
        options.dockProvider = "claude"
        XCTAssertEqual(resolve().indicator,.value(57,"provider-claude-code"))
        XCTAssertEqual(resolve().session,12)
        let old = Data(#"{"dockWindow":"Most constrained","separateItems":true,"dockProvider":"codex"}"#.utf8)
        let migrated = try JSONDecoder().decode(DisplayOptions.self, from:old)
        XCTAssertEqual(migrated.dockProvider,"codex")
        XCTAssertEqual(migrated.dockWindow,.session)
        XCTAssertTrue(migrated.separateItems)
        XCTAssertEqual(migrated.refreshMinutes,5)
        XCTAssertEqual(migrated.theme,.system)
    }

    func testHealthBoundaries() {
        let standard = Thresholds()
        XCTAssertEqual([0,59.99,60,84.99,85,100].map(standard.tier),[1,1,2,2,3,3])
        XCTAssertEqual([49,50,69,70].map(Thresholds(amber:50,red:70).tier),[1,2,2,3])
    }

    @MainActor func testSettingsRemainsReachableWithCrowdedMenuBar() throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let saved = delegate.preferences.options
        let bar = NSStatusBar.system
        let fillers = (0..<12).map { _ in bar.statusItem(withLength: 70) }
        defer {
            fillers.forEach { bar.removeStatusItem($0) }
            delegate.preferences.options = saved
        }
        for item in fillers { item.button?.title = "•••" }
        delegate.preferences.options.placement = .menu
        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        let settings = try XCTUnwrap(NSApp.windows.first { $0.title == "AI Usage Menu Settings" && $0.isVisible })
        settings.close()
    }

    @MainActor func testLivePlacementAndDockNavigation() throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let prefs = delegate.preferences
        let saved = prefs.options
        defer { prefs.options = saved }
        prefs.options.placement = .menu
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertEqual(delegate.statusItemCount, 1)
        let button = try XCTUnwrap(delegate.items["auto"]?.button)
        button.performClick(nil)
        XCTAssertTrue(delegate.popover.isShown)
        for theme in [AppTheme.light, .dark] {
            prefs.options.theme = theme
            let content = try XCTUnwrap(delegate.popover.contentViewController?.view)
            XCTAssertEqual(content.effectiveAppearance.bestMatch(from: [.aqua,.darkAqua]), theme.appearance?.name)
        }
        delegate.popover.performClose(nil)
        prefs.options.placement = .dock
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertEqual(delegate.statusItemCount, 0)
        XCTAssertNil(NSApp.dockTile.badgeLabel)
        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "AI Usage Menu" && $0.isVisible })
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(delegate.applicationDockMenu(NSApp)?.items.contains { $0.title == "Settings…" } == true)
        let area = try XCTUnwrap(window.screen?.visibleFrame)
        XCTAssertEqual(window.frame.midX, area.midX, accuracy: 2)
        XCTAssertEqual(window.frame.midY, area.midY, accuracy: 2)
        window.setFrameOrigin(.init(x: area.minX + 10, y: area.minY + 10))
        let moved = window.frame
        window.close()
        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        XCTAssertEqual(window.frame, moved)
        for theme in [AppTheme.dark, .light, .system] {
            prefs.options.theme = theme
            let expected = (theme.appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua,.darkAqua])
            XCTAssertEqual(delegate.popover.appearance?.bestMatch(from: [.aqua,.darkAqua]), expected)
            XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua,.darkAqua]), expected)
        }
        delegate.showSettings()
        let settings = try XCTUnwrap(NSApp.windows.first { $0.title == "AI Usage Menu Settings" && $0.isVisible })
        settings.close()
        window.close()
        prefs.options.placement = .both
        prefs.options.separateItems = true
        XCTAssertEqual(delegate.statusItemCount, 2)
        prefs.options.placement.showsDock = false
        prefs.options.placement.showsMenu = false
        XCTAssertEqual(prefs.options.placement, .hidden)
        XCTAssertEqual(delegate.statusItemCount, 0)
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        XCTAssertTrue(settings.isVisible)
        settings.close()
        prefs.options.placement.showsMenu = true
        prefs.options.placement.showsDock = true
        XCTAssertEqual(prefs.options.placement, .both)
        XCTAssertEqual(DisplayOptions().placement, .both)
    }
}
