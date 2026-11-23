import SwiftUI

struct BreakdownView: View {
    let periods: [BreakdownPeriod]
    @State private var selection = 0
    @State private var showGroups = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                KitIcon(name: "breakdown", size: 18).foregroundStyle(Color("orchid"))
                Text("What's contributing?").font(.system(size: 15, weight: .bold))
                Spacer(minLength: 2)
                HStack(spacing: 2) {
                    ForEach(periods.indices, id: \.self) { index in
                        Button("Last " + periods[index].span) { selection = index }
                            .buttonStyle(.plain).font(.caption.weight(.medium)).fixedSize()
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .foregroundStyle(index == selection ? Color.white : Color("textSecondary"))
                            .background { if index == selection { Capsule().fill(Color("violet")) } }
                            .accessibilityAddTraits(index == selection ? .isSelected : [])
                    }
                }.padding(2).background(Color("surfaceRaised"), in: Capsule())
            }
            if let period = periods.indices.contains(selection) ? periods[selection] : periods.first {
                Text("\(period.requests.formatted()) requests · \(period.sessions.formatted()) sessions").font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("Each figure is the share of this activity it applies to. They overlap, so they don't add up to 100%.")
                }.font(.caption).foregroundStyle(Color("textSecondary")).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(period.tips.indices, id: \.self) { index in
                        let tip = period.tips[index]
                        if index > 0 { Divider() }
                        TipRow(tip: tip)
                    }
                }.padding(.horizontal, 11).background(Color("surface"), in: RoundedRectangle(cornerRadius: 12))
                if !period.groups.isEmpty {
                    Button(showGroups ? "Show less" : "Show top MCP servers, skills and subagents") { showGroups.toggle() }
                        .buttonStyle(.link).font(.caption)
                }
                if showGroups {
                    ForEach(period.groups.keys.sorted(), id: \.self) { group in
                        Text("Top " + group).font(.caption.bold())
                        VStack(spacing: 10) {
                            ForEach(Array((period.groups[group] ?? []).enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(item.name); Spacer(); Text("\(item.percent)%").monospacedDigit().fontWeight(.semibold) }
                                    Meter(fraction: Double(item.percent) / 100)
                                }.accessibilityElement(children: .combine)
                            }
                        }.font(.caption).padding(12).background(Color("surface"), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

private struct TipRow: View {
    let tip: Contribution
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(shortTitle(tip.name)).font(.system(size: 12, weight: .semibold)).help(tip.name)
                Spacer(minLength: 2)
                Text("\(tip.percent)%").font(.caption.monospacedDigit().bold()).fixedSize()
            }
            if let detail = tip.detail {
                if detail.hasPrefix("run /") {
                    CopyChip(text: String(detail.dropFirst(4)))
                } else {
                    Text(detail).font(.caption).foregroundStyle(Color("textSecondary"))
                }
            }
            Meter(fraction: Double(tip.percent) / 100).padding(.top, 2)
        }.padding(.vertical, 9)
    }

    private func shortTitle(_ title: String) -> String {
        guard title.hasPrefix("Trim "), title.dropFirst(5).contains("/") else { return title }
        return "Trim " + (String(title.dropFirst(5)) as NSString).lastPathComponent
    }
}

private struct Meter: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Color("border").opacity(0.3)).overlay(alignment: .leading) {
                Capsule().fill(Color("orchid")).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }.frame(height: 3)
    }
}

/// A command shown as a chip that copies itself when clicked.
struct CopyChip: View {
    let text: String
    @State private var copied = false
    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            HStack(spacing: 4) {
                Text(text).font(.caption.monospaced())
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption2)
            }.padding(.horizontal, 7).padding(.vertical, 2).background(Color("surfaceRaised"), in: Capsule())
        }.buttonStyle(.plain).help(copied ? "Copied" : "Copy \(text)").accessibilityLabel(copied ? "Copied" : "Copy \(text)")
    }
}

/// Unrecognized output, collapsed by default, with home paths shortened.
struct RawOutput: View {
    let text: String
    let title: String
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(title, isExpanded: $expanded) {
            Text(Diagnostics.redact(text)).font(.caption.monospaced()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
        }.font(.caption)
    }
}

enum Diagnostics {
    /// Replaces the home folder with ~ and removes anything shaped like an email address.
    static func redact(_ text: String) -> String {
        var result = text.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        result = result.replacingOccurrences(of: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, with: "<email>", options: .regularExpression)
        return result
    }

    static func report(provider: String, state: ProviderState, text: String?) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "AI Usage Menu \(version), macOS \(os)\nProvider: \(provider)\nState: \(state)\n\n" + redact(text ?? "")
    }
}

