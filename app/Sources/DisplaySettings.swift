import SwiftUI

enum SettingsPane: String, CaseIterable {
    case general = "General", menu = "Menu bar", dock = "Dock icon", behavior = "Alerts & updates", about = "About"
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
    @State private var showAcknowledgements = false

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
                    Text("AI Usage Menu").font(.headline).lineLimit(2)
                }.padding(.horizontal, 6).padding(.bottom, 22)
                ForEach(SettingsPane.allCases, id: \.self) { item in
                    Button { pane = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.system(size: 13, weight: pane == item ? .semibold : .regular))
                            .overlay(alignment: .trailing) {
                                if item == .behavior { UpdateDot(updates: services.updates).offset(x: 14) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                            .background(pane == item ? Color("violet").opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityAddTraits(pane == item ? .isSelected : [])
                }
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 20).frame(width: 172).background(Color("surface"))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(pane.rawValue).font(.system(size: 24, weight: .bold)).padding(.bottom, 16)
                    switch pane {
                    case .behavior:
                        UpdateCard(updates: services.updates) { services.showUpdate?() }.padding(.bottom, 10)
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
                        Button("Check for Updates…") { services.checkUpdates() }.buttonStyle(SecondaryButtonStyle()).padding(.top)
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
                                Text("Usage is processed on this Mac. Claude Code may contact Anthropic. AI Usage Menu itself only checks aiusagemenu.com for updates, once a day, and you can turn that off.").fixedSize(horizontal: false, vertical: true)
                            }.padding(14).background(Color("surface"), in: RoundedRectangle(cornerRadius: 12))
                            Link(destination: URL(string: "https://typefire.app")!) {
                                HStack {
                                    Image("TypeFire").resizable().frame(width: 36, height: 36)
                                    Text("From the makers of TypeFire").fontWeight(.semibold)
                                    Spacer()
                                    KitIcon(name: "external-link", size: 14)
                                }.padding(12).background(Color("surfaceRaised"), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                            HStack(spacing: 14) {
                                Text("MIT License · BaseThread LLC").foregroundStyle(Color("textSecondary"))
                                Spacer()
                                Button("Acknowledgements") { showAcknowledgements = true }.buttonStyle(.link)
                                if !AppLinks.repository.absoluteString.contains("/OWNER/") {
                                    Link("Source code", destination: AppLinks.repository)
                                }
                            }.font(.caption)
                            .sheet(isPresented: $showAcknowledgements) { Acknowledgements() }
                        }
                    case .general: general
                    case .menu, .dock: displayPane
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }.id(pane)
        }.frame(width: 596, height: 500).background(Color("background"))
            .foregroundStyle(Color("text")).tint(Color("violet")).toggleStyle(VioletSwitch(showsLabel: false))
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
            ThresholdBar(thresholds: $preferences.options.thresholds).padding(.vertical, 10)
            threshold("Amber", value: $preferences.options.thresholds.amber, range: 1...(preferences.options.thresholds.red - 1))
            threshold("Red", value: $preferences.options.thresholds.red, range: (preferences.options.thresholds.amber + 1)...100)
        }
    }

    // The Menu bar and Dock panes are two separate views, each bound straight to its own settings.
    // They used to share one view whose controls switched bindings by pane, which let Settings show
    // one setting while the app used another (2026-11-23: "Claude Code" shown, Codex saved).
    private var displayPane: some View {
        Group {
            if pane == .dock { dockPane } else { menuPane }
        }
    }

    /// Every enabled provider is offered, even one without a reading yet, so the saved choice always
    /// has a matching item and the picker never displays a value that isn't the one in use.
    private var providerChoices: [any Provider] { store.enabled }

    private var menuPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            visibilitySwitch(isDock: false).padding(.bottom, 12)
            previewCard(preview: AnyView(menuPreview)) {
                if preferences.options.separateItems {
                    Text("One item per provider")
                } else {
                    Picker("Menu bar provider", selection: $preferences.options.menuProvider) {
                        Text("Auto (most used)").tag("auto")
                        ForEach(providerChoices, id: \.id) { Text($0.displayName).tag($0.id) }
                    }.labelsHidden().fixedSize()
                }
            }
            if preferences.options.showPercent {
                row("Numbers") {
                    Picker("Menu bar numbers", selection: $preferences.options.twoMenuNumbers) {
                        Text("One").tag(false)
                        Text("Two").tag(true)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
                }
            }
            if preferences.options.twoMenuNumbers && preferences.options.showPercent {
                row("Top number") { Text("5-hour session") }
                row("Bottom number") { Text("Weekly") }
            } else {
                row("Window") {
                    Picker("Menu bar window", selection: $preferences.options.menuWindow) {
                        Text("5-hour").tag(WindowChoice.session)
                        Text("Weekly").tag(WindowChoice.weekly)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
            }
            row("One item per provider") { Toggle("One item per provider", isOn: $preferences.options.separateItems).labelsHidden() }
            row("Show percentage") { Toggle("Show percentage", isOn: $preferences.options.showPercent).labelsHidden() }
        }
    }

    private var dockPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            visibilitySwitch(isDock: true).padding(.bottom, 12)
            previewCard(preview: AnyView(Image(nsImage: DockIconRenderer.image(for: dockPreview, size: 256)).resizable().frame(width: 104, height: 104).accessibilityLabel("Dock preview"))) {
                Picker("Dock provider", selection: $preferences.options.dockProvider) {
                    Text("Auto (most used)").tag("auto")
                    ForEach(providerChoices, id: \.id) { Text($0.displayName).tag($0.id) }
                }.labelsHidden().fixedSize()
            }
            row("Numbers") {
                Picker("Dock numbers", selection: $preferences.options.twoDockNumbers) {
                    Text("One").tag(false)
                    Text("Two").tag(true)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 160)
            }
            if preferences.options.twoDockNumbers {
                row("Top number") { Text("5-hour session") }
                row("Bottom number") { Text("Weekly") }
            } else {
                row("Center number") {
                    Picker("Dock window", selection: $preferences.options.dockWindow) {
                        Text("5-hour").tag(WindowChoice.session)
                        Text("Weekly").tag(WindowChoice.weekly)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
            }
            row("Dock appearance") { themePicker($preferences.options.dockTheme) }
        }
    }

    private func previewCard<Control: View>(preview: AnyView, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 20) {
            preview.frame(minWidth: 88, minHeight: 90)
            Divider().frame(height: 60)
            VStack(alignment: .leading, spacing: 8) {
                Text("Provider").font(.caption).foregroundStyle(Color("textSecondary"))
                control()
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).frame(maxWidth: .infinity)
            .background(Color("surface"), in: RoundedRectangle(cornerRadius: 12)).padding(.bottom, 14)
    }

    private func visibilitySwitch(isDock: Bool) -> some View {
        let label = isDock ? "Show in Dock" : "Show in menu bar"
        return row(label) {
            Toggle(label, isOn: isDock ? $preferences.options.placement.showsDock : $preferences.options.placement.showsMenu)
                .labelsHidden()
        }
    }

    /// The user's current menu bar item on a light and a dark menu bar strip, at true size.
    private var menuPreview: some View {
        VStack(alignment: .trailing, spacing: 6) {
            menuStrip(dark: false)
            menuStrip(dark: true)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Menu bar preview")
    }

    private func menuStrip(dark: Bool) -> some View {
        let keys = preferences.options.separateItems && !store.displayProviders.isEmpty ? store.displayProviders.map(\.id) : ["auto"]
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let ink: Color = dark ? .white : .black
        return HStack(spacing: 10) {
            Image(systemName: "wifi").font(.system(size: 12))
            ForEach(keys, id: \.self) { key in
                let visual = MenuItemVisual(value: store.menuValue(key, options: preferences.options), pair: preferences.options.twoMenuNumbers && preferences.options.showPercent ? store.menuPair(key, options: preferences.options) : nil, provider: store.providers.first { $0.id == key }, options: preferences.options, appearance: appearance)
                HStack(spacing: 3) {
                    if let image = visual.image {
                        Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
                            .foregroundStyle(visual.iconTint.map { Color(nsColor: $0) } ?? ink)
                    }
                    if !visual.title.isEmpty { Text(visual.title).font(.system(size: 12, weight: .semibold)).monospacedDigit() }
                }
            }
            Text("9:41").font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(ink).padding(.horizontal, 10).frame(height: 24).fixedSize()
        .background(dark ? Color(white: 0.16) : Color(white: 0.93), in: RoundedRectangle(cornerRadius: 6))
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

enum AppLinks {
    /// Filled in by TF ENG when the GitHub repository is public; links stay hidden until then.
    static let repository = URL(string: "https://github.com/navbuildz/ai-usage-menu")!
}

/// Third-party licenses that ship inside the app (Sparkle).
private struct Acknowledgements: View {
    @Environment(\.dismiss) private var dismiss
    private var sparkle: String {
        Bundle.main.url(forResource: "Sparkle-LICENSE", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Sparkle license not found."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Acknowledgements").font(.title2.bold())
            Text("AI Usage Menu includes Sparkle (sparkle-project.org), used only for update checks you turn on.")
                .foregroundStyle(Color("textSecondary")).fixedSize(horizontal: false, vertical: true)
            ScrollView { Text(sparkle).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .padding(10).background(Color("surface"), in: RoundedRectangle(cornerRadius: 10))
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction) }
        }.padding(22).frame(width: 520, height: 440).background(Color("background"))
    }
}

/// Mint, amber and red bands with two draggable handles for the amber and red levels.
private struct ThresholdBar: View {
    @Binding var thresholds: Thresholds
    private let handle: CGFloat = 16

    var body: some View {
        GeometryReader { area in
            let width = area.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Color("mint").frame(width: width * CGFloat(thresholds.amber) / 100)
                    Color("amber").frame(width: width * CGFloat(thresholds.red - thresholds.amber) / 100)
                    Color("danger")
                }.frame(height: 8).clipShape(Capsule())
                knob(value: thresholds.amber, width: width, label: "Amber level") { thresholds.amber = min(max(1, $0), thresholds.red - 1) }
                knob(value: thresholds.red, width: width, label: "Red level") { thresholds.red = min(max(thresholds.amber + 1, $0), 100) }
            }.frame(maxHeight: .infinity)
        }.frame(height: 24)
    }

    private func knob(value: Int, width: CGFloat, label: String, set: @escaping (Int) -> Void) -> some View {
        Circle().fill(Color.white).frame(width: handle, height: handle)
            .overlay(Circle().stroke(Color.black.opacity(0.18)))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .offset(x: width * CGFloat(value) / 100 - handle / 2)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                set(Int((drag.location.x / width * 100).rounded()))
            })
            .help("\(label): \(value)%")
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(value) percent")
            .accessibilityAdjustableAction { direction in
                set(direction == .increment ? value + 1 : value - 1)
            }
    }
}
