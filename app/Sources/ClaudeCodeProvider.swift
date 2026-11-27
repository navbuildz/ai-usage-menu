// Claude Code provider: the code that touches your Claude data.
// Reads:  the claude binary's location, and one field of ~/.claude.json, cachedUsageUtilization,
//         which Claude Code refreshes during /usage (no other field is decoded).
// Runs:   your own `claude -p /usage` (and `claude --version` once), from
//         ~/Library/Application Support/AI Usage Menu/claude-workdir, with no MCP servers,
//         no user settings, hooks or plugins, and Claude Code's update check off.
// Writes: nothing itself. Claude Code may update its own files under ~/.claude.
// Sends:  nothing itself. Claude Code contacts Anthropic to fetch your usage, as /usage does.

import Foundation
import Darwin

struct CommandOutput {
    var status: Int32
    var stdout: String
    var stderr: String
}

// Drain both pipes while the child runs, including when a verbose CLI fills stderr.
enum LocalCommand {
    enum Failure: Error { case timedOut, oversized }
    static func run(_ binary: URL, _ arguments: [String], in directory: URL, timeout: TimeInterval = 20, extraEnvironment: [String: String] = [:]) throws -> CommandOutput {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if !extraEnvironment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(extraEnvironment) { _, new in new }
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let handles = [output.fileHandleForReading, errors.fileHandleForReading]
        for handle in handles {
            let fd = handle.fileDescriptor
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0 else { throw POSIXError(.EIO) }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        try process.run()
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        var buffers = [Data(), Data()]
        var bytes = [UInt8](repeating: 0, count: 16384)
        var finished = [false,false]
        while process.isRunning || finished.contains(false) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure.timedOut }
            for index in handles.indices where !finished[index] {
                let count = Darwin.read(handles[index].fileDescriptor, &bytes, bytes.count)
                if count > 0 {
                    buffers[index].append(contentsOf: bytes.prefix(count))
                    if buffers[index].count > 4 * 1024 * 1024 { throw Failure.oversized }
                } else if count == 0 { finished[index] = true }
                else if errno != EWOULDBLOCK && errno != EINTR { throw POSIXError(.EIO) }
            }
            if process.isRunning || finished.contains(false) { Thread.sleep(forTimeInterval: 0.005) }
        }
        return .init(status: process.terminationStatus, stdout: String(decoding: buffers[0], as: UTF8.self), stderr: String(decoding: buffers[1], as: UTF8.self))
    }
    /// Runs the command on a utility dispatch thread so a slow child (up to the timeout)
    /// never occupies a thread from Swift's small cooperative pool.
    static func runOffPool(_ binary: URL, _ arguments: [String], in directory: URL, timeout: TimeInterval = 20, extraEnvironment: [String: String] = [:]) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try run(binary, arguments, in: directory, timeout: timeout, extraEnvironment: extraEnvironment) })
            }
        }
    }
}

