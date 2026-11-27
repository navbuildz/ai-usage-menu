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
        // A window that has reset since the reading shows 0%, never "!" (Codex shows "100% left").
        XCTAssertEqual(Indicator.select(providers: providers, snapshots: ["codex": expired], window: .session, at: now), .value(0, "provider-codex"))
        XCTAssertEqual(Indicator.select(providers: providers, snapshots: ["codex": .init(asOf: now, state: .noSessions)], at: now), .absent)
        XCTAssertEqual(Indicator.select(providers: providers, snapshots: ["codex": .init(asOf: now, state: .timedOut)], at: now), .warning)
        var options = DisplayOptions(); options.dockProvider = "codex"
        XCTAssertEqual(DockSnapshot.resolve(providers: providers, snapshots: ["codex": expired], options: options, now: now).indicator, .value(0, "provider-codex"))
    }

    // [2026-11-23 Nav] A window whose reset time has passed shows 0% used, not "-".
    func testPassedResetReadsZero() {
        let now = date("2026-11-24T06:44:00Z")
        let session = LimitWindow(label: "Session", usedPercent: 99, resetsAt: now.addingTimeInterval(-3600), windowMinutes: 300, source: "Last Codex activity")
        let weekly = LimitWindow(label: "Weekly", usedPercent: 16, resetsAt: now.addingTimeInterval(6 * 86400), windowMinutes: 10080, source: "Last Codex activity")
        XCTAssertEqual(session.percent(at: now), 0)
        XCTAssertTrue(session.hasReset(at: now))
        XCTAssertNil(Pace.elapsedFraction(session, at: now))
        XCTAssertEqual(weekly.percent(at: now), 16)
        XCTAssertNil(LimitWindow(label: "Session", usedPercent: nil, resetsAt: now.addingTimeInterval(-60), windowMinutes: 300, source: "").percent(at: now))
    }

    private func codexLine(_ timestamp: String, session: Double, weekly: Double, limitID: String = "codex") -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"limit_id\":\"\(limitID)\",\"primary\":{\"used_percent\":\(session),\"window_minutes\":300,\"resets_at\":1795493629},\"secondary\":{\"used_percent\":\(weekly),\"window_minutes\":10080,\"resets_at\":1796080429},\"plan_type\":\"plus\"}}}\n"
    }

    // [2026-11-23 Nav] A session started yesterday keeps writing into yesterday's folder, and
    // parallel sessions each log the limits they last saw: the highest reading in a window wins.
    func testCodexReadsYesterdaysLiveSessionAndTakesTheHighestReading() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let manager = FileManager.default
        let yesterday = home.appendingPathComponent("sessions/2026/11/22"), today = home.appendingPathComponent("sessions/2026/11/23")
        try manager.createDirectory(at: yesterday, withIntermediateDirectories: true)
        try manager.createDirectory(at: today, withIntermediateDirectories: true)
        let live = yesterday.appendingPathComponent("rollout-live.jsonl")
        let other = today.appendingPathComponent("rollout-other.jsonl")
        let premiumTail = "{\"timestamp\":\"2026-11-23T23:38:50.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"limit_id\":\"premium\",\"primary\":null,\"secondary\":null,\"plan_type\":\"plus\"}}}\n"
        try (codexLine("2026-11-23T23:38:26.159Z", session: 99, weekly: 16) + premiumTail).write(to: live, atomically: true, encoding: .utf8)
        try (codexLine("2026-11-23T23:38:49.622Z", session: 92, weekly: 14) + premiumTail).write(to: other, atomically: true, encoding: .utf8)
        try manager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -120)], ofItemAtPath: other.path)
        XCTAssertEqual(try CodexProvider.newestRollout(in: home.appendingPathComponent("sessions"))?.lastPathComponent, "rollout-live.jsonl")
        // Make today's file the newest written: the merge must still report yesterday's higher numbers.
        try manager.setAttributes([.modificationDate: Date()], ofItemAtPath: other.path)
        try manager.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -120)], ofItemAtPath: live.path)
        let snapshot = await CodexProvider(home: home).read()
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.limits.map(\.usedPercent), [99, 16])
        let afterReset = Date(timeIntervalSince1970: 1795493629 + 60)
        XCTAssertEqual(snapshot.limits.map { $0.percent(at: afterReset) }, [0, 16])
    }

    // [2026-11-25 Nav] The weekly number can show a model's own weekly limit (Fable); all models by default.
    @MainActor func testWeeklyNumberCanShowAModelsOwnLimit() {
        let now = date("2026-11-25T19:30:00Z")
        var claude = ProviderSnapshot(asOf: now, state: .ready)
        claude.limits = [.init(label: "Current session", usedPercent: 97, resetsAt: now.addingTimeInterval(2400), windowMinutes: nil, source: "Claude Code"),
                         .init(label: "Current week (all models)", usedPercent: 42, resetsAt: now.addingTimeInterval(240000), windowMinutes: nil, source: "Claude Code"),
                         .init(label: "Current week (Fable)", usedPercent: 76, resetsAt: now.addingTimeInterval(240000), windowMinutes: nil, source: "Claude Code")]
        XCTAssertEqual(claude.weeklyModels, ["Fable"])
        let providers: [any Provider] = [ClaudeCodeProvider()]
        let snapshots = ["claude": claude]
        XCTAssertEqual(Indicator.select(providers: providers, snapshots: snapshots, window: .weekly, at: now).percent, 42)
        XCTAssertEqual(Indicator.select(providers: providers, snapshots: snapshots, window: .weekly, weeklyModel: "Fable", at: now).percent, 76)
        XCTAssertEqual(Indicator.select(providers: providers, snapshots: snapshots, window: .weekly, weeklyModel: "Opus", at: now).percent, 42, "a missing model falls back to all models")
        var options = DisplayOptions(); options.twoDockNumbers = true; options.dockProvider = "claude"
        XCTAssertEqual(DockSnapshot.resolve(providers: providers, snapshots: snapshots, options: options, now: now).weekly, 42)
        options.dockWeeklyModel = "Fable"
        let dock = DockSnapshot.resolve(providers: providers, snapshots: snapshots, options: options, now: now)
        XCTAssertEqual(dock.session, 97)
        XCTAssertEqual(dock.weekly, 76)
        // Older saved settings have no weekly choice and decode to all models.
        let old = try! JSONDecoder().decode(DisplayOptions.self, from: Data(#"{"twoDockNumbers":true}"#.utf8))
        XCTAssertEqual(old.dockWeeklyModel, "")
        XCTAssertEqual(old.menuWeeklyModel, "")
    }

    // [2026-11-25 Nav] Past a limit, usage can run over 100%. That reads as full, never as no reading.
    func testUsageOverOneHundredReadsAsFull() {
        let now = date("2026-11-25T19:30:00Z")
        let text = "Current session: 104% used · resets Nov 25 at 12:10pm (America/Los_Angeles)\nCurrent week (all models): 43% used · resets Nov 28 at 7am (America/Los_Angeles)"
        let parsed = ClaudeParser.parse(text, now: now)
        XCTAssertEqual(parsed.state, .ready)
        XCTAssertEqual(parsed.limits.map(\.usedPercent), [100, 43])
        let cache = ClaudeUsageCache.decode(Data(#"{"cachedUsageUtilization":{"fetchedAtMs":1795635350162,"utilization":{"five_hour":{"utilization":112.5,"resets_at":"2026-11-25T20:10:00.097382+00:00"},"seven_day":{"utilization":43,"resets_at":"2026-11-28T15:00:00+00:00"}}}}"#.utf8))
        XCTAssertEqual(cache?.session?.percent, 100)
        let codex = #"{"timestamp":"2026-11-25T19:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":101.0,"window_minutes":300,"resets_at":1795700000},"secondary":{"used_percent":20.0,"window_minutes":10080,"resets_at":1796080429},"plan_type":"plus"}}}"#
        XCTAssertEqual(CodexParser.parse(Data(codex.utf8))?.limits.first?.usedPercent, 100)
    }

    // [2026-11-25 Nav] Right after a reset Claude Code prints "Current session: 0% used" with no reset
    // time. Dropping that line left the Dock with nothing to show (the plain app icon).
    @MainActor func testWindowWithNoResetTimeStillCounts() {
        let now = date("2026-11-25T20:11:00Z")
        let text = "You are currently using your subscription to power your Claude Code usage\n\nCurrent session: 0% used\nCurrent week (all models): 43% used · resets Nov 28 at 7am (America/Los_Angeles)\nCurrent week (Fable): 76% used · resets Nov 28 at 7am (America/Los_Angeles)"
        let parsed = ClaudeParser.parse(text, now: now)
        XCTAssertEqual(parsed.state, .ready)
        XCTAssertEqual(parsed.limits.map(\.label), ["Current session", "Current week (all models)", "Current week (Fable)"])
        XCTAssertEqual(parsed.limits.first?.usedPercent, 0)
        XCTAssertNil(parsed.limits.first?.resetsAt)
        XCTAssertNil(parsed.rawText)
        let dock = DockSnapshot.resolve(providers: [ClaudeCodeProvider()], snapshots: ["claude": parsed], options: DisplayOptions(), now: now)
        XCTAssertEqual(dock.indicator.percent, 0, "the Dock shows 0, not the plain icon")
    }
    // [2026-11-25 Nav] After sleep the Dock showed the plain icon and Refresh did nothing for minutes:
    // Claude Code couldn't fetch usage and printed its last-known numbers, with the session missing.
    @MainActor func testLastKnownUsageAfterSleepStillDrawsAndCountsAsFailed() {
        let now = date("2026-11-26T02:05:00Z") // 6:05pm PT, after a 5:09pm session reset
        let text = "You are currently using your subscription to power your Claude Code usage\n\nCurrent session: 61% used · resets Nov 25 at 5:09pm (America/Los_Angeles)\nCurrent week (all models): 46% used · resets Nov 28 at 6:59am (America/Los_Angeles)\nCurrent week (Fable): 82% used · resets Nov 28 at 6:59am (America/Los_Angeles)\nShowing last-known usage (couldn't refresh)"
        let parsed = ClaudeParser.parse(text, now: now)
        XCTAssertEqual(parsed.state, .ready)
        XCTAssertEqual(parsed.refreshError, "Showing last-known usage (couldn't refresh)")
        XCTAssertNil(parsed.rawText)
        XCTAssertEqual(parsed.limits.first?.resetsAt, date("2026-11-26T01:09:00Z"), "a passed reset stays in the past, not next year")
        XCTAssertEqual(parsed.limits.first?.percent(at: now), 0)
        XCTAssertEqual(ClaudeParser.reset("Dec 31 at 11pm", zone: "America/Los_Angeles", after: date("2027-01-01T09:00:00Z")), date("2027-01-01T07:00:00Z"))
        let limited = ClaudeParser.parse("Claude is temporarily limiting requests to the usage page (not your usage limit). Try again in a moment.", now: now)
        XCTAssertEqual(limited.state, .failed("Claude is temporarily limiting requests to the usage page (not your usage limit). Try again in a moment."))
    }

    @MainActor func testDockShowsTheOtherWindowWhenTheChosenOneIsMissing() {
        let now = date("2026-11-26T02:05:00Z")
        let weeklyOnly = ProviderSnapshot(limits: [.init(label: "Current week (all models)", usedPercent: 46, resetsAt: date("2026-11-28T14:59:00Z"), windowMinutes: nil, source: "Claude Code")], asOf: now, state: .ready)
        let dock = DockSnapshot.resolve(providers: [ClaudeCodeProvider()], snapshots: ["claude": weeklyOnly], options: DisplayOptions(), now: now)
        XCTAssertEqual(dock.indicator.percent, 46, "the Dock shows the weekly number, not the plain icon")
    }
    // [2026-11-26 Nav] Once the 5-hour limit is hit, the Dock's top ring counts down to the reset.
    @MainActor func testFullWindowCountsDownToItsReset() throws {
        let now = date("2026-11-26T20:00:00Z")
        XCTAssertEqual(DockSnapshot.countdown(2 * 3600 + 14 * 60), "2h")
        XCTAssertEqual(DockSnapshot.countdown(47 * 60), "47m")
        XCTAssertEqual(DockSnapshot.countdown(20), "1m")
        XCTAssertEqual(DockSnapshot.countdown(3 * 86_400 + 3600), "3d")
        func reading(session: Double, weekly: Double, weeklyReset: TimeInterval = 3 * 86_400) -> ProviderSnapshot {
            ProviderSnapshot(limits: [
                .init(label: "Current session", usedPercent: session, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60), windowMinutes: nil, source: "Claude Code"),
                .init(label: "Current week (all models)", usedPercent: weekly, resetsAt: now.addingTimeInterval(weeklyReset), windowMinutes: nil, source: "Claude Code")],
                asOf: now, state: .ready)
        }
        var options = DisplayOptions()
        options.twoDockNumbers = true
        let full = DockSnapshot.resolve(providers: [ClaudeCodeProvider()], snapshots: ["claude": reading(session: 100, weekly: 51)], options: options, now: now)
        XCTAssertEqual(full.sessionLeft, 2 * 3600 + 14 * 60)
        XCTAssertNil(full.weeklyLeft)
        XCTAssertEqual(full.session, 100, "the reading itself still says 100")
        let open = DockSnapshot.resolve(providers: [ClaudeCodeProvider()], snapshots: ["claude": reading(session: 64, weekly: 51)], options: options, now: now)
        XCTAssertNil(open.sessionLeft)
        let weeklyFull = DockSnapshot.resolve(providers: [ClaudeCodeProvider()], snapshots: ["claude": reading(session: 100, weekly: 100, weeklyReset: 2 * 86_400 + 5 * 3600)], options: options, now: now)
        XCTAssertEqual(weeklyFull.weeklyLeft, 2 * 86_400 + 5 * 3600)
        var single = DisplayOptions(); single.twoDockNumbers = false
        let one = DockSnapshot.resolve(providers: [ClaudeCodeProvider()], snapshots: ["claude": reading(session: 100, weekly: 51)], options: single, now: now)
        XCTAssertEqual(one.sessionLeft, 2 * 3600 + 14 * 60)
        XCTAssertFalse(one.centerIsWeekly)
        if let look = ProcessInfo.processInfo.environment["LOOK_DIR"].map({ URL(fileURLWithPath: $0) }) {
            for (name, var snap) in [("count-two", full), ("count-both", weeklyFull), ("count-single", one), ("solid-open", open)] {
                for light in [false, true] {
                    snap.light = light
                    let image = DockIconRenderer.image(for: snap, size: 256)
                    if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: look.appendingPathComponent("\(name)-\(light ? "light" : "dark").png"))
                    }
                }
            }
        }
    }

    @MainActor func testMenuBarCountsDownAndDockRingsCanCountDown() async throws {
        struct Fixed: Provider {
            let snapshot: ProviderSnapshot
            var id: String { "claude" }
            var displayName: String { "Claude Code" }
            var glyph: String { "provider-claude-code" }
            func isAvailable() async -> Bool { true }
            func read() async -> ProviderSnapshot { snapshot }
        }
        let now = Date()
        let full = ProviderSnapshot(limits: [
            .init(label: "Current session", usedPercent: 100, resetsAt: now.addingTimeInterval(2 * 3600 + 600), windowMinutes: nil, source: "Claude Code"),
            .init(label: "Current week (all models)", usedPercent: 46, resetsAt: now.addingTimeInterval(3 * 86_400), windowMinutes: nil, source: "Claude Code")],
            asOf: now, state: .ready)
        let store = UsageStore(providers: [Fixed(snapshot: full)])
        _ = await store.read(store.providers[0])
        var options = DisplayOptions()
        let appearance = NSAppearance(named: .darkAqua)!
        let value = store.menuValue("auto", options: options)
        let single = MenuItemVisual(value: value, countdown: store.menuCountdown(value, options: options), provider: nil, options: options, appearance: appearance)
        XCTAssertEqual(single.title, "2h", "a full session reads the time to its reset, not 100%")
        options.twoMenuNumbers = true
        let pair = store.menuPair("auto", options: options)
        let double = MenuItemVisual(value: store.menuValue("auto", options: options), pair: pair, provider: nil, options: options, appearance: appearance)
        XCTAssertEqual(double.usageDescription, "5-hour 2h, weekly 46%")

        // Rings that count down: 75% used draws a quarter ring and reads 25.
        var down = DockSnapshot(indicator: .value(75, "provider-claude-code"), thresholds: Thresholds(), session: 75, weekly: 30)
        let up = DockIconRenderer.image(for: down, size: 128)
        down.countsDown = true
        let shrunk = DockIconRenderer.image(for: down, size: 128)
        XCTAssertNotEqual(up.tiffRepresentation, shrunk.tiffRepresentation)
        var saved = DisplayOptions(); saved.dockRingsCountDown = true
        XCTAssertTrue(try JSONDecoder().decode(DisplayOptions.self, from: JSONEncoder().encode(saved)).dockRingsCountDown)
        XCTAssertFalse(try JSONDecoder().decode(DisplayOptions.self, from: Data("{}".utf8)).dockRingsCountDown, "older settings keep the rings filling up")
        if let look = ProcessInfo.processInfo.environment["LOOK_DIR"].map({ URL(fileURLWithPath: $0) }) {
            for (name, var snap) in [("down-75", down), ("down-two", { var s = down; s.twoNumbers = true; return s }()), ("down-100", DockSnapshot(indicator: .value(96, "g"), thresholds: Thresholds(), session: 96, weekly: 12, countsDown: true))] {
                for light in [false, true] {
                    snap.light = light
                    if let tiff = DockIconRenderer.image(for: snap, size: 256).tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: look.appendingPathComponent("\(name)-\(light ? "light" : "dark").png"))
                    }
                }
            }
        }
    }
}
