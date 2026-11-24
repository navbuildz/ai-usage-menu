import AppKit
import SwiftUI
import XCTest
@testable import AI_Usage_Menu

/// Simulates a week of 5-minute refreshes (2,016 reads) in seconds and checks memory stays flat.
private actor ChangingProvider: Provider {
    let id: String
    nonisolated var displayName: String { id }
    nonisolated var glyph: String { id == "claude" ? "provider-claude-code" : "provider-codex" }
    private var tick = 0
    init(_ id: String) { self.id = id }
    func isAvailable() -> Bool { true }
    func read() async -> ProviderSnapshot {
        tick += 1
        let now = Date()
        var snapshot = ProviderSnapshot(asOf: now, state: .ready)
        snapshot.limits = [
            .init(label: "Current session", usedPercent: Double(tick % 100), resetsAt: now.addingTimeInterval(3600), windowMinutes: 300, source: id),
            .init(label: "Current week (all models)", usedPercent: Double((tick / 7) % 100), resetsAt: now.addingTimeInterval(86400 * 3), windowMinutes: 10080, source: id)
        ]
        snapshot.details = [.init(label: "Plan", value: "Max")]
        snapshot.breakdown = [BreakdownPeriod(span: "24h", requests: tick, sessions: tick % 20,
                                              tips: [.init(name: "Start fresh when you switch tasks", percent: tick % 100, detail: "run /clear")])]
        return snapshot
    }
}

final class SoakTests: XCTestCase {
    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    @MainActor func testAWeekOfRefreshesKeepsMemoryFlat() async {
        let store = UsageStore(providers: [ChangingProvider("claude"), ChangingProvider("codex")])
        let preferences = DisplayPreferences(defaults: UserDefaults(suiteName: "ai.aiusagemenu.tests.soak")!)
        let dock = DockTileController()
        let tile = NSApp.dockTile
        let panel = NSHostingView(rootView: UsageView(store: store, preferences: preferences, navigation: Navigation(), settings: {}, fitsContent: true))
        panel.frame = NSRect(x: 0, y: 0, width: 380, height: 600)
        let appearance = NSAppearance(named: .darkAqua)!

        func cycle() async {
            for provider in store.providers { _ = await store.read(provider) }
            var options = preferences.options
            options.placement = .both
            dock.update(store: store, options: options, tile: tile)
            _ = DockIconRenderer.image(for: DockSnapshot.resolve(providers: store.displayProviders, snapshots: store.snapshots, options: options, now: .now), size: 256)
            for key in ["auto", "claude", "codex"] {
                _ = MenuItemVisual(value: store.menuValue(key, options: options), pair: store.menuPair(key, options: options), provider: nil, options: options, appearance: appearance)
            }
            panel.layoutSubtreeIfNeeded()
            panel.display()
        }

        for _ in 0..<200 { await cycle() }   // warm up caches
        let start = footprintMB()
        for _ in 0..<2016 { await cycle() }
        let end = footprintMB()
        print("Soak: footprint \(String(format: "%.1f", start)) MB after warm-up, \(String(format: "%.1f", end)) MB after 2,016 refreshes")
        XCTAssertLessThan(end - start, 8, "memory grew by \(end - start) MB over a simulated week")
    }
}
