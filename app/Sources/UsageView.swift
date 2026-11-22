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
                                    .background(preferences.options.theme == theme ? Color("surface") : .clear, in: Circle())
                                    .foregroundStyle(preferences.options.theme == theme ? Color("violet") : Color("textSecondary"))
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
                                        if selected { LinearGradient(colors: [Color("violet"),Color(red: 0.75,green: 0.365,blue: 1)], startPoint: .leading, endPoint: .trailing) }
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
                                LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], spacing: 8) {
                                    ForEach(snapshot.limits.indices, id: \.self) { i in
                                        LimitCard(limit: snapshot.limits[i], provider: provider.displayName, now: tick.date, asOf: snapshot.asOf, thresholds: preferences.options.thresholds)
                                    }
                                }
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
                            if let raw = snapshot.rawText {
                                Text("Couldn't read this, showing it as Claude Code printed it").font(.caption.bold())
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
            }.font(.caption).fixedSize(horizontal: true, vertical: false)
        }
    }

}

private struct RefreshGlyph: View {
    var running: Bool
    var body: some View {
        if running {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { tick in
                KitIcon(name: "refresh").rotationEffect(.degrees(tick.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) * 300))
            }
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

private struct LimitCard: View {
    let limit: LimitWindow
    let provider: String
    let now: Date
    let asOf: Date
    let thresholds: Thresholds
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let percent = limit.percent(at: now)
        let tint = percent.map { thresholds.color($0) } ?? .secondaryLabelColor
        let ink: NSColor = scheme == .light ? (tint.blended(withFraction: 0.55, of: NSColor.black) ?? tint) : tint
        let percentageLabel = percent.map { $0.usageNumber + " percent used" } ?? "Usage unavailable"
        let resetLabel = limit.resetsAt.map { ", resets " + $0.formatted() } ?? ""
        let spoken = [provider, limit.title, percentageLabel + resetLabel].joined(separator: ", ")
        VStack(alignment: .leading, spacing: 6) {
            Text(limit.title).font(.caption.weight(.semibold))
            if let percent {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(percent.usageNumber + "%").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Color(nsColor: ink))
                    Text((100 - percent).usageNumber + "% left").font(.caption2).foregroundStyle(Color("textSecondary"))
                }.minimumScaleFactor(0.75)
            }
            GeometryReader { geo in
                Capsule().fill(Color("border").opacity(0.5)).overlay(alignment: .leading) {
                    Capsule().fill(Color(nsColor: tint)).frame(width: geo.size.width * (percent ?? 0) / 100)
                }
            }.frame(height: 6)
            if let reset = limit.resetsAt, reset <= now {
                Text(provider == "Codex" ? "Reset since your last Codex session" : "Reset since the last read")
            } else if let date = limit.resetsAt {
                Text("Resets in " + countdown(date, now))
                Text(Calendar.current.isDateInToday(date) ? "Today " + date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
            } else { Text("Reset time unavailable") }
            if percent == nil && (limit.resetsAt ?? .distantFuture) > now { Text("Usage unavailable") }
            if provider == "Codex" { Text("As of " + relative(asOf, now)) }
        }.font(.caption).monospacedDigit().foregroundStyle(Color("textSecondary")).frame(maxWidth: .infinity, alignment: .leading).padding(11)
            .background(Color("surface"), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("border"), lineWidth: 0.7))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: percent)
            .accessibilityElement(children: .combine).accessibilityLabel(spoken)
    }
}
