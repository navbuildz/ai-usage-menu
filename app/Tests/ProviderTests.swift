import AppKit
import XCTest
@testable import AI_Usage_Menu

final class ProviderTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-22T16:00:00Z")!
    private func fixture(_ name: String, _ ext: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testClaudeFixture() throws {
        let s = ClaudeParser.parse(try fixture("subscription","txt"), now: now)
        XCTAssertEqual(s.limits.compactMap(\.usedPercent), [94,57,90])
        XCTAssertNil(s.rawText)
        XCTAssertEqual(s.breakdown?.map(\.requests), [2446,9769])
        XCTAssertEqual(s.breakdown?.map(\.sessions), [16,18])
        XCTAssertEqual(s.breakdown?.map { $0.tips.count }, [4,4])
        XCTAssertEqual(s.breakdown?.first?.groups["skills"]?.first?.name, "/claude-api")
        XCTAssertEqual(s.breakdown?.last?.groups["MCP servers"]?.last?.percent, 1)
        XCTAssertEqual(s.breakdown?.first?.groups["subagents"]?.first?.name, "general-purpose")
    }

    func testClaudeVariants() {
        let line = "New budget: 0% used · resets Jan 2 at 7am (Asia/Tokyo)"
        let bad = "Current session: ?% used · resets tomorrow"
        let s = ClaudeParser.parse([line,bad,"extra text"].joined(separator: "\n"), now: now)
        XCTAssertEqual(s.state,.ready)
        XCTAssertEqual(s.limits.first?.label,"New budget")
        XCTAssertEqual(s.limits.first?.resetsAt,ISO8601DateFormatter().date(from:"2027-01-01T22:00:00Z"))
        XCTAssertEqual(s.rawText,bad+"\nextra text")
        XCTAssertNil(s.breakdown)
        for (text,state) in [("Please log in",ProviderState.signedOut),("Signed in with an API key",.nonSubscription),("Bedrock",.nonSubscription),("garbage",.nonSubscription),("You are currently using your subscription to power your Claude Code usage",.unknownFormat)] {
            let parsed = ClaudeParser.parse(text, now: now)
            XCTAssertEqual(parsed.state,state)
            XCTAssertTrue(parsed.limits.isEmpty)
            if state == .unknownFormat { XCTAssertEqual(parsed.rawText,text) }
        }
    }

    func testPlanCompatibilityFixtures() async throws {
        // Illustrative Claude wording until a real API-key account can be observed.
        let text = try fixture("claude-api-key-guessed","txt")
        let claude = ClaudeParser.parse(text, now: now)
        XCTAssertEqual(claude.state, .nonSubscription)
        XCTAssertEqual(claude.rawText, text)
        XCTAssertTrue(claude.limits.isEmpty)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let auth = home.appendingPathComponent("auth.json")
        try fixture("auth-apikey","json").write(to: auth, atomically: true, encoding: .utf8)
        let mode: String? = try CodexProvider.authMode(in: auth)
        XCTAssertEqual(mode, "apikey")
        let file = sessions.appendingPathComponent("rollout-test.jsonl")
        try fixture("rate-limits","jsonl").write(to: file, atomically: true, encoding: .utf8)
        let provider = CodexProvider(home: home)
        let api = await provider.read()
        XCTAssertEqual(api.state, .nonSubscription)
        XCTAssertTrue(api.limits.isEmpty)
        try Data(#"{"auth_mode":"chatgpt"}"#.utf8).write(to: auth)
        let lines = try fixture("rate-limits","jsonl") + "\n" + fixture("null-limits","jsonl")
        try lines.write(to: file, atomically: true, encoding: .utf8)
        let waiting = await provider.read()
        XCTAssertEqual(waiting.state, .noSessions)
        XCTAssertEqual(waiting.onboardingStatus, "Plan: subscription")
        XCTAssertTrue(waiting.limits.isEmpty)
    }

    func testResetMath() {
        let iso = ISO8601DateFormatter()
        let zone = "America/New_York"
        let winter = iso.date(from:"2026-01-01T00:00:00Z")!
        XCTAssertEqual(ClaudeParser.reset("Mar 8 at 3:01am", zone: zone, after: winter),iso.date(from:"2026-03-08T07:01:00Z"))
        XCTAssertNil(ClaudeParser.reset("Mar 8 at 2:30am", zone: zone, after: winter))
        XCTAssertEqual(ClaudeParser.reset("Nov 1 at 1:30am",zone: zone, after: iso.date(from:"2026-11-01T05:45:00Z")!),iso.date(from:"2026-11-01T06:30:00Z"))
        XCTAssertNil(ClaudeParser.reset("Feb 31 at 7am",zone: zone,after: winter))
        XCTAssertNil(ClaudeParser.reset("Apr 1 at 7am",zone: "invalid",after: winter))
    }

    func testCodexWindowsAndNulls() throws {
        let text = try fixture("rate-limits","jsonl")
        let s = try XCTUnwrap(CodexParser.parse(Data(text.utf8)))
        XCTAssertEqual(s.limits.map(\.label),["Session","Weekly"])
        XCTAssertEqual(s.details.first?.value,"Plus")
        XCTAssertEqual(s.details.count,1)
        XCTAssertNil(s.limits.first?.percent(at: Date(timeIntervalSince1970:1795345015)))
        XCTAssertEqual(s.limits.last?.percent(at: now),14)
        let variant = text.replacingOccurrences(of: "300,", with: "240,").replacingOccurrences(of: "0.0,", with: "null,").replacingOccurrences(of: "\"rate_limit_reached_type\":null", with: "\"rate_limit_reached_type\":\"weekly\"").replacingOccurrences(of: "\"unlimited\":false",with:"\"unlimited\":true")
        let reached = try XCTUnwrap(CodexParser.parse(Data(variant.utf8)))
        XCTAssertEqual(reached.state,.limitReached("weekly"))
        XCTAssertEqual(reached.limits.first?.label,"240 min")
        XCTAssertNil(reached.limits.first?.percent(at:now))
        XCTAssertEqual(reached.details.last?.value,"Unlimited")
        XCTAssertNil(CodexParser.parse(Data(text.replacingOccurrences(of: "token_count", with:"other").utf8)))
    }

    func testAuxiliaryQuotaDoesNotHideCodexWindows() throws {
        let base = try fixture("rate-limits","jsonl")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let auxiliary = #"{"timestamp":"2026-11-23T10:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"premium","plan_type":"plus","primary":null,"secondary":null}}}"#
        try (base + "\n" + auxiliary).write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try CodexProvider.latest(in: file)?.limits.count, 2)
    }

    func testLargeTail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let event = try fixture("rate-limits","jsonl")
        try Data(event.utf8).write(to:url)
        let file = try FileHandle(forWritingTo:url)
        try file.seek(toOffset: 50 * 1024 * 1024)
        try file.write(contentsOf: Data(("\n"+event.replacingOccurrences(of:"14.0",with:"38.0")+"{partial").utf8))
        try file.close()
        let start = ProcessInfo.processInfo.systemUptime
        let latest = try CodexProvider.latest(in:url)
        let ms = (ProcessInfo.processInfo.systemUptime-start)*1000
        print("50 MiB tail read: \(ms) ms")
        XCTAssertLessThan(ms,50)
        XCTAssertEqual(latest?.limits.last?.usedPercent,38)
    }

    func testCodexFileStates() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let provider = CodexProvider(home: home)
        let missing = await provider.read()
        XCTAssertEqual(missing.state,.notInstalled)
        let folder = home.appendingPathComponent("sessions/2026/11/22")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:home) }
        let empty = await provider.read()
        XCTAssertEqual(empty.state,.noSessions)
        try Data("unknown".utf8).write(to:folder.appendingPathComponent("rollout-test.jsonl"))
        let unknown = await provider.read()
        XCTAssertEqual(unknown.state,.nonSubscription)
    }

    func testChildIOAndTimeout() throws {
        let dir = URL(fileURLWithPath:"/")
        let output = try LocalCommand.run(URL(fileURLWithPath:"/bin/sh"),["-c","printf usage; printf diagnostic >&2; exit 1"],in:dir)
        XCTAssertEqual(output.stdout,"usage")
        XCTAssertEqual(output.stderr,"diagnostic")
        XCTAssertEqual(output.status,1)
        XCTAssertThrowsError(try LocalCommand.run(URL(fileURLWithPath:"/bin/sleep"),["3"],in:dir,timeout:0.1)) { XCTAssertTrue($0 is LocalCommand.Failure) }
    }

    func testNoNetworkCodeOutsideUpdater() throws {
        let dir = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at:dir,includingPropertiesForKeys:nil))
        for case let file as URL in files where file.pathExtension == "swift" && !file.pathComponents.contains("Updater") {
            let code = try String(contentsOf:file,encoding:.utf8)
            XCTAssertNil(code.range(of:#"\b(URLSession\w*|NWConnection\w*|CFStream\w*|CF(Read|Write)StreamCreatePairWithSocket\w*|socket|connect|getaddrinfo)\b|import\s+(Network|CFNetwork)\b"#,options:.regularExpression),file.lastPathComponent)
        }
    }

    func testLiveProviders() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["AI_USAGE_MENU_LIVE"] == "1")
        for provider: any Provider in [ClaudeCodeProvider(),CodexProvider()] {
            let snapshot = await provider.read()
            if provider.id == "codex" { print("Codex read state: \(snapshot.state)") }
            XCTAssertFalse(snapshot.limits.isEmpty,"\(provider.displayName) returned no windows")
            print("\(provider.displayName): \(snapshot.limits.count) parsed windows")
        }
    }
}
