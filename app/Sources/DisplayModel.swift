import AppKit
import SwiftUI

enum Placement: String, CaseIterable, Codable {
    case both = "Menu bar and Dock", menu = "Menu bar only", dock = "Dock only"
}

enum WindowChoice: String, CaseIterable, Codable {
    case highest = "Most constrained", session = "Session", weekly = "Weekly"

    func includes(_ window: LimitWindow) -> Bool {
        let label = window.label.lowercased()
        switch self {
        case .highest: return true
        case .session: return window.windowMinutes == 300 || label == "current session" || label == "session"
        case .weekly: return window.windowMinutes == 10080 || label == "weekly" || label == "current week (all models)" || label == "current week"
        }
    }
}

struct Thresholds: Equatable, Codable {
    var amber = 60
    var red = 85
    func tier(_ value: Double) -> Int { value >= Double(red) ? 3 : value >= Double(amber) ? 2 : 1 }

    func color(_ value: Double, sweep: Bool = false) -> NSColor {
        let colors = ["mint", "amber", "danger"]
        let level = tier(value) - 1
        let end = NSColor(named: colors[level])!.usingColorSpace(.sRGB)!
        guard sweep && level > 0 else { return end }
        let boundary = level == 1 ? amber : red
        let band = max(1, min(6, level == 1 ? red - amber : 100 - red))
        let fraction = min(1, (value - Double(boundary)) / Double(band))
        return NSColor(named: colors[level - 1])!.usingColorSpace(.sRGB)!.blended(withFraction: fraction, of: end) ?? end
    }
}

enum AppTheme: String, CaseIterable, Codable {
    case system = "System", light = "Light", dark = "Dark"
    var symbol: String {
        switch self { case .system: "display"; case .light: "sun.max"; case .dark: "moon" }
    }
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct DisplayOptions: Equatable, Codable {
    var placement = Placement.both
    var separateItems = false
    var showPercent = true
    var dockProvider = "auto"
    var dockWindow = WindowChoice.session
    var menuProvider = "auto"
    var menuWindow = WindowChoice.session
    var theme = AppTheme.system
    var refreshMinutes = 5
    var thresholds = Thresholds()
    var disabled: Set<String> = []

    init() {}

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        placement = try fields.decodeIfPresent(Placement.self, forKey: .placement) ?? .both
        separateItems = try fields.decodeIfPresent(Bool.self, forKey: .separateItems) ?? false
        showPercent = try fields.decodeIfPresent(Bool.self, forKey: .showPercent) ?? true
        dockProvider = try fields.decodeIfPresent(String.self, forKey: .dockProvider) ?? "auto"
        dockWindow = try fields.decodeIfPresent(WindowChoice.self, forKey: .dockWindow) == .weekly ? .weekly : .session
        menuProvider = try fields.decodeIfPresent(String.self, forKey: .menuProvider) ?? "auto"
        menuWindow = try fields.decodeIfPresent(WindowChoice.self, forKey: .menuWindow) == .weekly ? .weekly : .session
        theme = try fields.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        refreshMinutes = try fields.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 5
        thresholds = try fields.decodeIfPresent(Thresholds.self, forKey: .thresholds) ?? Thresholds()
        disabled = try fields.decodeIfPresent(Set<String>.self, forKey: .disabled) ?? []
    }
}

@MainActor
final class DisplayPreferences: ObservableObject {
    @Published var options: DisplayOptions {
        didSet {
            guard options != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(options), forKey: "displayOptions")
            changed?()
        }
    }
    var changed: (() -> Void)?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        options = defaults.data(forKey: "displayOptions").flatMap { try? JSONDecoder().decode(DisplayOptions.self, from: $0) } ?? DisplayOptions()
    }
}

enum Indicator: Equatable {
    case absent, warning, value(Double, String)
    var percent: Double? {
        if case let .value(percent, _) = self { return percent }
        return nil
    }

    static func select(providers: [any Provider], snapshots: [String: ProviderSnapshot], providerID: String = "auto", window: WindowChoice = .highest, at now: Date) -> Indicator {
        var best: Indicator = .absent
        for provider in providers where providerID == "auto" || provider.id == providerID {
            guard let snapshot = snapshots[provider.id], snapshot.state != .notInstalled else { continue }
            if best == .absent { best = .warning }
            switch snapshot.state {
            case .ready, .limitReached:
                for limit in snapshot.limits where window.includes(limit) {
                    if let p = limit.percent(at: now), p > (best.percent ?? -1) { best = .value(p, provider.glyph) }
                }
            default: continue
            }
        }
        return best
    }
}

extension Double {
    var usageNumber: String { formatted(.number.precision(.fractionLength(0...2))) }
}
