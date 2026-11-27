import AppKit
import SwiftUI

enum Placement: String, CaseIterable, Codable {
    case both = "Menu bar and Dock", menu = "Menu bar only", dock = "Dock only", hidden = "Both hidden"

    var showsMenu: Bool {
        get { self == .both || self == .menu }
        set { self = newValue ? (showsDock ? .both : .menu) : (showsDock ? .dock : .hidden) }
    }
    var showsDock: Bool {
        get { self == .both || self == .dock }
        set { self = newValue ? (showsMenu ? .both : .dock) : (showsMenu ? .menu : .hidden) }
    }
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

extension LimitWindow {
    /// The model a per-model weekly window is for ("Fable" for "Current week (Fable)"), or nil
    /// for the session and the all-models weekly window.
    var weeklyModel: String? {
        let lower = label.lowercased()
        guard lower.hasPrefix("current week ("), label.hasSuffix(")"), lower != "current week (all models)" else { return nil }
        let name = label.dropFirst("Current week (".count).dropLast()
        return name.isEmpty ? nil : String(name)
    }
}

extension ProviderSnapshot {
    /// Per-model weekly windows in this reading, in the order Claude Code prints them.
    var weeklyModels: [String] { limits.compactMap(\.weeklyModel) }
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
    var twoMenuNumbers = false
    var twoDockNumbers = false
    var dockWindow = WindowChoice.session
    var menuProvider = "auto"
    var menuWindow = WindowChoice.session
    /// Which weekly window the menu bar and Dock show: "" for all models, or a model name such as
    /// "Fable" for that model's own weekly limit (falls back to all models when it isn't there).
    var menuWeeklyModel = ""
    var dockWeeklyModel = ""
    /// Dock rings start empty and fill as you use a limit (false), or start full and shrink to
    /// what is left, with the number showing percent left (true).
    var dockRingsCountDown = false
    var dockTheme = AppTheme.system
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
        twoMenuNumbers = try fields.decodeIfPresent(Bool.self, forKey: .twoMenuNumbers) ?? false
        twoDockNumbers = try fields.decodeIfPresent(Bool.self, forKey: .twoDockNumbers) ?? false
        dockWindow = try fields.decodeIfPresent(WindowChoice.self, forKey: .dockWindow) == .weekly ? .weekly : .session
        menuProvider = try fields.decodeIfPresent(String.self, forKey: .menuProvider) ?? "auto"
        menuWindow = try fields.decodeIfPresent(WindowChoice.self, forKey: .menuWindow) == .weekly ? .weekly : .session
        menuWeeklyModel = try fields.decodeIfPresent(String.self, forKey: .menuWeeklyModel) ?? ""
        dockWeeklyModel = try fields.decodeIfPresent(String.self, forKey: .dockWeeklyModel) ?? ""
        dockRingsCountDown = try fields.decodeIfPresent(Bool.self, forKey: .dockRingsCountDown) ?? false
        dockTheme = try fields.decodeIfPresent(AppTheme.self, forKey: .dockTheme) ?? .system
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

    static func select(providers: [any Provider], snapshots: [String: ProviderSnapshot], providerID: String = "auto", window: WindowChoice = .highest, weeklyModel: String = "", at now: Date) -> Indicator {
        var best: Indicator = .absent
        for provider in providers where providerID == "auto" || provider.id == providerID {
            guard let snapshot = snapshots[provider.id], snapshot.state != .notInstalled else { continue }
            // "!" means something is wrong. A reading that is simply not in yet, or whose window has
            // reset since it was taken, shows the plain icon instead (first launch showed "!" for seconds).
            if best == .absent && snapshot.state.isProblem { best = .warning }
            switch snapshot.state {
            case .ready, .limitReached:
                var limits = snapshot.limits.filter(window.includes)
                if window == .weekly, !weeklyModel.isEmpty {
                    let model = snapshot.limits.filter { $0.weeklyModel?.lowercased() == weeklyModel.lowercased() }
                    if !model.isEmpty { limits = model }
                }
                for limit in limits {
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
    /// Whole number for the menu bar and Dock, where there is no room for decimals.
    /// Never rounds up to 100 unless the window is actually full.
    var compactUsage: String {
        let whole = Int(rounded())
        return String(self < 100 ? min(99, whole) : whole)
    }
}

extension ProviderState {
    /// States the user should act on. Waiting, no plan and no sessions are not problems.
    var isProblem: Bool {
        switch self {
        case .failed, .timedOut, .unreadable, .unknownFormat, .signedOut: true
        default: false
        }
    }
}