struct ProviderMessage: View {
    let snapshot: ProviderSnapshot
    let provider: any Provider
    let allMissing: Bool
    var retry: () -> Void
    @State private var copied = false

    private struct Content {
        var icon: String
        var tint: String
        var title: String
        var body: String
        var action: String?
        var link: (String, URL)?
        var command: String?
        var details: String?
    }

    private var content: Content {
        let name = provider.displayName
        let isClaude = provider.id == "claude"
        switch snapshot.state {
        case .notInstalled:
            let url = URL(string: isClaude ? "https://code.claude.com/docs/en/setup" : "https://developers.openai.com/codex/cli/")!
            return allMissing
                ? .init(icon: "link", tint: "violet", title: "Connect your first tool", body: "AI Usage Menu reads from Claude Code and Codex on this Mac. Install one and sign in with a plan to see its limits.", link: ("Install " + name, url))
                : .init(icon: "shippingbox", tint: "textSecondary", title: "\(name) isn't installed", body: "Install \(name) on this Mac to see its limits here.", link: ("Install " + name, url))
        case .signedOut:
            return .init(icon: "person.crop.circle.badge.exclamationmark", tint: "amber", title: "Sign in to \(name)",
                         body: "Open Terminal, run the command below and sign in with your plan. Then check again.", action: "Check again", command: isClaude ? "claude" : "codex login")
        case .nonSubscription:
            return .init(icon: "gauge.with.dots.needle.0percent", tint: "textSecondary", title: "No plan limits to show",
                         body: isClaude ? "This Claude Code is signed in with an API key or a cloud provider, which bills per token and has no session or weekly limits. AI Usage Menu shows Claude Pro, Max and Team limits."
                                        : "Codex is signed in with an API key, which has no plan limits. AI Usage Menu shows ChatGPT plan limits.",
                         action: "Check again", details: snapshot.rawText)
        case .noSessions, .noLimits:
            return .init(icon: "clock", tint: "textSecondary", title: snapshot.state == .noSessions ? "No Codex sessions yet" : "No usage reading yet",
                         body: "Use Codex on this Mac. Your limits appear here after its next session.", action: "Check again")
        case .failed(let message):
            return .init(icon: "exclamationmark.triangle", tint: "danger", title: "Couldn't read \(name) usage",
                         body: "\(name) returned an error. It's often temporary, so try again. If it keeps happening, copy the details and report it.", action: "Try again", details: message)
        case .timedOut:
            return .init(icon: "hourglass", tint: "amber", title: "\(name) took too long",
                         body: "The read stopped after 20 seconds, usually because the Mac was busy or offline. Try again in a moment.", action: "Try again")
        case .unreadable:
            return .init(icon: "lock", tint: "amber", title: "Couldn't open the Codex sessions folder",
                         body: "AI Usage Menu reads ~/.codex/sessions. Check that the folder exists and that your account can read it.", action: "Try again")
        case .unknownFormat:
            return .init(icon: "questionmark.diamond", tint: "amber", title: "\(name) changed its usage output",
                         body: "AI Usage Menu doesn't recognize what \(name) printed, so it needs an update. Copy the details and report it, and check for updates.", action: "Read again", details: snapshot.rawText)
        case .ready, .limitReached:
            return .init(icon: "info.circle", tint: "textSecondary", title: "Window details are unavailable", body: "\(name) didn't report any usage windows this time.", action: "Check again")
        }
    }

    var body: some View {
        let item = content
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: item.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(item.tint))
                    .frame(width: 34, height: 34).background(Color(item.tint).opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                Text(item.title).font(.headline)
            }
            Text(item.body).font(.callout).foregroundStyle(Color("textSecondary")).fixedSize(horizontal: false, vertical: true)
            if let command = item.command { CopyChip(text: command) }
            HStack(spacing: 10) {
                if let action = item.action {
                    Button(action, action: retry).buttonStyle(PrimaryButtonStyle())
                }
                if let (title, url) = item.link {
                    Link(destination: url) { Text(title) }.buttonStyle(PrimaryButtonStyle())
                }
                if let details = item.details, !details.isEmpty {
                    Button(copied ? "Copied" : "Copy details") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Diagnostics.report(provider: provider.displayName, state: snapshot.state, text: details), forType: .string)
                        copied = true
                    }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if let details = item.details, !details.isEmpty {
                RawOutput(text: details, title: "Show what \(provider.displayName) printed")
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color("surface"), in: RoundedRectangle(cornerRadius: 14))
    }
}
