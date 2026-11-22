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
    func isAvailable() -> Bool { true }
    func read() async -> ProviderSnapshot {
        reads += 1
        try? await Task.sleep(for:.milliseconds(20))
        return snapshot
    }
}

final class UsageStoreTests: XCTestCase {
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
        await waitForChanges(2) { store.refreshAll(); store.refreshAll() }
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
        XCTAssertEqual(store.snapshots["codex"]?.state, .noLimits)

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
}
