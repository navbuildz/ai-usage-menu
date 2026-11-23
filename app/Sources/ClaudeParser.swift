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
        for candidateYear in year...(year + 1) {
            components.year = candidateYear
            guard let candidate = calendar.date(from: components),
                  calendar.date(candidate, matchesComponents: components) else { return nil }
            if candidate > now { return candidate }
            if let repeated = calendar.nextDate(after: candidate.addingTimeInterval(-1), matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last), repeated > now { return repeated }
        }
        return nil
    }

    static func parse(_ text: String, now: Date) -> ProviderSnapshot {
        var result = ProviderSnapshot(asOf: now, state: .ready)
        var periods: [BreakdownPeriod] = []
        var unknown: [String] = []
        var index: Int?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "What's contributing to your usage?" || line.hasPrefix("Approximate ·") ||
                line == "You are currently using your subscription to power your Claude Code usage" { continue }
            if let f = fields(#"^(.+?):\s*(\d+(?:\.\d+)?)% used\s*·\s*resets (.+) \(([^()]+)\)$"#, line),
               let pct = Double(f[1]), (0...100).contains(pct), let date = reset(f[2], zone: f[3], after: now) {
                result.limits.append(.init(label: f[0], usedPercent: pct, resetsAt: date, windowMinutes: nil, source: "Claude Code"))
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
        if result.limits.isEmpty {
            let lower = text.lowercased()
            if ["log in","login","log into","sign in","not logged in","signed out","logged out"].contains(where: lower.contains) {
                result.state = .signedOut
            } else {
                let header = "You are currently using your subscription to power your Claude Code usage"
                result.state = text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(header) ? .unknownFormat : .nonSubscription
                result.rawText = text
            }
        } else {
            result.details = [.init(label: "Plan", value: "Claude subscription")]
            if !unknown.isEmpty { result.rawText = unknown.joined(separator: "\n") }
        }
        result.breakdown = periods.isEmpty ? nil : periods
        return result
    }
}
