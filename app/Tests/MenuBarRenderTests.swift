import AppKit
import XCTest
@testable import AI_Usage_Menu

/// Renders the real menu bar item on a menu-bar-colored strip at 2x so its legibility can be
/// checked by eye (RECORD_PANEL=1 writes handoff/screenshots/icon/menubar-*.png).
final class MenuBarRenderTests: XCTestCase {
    @MainActor func testMenuItemRenders() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("handoff/screenshots/icon")
        let record = ProcessInfo.processInfo.environment["RECORD_PANEL"] == "1"
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            var options = DisplayOptions()
            let single = MenuItemVisual(value: .value(72, "provider-claude-code"), provider: nil, options: options, appearance: appearance)
            options.twoMenuNumbers = true
            let pair = DockSnapshot(indicator: .value(72, "provider-claude-code"), thresholds: Thresholds(), session: 72, weekly: 41)
            let double = MenuItemVisual(value: .value(72, "provider-claude-code"), pair: pair, provider: nil, options: options, appearance: appearance)
            XCTAssertEqual(single.title, "72%")
            XCTAssertNotNil(double.image)
            XCTAssertEqual(double.usageDescription, "5-hour 72%, weekly 41%")
            guard record else { continue }
            for (name, visual) in [("single", single), ("two", double)] {
                let png = try strip(visual, dark: dark)
                try png.write(to: folder.appendingPathComponent("menubar-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    @MainActor private func strip(_ visual: MenuItemVisual, dark: Bool) throws -> Data {
        let scale: CGFloat = 2, size = NSSize(width: 120, height: 24)
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSRect(origin: .zero, size: size).fill()
        var x: CGFloat = 8
        if let image = visual.image {
            image.draw(in: NSRect(x: x, y: (size.height - image.size.height) / 2, width: image.size.width, height: image.size.height))
            x += image.size.width + 3
        }
        if !visual.title.isEmpty {
            let text = NSAttributedString(string: visual.title, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: dark ? NSColor.white : NSColor.black])
            text.draw(at: NSPoint(x: x, y: (size.height - text.size().height) / 2))
        }
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
