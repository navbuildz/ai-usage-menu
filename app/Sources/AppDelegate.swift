import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    private let store = UsageStore()

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(named: "UsageTemplate")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "AI Usage Menu"
        item.button?.setAccessibilityLabel("AI Usage Menu")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Quit AI Usage Menu",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { store.start() }
    }

    func applicationWillTerminate(_ notification: Notification) { store.stop() }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { store.opened() }
}
