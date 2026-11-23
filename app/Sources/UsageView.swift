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

private func relative(_ date: Date, _ now: Date) -> String {
    if abs(date.timeIntervalSince(now)) < 5 { return "just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: now)
}

private func countdown(_ date: Date, _ now: Date) -> String {
    let seconds = max(0, Int(ceil(date.timeIntervalSince(now))))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m \(seconds % 60)s" }
    if minutes < 1440 { return "\(minutes / 60)h \(minutes % 60)m" }
    return "\(minutes / 1440)d \(minutes % 1440 / 60)h"
}

private extension LimitWindow {
    var title: String {
        if label == "Current session" { return "Session" }
        if label == "Current week (all models)" { return "Weekly (all models)" }
        if label.hasPrefix("Current week ("), label.hasSuffix(")") { return "Weekly · " + label.dropFirst(14).dropLast() }
        return label
    }
}

struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var preferences: DisplayPreferences
    @ObservedObject var navigation: Navigation
    var settings: () -> Void
    var close: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var provider: (any Provider)? { store.enabled.first { $0.id == navigation.provider } ?? store.enabled.first }
    private var snapshot: ProviderSnapshot? { provider.flatMap { store.snapshots[$0.id] } }

    var body: some View {
        let urgent = snapshot?.limits.contains { limit in
            guard let date = limit.resetsAt else { return false }
            return (0..<3600).contains(date.timeIntervalSinceNow)
        } == true
        TimelineView(.periodic(from: .now, by: urgent ? 1 : 60)) { tick in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ZStack(alignment: .bottomLeading) {
                        Link(destination: URL(string: "https://www.aiusagemenu.com/")!) {
                            HStack(spacing: 8) {
                                KitIcon(name: "BrandMark", size: 32)
                                Text("AI Usage").font(.system(size: 16, weight: .bold)).padding(.bottom, 13)
                            }
                        }.buttonStyle(.plain).accessibilityLabel("AI Usage Menu website")
                        if let snapshot {
                            Text("Updated " + relative(snapshot.asOf, tick.date)).font(.caption2)
                                .foregroundStyle(Color("textSecondary")).padding(.leading, 40)
                                .help(snapshot.asOf.formatted())
                        }
                    }.fixedSize()
                    Spacer(minLength: 2).frame(height: 32).overlay(HeaderDragArea())
                    HStack(spacing: 1) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Button { preferences.options.theme = theme } label: {
                                Image(systemName: theme.symbol).font(.system(size: 11, weight: .medium)).frame(width: 22, height: 22)
                                    .background(preferences.options.theme == theme ? Color("violet") : .clear, in: Circle())
                                    .foregroundStyle(preferences.options.theme == theme ? Color.white : Color("textSecondary"))
                            }.help(theme.rawValue + " appearance").accessibilityLabel(theme.rawValue + " appearance")
                                .accessibilityAddTraits(preferences.options.theme == theme ? .isSelected : [])
                        }
                    }.padding(2).background(Color("surfaceRaised"), in: Capsule())
                    Button(action: store.refreshAll) {
                        RefreshGlyph(running: !store.active.isEmpty && !reduceMotion)
                    }.help("Refresh (⌘R)").accessibilityLabel("Refresh usage")
                    Button(action: settings) { KitIcon(name: "settings") }.help("Settings (⌘,)").accessibilityLabel("Settings")
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 20,height: 22) }
                        .help("Close (⌘W)").accessibilityLabel("Close usage window")
                }.buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 12)

                    HStack(spacing: 4) {
                        ForEach(store.enabled, id: \.id) { p in
                            let selected = p.id == provider?.id
                            Button { navigation.select(p.id) } label: {
                                HStack { KitIcon(name: p.glyph); Text(p.displayName).fontWeight(.semibold) }
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .foregroundStyle(selected ? Color.white : Color("text"))
                                    .background {
                                        if selected { LinearGradient(colors: [Color("violet"),Color(red: 0.75,green: 0.365,blue: 1)], startPoint: .leading, endPoint: .trailing).overlay(Color.black.opacity(0.18)) }
                                    }.clipShape(RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }.padding(4).background(Color("surfaceRaised"), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let provider, let snapshot {
                            if case .limitReached = snapshot.state {
                                Text("Limit reached").font(.headline).foregroundStyle(Color("text"))
                            }
                            if !snapshot.limits.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(snapshot.limits.indices, id: \.self) { i in
                                        if i > 0 { Divider().opacity(0.45).padding(.horizontal, 16) }
                                        LimitRow(limit: snapshot.limits[i], provider: provider.displayName, now: tick.date, thresholds: preferences.options.thresholds)
                                    }
                                }.background(Color("surface"), in: RoundedRectangle(cornerRadius: 17))
                            } else {
                                ProviderMessage(snapshot: snapshot, provider: provider, allMissing: store.enabled.allSatisfy { store.snapshots[$0.id]?.state == .notInstalled }) { store.refresh(provider) }
                            }
                            if !snapshot.details.isEmpty {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 16) { metadata(snapshot) }
                                    VStack(alignment: .leading, spacing: 5) { metadata(snapshot) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 3)
                            }
                            if provider.id == "codex" && !snapshot.limits.isEmpty {
                                Text("As of \(relative(snapshot.asOf, tick.date)) (last Codex activity)").font(.caption).foregroundStyle(Color("textSecondary")).help(snapshot.asOf.formatted())
                            }
                            if let raw = snapshot.rawText, snapshot.state != .nonSubscription {
                                Text(snapshot.state == .ready ? "More from Claude Code" : "What Claude Code printed").font(.caption.bold())
                                Text(raw).font(.caption.monospaced()).textSelection(.enabled)
                            }
                            if let periods = snapshot.breakdown, !periods.isEmpty {
                                Divider().padding(.vertical, 2)
                                BreakdownView(periods: periods)
                            }
                        } else if provider == nil {
                            Text("Choose a provider in Settings to see your usage.")
                            Button("Open Settings", action: settings)
                        } else { Text("Reading usage…").foregroundStyle(Color("textSecondary")) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                Divider()
                HStack {
                    Link(destination: URL(string: "https://typefire.app")!) { HStack(spacing: 4) { Text("From the makers of TypeFire"); KitIcon(name: "external-link", size: 11) } }
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain)
                }.font(.caption).foregroundStyle(Color("textSecondary")).padding(.horizontal, 16).padding(.vertical, 10)
            }.foregroundStyle(Color("text")).background(Color("background"))
        }
        .frame(minWidth: 380, minHeight: 420)
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

    var body: some View {
        let percent = limit.percent(at: now)
        let tint = percent.map { Color(nsColor: thresholds.color($0)) } ?? Color("textSecondary")
        let fraction = min(1, max(0, (percent ?? 0) / 100))
        let reset = limit.resetsAt.map { date in
            date <= now ? "Reset since the last read" : "Resets in " + countdown(date, now)
        } ?? "Reset time unavailable"
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(tint.opacity(0.17), lineWidth: 4)
                if fraction > 0 {
                    Circle().trim(from: 0, to: fraction).stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                Text(percent.map { $0.usageNumber + "%" } ?? "–")
                    .font(.system(size: 16, weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75).padding(.horizontal, 5)
            }.frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(limit.title).font(.headline)
                Text(reset).font(.caption).foregroundStyle(Color("textSecondary"))
                if let date = limit.resetsAt, date > now {
                    Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.caption2).foregroundStyle(Color("textSecondary"))
                }
            }
            Spacer(minLength: 3)
            VStack(alignment: .trailing, spacing: 2) {
                if let percent {
                    Text((100 - percent).usageNumber + "% left").font(.caption.weight(.medium)).foregroundStyle(Color("textSecondary"))
                } else { Text("Unavailable").font(.caption).foregroundStyle(Color("textSecondary")) }
            }.monospacedDigit()
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(Color("text"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([provider, limit.title, percent.map { $0.usageNumber + " percent used" } ?? "Usage unavailable", reset].joined(separator: ", "))
    }
}
