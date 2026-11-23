import Foundation

enum CodexParser {
    private struct Window: Decodable {
        var used_percent: Double?
        var window_minutes: Int?
        var resets_at: Double?
    }
    private struct Credits: Decodable {
        var has_credits: Bool?
        var unlimited: Bool?
        var balance: String?
    }
    private struct Limits: Decodable {
        var limit_id: String?
        var primary: Window?
        var secondary: Window?
        var plan_type: String?
        var credits: Credits?
        var rate_limit_reached_type: String?
    }
    private struct Event: Decodable {
        struct Payload: Decodable {
            var type: String
            var rate_limits: Limits?
        }
        var timestamp: String
        var type: String
        var payload: Payload
    }

    static func parse(_ line: Data) -> ProviderSnapshot? {
        guard let event = try? JSONDecoder().decode(Event.self, from: line),
              event.type == "event_msg", event.payload.type == "token_count" else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: event.timestamp) ?? ISO8601DateFormatter().date(from: event.timestamp)
        guard let date else { return nil }
        var result = ProviderSnapshot(asOf: date, state: .ready)
        guard let limits = event.payload.rate_limits else { result.state = .noLimits; return result }
        if let id = limits.limit_id, id != "codex" { return nil }
        for window in [limits.primary, limits.secondary].compactMap({ $0 }) {
            let label: String
            switch window.window_minutes {
            case 300: label = "Session"
            case 10080: label = "Weekly"
            case let minutes? where minutes > 0: label = "\(minutes) min"
            default: label = "Usage window"
            }
            let pct = window.used_percent.flatMap { (0...100).contains($0) ? $0 : nil }
            result.limits.append(.init(label: label, usedPercent: pct, resetsAt: window.resets_at.map(Date.init(timeIntervalSince1970:)), windowMinutes: window.window_minutes, source: "Last Codex activity"))
        }
        if let plan = limits.plan_type { result.details.append(.init(label: "Plan", value: plan.capitalized)) }
        if let credits = limits.credits, credits.unlimited == true || credits.has_credits == true {
            result.details.append(.init(label: "Credits", value: credits.unlimited == true ? "Unlimited" : credits.balance ?? "Available"))
        }
        if let reached = limits.rate_limit_reached_type { result.state = .limitReached(reached) }
        else if result.limits.allSatisfy({ $0.usedPercent == nil }) { result.state = .noLimits; result.limits = [] }
        return result
    }
}

struct CodexProvider: Provider {
    let id = "codex", displayName = "Codex", glyph = "provider-codex"
    let home: URL
    init(home: URL = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) { self.home = home }
    var watchedDirectory: URL? { home.appendingPathComponent("sessions") }
    func isAvailable() async -> Bool { FileManager.default.fileExists(atPath: home.path) }
    static func authMode(in file: URL) throws -> String? {
        struct Mode: Decodable { let auth_mode: String? }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(Mode.self, from: Data(contentsOf: file, options: .mappedIfSafe)).auth_mode
    }

    func read() async -> ProviderSnapshot {
        guard await isAvailable() else { return .init(asOf: Date(), state: .notInstalled) }
        let mode: String?
        do { mode = try Self.authMode(in: home.appendingPathComponent("auth.json")) }
        catch { return .init(asOf: Date(), state: .unreadable) }
        // auth.json can be absent when Codex keeps its sign-in in the keychain, so a missing
        // mode is not "signed out" or "API key": we still read the sessions and let them decide.
        if let mode, mode != "chatgpt" { return .init(asOf: Date(), state: .nonSubscription) }
        let waiting = ProviderSnapshot(details: mode == "chatgpt" ? [.init(label: "Plan", value: "ChatGPT subscription")] : [], asOf: Date(), state: .noSessions)
        let root = home.appendingPathComponent("sessions")
        guard FileManager.default.fileExists(atPath: root.path) else { return waiting }
        do {
            guard let newest = try Self.newestRollout(in: root) else { return waiting }
            if let snapshot = try Self.latest(in: newest), snapshot.state != .noLimits { return snapshot }
            return waiting
        } catch { return .init(asOf: Date(), state: .unreadable) }
    }

    /// Finds the most recently modified rollout file without walking the whole history.
    /// Codex stores sessions as sessions/YYYY/MM/DD/rollout-*.jsonl, so we look in the newest
    /// date folder that has any rollout file. Older Codex versions wrote rollouts directly
    /// into sessions/, so those are compared too.
    static func newestRollout(in root: URL) throws -> URL? {
        let manager = FileManager.default
        func children(_ folder: URL) throws -> [URL] {
            try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        }
        func numberedFolders(_ folder: URL) throws -> [URL] {
            try children(folder)
                .filter { Int($0.lastPathComponent) != nil && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { Int($0.lastPathComponent)! > Int($1.lastPathComponent)! }
        }
        var candidates = try rollouts(in: try children(root))
        search: for year in try numberedFolders(root) {
            for month in try numberedFolders(year) {
                for day in try numberedFolders(month) {
                    let found = try rollouts(in: try children(day))
                    if !found.isEmpty { candidates += found; break search }
                }
            }
        }
        return candidates.max { $0.date < $1.date || ($0.date == $1.date && $0.url.path < $1.url.path) }?.url
    }

    private static func rollouts(in urls: [URL]) throws -> [(url: URL, date: Date)] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        return try urls.compactMap { url in
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-") else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true, let date = values.contentModificationDate else { return nil }
            return (url, date)
        }
    }

    static func latest(in file: URL) throws -> ProviderSnapshot? {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var position = try handle.seekToEnd()
        var suffix = Data()
        var skippingLongLine = false
        while position > 0 {
            let length = Int(min(position, 65536))
            position -= UInt64(length)
            try handle.seek(toOffset: position)
            guard let data = try handle.read(upToCount: length), data.count == length else { throw CocoaError(.fileReadUnknown) }
            var end = data.endIndex
            func consume(_ part: Data.SubSequence, complete: Bool) -> ProviderSnapshot? {
                if !skippingLongLine {
                    if part.count + suffix.count > 1024 * 1024 { skippingLongLine = true; suffix.removeAll() }
                    else { suffix = Data(part) + suffix }
                }
                guard complete else { return nil }
                defer { suffix.removeAll(); skippingLongLine = false }
                guard !skippingLongLine, suffix.range(of: Data("\"token_count\"".utf8)) != nil else { return nil }
                return CodexParser.parse(suffix)
            }
            while let newline = data[..<end].lastIndex(of: 10) {
                if let snapshot = consume(data[(newline+1)..<end], complete: true) { return snapshot }
                end = newline
            }
            if let snapshot = consume(data[..<end], complete: position == 0) { return snapshot }
        }
        return nil
    }
}
