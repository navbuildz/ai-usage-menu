import SwiftUI

struct BreakdownView: View {
    let periods: [BreakdownPeriod]
    @State private var selection = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                KitIcon(name: "breakdown", size: 18).foregroundStyle(Color("orchid"))
                Text("What's contributing?").font(.system(size: 15, weight: .bold))
                Spacer(minLength: 2)
                HStack(spacing: 2) {
                    ForEach(periods.indices, id: \.self) { i in
                        Button("Last " + periods[i].span) { selection = i }
                            .buttonStyle(.plain).font(.caption.weight(.medium)).fixedSize()
                            .padding(.horizontal, 5).padding(.vertical, 4)
                            .foregroundStyle(i == selection ? Color("violet") : Color("textSecondary"))
                            .background(i == selection ? Color("violet").opacity(0.12) : .clear, in: Capsule())
                            .accessibilityAddTraits(i == selection ? .isSelected : [])
                    }
                }.padding(2).background(Color("surfaceRaised"), in: Capsule())
            }
            if let period = periods.indices.contains(selection) ? periods[selection] : periods.first {
                Text("\(period.requests.formatted()) requests · \(period.sessions.formatted()) sessions").font(.subheadline.weight(.semibold))
                Text("Approximate · this Mac only · shares overlap").font(.caption).foregroundStyle(Color("textSecondary"))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(period.tips.indices, id: \.self) { i in
                        let tip = period.tips[i]
                        if i > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(shortTitle(tip.name)).font(.system(size: 12, weight: .semibold)).help(tip.name)
                                Spacer(minLength: 2)
                                Text("\(tip.percent)%").font(.caption.monospacedDigit().bold()).fixedSize()
                            }
                            if let detail = tip.detail {
                                if detail.hasPrefix("run /") {
                                    Text(String(detail.dropFirst(4))).font(.caption.monospaced()).padding(.horizontal, 6).background(Color("surfaceRaised"), in: Capsule())
                                } else { Text(detail).font(.caption).foregroundStyle(Color("textSecondary")) }
                            }
                            GeometryReader { geo in
                                Capsule().fill(Color("border").opacity(0.3)).overlay(alignment: .leading) {
                                    Capsule().fill(Color("orchid")).frame(width: geo.size.width * CGFloat(tip.percent) / 100)
                                }
                            }.frame(height: 3).padding(.top, 2)
                        }.padding(.vertical, 9)
                    }
                }.padding(.horizontal, 11).background(Color("surface"), in: RoundedRectangle(cornerRadius: 12))
                ForEach(period.groups.keys.sorted(), id: \.self) { group in
                    Text("Top " + group).font(.caption.bold())
                    FlowLayout {
                        ForEach(Array((period.groups[group] ?? []).enumerated()), id: \.offset) { _, item in
                            Text("\(item.name) \(item.percent)%").font(.caption).padding(.horizontal, 7).padding(.vertical, 4).background(Color("surfaceRaised"), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private func shortTitle(_ title: String) -> String {
        guard title.hasPrefix("Trim "), title.dropFirst(5).contains("/") else { return title }
        return "Trim " + (String(title.dropFirst(5)) as NSString).lastPathComponent
    }

}

private struct FlowLayout: Layout {
    private func layout(_ children: Subviews, width: CGFloat) -> ([CGPoint], CGFloat) {
        var points = [CGPoint](), x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for child in children {
            let size = child.sizeThatFits(.init(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += height + 4; height = 0 }
            points.append(.init(x: x, y: y))
            x += size.width + 5
            height = max(height, size.height)
        }
        return (points, y + height)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        return .init(width: width, height: layout(subviews, width: width).1)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (child, point) in zip(subviews, layout(subviews, width: bounds.width).0) {
            child.place(at: .init(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .init(width: min(bounds.width, child.sizeThatFits(.unspecified).width), height: nil))
        }
    }
}

struct ProviderMessage: View {
    let snapshot: ProviderSnapshot
    let provider: any Provider
    let allMissing: Bool
    var retry: () -> Void
    @State private var details = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch snapshot.state {
            case .notInstalled:
                if allMissing { Text("Connect your first tool").font(.headline); Text("AI Usage Menu reads from Claude Code and Codex on this Mac. Install a tool and sign in to see its plan limits.") }
                else { Text("\(provider.displayName) isn't installed").font(.headline) }
                Link("Install " + provider.displayName, destination: URL(string: provider.id == "claude" ? "https://code.claude.com/docs/en/setup" : "https://developers.openai.com/codex/cli/")!)
            case .signedOut:
                Text("Sign in to Claude Code").font(.headline)
                Text("Open Terminal and run claude to sign in.")
                Button("Copy command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("claude", forType: .string) }
            case .nonSubscription:
                Text("Claude subscription required").font(.headline)
                Text("Plan limits appear when Claude Code is signed in with a Claude subscription.")
                Button("Check again", action: retry)
            case .noSessions, .noLimits:
                Text(snapshot.state == .noSessions ? "No Codex sessions yet" : "No usage reading yet").font(.headline)
                Text("Use Codex on this Mac. Your limits appear when a session records them.")
                Button("Check again", action: retry)
            case .failed(let message):
                Text("Couldn't read usage").font(.headline)
                Button("Retry", action: retry)
                DisclosureGroup("Show details", isExpanded: $details) { Text(message).font(.caption.monospaced()).textSelection(.enabled) }
            case .timedOut, .unreadable:
                Text(snapshot.state == .timedOut ? "Claude Code took too long" : "Couldn't read the Codex session").font(.headline)
                Text(snapshot.state == .timedOut ? "The read stopped after 20 seconds." : "Check access to the local sessions folder.")
                Button("Retry", action: retry)
            case .unknownFormat:
                Text("Unrecognized usage format").font(.headline)
                Button("Read again", action: retry)
            case .ready, .limitReached: Text("Window details are unavailable.")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color("surface"), in: RoundedRectangle(cornerRadius: 14))
    }
}
