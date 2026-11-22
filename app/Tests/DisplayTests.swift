import AppKit
import SwiftUI
import XCTest
@testable import AI_Usage_Menu

final class DisplayTests: XCTestCase {
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

    @MainActor func testDockSnapshots() throws {
        let record = ProcessInfo.processInfo.environment["RECORD_DOCK"] == "1"
        if record { try FileManager.default.createDirectory(at: screenshotFolder, withIntermediateDirectories: true) }
        var samples: [(String, Indicator, Thresholds)] = [0,12,30,57,72,94,100].map { ("usage-\($0)",.value(Double($0),"provider-claude-code"),Thresholds()) }
        let thresholds = Thresholds(amber: 50, red: 70)
        samples += [("custom-57",.value(57,"provider-claude-code"),thresholds), ("custom-78",.value(78,"provider-claude-code"),thresholds)]
        func resolved(_ readings: [String: ProviderSnapshot]) -> Indicator {
            Indicator.select(providers: providers, snapshots: readings, at: now)
        }
        let stale = resolved(["codex":snapshot(94,100,stale:true)])
        let error = resolved(["claude":.init(asOf: now,state:.timedOut)])
        let missing = resolved(["codex":.init(asOf: now,state:.notInstalled)])
        XCTAssertEqual(stale,.warning); XCTAssertEqual(error,.warning); XCTAssertEqual(missing,.absent)
        samples += [("codex-stale",stale,.init()),("error",error,.init()),("no-providers",missing,.init()),("auto-both",resolved(["claude":snapshot(12,30),"codex":snapshot(72,57)]),.init())]
        for (name, indicator, colors) in samples {
            for size in [32,128,1024] {
                let image = DockIconRenderer.image(for: .init(indicator: indicator, thresholds: colors), size: size)
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

    func testHealthBoundaries() {
        let standard = Thresholds()
        XCTAssertEqual([0,59.99,60,84.99,85,100].map(standard.tier),[1,1,2,2,3,3])
        XCTAssertEqual([49,50,69,70].map(Thresholds(amber:50,red:70).tier),[1,2,2,3])
    }

    @MainActor func testLivePlacementAndDockNavigation() throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let prefs = delegate.preferences
        let saved = prefs.options
        defer { prefs.options = saved }
        prefs.options.placement = .menu
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertEqual(delegate.statusItemCount, 1)
        prefs.options.placement = .dock
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertEqual(delegate.statusItemCount, 0)
        XCTAssertNil(NSApp.dockTile.badgeLabel)
        XCTAssertTrue(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "AI Usage Menu" && $0.isVisible })
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(delegate.applicationDockMenu(NSApp)?.items.contains { $0.title == "Settings…" } == true)
        delegate.showSettings()
        let settings = try XCTUnwrap(NSApp.windows.first { $0.title == "AI Usage Menu Settings" && $0.isVisible })
        settings.close()
        window.close()
        prefs.options.placement = .both
        prefs.options.separateItems = true
        XCTAssertEqual(delegate.statusItemCount, 2)
        prefs.options.placement = .menu
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }
}
