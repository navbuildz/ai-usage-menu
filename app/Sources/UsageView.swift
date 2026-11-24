import SwiftUI

@MainActor
final class Navigation: ObservableObject {
    @Published var provider = "claude"
    func select(_ id: String) { provider = id }
}

struct KitIcon: View {
    let name: String
    var size: CGFloat = 16
    var body: some View {
        Image(name).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}

func relative(_ date: Date, _ now: Date) -> String {
    if abs(date.timeIntervalSince(now)) < 5 { return "just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: now)
}

func countdown(_ date: Date, _ now: Date) -> String {
    let seconds = max(0, Int(ceil(date.timeIntervalSince(now))))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    if minutes < 1440 { return "\(minutes / 60)h \(minutes % 60)m" }
    return "\(minutes / 1440)d \(minutes % 1440 / 60)h"
}

/// "5:28 PM" when the reset is today, "Sat 3:36 PM" when it is later.
func resetClock(_ date: Date, _ now: Date) -> String {
    if Calendar.current.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
    return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
}

extension LimitWindow {
    var title: String {
        if label == "Current session" { return "Session" }
        if label == "Current week (all models)" { return "Weekly (all models)" }
        if label.hasPrefix("Current week ("), label.hasSuffix(")") { return "Weekly · " + label.dropFirst(14).dropLast() }
        return label
    }

    /// Window length in minutes, from the source when given, otherwise from the label.
    var lengthMinutes: Int? {
        if let windowMinutes, windowMinutes > 0 { return windowMinutes }
        let lower = label.lowercased()
        if lower.contains("session") { return 300 }
        if lower.contains("week") { return 10080 }
        return nil
    }
}

extension ProviderSnapshot {
    /// Codex numbers come from the last Codex activity, so they can be hours old.
    static let staleAfter: TimeInterval = 30 * 60
    func isStale(providerID: String, at now: Date) -> Bool {
        providerID == "codex" && now.timeIntervalSince(asOf) > Self.staleAfter
    }
}

/// Projects usage at the window's reset from how much of the window has passed.
enum Pace: Equatable {
    case onTrack
    /// Seconds until the window is full at the current pace, when that comes before the reset.
    case fullIn(TimeInterval)

    static func evaluate(_ limit: LimitWindow, at now: Date) -> Pace? {
        guard let percent = limit.percent(at: now), percent >= 5, percent < 100,
              let reset = limit.resetsAt, let minutes = limit.lengthMinutes else { return nil }
        let length = Double(minutes * 60)
        let elapsed = length - reset.timeIntervalSince(now)
        // The first tenth of a window is too noisy to project from.
        guard elapsed >= length * 0.1, elapsed <= length else { return nil }
        let ratePerSecond = percent / elapsed
        let secondsToFull = (100 - percent) / ratePerSecond
        let early = reset.timeIntervalSince(now) - secondsToFull
        return early > 60 ? .fullIn(secondsToFull) : .onTrack
    }

    static func elapsedFraction(_ limit: LimitWindow, at now: Date) -> Double? {
        guard let reset = limit.resetsAt, let minutes = limit.lengthMinutes else { return nil }
        let length = Double(minutes * 60)
        return min(1, max(0, (length - reset.timeIntervalSince(now)) / length))
    }

    var text: String {
        switch self {
        case .onTrack: "On track for this window"
        case .fullIn(let seconds): "At this pace, full in about \(countdown(Date().addingTimeInterval(seconds), Date()))"
        }
    }
}

struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: DisplayPreferences
    @ObservedObject var navigation: Navigation
    var settings: () -> Void
    var close: () -> Void = {}
    /// In the menu bar popover the view sizes itself to its content; in the window it fills the window.
    var fitsContent = false
    /// When set, the panel shows the update banner and a red dot on the Settings button.
    var updates: UpdateService? = nil
    var openUpdate: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 200
    private var provider: (any Provider)? { store.enabled.first { $0.id == navigation.provider } ?? store.enabled.first }
    private var snapshot: ProviderSnapshot? { provider.flatMap { store.snapshots[$0.id] } }
    private static let maxScrollHeight: CGFloat = 520

    var body: some View {
        let urgent = snapshot?.limits.contains { limit in
            guard let date = limit.resetsAt else { return false }
            return (0..<3600).contains(date.timeIntervalSinceNow)
        } == true
        TimelineView(.periodic(from: .now, by: urgent ? 1 : 30)) { tick in
            VStack(spacing: 0) {
                header(tick.date)
                if let updates { UpdateBanner(updates: updates, open: openUpdate) }
                tabs(tick.date)
                ScrollView {
                    content(tick.date)
                        .background(GeometryReader { proxy in Color.clear.preference(key: HeightKey.self, value: proxy.size.height) })
                }
                .frame(height: fitsContent ? min(contentHeight, Self.maxScrollHeight) : nil)
                .onPreferenceChange(HeightKey.self) { height in
                    if abs(height - contentHeight) > 1 { contentHeight = height }
                }
                Divider()
                footer
            }.foregroundStyle(Color("text")).background(Color("background"))
        }
        .frame(width: fitsContent ? 380 : nil)
        .frame(minWidth: 380, minHeight: fitsContent ? nil : 420)
    }

    // MARK: Header

    private func header(_ now: Date) -> some View {
        HStack(spacing: 10) {
            Link(destination: URL(string: "https://aiusagemenu.com/")!) {
                HStack(spacing: 8) {
                    KitIcon(name: "BrandMark", size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("AI Usage Menu").font(.system(size: 15, weight: .bold))
                        Text(snapshot.map { "Updated " + relative($0.asOf, now) } ?? "Reading…")
                            .font(.caption2).foregroundStyle(Color("textSecondary"))
                    }
                }
            }.buttonStyle(.plain).accessibilityLabel("AI Usage Menu website").fixedSize()
            Spacer(minLength: 4).frame(height: 32).overlay(HeaderDragArea())
            HeaderButton(help: "Refresh (⌘R)", label: "Refresh usage", action: store.refreshAll) {
                RefreshGlyph(running: !store.active.isEmpty && !reduceMotion)
            }
            HeaderButton(help: "Settings (⌘,)", label: "Settings", action: settings) {
                KitIcon(name: "settings").overlay(alignment: .topTrailing) {
                    if let updates { UpdateDot(updates: updates).offset(x: 4, y: -4) }
                }
            }
            HeaderButton(help: "Close (⌘W)", label: "Close", action: close) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
            }
        }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
    }

