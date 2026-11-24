import AppKit
import SwiftUI
import XCTest
@testable import AI_Usage_Menu

final class UpdateTests: XCTestCase {
    func testReleaseNotesBecomeBullets() {
        let html = "<ul>\n  <li>One &amp; two</li>\n  <li><b>Bold</b> three</li>\n  <li> </li>\n</ul>"
        XCTAssertEqual(UpdateService.bullets(from: html), ["One & two", "Bold three"])
        XCTAssertEqual(UpdateService.bullets(from: nil), [])
    }

    func testBundledNotesForThisVersion() {
        XCTAssertFalse(ReleaseNotes.bullets(for: "1.0.0", bundle: Bundle(for: AppDelegate.self)).isEmpty)
        XCTAssertTrue(ReleaseNotes.bullets(for: "9.9.9", bundle: Bundle(for: AppDelegate.self)).isEmpty)
    }

    /// The update window once showed no notes: its list collapsed to zero height.
    @MainActor func testUpdateWindowShowsEveryNote() throws {
        let notes = ["The menu bar icon is now three simple bars that match your menu bar.",
                     "Settings always shows the provider and numbers the menu bar is really using.",
                     "Updates install in one click and the app reopens by itself."]
        for mode in [UpdateWindowView.Mode.available, .whatsNew] {
            let view = NSHostingView(rootView: UpdateWindowView(mode: mode, version: "1.0.1", notes: notes, close: {}))
            let size = view.fittingSize
            XCTAssertGreaterThan(size.height, 230, "the notes list must take real height")
            guard ProcessInfo.processInfo.environment["RECORD_PANEL"] == "1" else { continue }
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            try rep.representation(using: .png, properties: [:])?.write(to: root.appendingPathComponent("handoff/screenshots/window/update-\(mode == .available ? "available" : "whatsnew").png"))
        }
    }
}
