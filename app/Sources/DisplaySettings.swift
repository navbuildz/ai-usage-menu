import SwiftUI

struct DisplaySettings: View {
    @ObservedObject var preferences: DisplayPreferences
    @ObservedObject var store: UsageStore
    var body: some View {
        Form {
            Section("Show in") {
                Picker("Show in", selection: $preferences.options.placement) {
                    ForEach(Placement.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
            }
            Section("General") {
                Picker("Appearance", selection: $preferences.options.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Refresh frequency", selection: $preferences.options.refreshMinutes) {
                    ForEach([2, 5, 10, 15, 30], id: \.self) { minutes in
                        Text(minutes == 5 ? "5 minutes (recommended)" : "\(minutes) minutes").tag(minutes)
                    }
                }
            }
            Section("Providers") {
                ForEach(store.providers, id: \.id) { provider in
                    Toggle(provider.displayName, isOn: Binding(get: { !preferences.options.disabled.contains(provider.id) }, set: { on in
                        if on { preferences.options.disabled.remove(provider.id) }
                        else { preferences.options.disabled.insert(provider.id) }
                    }))
                }
            }
            Section("Menu bar") {
                sourceControls(provider: $preferences.options.menuProvider, window: $preferences.options.menuWindow, isDock: false)
                Toggle("One item per provider", isOn: $preferences.options.separateItems)
                Toggle("Show percentage", isOn: $preferences.options.showPercent)
            }
            Section("Dock icon") {
                HStack {
                    let snapshot = DockSnapshot.resolve(providers: store.displayProviders, snapshots: store.snapshots, options: preferences.options, now: .now)
                    Image(nsImage: DockIconRenderer.image(for: snapshot, size: 128)).resizable().frame(width: 68, height: 68).accessibilityLabel("Dock preview")
                    VStack { sourceControls(provider: $preferences.options.dockProvider, window: $preferences.options.dockWindow, isDock: true) }

                }
            }
            Section("Health thresholds") {
                Stepper("Amber at \(preferences.options.thresholds.amber)%", value: $preferences.options.thresholds.amber, in: 1...(preferences.options.thresholds.red - 1))
                Stepper("Red at \(preferences.options.thresholds.red)%", value: $preferences.options.thresholds.red, in: (preferences.options.thresholds.amber + 1)...100)
            }
        }.formStyle(.grouped).frame(width: 430, height: 600)
    }

    @ViewBuilder private func sourceControls(provider: Binding<String>, window: Binding<WindowChoice>, isDock: Bool) -> some View {
        let candidates = store.displayProviders
        if !isDock && preferences.options.separateItems {
            LabeledContent("Provider", value: "One item per provider")
        } else if candidates.count < 2 {
            LabeledContent("Provider", value: candidates.first?.displayName ?? "None connected")
        } else {
            Picker("Provider", selection: provider) {
                Text("Auto").tag("auto")
                ForEach(candidates, id: \.id) { Text($0.displayName).tag($0.id) }
            }
        }
        Picker(isDock ? "Center number" : "Window", selection: window) {
            Text("5-hour").tag(WindowChoice.session)
            Text("Weekly").tag(WindowChoice.weekly)
        }
    }
}
