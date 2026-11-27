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

struct LimitWindow: Codable {
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

struct DetailRow: Codable { let label: String; let value: String }
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
    /// Reads in a row that failed since this reading was taken. The reading stays on screen while
    /// they fail, so one bad read never blanks the menu bar and Dock; the panel shows the count.
    var failedReads = 0
    /// What the most recent failed read said, for the panel's details.
    var refreshError: String?
    /// True for a reading restored from the last time the app ran, shown until the first read lands.
    var restored = false
}

/// The last good reading per provider, saved so the menu bar and Dock show numbers the moment
/// the app opens instead of the plain icon while Claude Code starts (Nav, 2026-11-25).
struct SavedReading: Codable {
    let limits: [LimitWindow]
    let details: [DetailRow]
    let asOf: Date
    let limitReached: String?

    init?(_ snapshot: ProviderSnapshot) {
        guard !snapshot.limits.isEmpty else { return nil }
        switch snapshot.state {
        case .ready: limitReached = nil
        case .limitReached(let text): limitReached = text
        default: return nil
        }
        limits = snapshot.limits; details = snapshot.details; asOf = snapshot.asOf
    }

    var snapshot: ProviderSnapshot {
        var restored = ProviderSnapshot(limits: limits, details: details, asOf: asOf, state: limitReached.map { .limitReached($0) } ?? .ready)
        restored.restored = true
        return restored
    }

    static let key = "lastReadings"
    static func load(from defaults: UserDefaults) -> [String: ProviderSnapshot] {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode([String: SavedReading].self, from: data) else { return [:] }
        // A reading older than a week has nothing left to say: every window in it has reset.
        return saved.filter { Date().timeIntervalSince($0.value.asOf) < 7 * 86_400 }.mapValues(\.snapshot)
    }
    static func save(_ snapshots: [String: ProviderSnapshot], to defaults: UserDefaults) {
        let saved = snapshots.compactMapValues { SavedReading($0) }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: key) }
    }
}

extension ProviderSnapshot {
    /// A failed read keeps the last good reading on screen when the failure is temporary
    /// (an error, a timeout, output it couldn't parse). Being signed out, an API key or Claude
    /// Code missing are real answers and replace the reading.
    func keepingReading(after failure: ProviderSnapshot) -> ProviderSnapshot? {
        guard state == .ready || { if case .limitReached = state { return true }; return false }(),
              !limits.isEmpty else { return nil }
        let detail: String
        switch failure.state {
        case .failed(let text): detail = text
        case .timedOut: detail = "The read timed out."
        case .unknownFormat: detail = failure.rawText ?? "The output was not in a format the app knows."
        case .unreadable: detail = "The usage file could not be read."
        case .nonSubscription where failedReads < 2:
            // Claude Code prints its pay-per-use cost summary when, for a moment, it doesn't see the
            // subscription (seen after a limit and a model switch). One or two in a row after a plan
            // reading are treated as a failed read; the third in a row is believed.
            detail = "Claude Code printed its cost summary instead of your plan limits."
        default: return nil
        }
        var kept = self
        kept.failedReads += 1
        kept.refreshError = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return kept
    }
}

extension ProviderSnapshot {
    var onboardingStatus: String {
        if state == .nonSubscription { return "API key (no plan limits)" }
        if state == .ready || details.contains(where: { $0.label == "Plan" }) { return "Plan: subscription" }
        if case .limitReached = state { return "Plan: subscription" }
        return state.detectionLabel
    }
}
