import XCTest
@testable import AI_Usage_Menu

/// Tests for the 2026-11-23 hardening pass (audit IDs in brackets).
final class HardeningTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    // [A1] Only Claude Code's cost summary means "no plan". Anything else is an unknown format.
    func testOnlyCostSummaryMeansNoPlan() {
        let now = date("2026-11-23T20:00:00Z")
        let summary = "Estimated cost:        $0.0000\nTotal duration (API):  0s\nUsage:                 0 input, 0 output"
        XCTAssertEqual(ClaudeParser.parse(summary, now: now).state, .nonSubscription)
        for text in ["Error: connect ETIMEDOUT 160.79.104.10:443",
                     "Claude Code has been updated. Restart to continue.",
                     "API Error: 529 Overloaded",
                     "Usage: claude [options]",
                     ""] {
            XCTAssertEqual(ClaudeParser.parse(text, now: now).state, .unknownFormat, text)
        }
    }

    // [A2] Reset times across a year boundary, midnight, noon and a half-hour time zone.
    func testResetDateEdges() {
        let newYearsEve = date("2026-12-31T20:00:00Z")
        XCTAssertEqual(ClaudeParser.reset("Jan 1 at 7am", zone: "America/Los_Angeles", after: newYearsEve), date("2027-01-01T15:00:00Z"))
        let now = date("2026-11-23T20:00:00Z")
        XCTAssertEqual(ClaudeParser.reset("Nov 24 at 12am", zone: "America/Los_Angeles", after: now), date("2026-11-24T08:00:00Z"))
        XCTAssertEqual(ClaudeParser.reset("Nov 24 at 12pm", zone: "America/Los_Angeles", after: now), date("2026-11-24T20:00:00Z"))
        XCTAssertEqual(ClaudeParser.reset("Nov 24 at 9:30am", zone: "Asia/Kolkata", after: now), date("2026-11-24T04:00:00Z"))
        XCTAssertNil(ClaudeParser.reset("Nov 24 at 13pm", zone: "America/Los_Angeles", after: now))
        XCTAssertNil(ClaudeParser.reset("Nov 24 at 9am", zone: "Not/AZone", after: now))
    }

    // [A2] Real subscription output: every window parsed with its value and a future reset.
    func testRealSubscriptionLineParses() {
        let now = date("2026-11-23T23:00:00Z")
        let text = """
        Current session: 13% used · resets Nov 23 at 7:09pm (America/Los_Angeles)
        Current week (all models): 78% used · resets Nov 28 at 6:59am (America/Los_Angeles)
        Current week (Fable): 90% used · resets Nov 28 at 6:59am (America/Los_Angeles)
        """
        let snapshot = ClaudeParser.parse(text, now: now)
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.limits.map(\.usedPercent), [13, 78, 90])
        XCTAssertEqual(snapshot.limits.first?.resetsAt, date("2026-11-24T03:09:00Z"))
        XCTAssertTrue(snapshot.limits.allSatisfy { ($0.resetsAt ?? .distantPast) > now })
    }

    // [A4] With 5,000 old rollout files, finding the newest reads only the newest date folder.
    func testNewestRolloutIgnoresHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = FileManager.default
        for index in 0..<5000 {
            let day = root.appendingPathComponent(String(format: "2025/%02d/%02d", index % 12 + 1, index % 28 + 1))
            try manager.createDirectory(at: day, withIntermediateDirectories: true)
            manager.createFile(atPath: day.appendingPathComponent("rollout-\(index).jsonl").path, contents: Data())
        }
        let today = root.appendingPathComponent("2026/11/23")
        try manager.createDirectory(at: today, withIntermediateDirectories: true)
        let older = today.appendingPathComponent("rollout-a.jsonl"), newest = today.appendingPathComponent("rollout-b.jsonl")
        manager.createFile(atPath: older.path, contents: Data())
        manager.createFile(atPath: newest.path, contents: Data())
        try manager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: older.path)
        let start = Date()
        let found = try CodexProvider.newestRollout(in: root)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(found?.lastPathComponent, "rollout-b.jsonl")
        XCTAssertLessThan(elapsed, 0.05, "newest-rollout search should not walk the history")
    }

    // [A4] A flat rollout from an older Codex version still counts when it is newest.
    func testFlatLegacyRolloutStillFound() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appendingPathComponent("2026/11/20")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: day.appendingPathComponent("rollout-dated.jsonl").path, contents: Data())
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: day.appendingPathComponent("rollout-dated.jsonl").path)
        FileManager.default.createFile(atPath: root.appendingPathComponent("rollout-flat.jsonl").path, contents: Data())
        XCTAssertEqual(try CodexProvider.newestRollout(in: root)?.lastPathComponent, "rollout-flat.jsonl")
    }

    // [A9] Compact surfaces show whole numbers and never round up to 100.
    func testCompactUsage() {
        XCTAssertEqual(12.5.compactUsage, "13")
        XCTAssertEqual(99.6.compactUsage, "99")
        XCTAssertEqual(100.0.compactUsage, "100")
        XCTAssertEqual(0.4.compactUsage, "0")
    }

    // [A7] Alerts follow the health thresholds unless the user chose custom levels.
    func testAlertLevelsFollowHealthByDefault() {
        let defaults = UserDefaults(suiteName: "ai.aiusagemenu.tests.alerts")!
        defaults.removePersistentDomain(forName: "ai.aiusagemenu.tests.alerts")
        let health = Thresholds(amber: 60, red: 85)
        XCTAssertEqual(AppServices.alertLevels(defaults: defaults, health: health), [60, 85])
        defaults.set(70, forKey: "notifyLow"); defaults.set(95, forKey: "notifyHigh")
        XCTAssertEqual(AppServices.alertLevels(defaults: defaults, health: health), [60, 85], "custom values are ignored until turned on")
        defaults.set(true, forKey: "customAlertLevels")
        XCTAssertEqual(AppServices.alertLevels(defaults: defaults, health: health), [70, 95])
    }

    // [A3] The Claude read runs with Claude Code's update check and telemetry off.
    func testChildEnvironmentIsQuiet() throws {
        let output = try LocalCommand.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "printf \"$DISABLE_AUTOUPDATER/$CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC\""],
                                          in: URL(fileURLWithPath: "/"), extraEnvironment: ClaudeCodeProvider.quietEnvironment)
        XCTAssertEqual(output.stdout, "1/1")
    }
}