    // MARK: Provider tabs

    private func tabs(_ now: Date) -> some View {
        HStack(spacing: 4) {
            ForEach(store.enabled, id: \.id) { item in
                let selected = item.id == provider?.id
                Button { navigation.select(item.id) } label: {
                    HStack(spacing: 6) {
                        KitIcon(name: item.glyph)
                        Text(item.displayName).fontWeight(.semibold)
                        Circle().fill(statusColor(for: item.id, now)).frame(width: 6, height: 6)
                            .accessibilityLabel(statusLabel(for: item.id, now))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .foregroundStyle(selected ? Color.white : Color("text"))
                    .background(selected ? Color("violet") : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(3).background(Color("surfaceRaised"), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 14)
    }

    private func statusColor(for id: String, _ now: Date) -> Color {
        guard let snapshot = store.snapshots[id] else { return Color("textSecondary").opacity(0.4) }
        switch snapshot.state {
        case .ready, .limitReached:
            return snapshot.isStale(providerID: id, at: now) ? Color("textSecondary") : Color("mint")
        case .failed, .timedOut, .unreadable, .unknownFormat: return Color("danger")
        default: return Color("textSecondary").opacity(0.4)
        }
    }

    private func statusLabel(for id: String, _ now: Date) -> String {
        guard let snapshot = store.snapshots[id] else { return "Not read yet" }
        if snapshot.isStale(providerID: id, at: now) { return "Reading from an earlier session" }
        return snapshot.state.detectionLabel
    }

    // MARK: Content

    @ViewBuilder private func content(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let provider, let snapshot {
                let stale = snapshot.isStale(providerID: provider.id, at: now)
                if !snapshot.limits.isEmpty {
                    SummaryLine(limits: snapshot.limits, state: snapshot.state, stale: stale, now: now, thresholds: preferences.options.thresholds)
                    VStack(spacing: 0) {
                        ForEach(snapshot.limits.indices, id: \.self) { index in
                            if index > 0 { Divider().opacity(0.45).padding(.horizontal, 16) }
                            LimitRow(limit: snapshot.limits[index], provider: provider.displayName, now: now,
                                     thresholds: preferences.options.thresholds, stale: stale)
                        }
                    }.background(Color("surface"), in: RoundedRectangle(cornerRadius: 16))
                    if stale {
                        Label("From your last Codex session \(relative(snapshot.asOf, now)). Numbers update when you use Codex again.", systemImage: "clock")
                            .font(.caption).foregroundStyle(Color("textSecondary"))
                            .help(snapshot.asOf.formatted())
                    }
                } else {
                    ProviderMessage(snapshot: snapshot, provider: provider,
                                    allMissing: store.enabled.allSatisfy { store.snapshots[$0.id]?.state == .notInstalled }) { store.refresh(provider) }
                }
                if !snapshot.details.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { metadata(snapshot) }
                        VStack(alignment: .leading, spacing: 5) { metadata(snapshot) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 3)
                }
                if let raw = snapshot.rawText, snapshot.state == .ready {
                    RawOutput(text: raw, title: "More from Claude Code")
                }
                if let periods = snapshot.breakdown, !periods.isEmpty {
                    Divider().padding(.vertical, 2)
                    BreakdownView(periods: periods)
                }
            } else if provider == nil {
                Text("Turn on a provider in Settings to see your usage.")
                Button("Open Settings", action: settings).buttonStyle(PrimaryButtonStyle())
            } else {
                Text("Reading usage…").foregroundStyle(Color("textSecondary"))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Link(destination: URL(string: "https://typefire.app")!) {
                HStack(spacing: 4) { Text("From the makers of TypeFire"); KitIcon(name: "external-link", size: 11) }
            }
            Spacer()
            if store.lowPower {
                Label("Low Power: Claude every \(UsageStore.lowPowerMinutes) min", systemImage: "leaf")
                    .labelStyle(.titleAndIcon).help("Low Power Mode is on, so Claude Code is read less often.")
            }
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
        }.font(.caption).foregroundStyle(Color("textSecondary")).padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder private func metadata(_ snapshot: ProviderSnapshot) -> some View {
        ForEach(snapshot.details.indices, id: \.self) { index in
            let row = snapshot.details[index]
            let version = row.label == "Claude Code"
            HStack(spacing: 4) {
                Text(version ? "CLI version" : row.label).foregroundStyle(Color("textSecondary"))
                Text(version ? row.value.replacingOccurrences(of: " (Claude Code)", with: "") : row.value).fontWeight(.medium)
            }.font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A 28-point header button with a hover state.
private struct HeaderButton<Label: View>: View {
    let help: String
    let label: String
    let action: () -> Void
    @ViewBuilder let content: () -> Label
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            content().frame(width: 28, height: 28)
                .background(hovering ? Color("surfaceRaised") : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(label)
        .onHover { hovering = $0 }
    }
}

/// One sentence for the most constrained window: what a glance needs.
private struct SummaryLine: View {
    let limits: [LimitWindow]
    let state: ProviderState
    let stale: Bool
    let now: Date
    let thresholds: Thresholds
    var body: some View {
        let top = limits.compactMap { limit in limit.percent(at: now).map { (limit, $0) } }.max { $0.1 < $1.1 }
        if case .limitReached = state {
            Label("Limit reached", systemImage: "exclamationmark.octagon.fill").font(.headline).foregroundStyle(Color("danger"))
        } else if let (limit, percent) = top {
            let reset = limit.resetsAt.map { " · resets in " + countdown($0, now) } ?? ""
            HStack(spacing: 6) {
                Circle().fill(stale ? Color("textSecondary") : Color(nsColor: thresholds.color(percent))).frame(width: 8, height: 8)
                Text("\(limit.title) \(percent.compactUsage)% used" + reset).font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct RefreshGlyph: View {
    var running: Bool
    var body: some View {
        if running {
            ProgressView().controlSize(.small).frame(width: 16, height: 16)
        } else {
            KitIcon(name: "refresh")
        }
    }
}

private struct HeaderDragArea: NSViewRepresentable {
    final class Handle: NSView {
        override func mouseDown(with event: NSEvent) {
            if window?.styleMask.contains(.resizable) == true { window?.performDrag(with: event) }
        }
    }
    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) {}
}

private struct LimitRow: View {
    let limit: LimitWindow
    let provider: String
    let now: Date
    let thresholds: Thresholds
    let stale: Bool

    var body: some View {
        let percent = limit.percent(at: now)
        let tint = stale ? Color("textSecondary") : (percent.map { Color(nsColor: thresholds.color($0, sweep: true)) } ?? Color("textSecondary"))
        let fraction = min(1, max(0, (percent ?? 0) / 100))
        let elapsed = Pace.elapsedFraction(limit, at: now)
        let pace = stale ? nil : Pace.evaluate(limit, at: now)
        let reset: String = limit.resetsAt.map { date in
            date <= now ? "Reset since the last read" : "Resets in " + countdown(date, now) + " · " + resetClock(date, now)
        } ?? "Reset time unavailable"
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(tint.opacity(0.17), lineWidth: 4)
                if fraction > 0 {
                    Circle().trim(from: 0, to: fraction).stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                if let elapsed, percent != nil {
                    // A tick at how much of the window has passed, to compare usage against time.
                    Capsule().fill(Color("text").opacity(0.55)).frame(width: 2, height: 8)
                        .offset(y: -26).rotationEffect(.degrees(elapsed * 360))
                        .accessibilityHidden(true)
                }
                Text(percent.map { $0.compactUsage + "%" } ?? "–")
                    .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 5)
            }.frame(width: 52, height: 52).opacity(stale ? 0.6 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(limit.title).font(.headline)
                Text(reset).font(.caption).foregroundStyle(Color("textSecondary"))
                if let pace {
                    Text(pace.text).font(.caption.weight(.medium))
                        .foregroundStyle(pace == .onTrack ? Color("textSecondary") : Color(nsColor: thresholds.color(90)))
                }
            }
            Spacer(minLength: 3)
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(Color("text"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel(percent: percent, reset: reset, pace: pace))
    }

    private func spokenLabel(percent: Double?, reset: String, pace: Pace?) -> String {
        var parts: [String] = [provider, limit.title]
        if let percent {
            let used: String = percent.compactUsage
            let left: String = (100 - percent).compactUsage
            parts.append(used + " percent used, " + left + " percent left")
        } else {
            parts.append("Usage unavailable")
        }
        parts.append(reset)
        if let pace { parts.append(pace.text) }
        if stale { parts.append("from an earlier session") }
        return parts.joined(separator: ", ")
    }
}

/// Violet filled button that keeps its color in inactive windows and popovers.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color("violet").opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Quiet outlined button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout.weight(.medium)).foregroundStyle(Color("text"))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color("surfaceRaised").opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color("border").opacity(0.5)))
    }
}

/// A switch that is violet when on and gray when off, in active and inactive windows alike
/// (the system switch turns gray when its window is not key, so on and off looked the same).
struct VioletSwitch: ToggleStyle {
    /// Settings rows draw their own label beside the switch, so they pass false.
    var showsLabel = true
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if showsLabel {
                configuration.label
                Spacer(minLength: 0)
            }
            Capsule()
                .fill(configuration.isOn ? Color("violet") : Color("border").opacity(0.55))
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 1, y: 1).padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                .contentShape(Capsule())
                .onTapGesture { configuration.isOn.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}
