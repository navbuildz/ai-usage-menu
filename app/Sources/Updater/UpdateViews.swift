import SwiftUI

/// The update window, before an update ("ready to install") and after it ("what's new").
struct UpdateWindowView: View {
    enum Mode { case available, whatsNew }
    let mode: Mode
    let version: String
    let notes: [String]
    var ready = true
    var install: () -> Void = {}
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                KitIcon(name: "BrandMark", size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode == .available ? "AI Usage Menu \(version) is available" : "What's new in AI Usage Menu \(version)")
                        .font(.title3.bold())
                    Text(mode == .available
                         ? (ready ? "It's downloaded and ready. Updating takes a few seconds and reopens the app." : "Click Update to download and install it.")
                         : "You're up to date. Here's what changed.")
                        .font(.callout).foregroundStyle(Color("textSecondary"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !notes.isEmpty {
                // A plain list sized to its content; it scrolls only past eight notes.
                let list = VStack(alignment: .leading, spacing: 9) {
                    ForEach(notes.indices, id: \.self) { index in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle().fill(Color("violet")).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            Text(notes[index]).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                Group {
                    if notes.count > 8 { ScrollView { list }.frame(height: 240) } else { list }
                }
                .background(Color("surface"), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Spacer()
                if mode == .available {
                    Button("Later", action: close).buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    Button(ready ? "Update and Relaunch" : "Update", action: install).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: close).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24).frame(width: 460).background(Color("background")).foregroundStyle(Color("text"))
    }
}

/// The banner at the top of the usage panel when an update is waiting.
struct UpdateBanner: View {
    @ObservedObject var updates: UpdateService
    let open: () -> Void
    var body: some View {
        if let available = updates.available {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color("violet"))
                    Text("Update available: \(available.version)").fontWeight(.semibold)
                    Spacer(minLength: 4)
                    Text("See what's new").foregroundStyle(Color("violet"))
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Color("violet"))
                }
                .font(.callout).padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color("violet").opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("violet").opacity(0.35)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.horizontal, 14).padding(.bottom, 8)
            .accessibilityLabel("Update available, version \(available.version). See what's new.")
        }
    }
}

/// A red dot drawn on a control while an update is waiting.
struct UpdateDot: View {
    @ObservedObject var updates: UpdateService
    var body: some View {
        if updates.available != nil {
            Circle().fill(Color("danger")).frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color("background"), lineWidth: 1.5))
                .accessibilityLabel("Update available")
        }
    }
}

/// The updates card in Settings > Alerts.
struct UpdateCard: View {
    @ObservedObject var updates: UpdateService
    let open: () -> Void
    var body: some View {
        if let available = updates.available {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(Color("violet"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(available.version) is available").fontWeight(.semibold)
                    Text(available.ready ? "Downloaded and ready to install." : "Ready to download.").font(.caption).foregroundStyle(Color("textSecondary"))
                }
                Spacer()
                Button("See what's new", action: open).buttonStyle(PrimaryButtonStyle())
            }.padding(12).background(Color("violet").opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        } else if let checked = updates.lastChecked {
            Text("Up to date. Last checked \(checked.formatted(.relative(presentation: .named))).")
                .font(.caption).foregroundStyle(Color("textSecondary"))
        }
    }
}
