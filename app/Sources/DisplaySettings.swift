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
            Section("Providers") {
                ForEach(store.providers, id: \.id) { provider in
                    Toggle(provider.displayName, isOn: Binding(get: { !preferences.options.disabled.contains(provider.id) }, set: { on in
                        if on { preferences.options.disabled.remove(provider.id) }
                        else { preferences.options.disabled.insert(provider.id) }
                    }))
                }
            }
            Section("Menu bar") {
                Toggle("One item per provider", isOn: $preferences.options.separateItems)
                Toggle("Show percentage", isOn: $preferences.options.showPercent)
            }
            Section("Dock icon") {
                HStack {
                    let indicator = Indicator.select(providers: store.enabled, snapshots: store.snapshots, providerID: preferences.options.dockProvider, window: preferences.options.dockWindow, at: .now)
                    Image(nsImage: DockIconRenderer.image(for: .init(indicator: indicator, thresholds: preferences.options.thresholds), size: 128)).resizable().frame(width: 72, height: 72).accessibilityLabel("Dock preview")
                    VStack {
                        Picker("Provider", selection: $preferences.options.dockProvider) {
                            Text("Auto").tag("auto")
                            ForEach(store.providers, id: \.id) { Text($0.displayName).tag($0.id) }
                        }
                        Picker("Window", selection: $preferences.options.dockWindow) {
                            ForEach(WindowChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }
                }
            }
            Section("Health thresholds") {
                Stepper("Amber at \(preferences.options.thresholds.amber)%", value: $preferences.options.thresholds.amber, in: 1...(preferences.options.thresholds.red - 1))
                Stepper("Red at \(preferences.options.thresholds.red)%", value: $preferences.options.thresholds.red, in: (preferences.options.thresholds.amber + 1)...100)
            }
        }.formStyle(.grouped).frame(width: 430, height: 530)
    }
}