actor ClaudeCodeProvider: Provider {
    let id = "claude", displayName = "Claude Code", glyph = "provider-claude-code"
    private var cached: URL?
    private var version: String?
    private var attemptedShell = false
    private var lastOverride: String?
    /// Claude Code skips its own update check during the read. Do NOT add
    /// CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: it stops /usage from fetching usage at all, so Claude
    /// Code prints its cache, and prints no limits once that cache is about an hour old (found 2026-11-23).
    static let quietEnvironment = ["DISABLE_AUTOUPDATER": "1"]
    private let workdir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AI Usage Menu/claude-workdir")

    func resolve() async -> URL? {
        let override = UserDefaults.standard.string(forKey: "claudePath")
        if override != lastOverride || cached.map({ !FileManager.default.isExecutableFile(atPath: $0.path) }) == true {
            cached = nil; version = nil; attemptedShell = false; lastOverride = override
        }
        if let cached { return cached }
        var paths = [override, "~/.local/bin/claude", "~/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"].compactMap { $0 }
        paths = paths.map { ($0 as NSString).expandingTildeInPath }
        if let found = paths.first(where: FileManager.default.isExecutableFile(atPath:)) {
            cached = URL(fileURLWithPath: found)
        } else if !attemptedShell {
            attemptedShell = true
            // The login shell runs the user's profile, so it gets a short timeout and runs once per launch.
            if let shell = try? await LocalCommand.runOffPool(URL(fileURLWithPath: "/bin/zsh"), ["-lc","command -v claude"], in: URL(fileURLWithPath: "/"), timeout: 5),
               let path = shell.stdout.split(separator: "\n").last.map(String.init), path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) { cached = URL(fileURLWithPath: path) }
        }
        return cached
    }

    func isAvailable() async -> Bool { await resolve() != nil }
    func read() async -> ProviderSnapshot {
        guard let binary = await resolve() else { return .init(asOf: Date(), state: .notInstalled) }
        let started = Date()
        do {
            try FileManager.default.createDirectory(at: workdir, withIntermediateDirectories: true)
            let output = try await LocalCommand.runOffPool(binary, ["-p","/usage","--output-format","json","--no-session-persistence","--strict-mcp-config","--mcp-config",#"{"mcpServers":{}}"#,"--setting-sources","project,local"], in: workdir, extraEnvironment: Self.quietEnvironment)
            struct Envelope: Decodable { let result: String }
            let body = (try? JSONDecoder().decode(Envelope.self, from: Data(output.stdout.utf8)))?.result ?? output.stdout
            var snapshot = ClaudeParser.parse(body.isEmpty ? output.stderr : body, now: Date())
            // /usage prints Claude Code's cached figures, then refreshes the cache. Use the refreshed
            // session and weekly numbers when this run wrote them, so the app is never one read behind.
            if let cache = ClaudeUsageCache.read(), cache.fetchedAt >= started.addingTimeInterval(-1) {
                snapshot.limits = ClaudeUsageCache.apply(cache, to: snapshot.limits)
            }
            if output.status != 0, snapshot.state != .signedOut, !(snapshot.state == .nonSubscription && !body.isEmpty && output.stderr.isEmpty) {
                return .init(asOf: Date(), state: .failed(output.stderr.isEmpty ? body : output.stderr))
            }
            if version == nil, let result = try? await LocalCommand.runOffPool(binary, ["--version"], in: workdir, timeout: 5), result.status == 0 {
                version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let version { snapshot.details.append(.init(label: "Claude Code", value: version)) }
            return snapshot
        } catch LocalCommand.Failure.timedOut { return .init(asOf: Date(), state: .timedOut) }
        catch { return .init(asOf: Date(), state: .failed(error.localizedDescription)) }
    }
}

/// The usage figures Claude Code caches in ~/.claude.json after fetching them from Anthropic.
/// Only the cachedUsageUtilization field is decoded; the rest of the file is never read into memory as values.
struct ClaudeUsageCache: Equatable {
    struct Window: Equatable { let percent: Double; let resetsAt: Date? }
    let fetchedAt: Date
    let session: Window?
    let weekly: Window?

    static func read(from file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")) -> ClaudeUsageCache? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> ClaudeUsageCache? {
        struct Raw: Decodable { let utilization: Double?; let resets_at: String? }
        struct Utilization: Decodable { let five_hour: Raw?; let seven_day: Raw? }
        struct Cache: Decodable { let fetchedAtMs: Double; let utilization: Utilization }
        struct File: Decodable { let cachedUsageUtilization: Cache? }
        guard let cache = (try? JSONDecoder().decode(File.self, from: data))?.cachedUsageUtilization else { return nil }
        func window(_ raw: Raw?) -> Window? {
            guard let value = raw?.utilization, value >= 0, value.isFinite else { return nil }
            return Window(percent: min(value, 100), resetsAt: raw?.resets_at.flatMap(date))
        }
        return .init(fetchedAt: Date(timeIntervalSince1970: cache.fetchedAtMs / 1000),
                     session: window(cache.utilization.five_hour), weekly: window(cache.utilization.seven_day))
    }

    /// Accepts "2026-11-24T03:10:00.253520+00:00" (microseconds) by dropping the fraction.
    static func date(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }

    /// Replaces the session and all-models weekly figures; per-model windows keep the printed values.
    static func apply(_ cache: ClaudeUsageCache, to limits: [LimitWindow]) -> [LimitWindow] {
        limits.map { limit in
            let label = limit.label.lowercased()
            let fresh: Window? = label == "current session" ? cache.session
                : label == "current week (all models)" ? cache.weekly : nil
            guard let fresh else { return limit }
            return LimitWindow(label: limit.label, usedPercent: fresh.percent, resetsAt: fresh.resetsAt ?? limit.resetsAt,
                               windowMinutes: limit.windowMinutes, source: limit.source)
        }
    }
}
