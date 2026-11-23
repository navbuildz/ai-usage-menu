import SwiftUI
import Security
import ServiceManagement
import UserNotifications

@MainActor
final class AppServices: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var loginNote = ""
    @Published private(set) var showNotificationSettings = true
    @Published private(set) var alertsNote = ""
    @Published private(set) var requestingAlerts = false
    var updatesConfigured: Bool { Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil }
    @Published private(set) var login = false
    @Published private(set) var alerts = UserDefaults.standard.bool(forKey: "usageAlerts")
    @Published private(set) var automatic = UserDefaults.standard.bool(forKey: "automaticUpdates")
    private let updates = UpdateService()
    private let center = UNUserNotificationCenter.current()

    func start() {
        center.delegate = self
        syncLogin()
        if automatic && updatesConfigured { updates.setAutomatic(true) }
    }

    func syncLogin() {
        let status = SMAppService.mainApp.status
        login = status == .enabled || status == .requiresApproval
        if status == .requiresApproval { loginNote = "Approve AI Usage Menu in Login Items to finish." }
        else if status == .enabled { loginNote = "" }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginNote = ""
        } catch {
            loginNote = enabled ? "macOS couldn’t register this copy. In Login Items, use + to add AI Usage Menu." : "Remove AI Usage Menu from Open at Login in System Settings."
        }
        syncLogin()
    }

    func setAlerts(_ enabled: Bool) {
        guard !requestingAlerts else { return }
        alertsNote = ""
        showNotificationSettings = true
        guard enabled else {
            alerts = false
            UserDefaults.standard.set(false, forKey: "usageAlerts")
            return
        }
        requestingAlerts = true
        Task {
            defer { requestingAlerts = false }
            do {
                alerts = try await center.requestAuthorization(options: [.alert, .sound])
                if !alerts { alertsNote = "Allow notifications for AI Usage Menu in System Settings, then try again." }
            } catch {
                alerts = false
                var code: SecStaticCode?
                let flags = SecCSFlags(rawValue: 0)
                if SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, flags, &code) == errSecSuccess,
                   let code, SecStaticCodeCheckValidity(code, flags, nil) != errSecSuccess {
                    alertsNote = "macOS rejected this build’s notification request. This copy has no valid app signature. Retry with the signed release."
                    showNotificationSettings = false
                } else {
                    let failure = error as NSError
                    alertsNote = "macOS couldn’t authorize notifications (\(failure.domain) \(failure.code)). Check notification access and try again."
                }
            }
            UserDefaults.standard.set(alerts, forKey: "usageAlerts")
        }
    }

    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }

    func setAutomatic(_ enabled: Bool) {
        automatic = enabled
        UserDefaults.standard.set(enabled, forKey: "automaticUpdates")
        if updatesConfigured { updates.setAutomatic(enabled) }
    }

    func checkUpdates() { updates.check() }

    func evaluate(_ store: UsageStore) {
        guard alerts else { return }
        let defaults = UserDefaults.standard
        var ledger = defaults.dictionary(forKey: "usageAlertCycles") as? [String: Double] ?? [:]
        let original = ledger
        let now = Date()
        for provider in store.enabled {
            guard let snapshot = store.snapshots[provider.id] else { continue }
            switch snapshot.state {
            case .ready, .limitReached: break
            default: continue
            }
            for limit in snapshot.limits {
                guard let reset = limit.resetsAt else { continue }
                let thresholds = [defaults.object(forKey: "notifyLow") as? Int ?? 75,
                                  defaults.object(forKey: "notifyHigh") as? Int ?? 90]
                let notices = Self.notices(for: limit, providerID: provider.id, reset: reset, now: now,
                                           thresholds: thresholds, resetsEnabled: defaults.bool(forKey: "notifyResets"), ledger: &ledger)
                for notice in notices { post(notice.id, provider.displayName, notice.body) }
            }
        }
        if original != ledger { defaults.set(ledger, forKey: "usageAlertCycles") }
    }

    static func notices(for limit: LimitWindow, providerID: String, reset: Date, now: Date,
                        thresholds: [Int], resetsEnabled: Bool, ledger: inout [String: Double]) -> [(id: String, body: String)] {
        let key = providerID + "/" + limit.label + "/"
        let cycle = reset.timeIntervalSince1970
        var result: [(id: String, body: String)] = []
        if let prior = ledger[key], now.timeIntervalSince1970 >= prior, ledger[key+"reset"] != prior, resetsEnabled {
            result.append((key+"reset", limit.label + " has reset."))
            ledger[key+"reset"] = prior
        }
        guard let percent = limit.percent(at: now) else { return result }
        ledger[key] = cycle
        for threshold in thresholds where percent >= Double(threshold) {
            let id = key + String(threshold)
            if ledger[id] != cycle {
                ledger[id] = cycle
                result.append((id, "\(limit.label) usage reached \(threshold)%."))
            }
        }
        return result
    }

    private func post(_ id: String, _ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(.init(identifier: id, content: content, trigger: nil)) { _ in }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .list] }
}

extension ProviderState {
    var detectionLabel: String {
        switch self {
        case .ready, .limitReached: "Found"
        case .signedOut: "Not signed in"
        case .notInstalled: "Not found"
        case .noSessions: "No local sessions"
        case .nonSubscription: "Subscription required"
        case .noLimits: "No usage data"
        case .timedOut: "Read timed out"
        case .failed, .unknownFormat, .unreadable: "Could not read usage"
        }
    }
}
