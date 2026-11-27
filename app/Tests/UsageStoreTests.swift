import AppKit
import XCTest
@testable import AI_Usage_Menu

private actor SampleProvider: Provider {
    let id: String
    nonisolated var displayName: String { id }
    nonisolated var glyph: String { id }
    var snapshot: ProviderSnapshot
    private(set) var reads = 0
    init(_ id: String, _ percent: Double) {
        self.id = id
        snapshot = .init(limits:[.init(label:"Session",usedPercent:percent,resetsAt:nil,windowMinutes:nil,source:id)],asOf:Date(),state:.ready)
    }
    func disconnect() { snapshot = .init(asOf:Date(),state:.notInstalled) }
    func set(_ next: ProviderSnapshot) { snapshot = next }
    func isAvailable() -> Bool { true }
    func read() async -> ProviderSnapshot {
        reads += 1
        try? await Task.sleep(for:.milliseconds(20))
        return snapshot
    }
}

final class UsageStoreTests: XCTestCase {
    @MainActor func testAlertThresholdsAndResetAreIndependentPerProviderAndCycle() {
        let start = Date(timeIntervalSince1970: 1000)
        var ledger: [String: Double] = [:]
        func count(_ percent: Double, _ second: Double, _ end: Double, provider: String = "claude") -> Int {
            let reset = start.addingTimeInterval(end)
            let window = LimitWindow(label: "Session", usedPercent: percent, resetsAt: reset, windowMinutes: 300, source: provider)
            return AppServices.notices(for: window, providerID: provider, reset: reset, now: start.addingTimeInterval(second),
                                       thresholds: [75,90], resetsEnabled: true, ledger: &ledger).count
        }
        XCTAssertEqual(count(74, 0, 60), 0)
        XCTAssertEqual(count(76, 1, 60), 1)
        XCTAssertEqual(count(95, 2, 60), 1)
        XCTAssertEqual(count(95, 3, 60), 0)
        XCTAssertEqual(count(95, 3, 60, provider: "codex"), 2)
        XCTAssertEqual(count(95, 60, 60), 1)
        XCTAssertEqual(count(95, 61, 60), 0)
        XCTAssertEqual(count(95, 62, 120), 2)
    }

    @MainActor func testRefreshCoalescingAndFailedReadReplacesPriorValues() async throws {
        let claude = SampleProvider("claude",90), codex = SampleProvider("codex",20)
        let providers = [claude,codex]
        let store = UsageStore(providers:providers)
        func waitForChanges(_ count: Int, action: () -> Void) async {
            let changed = expectation(description:"Read completed")
            changed.expectedFulfillmentCount = count
            store.onChange = { changed.fulfill() }
            action()
            await fulfillment(of:[changed],timeout:2)
            store.onChange = nil
        }
        await waitForChanges(2) { store.refreshAll(); store.opened(); XCTAssertEqual(store.active.count,2) }
        store.opened()
        XCTAssertTrue(store.active.isEmpty)
        let reads = await claude.reads
        XCTAssertEqual(reads,1)
        XCTAssertEqual(store.snapshots["claude"]?.limits.first?.usedPercent,90)
        XCTAssertEqual(store.snapshots["codex"]?.limits.first?.usedPercent,20)
        await codex.disconnect()
        await waitForChanges(1) { store.refresh(codex) }
        XCTAssertEqual(store.snapshots["codex"]?.state,.notInstalled)
        XCTAssertTrue(store.snapshots["codex"]?.limits.isEmpty == true)
        store.stop()
    }

