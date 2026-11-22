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
              event.type == "event_msg", event.payload.type == "token_count",
              let limits = event.payload.rate_limits else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: event.timestamp) ?? ISO8601DateFormatter().date(from: event.timestamp)
        guard let date else { return nil }
        var result = ProviderSnapshot(asOf: date, state: .ready)
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
        else if result.limits.isEmpty { result.state = .noLimits }
        return result
    }
}

struct CodexProvider: Provider {
    let id = "codex", displayName = "Codex", glyph = "provider-codex"
    let home: URL
    init(home: URL = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) { self.home = home }
    var watchedDirectory: URL? { home.appendingPathComponent("sessions") }
    func isAvailable() async -> Bool { FileManager.default.fileExists(atPath: home.path) }
    func read() async -> ProviderSnapshot {
        guard await isAvailable() else { return .init(asOf: Date(), state: .notInstalled) }
        let root = home.appendingPathComponent("sessions")
        guard FileManager.default.fileExists(atPath: root.path) else { return .init(asOf: Date(), state: .noSessions) }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        var failed = false
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, _ in failed = true; return true })
        var newest: (url: URL, date: Date)?
        do {
            while let url = walk?.nextObject() as? URL {
                guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix("rollout-") else { continue }
                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true, values.isSymbolicLink != true, let date = values.contentModificationDate else { continue }
                if newest == nil || date > newest!.date || (date == newest!.date && url.path > newest!.url.path) { newest = (url,date) }
            }
            guard !failed, walk != nil else { return .init(asOf: Date(), state: .unreadable) }
            guard let newest else { return .init(asOf: Date(), state: .noSessions) }
            return try Self.latest(in: newest.url) ?? .init(asOf: Date(), state: .noLimits)
        } catch { return .init(asOf: Date(), state: .unreadable) }
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
                guard !skippingLongLine, suffix.range(of: Data("\"rate_limits\"".utf8)) != nil else { return nil }
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
