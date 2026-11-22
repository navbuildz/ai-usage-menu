import AppKit
import XCTest

final class ScaffoldTests: XCTestCase {
    @MainActor func testStatusItemUsesKitTemplate() throws {
        let image = try XCTUnwrap(NSImage(named: "UsageTemplate"))
        XCTAssertTrue(image.isTemplate)
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testAccessoryAppMetadata() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "ai.aiusagemenu.app")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }

    func testAdaptiveCanvas() throws {
        let color = try XCTUnwrap(NSColor(named: "background"))
        for (appearance, expectedRed) in [(NSAppearance.Name.aqua, 246), (.darkAqua, 11)] {
            try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
                XCTAssertEqual(color.usingColorSpace(.sRGB)?.redComponent ?? -1,
                               CGFloat(expectedRed) / 255, accuracy: 0.001)
            }
        }
    }
}