    @MainActor func testWakeRefreshesEnabledProviders() async {
        let enabled = SampleProvider("enabled", 20), disabled = SampleProvider("disabled", 50)
        let store = UsageStore(providers: [enabled, disabled])
        defer { store.stop() }
        store.setDisabled([disabled.id])
        let initial = expectation(description: "Launch refresh")
        store.onChange = { initial.fulfill() }
        store.start()
        await fulfillment(of: [initial], timeout: 2)
        let wake = expectation(description: "Wake refresh")
        store.onChange = { wake.fulfill() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await fulfillment(of: [wake], timeout: 2)
        let enabledReads = await enabled.reads, disabledReads = await disabled.reads
        XCTAssertEqual(enabledReads, 2)
        XCTAssertEqual(disabledReads, 0)
    }

    @MainActor func testCodexWatcherPicksUpAppendedEvent() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = home.appendingPathComponent("sessions/2026/11/22")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = sessions.appendingPathComponent("rollout-watch.jsonl")
        try Data("unrelated\n".utf8).write(to: file)
        let store = UsageStore(providers: [CodexProvider(home: home)])
        defer { store.stop() }
        let initial = expectation(description: "Initial scan")
        store.onChange = { initial.fulfill(); store.onChange = nil }
        store.start()
        await fulfillment(of: [initial], timeout: 5)
        XCTAssertEqual(store.snapshots["codex"]?.state, .noSessions)

        let appended = expectation(description: "Appended limits observed")
        store.onChange = {
            if store.snapshots["codex"]?.limits.count == 2 {
                appended.fulfill()
                store.onChange = nil
            }
        }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "rate-limits", withExtension: "jsonl"))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(contentsOf: fixture))
        try handle.close()
        await fulfillment(of: [appended], timeout: 5)
    }

    // [2026-11-25 Nav] A failed read keeps the last good numbers on screen and counts the failures,
    // so the menu bar and Dock never flip to "!" or a blank on one bad read.
    @MainActor func testFailedReadsKeepTheLastReadingAndCount() async {
        let provider = SampleProvider("claude", 97)
        let store = UsageStore(providers: [provider])
        _ = await store.read(provider)
        await provider.set(.init(asOf: Date(), state: .failed("API Error: 429 rate limited")))
        _ = await store.read(provider)
        XCTAssertEqual(store.snapshots["claude"]?.state, .ready)
        XCTAssertEqual(store.snapshots["claude"]?.limits.first?.usedPercent, 97)
        XCTAssertEqual(store.snapshots["claude"]?.failedReads, 1)
        XCTAssertEqual(store.snapshots["claude"]?.refreshError, "API Error: 429 rate limited")
        await provider.set(.init(asOf: Date(), state: .timedOut))
        _ = await store.read(provider); _ = await store.read(provider)
        XCTAssertEqual(store.snapshots["claude"]?.failedReads, 3)
        XCTAssertEqual(Indicator.select(providers: [provider], snapshots: store.snapshots, at: .now).percent, 97)
        // A good read clears the count; a real answer (signed out) replaces the reading.
        await provider.set(.init(limits: [.init(label: "Session", usedPercent: 12, resetsAt: nil, windowMinutes: nil, source: "claude")], asOf: Date(), state: .ready))
        _ = await store.read(provider)
        XCTAssertEqual(store.snapshots["claude"]?.failedReads, 0)
        await provider.set(.init(asOf: Date(), state: .signedOut))
        _ = await store.read(provider)
        XCTAssertEqual(store.snapshots["claude"]?.state, .signedOut)
    }

    @MainActor func testLastKnownUsageCountsAsAFailedRead() async {
        let provider = SampleProvider("claude", 40)
        let store = UsageStore(providers: [provider])
        _ = await store.read(provider)
        var stale = ProviderSnapshot(limits: [.init(label: "Session", usedPercent: 46, resetsAt: nil, windowMinutes: nil, source: "claude")], asOf: Date(), state: .ready)
        stale.refreshError = "Showing last-known usage (couldn't refresh)"
        await provider.set(stale)
        _ = await store.read(provider)
        XCTAssertEqual(store.snapshots["claude"]?.limits.first?.usedPercent, 46)
        XCTAssertEqual(store.snapshots["claude"]?.failedReads, 1)
        _ = await store.read(provider)
        XCTAssertEqual(store.snapshots["claude"]?.failedReads, 2)
    }

    // [2026-11-25 Nav] After a limit and a model switch the Dock showed the plain app icon: Claude Code
    // briefly printed its cost summary, which reads as "no plan". Twice in a row is a failed read.
    @MainActor func testABriefCostSummaryDoesNotHideThePlan() async {
        let provider = SampleProvider("claude", 100)
        let store = UsageStore(providers: [provider])
        _ = await store.read(provider)
        let summary = ClaudeParser.parse("Total cost:            $0.0000\nTotal duration (API):  0s\nUsage:                 0 input, 0 output", now: Date())
        XCTAssertEqual(summary.state, .nonSubscription)
        await provider.set(summary)
        _ = await store.read(provider)
        XCTAssertEqual(store.snapshots["claude"]?.state, .ready)
        XCTAssertEqual(store.snapshots["claude"]?.failedReads, 1)
        XCTAssertEqual(DockSnapshot.resolve(providers: [provider], snapshots: store.snapshots, options: DisplayOptions(), now: .now).indicator.percent, 100)
        _ = await store.read(provider)
        XCTAssertEqual(store.snapshots["claude"]?.failedReads, 2)
        _ = await store.read(provider)
        XCTAssertEqual(store.snapshots["claude"]?.state, .nonSubscription, "the third summary in a row is believed")
    }

    func testOveragesHeaderIsKnown() {
        let text = "You are currently using your overages to power your Claude Code usage. We will automatically switch you back to your subscription rate limits when they reset\n\nCurrent session: 100% used · resets Nov 25 at 12:10pm (America/Los_Angeles)"
        let parsed = ClaudeParser.parse(text, now: Date(timeIntervalSince1970: 1795633000))
        XCTAssertEqual(parsed.state, .ready)
        XCTAssertNil(parsed.rawText)
        XCTAssertEqual(parsed.details.last?.value, "Extra usage until your limits reset")
    }
}
