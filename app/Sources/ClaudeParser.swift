import Foundation

enum ClaudeParser {
    private static func fields(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map {
            Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? ""
        }
    }

    static func reset(_ text: String, zone: String, after now: Date) -> Date? {
        guard let timeZone = TimeZone(identifier: zone),
              let f = fields(#"^([A-Za-z]{3}) (\d{1,2}) at (\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#, text),
              let month = ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"].firstIndex(of: f[0].lowercased()),
              let day = Int(f[1]), (1...31).contains(day),
              let hour = Int(f[2]), (1...12).contains(hour),
              let minute = Int(f[3].isEmpty ? "0" : f[3]), minute < 60 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents(month: month + 1, day: day, hour: hour % 12 + (f[4].lowercased() == "pm" ? 12 : 0), minute: minute, second: 0)
        let year = calendar.component(.year, from: now)
        var passed: Date?
        for candidateYear in (year - 1)...(year + 1) {
            components.year = candidateYear
            guard let candidate = calendar.date(from: components),
                  calendar.date(candidate, matchesComponents: components) else { return nil }
            if candidate > now { return passed ?? candidate }
            if let repeated = calendar.nextDate(after: candidate.addingTimeInterval(-1), matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last), repeated > now { return passed ?? repeated }
            // A reset time from the last week has passed; it is not next year's. Claude Code prints
            // these when it shows last-known usage because it couldn't refresh (after sleep, 2026-11-25).
            if now.timeIntervalSince(candidate) <= 8 * 86_400 { passed = candidate }
        }
        return passed
    }

    /// True when the text is Claude Code's cost summary ("Estimated cost:" plus a "Usage:" line).
    static func isCostSummary(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let hasCost = lines.contains { $0.hasPrefix("Estimated cost:") || $0.hasPrefix("Total cost:") }
        let hasUsage = lines.contains { $0.hasPrefix("Usage:") }
        return hasCost && hasUsage
    }

    /// Lines Claude Code prints when it shows last-known usage instead of a fresh reading.
    static let staleNotices = ["Showing last-known usage", "Couldn't refresh usage data", "Partial usage data",
                               "Per-model breakdown unavailable", "Claude is temporarily limiting requests to the usage page",
                               "The usage page is "]

    static func parse(_ text: String, now: Date) -> ProviderSnapshot {
        var result = ProviderSnapshot(asOf: now, state: .ready)
        var periods: [BreakdownPeriod] = []
        var unknown: [String] = []
        var index: Int?
        var overages = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "What's contributing to your usage?" || line.hasPrefix("Approximate ·") ||
                line == "You are currently using your subscription to power your Claude Code usage" { continue }
            if line.hasPrefix("You are currently using your overages to power your Claude Code usage") { overages = true; continue }
            if staleNotices.contains(where: line.hasPrefix) {
                // Claude Code couldn't fetch fresh usage (offline right after wake, or its usage page is
                // rate limited) and is printing what it last knew. The numbers still show, but the read
                // counts as failed so the app tries again soon.
                result.refreshError = line
                continue
            }
            if let f = fields(#"^(.+?):\s*(\d+(?:\.\d+)?)% used\s*·\s*resets (.+) \(([^()]+)\)$"#, line),
               let pct = Double(f[1]), pct >= 0, let date = reset(f[2], zone: f[3], after: now) {
                // Past a limit, usage can run over 100% (Claude Code documents this); show it as full.
                result.limits.append(.init(label: f[0], usedPercent: min(pct, 100), resetsAt: date, windowMinutes: nil, source: "Claude Code"))
            } else if let f = fields(#"^(Current [^:]+):\s*(\d+(?:\.\d+)?)% used$"#, line), let pct = Double(f[1]), pct >= 0 {
                // Right after a reset Claude Code prints the window with no reset time until the next
                // window starts ("Current session: 0% used", seen 2026-11-25 12:10 to 12:16).
                result.limits.append(.init(label: f[0], usedPercent: min(pct, 100), resetsAt: nil, windowMinutes: nil, source: "Claude Code"))
            } else if let f = fields(#"^Last (.+?) · ([\d,]+) requests? · ([\d,]+) sessions?$"#, line),
                      let requests = Int(f[1].replacingOccurrences(of: ",", with: "")), let sessions = Int(f[2].replacingOccurrences(of: ",", with: "")) {
                index = periods.count
                periods.append(.init(span: f[0], requests: requests, sessions: sessions))
            } else if let index, let f = fields(#"^(\d+)%\s+(.+?) · (.+)$"#, line), let percent = Int(f[0]), percent <= 100 {
                periods[index].tips.append(.init(name: f[1], percent: percent, detail: f[2]))
            } else if let index, let f = fields(#"^Top ([^:]+): (.+)$"#, line) {
                let items = f[1].components(separatedBy: ", ")
                let values: [Contribution] = items.compactMap { item in
                    guard let pair = fields(#"^(.+) (\d+)%$"#, item), let pct = Int(pair[1]), pct <= 100 else { return nil }
                    return Contribution(name: pair[0], percent: pct, detail: nil)
                }
                periods[index].groups[f[0]] = values
                if values.count != items.count { unknown.append(raw) }
            } else {
                if line.hasPrefix("Last ") { index = nil }
                unknown.append(raw)
            }
        }
        if result.limits.isEmpty, let notice = result.refreshError {
            result.state = .failed(notice)
        } else if result.limits.isEmpty {
            let lower = text.lowercased()
            if ["log in","login","log into","sign in","not logged in","signed out","logged out"].contains(where: lower.contains) {
                result.state = .signedOut
            } else {
                // Only call it "no plan" when Claude Code printed its pay-per-token cost summary,
                // which is what /usage shows for API-key, Bedrock and Vertex sign-ins.
                // Anything else (an error, a changed format, an update notice) is unknownFormat,
                // so a paying user is never told they have no plan.
                result.state = isCostSummary(text) ? .nonSubscription : .unknownFormat
                result.rawText = text
            }
        } else {
            result.details = [.init(label: "Plan", value: "Claude subscription")]
            if overages { result.details.append(.init(label: "Now using", value: "Extra usage until your limits reset")) }
            if !unknown.isEmpty { result.rawText = unknown.joined(separator: "\n") }
        }
        result.breakdown = periods.isEmpty ? nil : periods
        return result
    }
}
