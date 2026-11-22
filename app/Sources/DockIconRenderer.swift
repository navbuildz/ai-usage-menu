import AppKit

struct DockSnapshot: Equatable {
    var indicator: Indicator
    var thresholds: Thresholds
}

@MainActor
enum DockIconRenderer {
    static func image(for snapshot: DockSnapshot, size: Int) -> NSImage {
        let side = CGFloat(size)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.scaleBy(x: side / 100, y: side / 100)
        draw(snapshot, size: size, context: graphics.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(bitmap)
        return image
    }

    private static func draw(_ snapshot: DockSnapshot, size: Int, context c: CGContext) {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let empty = snapshot.indicator == .absent
        NSImage(named: empty ? "StaticIcon" : "DockBase")?.draw(in: bounds)
        guard !empty else { return }
        let center = CGPoint(x: 50, y: 50)
        let radius = 32.0
        let ring = CGRect(x: 18, y: 18, width: 64, height: 64)
        c.setLineWidth(8)
        c.setLineCap(.round)
        c.setStrokeColor(NSColor(srgbRed: 52/255, green: 52/255, blue: 82/255, alpha: 0.72).cgColor)
        c.strokeEllipse(in: ring)
        guard case let .value(percent, glyph) = snapshot.indicator else {
            c.setStrokeColor(NSColor.lightGray.withAlphaComponent(0.55).cgColor)
            c.strokeEllipse(in: ring)
            drawText("!", fontSize: 38, centerY: 50)
            return
        }

        func arc(_ from: Double, _ to: Double, _ radius: Double) {
            c.addArc(center: center, radius: radius, startAngle: .pi / 2 - from * .pi / 50, endAngle: .pi / 2 - to * .pi / 50, clockwise: true)
            c.strokePath()
        }
        if percent > 0 {
            c.saveGState()
            let end = snapshot.thresholds.color(percent, sweep: true)
            c.setShadow(offset: .zero, blur: 3.5, color: end.withAlphaComponent(0.5).cgColor)
            c.setStrokeColor(end.withAlphaComponent(0.55).cgColor)
            arc(0, percent, radius)
            c.restoreGState()
            var from = 0.0
            while from < percent {
                let to = min(percent, from + 0.45)
                c.setStrokeColor(snapshot.thresholds.color(to, sweep: true).cgColor)
                arc(from, to, radius)
                from = to
            }
            c.setLineWidth(0.65)
            c.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
            arc(0, percent, radius + 3)
        }
        let large = size >= 128
        let digits = percent.usageNumber
        drawText(digits + (large ? "%" : ""), fontSize: large ? 20 : 28, centerY: large ? 54 : 50)
        if large, let image = NSImage(named: glyph) {
            let rect = NSRect(x: 44, y: 32, width: 12, height: 12)
            let white = NSImage(size: rect.size, flipped: false) { area in
                image.draw(in: area)
                NSColor.white.setFill()
                area.fill(using: .sourceAtop)
                return true
            }
            white.draw(in: rect)
        }
    }

    private static func drawText(_ text: String, fontSize: Double, centerY: Double) {
        let descriptor = NSFont.systemFont(ofSize: fontSize, weight: .bold).fontDescriptor.withDesign(.rounded)!
        func attributes(_ size: Double) -> [NSAttributedString.Key: Any] {
            [.font: NSFont(descriptor: descriptor, size: size)!, .foregroundColor: NSColor.white]
        }
        let label = text as NSString
        var attrs = attributes(fontSize)
        let width = label.size(withAttributes: attrs).width
        if width > 49 { attrs = attributes(fontSize * 49 / width) }
        let size = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: 50 - size.width / 2, y: centerY - size.height / 2), withAttributes: attrs)
    }
}
