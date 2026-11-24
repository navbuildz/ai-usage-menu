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

    // [A3] The Claude read skips Claude Code's update check, and must never disable its usage fetch.
    func testChildEnvironment() throws {
        XCTAssertNil(ClaudeCodeProvider.quietEnvironment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"],
                     "this variable stops /usage from fetching, so limits go stale and then disappear")
        let output = try LocalCommand.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "printf \"$DISABLE_AUTOUPDATER\""],
                                          in: URL(fileURLWithPath: "/"), extraEnvironment: ClaudeCodeProvider.quietEnvironment)
        XCTAssertEqual(output.stdout, "1")
    }

    // [D3] Pace: projection from the share of the window that has passed.
    func testPace() {
        let now = date("2026-11-23T20:00:00Z")
        func session(_ percent: Double, resetIn minutes: Double) -> LimitWindow {
            LimitWindow(label: "Current session", usedPercent: percent, resetsAt: now.addingTimeInterval(minutes * 60), windowMinutes: nil, source: "test")
        }
        // 2.5 h of 5 h passed at 80%: full in 37.5 min, long before the reset in 150 min.
        guard case .fullIn(let seconds)? = Pace.evaluate(session(80, resetIn: 150), at: now) else { return XCTFail("expected fullIn") }
        XCTAssertEqual(seconds, 37.5 * 60, accuracy: 1)
        // 2.5 h passed at 40%: would reach 80% by the reset, so on track.
        XCTAssertEqual(Pace.evaluate(session(40, resetIn: 150), at: now), .onTrack)
        // First tenth of the window, low usage, full and unknown length: no projection.
        XCTAssertNil(Pace.evaluate(session(30, resetIn: 290), at: now))
        XCTAssertNil(Pace.evaluate(session(3, resetIn: 100), at: now))
        XCTAssertNil(Pace.evaluate(session(100, resetIn: 100), at: now))
        XCTAssertNil(Pace.evaluate(LimitWindow(label: "New budget", usedPercent: 50, resetsAt: now.addingTimeInterval(600), windowMinutes: nil, source: "t"), at: now))
        XCTAssertEqual(Pace.elapsedFraction(session(10, resetIn: 150), at: now) ?? -1, 0.5, accuracy: 0.001)
    }

    // [A6] Only Codex readings go stale, after 30 minutes.
    func testStaleness() {
        let now = date("2026-11-23T20:00:00Z")
        let old = ProviderSnapshot(asOf: now.addingTimeInterval(-31 * 60), state: .ready)
        XCTAssertTrue(old.isStale(providerID: "codex", at: now))
        XCTAssertFalse(old.isStale(providerID: "claude", at: now))
        XCTAssertFalse(ProviderSnapshot(asOf: now.addingTimeInterval(-29 * 60), state: .ready).isStale(providerID: "codex", at: now))
    }

    // [D7] Diagnostics never carry the home path or an email address.
    func testDiagnosticsRedaction() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let text = "Trim \(home)/notes/INDEX.md for someone@example.com"
        let redacted = Diagnostics.redact(text)
        XCTAssertFalse(redacted.contains(home))
        XCTAssertFalse(redacted.contains("someone@example.com"))
        XCTAssertTrue(redacted.contains("~/notes/INDEX.md"))
    }

    // [B5] The Dock tile redraws only when the picture changes.
    @MainActor func testDockTileRendersOncePerChange() {
        let store = UsageStore(providers: [])
        let controller = DockTileController()
        var options = DisplayOptions()
        options.placement = .both
        options.dockTheme = .dark
        for _ in 0..<100 { controller.update(store: store, options: options) }
        XCTAssertEqual(controller.renderCount, 1)
        options.dockTheme = .light
        controller.update(store: store, options: options)
        XCTAssertEqual(controller.renderCount, 2)
        options.placement = .menu
        controller.update(store: store, options: options)
        XCTAssertNil(controller.rendered)
    }

    // The app was one read behind: /usage prints the cached figures, then refreshes the cache.
    func testFreshCacheOverridesPrintedSessionAndWeekly() throws {
        let json = #"{"numStartups":3,"cachedUsageUtilization":{"fetchedAtMs":1795480178322,"accountUuid":"x","utilization":{"five_hour":{"utilization":25,"resets_at":"2026-11-24T03:10:00.253520+00:00"},"seven_day":{"utilization":80,"resets_at":"2026-11-28T15:00:00.253539+00:00"},"seven_day_opus":null,"extra_usage":{"utilization":null,"resets_at":null},"usage_scopes":[]}}}"#
        let cache = try XCTUnwrap(ClaudeUsageCache.decode(Data(json.utf8)))
        XCTAssertEqual(cache.session, .init(percent: 25, resetsAt: date("2026-11-24T03:10:00Z")))
        XCTAssertEqual(cache.weekly?.percent, 80)
        let now = date("2026-11-24T00:30:00Z")
        let printed = ClaudeParser.parse("""
        Current session: 17% used · resets Nov 23 at 7:09pm (America/Los_Angeles)
        Current week (all models): 79% used · resets Nov 28 at 6:59am (America/Los_Angeles)
        Current week (Fable): 90% used · resets Nov 28 at 6:59am (America/Los_Angeles)
        """, now: now).limits
        let merged = ClaudeUsageCache.apply(cache, to: printed)
        XCTAssertEqual(merged.map(\.usedPercent), [25, 80, 90])
        XCTAssertEqual(merged[0].resetsAt, date("2026-11-24T03:10:00Z"))
        XCTAssertNil(ClaudeUsageCache.decode(Data(#"{"numStartups":3}"#.utf8)))
    }

    // 2026-11-23: Claude Code was chosen, its read failed, and the menu bar showed Codex's number.
    @MainActor func testChosenProviderIsNeverSwappedForAnother() async {
        struct Fixed: Provider {
            let id: String; let snapshot: ProviderSnapshot
            var displayName: String { id }
            var glyph: String { id == "claude" ? "provider-claude-code" : "provider-codex" }
            func isAvailable() async -> Bool { true }
            func read() async -> ProviderSnapshot { snapshot }
        }
        let now = Date()
        var codex = ProviderSnapshot(asOf: now, state: .ready)
        codex.limits = [.init(label: "Session", usedPercent: 92, resetsAt: now.addingTimeInterval(3600), windowMinutes: 300, source: "c")]
        let claudeFailed = ProviderSnapshot(asOf: now, state: .unknownFormat, rawText: "no limits printed")
        let store = UsageStore(providers: [Fixed(id: "claude", snapshot: claudeFailed), Fixed(id: "codex", snapshot: codex)])
        for provider in store.providers { _ = await store.read(provider) }
        var options = DisplayOptions()
        options.menuProvider = "claude"
        XCTAssertEqual(store.menuValue("auto", options: options), .warning, "Claude chosen and unreadable must show a warning, not Codex")
        options.twoMenuNumbers = true
        XCTAssertNil(store.menuPair("auto", options: options).session)
        options.dockProvider = "claude"
        XCTAssertEqual(DockSnapshot.resolve(providers: store.displayProviders, snapshots: store.snapshots, options: options, now: now).indicator, .warning)
        options.menuProvider = "auto"; options.twoMenuNumbers = false
        XCTAssertEqual(store.menuValue("auto", options: options).percent, 92, "Auto still picks the provider with a reading")
    }

    // First launch showed "!" while readings were still arriving. Only real problems warn.
    @MainActor func testNoWarningWhileWaitingOrAfterReset() {
        let now = Date()
        var expired = ProviderSnapshot(asOf: now.addingTimeInterval(-7200), state: .ready)
        expired.limits = [.init(label: "Session", usedPercent: 92, resetsAt: now.addingTimeInterval(-60), windowMinutes: 300, source: "c")]
        let providers: [any Provider] = [CodexProvider()]
        XCTAssertEqual(Indicator.select(providers: providers, snapshots: ["codex": expired], window: .session, at: now), .absent)
        XCTAssertEqual(Indicator.select(providers: providers, snapshots: ["codex": .init(asOf: now, state: .noSessions)], at: now), .absent)
        XCTAssertEqual(Indicator.select(providers: providers, snapshots: ["codex": .init(asOf: now, state: .timedOut)], at: now), .warning)
        var options = DisplayOptions(); options.dockProvider = "codex"
        XCTAssertEqual(DockSnapshot.resolve(providers: providers, snapshots: ["codex": expired], options: options, now: now).indicator, .absent)
    }
}
