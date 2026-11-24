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

    /// Usage at `time`. Once the window's reset time has passed nothing has been used in the
    /// new window yet, so a known reading becomes 0 (Codex shows "100% left" then too).
    func percent(at time: Date) -> Double? {
        guard let usedPercent else { return nil }
        if hasReset(at: time) { return 0 }
        return usedPercent
    }

    func hasReset(at time: Date) -> Bool { resetsAt.map { $0 <= time } ?? false }
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

extension ProviderSnapshot {
    var onboardingStatus: String {
        if state == .nonSubscription { return "API key (no plan limits)" }
        if state == .ready || details.contains(where: { $0.label == "Plan" }) { return "Plan: subscription" }
        if case .limitReached = state { return "Plan: subscription" }
        return state.detectionLabel
    }
}
