import SwiftUI

enum SettingsPane: String, CaseIterable {
    case general = "General", menu = "Menu bar", dock = "Dock icon", behavior = "Automation", about = "About"
    var symbol: String {
        switch self { case .behavior: "bell"; case .about: "info.circle"; case .general: "slider.horizontal.3"; case .menu: "menubar.rectangle"; case .dock: "dock.rectangle" }
    }
}

struct DisplaySettings: View {
    @ObservedObject var preferences: DisplayPreferences
    @ObservedObject var store: UsageStore
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var services = AppServices()
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("notifyLow") private var low = 75
    @AppStorage("notifyHigh") private var high = 90
    @AppStorage("notifyResets") private var resets = false
    @AppStorage("customAlertLevels") private var customAlerts = false
    @State private var detectedPath = ""
    @State private var testResult = ""
    @State private var testing = false
    @State var pane: SettingsPane = .general

    init(preferences: DisplayPreferences, store: UsageStore, services: AppServices = AppServices(), pane: SettingsPane = .general) {
        self.preferences = preferences
        self.store = store
        self.services = services
        _pane = State(initialValue: pane)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                    Text("AI Usage").font(.headline)
                }.padding(.horizontal, 6).padding(.bottom, 22)
                ForEach(SettingsPane.allCases, id: \.self) { item in
                    Button { pane = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 13, weight: pane == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                            .background(pane == item ? Color("violet").opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityAddTraits(pane == item ? .isSelected : [])
                }
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 20).frame(width: 146).background(Color("surface"))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(pane.rawValue).font(.system(size: 24, weight: .bold)).padding(.bottom, 16)
                    switch pane {
                    case .behavior:
                        ServiceChoices(services: services)
                        if services.alerts {
                            row("Alert at the amber and red levels") {
                                Text("\(preferences.options.thresholds.amber)% and \(preferences.options.thresholds.red)%")
                                    .monospacedDigit().foregroundStyle(Color("textSecondary"))
                            }.opacity(customAlerts ? 0.45 : 1)
                            row("Use different alert levels") { Toggle("Use different alert levels", isOn: $customAlerts).labelsHidden() }
                            if customAlerts {
                                threshold("First alert", value: $low, range: 1...(high - 1))
                                threshold("Second alert", value: $high, range: (low + 1)...100)
                            }
                            row("Notify when a limit resets") { Toggle("Reset alerts", isOn: $resets).labelsHidden() }
                        }
                        Button("Check for Updates…") { services.checkUpdates() }.padding(.top)
                    case .about:
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 12) {
                                KitIcon(name: "BrandMark", size: 46)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("AI Usage Menu").font(.title2.bold())
                                    Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")).foregroundStyle(Color("textSecondary"))
                                }
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Privacy", systemImage: "lock").font(.headline)
                                Text("Usage is processed on this Mac. Claude Code may contact Anthropic. AI Usage Menu connects only for update checks you choose.").fixedSize(horizontal: false, vertical: true)
                            }.padding(14).background(Color("surface"), in: RoundedRectangle(cornerRadius: 12))
                            Link(destination: URL(string: "https://typefire.app")!) {
                                HStack {
                                    Image("TypeFire").resizable().frame(width: 36, height: 36)
                                    Text("From the makers of TypeFire").fontWeight(.semibold)
                                    Spacer()
                                    KitIcon(name: "external-link", size: 14)
                                }.padding(12).background(Color("surfaceRaised"), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                            HStack {
                                Text("MIT License · BaseThread LLC").foregroundStyle(Color("textSecondary"))
                                Spacer()
                                Link("Source code", destination: URL(string: "https://github.com/OWNER/aiusagemenu")!)
                            }.font(.caption)
                        }
                    case .general: general
                    case .menu, .dock: displayPane
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }.id(pane)
        }.frame(width: 570, height: 500).background(Color("background"))
            .foregroundStyle(Color("text")).tint(Color("violet")).toggleStyle(.switch)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            visibilitySwitch(isDock: false)
            visibilitySwitch(isDock: true)
            if preferences.options.placement == .hidden {
                Text("Open AI Usage Menu from Finder to show either icon again.")
                    .font(.caption).foregroundStyle(Color("textSecondary")).padding(.vertical, 5)
            }
            row("Appearance") { themePicker($preferences.options.theme) }
            row("Refresh frequency") {
                Picker("Refresh frequency", selection: $preferences.options.refreshMinutes) {
                    ForEach([2,5,10,15,30], id: \.self) { Text($0 == 5 ? "5 minutes (recommended)" : "\($0) minutes").tag($0) }
                }.labelsHidden()
            }
            sectionLabel("Providers")
            ForEach(store.providers, id: \.id) { provider in
                row(provider.displayName) {
                    Toggle(provider.displayName, isOn: Binding(get: { !preferences.options.disabled.contains(provider.id) }, set: { enabled in
                        if enabled { preferences.options.disabled.remove(provider.id) }
                        else { preferences.options.disabled.insert(provider.id) }
                    })).labelsHidden()
                }
            }
            if let claude = store.providers.compactMap({ $0 as? ClaudeCodeProvider }).first {
                sectionLabel("Claude Code executable")
                Text(claudePath.isEmpty ? (detectedPath.isEmpty ? "Auto-detect" : detectedPath) : claudePath)
                    .font(.caption).textSelection(.enabled).padding(.vertical, 6)
                    .task(id: claudePath) { detectedPath = await claude.resolve()?.path ?? "" }
                HStack {
                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        if panel.runModal() == .OK, let path = panel.url?.path {
                            if FileManager.default.isExecutableFile(atPath: path) { claudePath = path; testResult = "" }
                            else { testResult = "Choose an executable file." }
                        }
                    }
                    if !claudePath.isEmpty { Button("Use Auto") { claudePath = ""; testResult = "" } }
                    Button(testing ? "Testing…" : "Test") {
                        testing = true
                        Task {
                            // Goes through the store so it never runs alongside a scheduled read.
                            if let result = await store.read(claude) {
                                testResult = result.state == .ready ? "Read succeeded: " + String(result.limits.count) + " usage windows." : result.state.detectionLabel
                            } else {
                                testResult = "A read is already running. Try again in a moment."
                            }
                            testing = false
                        }
                    }.disabled(testing)
                }
                if !testResult.isEmpty { Text(testResult).font(.caption).padding(.top, 5) }
            }
            sectionLabel("Health thresholds")
            let levels = preferences.options.thresholds
            GeometryReader { area in
                HStack(spacing: 0) {
                    Color("mint").frame(width: area.size.width * CGFloat(levels.amber) / 100)
                    Color("amber").frame(width: area.size.width * CGFloat(levels.red - levels.amber) / 100)
                    Color("danger")
                }.clipShape(Capsule())
            }.frame(height: 8).padding(.vertical, 8).accessibilityHidden(true)
            threshold("Amber", value: $preferences.options.thresholds.amber, range: 1...(preferences.options.thresholds.red - 1))
            threshold("Red", value: $preferences.options.thresholds.red, range: (preferences.options.thresholds.amber + 1)...100)
        }
    }

    private var displayPane: some View {
        let isDock = pane == .dock
        return VStack(alignment: .leading, spacing: 0) {
            visibilitySwitch(isDock: isDock).padding(.bottom, 12)
            HStack(spacing: 20) {
                Group {
                    if isDock {
                        Image(nsImage: DockIconRenderer.image(for: dockPreview, size: 128)).resizable().frame(width: 70, height: 70).accessibilityLabel("Dock preview")
                    } else { menuPreview }
                }.frame(minWidth: 88, minHeight: 90)
                Divider().frame(height: 60)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider").font(.caption).foregroundStyle(Color("textSecondary"))
                    let candidates = store.displayProviders
                    if !isDock && preferences.options.separateItems { Text("One item per provider") }
                    else if candidates.count <= 1 { Text(candidates.first?.displayName ?? "None connected") }
                    else {
                        Picker("Provider", selection: isDock ? $preferences.options.dockProvider : $preferences.options.menuProvider) {
                            Text("Auto").tag("auto")
                            ForEach(candidates, id: \.id) { Text($0.displayName).tag($0.id) }
                        }.labelsHidden()
                    }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).frame(maxWidth: .infinity)
                .background(Color("surface"), in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 14)
            if isDock || preferences.options.showPercent {
                row("Numbers") {
                    Picker("Numbers", selection: isDock ? $preferences.options.twoDockNumbers : $preferences.options.twoMenuNumbers) {
                        Text("One").tag(false)
                        Text("Two").tag(true)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                }
            }
            if isDock ? preferences.options.twoDockNumbers : preferences.options.twoMenuNumbers && preferences.options.showPercent {
                row("Top number") { Text("5-hour session") }
                row("Bottom number") { Text("Weekly") }
            } else {
                row(isDock ? "Center number" : "Window") {
                    Picker("Usage window", selection: isDock ? $preferences.options.dockWindow : $preferences.options.menuWindow) {
                        Text("5-hour").tag(WindowChoice.session)
                        Text("Weekly").tag(WindowChoice.weekly)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
            }
            if isDock {
                row("Dock appearance") { themePicker($preferences.options.dockTheme) }
            } else {
                row("One item per provider") { Toggle("One item per provider", isOn: $preferences.options.separateItems).labelsHidden() }
                row("Show percentage") { Toggle("Show percentage", isOn: $preferences.options.showPercent).labelsHidden() }
            }
        }
    }

    private func visibilitySwitch(isDock: Bool) -> some View {
        let label = isDock ? "Show in Dock" : "Show in menu bar"
        return row(label) {
            Toggle(label, isOn: isDock ? $preferences.options.placement.showsDock : $preferences.options.placement.showsMenu)
                .labelsHidden()
        }
    }

    private var menuPreview: some View {
        let keys = preferences.options.separateItems && !store.displayProviders.isEmpty ? store.displayProviders.map(\.id) : ["auto"]
        return HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                let visual = MenuItemVisual(value: store.menuValue(key, options: preferences.options), pair: preferences.options.twoMenuNumbers && preferences.options.showPercent ? store.menuPair(key, options: preferences.options) : nil, provider: store.providers.first { $0.id == key }, options: preferences.options, appearance: NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!)
                HStack(spacing: 3) {
                    if let image = visual.image {
                        Image(nsImage: image).foregroundStyle(Color(nsColor: visual.iconTint ?? .labelColor))
                    }
                    if !visual.title.isEmpty { Text(visual.title).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.primary) }
                }.padding(5).background(Color("surfaceRaised"), in: Capsule())
            }
        }.accessibilityLabel("Menu bar preview")
    }

    private var dockPreview: DockSnapshot {
        var snapshot = DockSnapshot.resolve(providers: store.displayProviders, snapshots: store.snapshots, options: preferences.options, now: .now)
        snapshot.light = (preferences.options.dockTheme.appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua,.darkAqua]) == .aqua
        return snapshot
    }

    private func themePicker(_ selection: Binding<AppTheme>) -> some View {
        Picker("Appearance", selection: selection) {
            ForEach(AppTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).frame(width: 190)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.headline).padding(.top, 16).padding(.bottom, 3)
    }

    private func threshold(_ name: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        row(name) {
            Text("\(value.wrappedValue)%").monospacedDigit()
            Stepper(name, value: value, in: range).labelsHidden()
        }
    }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(label)
                Spacer(minLength: 8)
                control()
            }.frame(minHeight: 39)
            Divider().opacity(0.32)
        }
    }
}
