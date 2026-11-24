import SwiftUI

struct ServiceChoices: View {
    @ObservedObject var services: AppServices
    var body: some View {
        choice("Launch at login", "Start in your chosen menu bar and Dock mode.", services.login, services.setLogin)
        if !services.loginNote.isEmpty { notice(services.loginNote, "Open Login Items", services.openLoginSettings) }
        choice("Usage notifications", "Get a local alert when a usage window reaches a threshold.", services.alerts, services.setAlerts)
            .disabled(services.requestingAlerts)
        if !services.alertsNote.isEmpty { notice(services.alertsNote, services.showNotificationSettings ? "Open Notifications" : nil, services.openNotificationSettings) }
        choice("Automatic updates", "Check aiusagemenu.com when the app opens and once a day, and download new versions in the background. You choose when to install.", services.automatic, services.setAutomatic)
    }
    private func notice(_ text: String, _ actionTitle: String?, _ action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(Color("textSecondary"))
            VStack(alignment: .leading, spacing: 5) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let actionTitle { Button(actionTitle, action: action).buttonStyle(.link) }
            }
            Spacer(minLength: 0)
        }.padding(10).background(Color("surfaceRaised"), in: RoundedRectangle(cornerRadius: 8))
    }
    private func choice(_ title: String, _ detail: String, _ value: Bool, _ action: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: action)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(Color("textSecondary"))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(VioletSwitch()).padding(.vertical, 5)
    }
}

struct Onboarding: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var services: AppServices
    var preferences: DisplayPreferences? = nil
    let finish: () -> Void
    @State private var page = 0
    private let titles = ["Your AI usage at a glance", "Providers on this Mac", "Make it yours"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Capsule().fill(index == page ? Color("violet") : Color("border").opacity(0.5)).frame(width: index == page ? 18 : 6, height: 6)
                }
            }.accessibilityLabel("Step \(page + 1) of 3")
            Text(titles[page]).font(.title.bold())
            switch page {
            case 0: welcome
            case 1: providers
            default: choices
            }
            Spacer(minLength: 0)
            HStack {
                if page > 0 { Button("Back") { page -= 1 }.buttonStyle(SecondaryButtonStyle()) }
                Spacer()
                Button(page == 2 ? "Done" : "Continue") { if page == 2 { finish() } else { page += 1 } }
                    .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 460, height: 430).background(Color("background")).foregroundStyle(Color("text")).tint(Color("violet"))
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(nsImage: DockIconRenderer.image(for: DockSnapshot(indicator: .value(72, "provider-claude-code"), thresholds: Thresholds(), session: 72, weekly: 41), size: 160))
                    .resizable().frame(width: 84, height: 84).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("See your Claude Code and Codex limits in the menu bar and Dock, with the time each one resets.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The ring fills green, then amber, then red as you use your plan.").font(.callout).foregroundStyle(Color("textSecondary"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Label {
                Text("Usage stays on your Mac. No cookies or API keys. Claude Code may contact Anthropic when it reads usage; AI Usage Menu itself only checks for updates, when it opens and once a day.")
                    .font(.callout).foregroundStyle(Color("textSecondary")).fixedSize(horizontal: false, vertical: true)
            } icon: { Image(systemName: "lock.shield").foregroundStyle(Color("mint")) }
        }
    }

    private var providers: some View {
        VStack(spacing: 0) {
            ForEach(store.providers, id: \.id) { provider in
                let snapshot = store.snapshots[provider.id]
                let found = snapshot.map { $0.state == .ready || $0.state == .noSessions || { if case .limitReached = $0.state { return true }; return false }($0) } ?? false
                HStack(spacing: 10) {
                    KitIcon(name: provider.glyph, size: 20)
                    Text(provider.displayName).fontWeight(.semibold)
                    Spacer()
                    Circle().fill(found ? Color("mint") : Color("textSecondary").opacity(0.5)).frame(width: 7, height: 7)
                    Text(store.disabled.contains(provider.id) ? "Disabled" : snapshot?.onboardingStatus ?? "Checking…")
                        .font(.callout).foregroundStyle(Color("textSecondary"))
                }.padding(.vertical, 12)
                Divider()
            }
            Text("You can turn providers on or off later in Settings.").font(.caption).foregroundStyle(Color("textSecondary")).padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var choices: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let preferences {
                    PlacementCards(preferences: preferences)
                }
                ServiceChoices(services: services)
            }.padding(.trailing, 4)
        }
    }
}

/// Menu bar, Dock or both, as three visual cards.
private struct PlacementCards: View {
    @ObservedObject var preferences: DisplayPreferences
    var body: some View {
        HStack(spacing: 8) {
            ForEach([Placement.menu, .dock, .both], id: \.self) { placement in
                let selected = preferences.options.placement == placement
                Button { preferences.options.placement = placement } label: {
                    VStack(spacing: 6) {
                        Image(systemName: placement == .menu ? "menubar.rectangle" : placement == .dock ? "dock.rectangle" : "rectangle.split.2x1")
                            .font(.system(size: 20))
                        Text(placement == .both ? "Both" : placement == .menu ? "Menu bar" : "Dock").font(.callout.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(selected ? Color("violet").opacity(0.16) : Color("surface"), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color("violet") : Color("border").opacity(0.4), lineWidth: selected ? 2 : 1))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
