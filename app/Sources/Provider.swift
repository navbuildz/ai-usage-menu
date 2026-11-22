import Foundation

protocol Provider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var glyph: String { get }
    var watchedDirectory: URL? { get }
    func isAvailable() async -> Bool
    func read() async -> ProviderSnapshot
}

extension Provider {
    var watchedDirectory: URL? { nil }
}

enum ProviderState: Equatable {
    case ready, notInstalled, signedOut, nonSubscription, timedOut, unknownFormat
    case noSessions, noLimits, unreadable, failed(String), limitReached(String)
}

struct LimitWindow {
    let label: String
    let usedPercent: Double?
    let resetsAt: Date?
    let windowMinutes: Int?
    let source: String

    func percent(at time: Date) -> Double? {
        if let resetsAt, resetsAt <= time { return nil }
        return usedPercent
    }
}

struct DetailRow { let label: String; let value: String }
struct Contribution { let name: String; let percent: Int; let detail: String? }
struct BreakdownPeriod {
    let span: String
    let requests: Int
    let sessions: Int
    var tips: [Contribution] = []
    var groups: [String: [Contribution]] = [:]
}

struct ProviderSnapshot {
    var limits: [LimitWindow] = []
    var details: [DetailRow] = []
    var breakdown: [BreakdownPeriod]?
    var asOf: Date
    var state: ProviderState
    var rawText: String?
}
