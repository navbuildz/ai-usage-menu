import AppKit
import SwiftUI
import XCTest
@testable import AI_Usage_Menu

private struct FixtureProvider: Provider {
    let id: String
    let result: ProviderSnapshot
    var displayName: String { id == "claude" ? "Claude Code" : "Codex" }
    var glyph: String { id == "claude" ? "provider-claude-code" : "provider-codex" }
    func isAvailable() async -> Bool { result.state != .notInstalled }
    func read() async -> ProviderSnapshot { result }
}

final class PanelTests: XCTestCase {
    @MainActor func testPanelStatesInBothAppearances() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("handoff/screenshots/window")
        let record = ProcessInfo.processInfo.environment["RECORD_PANEL"] == "1"
        if record { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "subscription", withExtension: "txt"))
        let text = try String(contentsOf: fixture, encoding: .utf8)
        let now = Date()
        var high = ClaudeParser.parse(text, now: now)
        high.limits = high.limits.enumerated().map { index, limit in
            .init(label: limit.label, usedPercent: limit.usedPercent, resetsAt: now.addingTimeInterval(index == 0 ? 6720 : 518400), windowMinutes: nil, source: limit.source)
        }
        high.details.append(.init(label:"Claude Code",value:"2.1.330"))
        var normal = high
        normal.limits = [.init(label:"Current session",usedPercent:30,resetsAt:now.addingTimeInterval(6720),windowMinutes:nil,source:"Claude Code"),
                         .init(label:"Current week (all models)",usedPercent:57,resetsAt:now.addingTimeInterval(518400),windowMinutes:nil,source:"Claude Code")]
        var stale = ProviderSnapshot(asOf:now.addingTimeInterval(-86400),state:.ready)
        stale.limits = [.init(label:"Session",usedPercent:94,resetsAt:now.addingTimeInterval(-3600),windowMinutes:300,source:"Last Codex activity")]
        var reached = stale
        reached.state = .limitReached("weekly")
        reached.limits = [.init(label:"Weekly",usedPercent:100,resetsAt:now.addingTimeInterval(7200),windowMinutes:10080,source:"Last Codex activity")]
        let missing = ProviderSnapshot(asOf:now,state:.notInstalled)
        var cases: [(String,String,ProviderSnapshot)] = [("normal","claude",normal),("high","claude",high),("breakdown","claude",high),("stale","codex",stale),("limit-reached","codex",reached),("missing","claude",missing)]
        for (name, id, state) in [("signed-out","claude",ProviderState.signedOut),("api-key","claude",.nonSubscription),("timeout","claude",.timedOut),("no-sessions","codex",.noSessions),("no-limits","codex",.noLimits),("unreadable","codex",.unreadable),("failed","claude",.failed("Fixture diagnostic"))] {
            cases.append((name,id,.init(asOf:now,state:state)))
        }
        cases.append(("unknown","claude",.init(asOf:now,state:.unknownFormat,rawText:"Unrecognized fixture output")))
        let preferences = DisplayPreferences(defaults: UserDefaults(suiteName:"ai.aiusagemenu.tests.panel")!)
        for (name,id,snapshot) in cases {
            let providers = ["claude","codex"].map { FixtureProvider(id:$0,result:$0 == id ? snapshot : missing) }
            let store = UsageStore(providers:providers)
            let loaded = expectation(description:"Load fixtures")
            loaded.expectedFulfillmentCount = 2
            store.onChange = { loaded.fulfill() }
            store.refreshAll()
            await fulfillment(of:[loaded], timeout:3)
            store.onChange = nil
            let navigation = Navigation()
            navigation.select(id)
            navigation.detail = name == "breakdown"
            for (suffix,theme) in [("dark",ColorScheme.dark),("light",ColorScheme.light)] {
                let view = UsageView(store:store,preferences:preferences,navigation:navigation,settings:{})
                    .environment(\.colorScheme,theme).frame(width:380,height:535)
                try capture(view, name:name+"-"+suffix, folder:folder, record:record, theme:theme)
                if name == "normal" {
                    try capture(DisplaySettings(preferences:preferences,store:store).environment(\.colorScheme,theme),name:"settings-"+suffix,folder:folder,record:record,theme:theme)
                }
            }
            store.stop()
        }
    }

    @MainActor private func capture<V: View>(_ root: V, name: String, folder: URL, record: Bool, theme: ColorScheme) throws {
        let host = NSHostingView(rootView:root)
        let size = host.fittingSize
        let window = NSWindow(contentRect:.init(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.appearance = NSAppearance(named:theme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.layoutIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:bitmap)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide,380)
        if record {
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:folder.appendingPathComponent(name+".png"))
        }
    }
}
