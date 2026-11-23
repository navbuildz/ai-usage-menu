import SwiftUI

struct ServiceChoices: View {
    @ObservedObject var services: AppServices
    var body: some View {
        choice("Launch at login", "Start in your chosen menu bar and Dock mode.", services.login, services.setLogin)
        if !services.loginNote.isEmpty { notice(services.loginNote, "Open Login Items", services.openLoginSettings) }
        choice("Usage notifications", "Get a local alert when a usage window reaches a threshold.", services.alerts, services.setAlerts)
            .disabled(services.requestingAlerts)
        if !services.alertsNote.isEmpty { notice(services.alertsNote, services.showNotificationSettings ? "Open Notifications" : nil, services.openNotificationSettings) }
        choice("Automatic update checks", "Check aiusagemenu.com for new versions.", services.automatic, services.setAutomatic)
        if services.automatic && !services.updatesConfigured {
            Text("Preference saved. Checks will start in a release configured for updates.")
                .font(.caption).foregroundStyle(Color("textSecondary"))
        }
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
        }.toggleStyle(.switch).padding(.vertical, 5)
    }
}

struct Onboarding: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var services: AppServices
    let finish: () -> Void
    @State private var page = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KitIcon(name: "BrandMark", size: 40)
            Text(["Your AI usage at a glance", "Providers on this Mac", "Make it yours"][page]).font(.title.bold())
            switch page {
            case 0:
                Text("See your Claude Code and Codex limits in the menu bar and Dock.")
                Text("Usage stays on your Mac. No cookies or API keys are required. Claude Code may contact Anthropic when it reads usage. The app only connects for updates you choose.").foregroundStyle(Color("textSecondary"))
            case 1:
                ForEach(store.providers, id: \.id) { provider in
                    HStack { Text(provider.displayName); Spacer(); Text(store.disabled.contains(provider.id) ? "Disabled" : store.snapshots[provider.id]?.onboardingStatus ?? "Checking…") }
                    Divider()
                }
            default: ScrollView { VStack(alignment: .leading, spacing: 6) { ServiceChoices(services: services) }.padding(.trailing, 4) }
            }
            Spacer()
            HStack {
                if page > 0 { Button("Back") { page -= 1 } }
                Spacer()
                Button(page == 2 ? "Done" : "Continue") { if page == 2 { finish() } else { page += 1 } }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440, height: 355).background(Color("background")).foregroundStyle(Color("text")).tint(Color("violet"))
    }
}
