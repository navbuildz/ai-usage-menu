import SwiftUI

struct DisplaySettings: View {
    @ObservedObject var preferences: DisplayPreferences
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            card("Show in") {
                Picker("Show in", selection: $preferences.options.placement) {
                    ForEach(Placement.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden()
            }
            card("General") {
                Picker("Appearance", selection: $preferences.options.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Refresh frequency", selection: $preferences.options.refreshMinutes) {
                    ForEach([2, 5, 10, 15, 30], id: \.self) { minutes in
                        Text(minutes == 5 ? "5 minutes (recommended)" : "\(minutes) minutes").tag(minutes)
                    }
                }
            }
            card("Providers") {
                ForEach(store.providers, id: \.id) { provider in
                    Toggle(provider.displayName, isOn: Binding(get: { !preferences.options.disabled.contains(provider.id) }, set: { on in
                        if on { preferences.options.disabled.remove(provider.id) }
                        else { preferences.options.disabled.insert(provider.id) }
                    }))
                }
            }
            card("Menu bar") {
                HStack(spacing: 16) {
                    let keys = preferences.options.separateItems && !store.displayProviders.isEmpty ? store.displayProviders.map(\.id) : ["auto"]
                    VStack(spacing: 5) {
                        ForEach(keys, id: \.self) { key in
                            let visual = MenuItemVisual(value: store.menuValue(key, options: preferences.options), provider: store.providers.first { $0.id == key }, options: preferences.options, appearance: NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!)
                            HStack(spacing: 3) {
                                if let image = visual.image {
                                    Image(nsImage: image).foregroundStyle(Color(nsColor: visual.iconTint ?? .labelColor))
                                }
                                if !visual.title.isEmpty { Text(visual.title).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(Color(nsColor: visual.textColor)) }
                            }.padding(5).background(Color("surfaceRaised"), in: Capsule())
                        }
                    }.frame(width: 74).accessibilityLabel("Menu bar preview")
                    VStack(alignment: .leading) { sourceControls(provider: $preferences.options.menuProvider, window: $preferences.options.menuWindow, isDock: false) }
                }
                Toggle("One item per provider", isOn: $preferences.options.separateItems)
                Toggle("Show percentage", isOn: $preferences.options.showPercent)
            }
            card("Dock icon") {
                HStack {
                    let snapshot = dockPreview
                    Image(nsImage: DockIconRenderer.image(for: snapshot, size: 128)).resizable().frame(width: 68, height: 68).accessibilityLabel("Dock preview")
                    VStack(alignment: .leading) {
                        sourceControls(provider: $preferences.options.dockProvider, window: $preferences.options.dockWindow, isDock: true)
                        Picker("Dock appearance", selection: $preferences.options.dockTheme) {
                            ForEach(AppTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                    }

                }
            }
            card("Health thresholds") {
                Stepper("Amber at \(preferences.options.thresholds.amber)%", value: $preferences.options.thresholds.amber, in: 1...(preferences.options.thresholds.red - 1))
                Stepper("Red at \(preferences.options.thresholds.red)%", value: $preferences.options.thresholds.red, in: (preferences.options.thresholds.amber + 1)...100)
            }
          }.padding(18)
        }.background(Color("background")).foregroundStyle(Color("text")).tint(Color("violet"))
            .toggleStyle(.switch).frame(width: 430, height: 600)
    }

    private var dockPreview: DockSnapshot {
        var snapshot = DockSnapshot.resolve(providers: store.displayProviders, snapshots: store.snapshots, options: preferences.options, now: .now)
        snapshot.light = (preferences.options.dockTheme.appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua,.darkAqua]) == .aqua
        return snapshot
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10, content: content)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Color("surface"), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("border").opacity(0.6)))
        }
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
