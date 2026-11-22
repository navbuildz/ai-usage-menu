import AppKit

struct DockSnapshot: Equatable {
    var indicator: Indicator
    var thresholds: Thresholds
    var session: Double?
    var weekly: Double?

    static func resolve(providers: [any Provider], snapshots: [String: ProviderSnapshot], options: DisplayOptions, now: Date) -> Self {
        let available = providers.filter { snapshots[$0.id]?.state != .notInstalled && snapshots[$0.id] != nil }
        var choices = available
        if available.count > 1, let selected = available.first(where: { $0.id == options.dockProvider }) { choices = [selected] }
        var result = Self(indicator: .absent, thresholds: options.thresholds)
        var best = -2.0
        for provider in choices {
            func value(_ window: WindowChoice) -> Double? {
                Indicator.select(providers: [provider], snapshots: snapshots, window: window, at: now).percent
            }
            let session = value(.session), weekly = value(.weekly)
            let score = max(session ?? -1, weekly ?? -1)
            guard score > best else { continue }
            best = score
            let center = options.dockWindow == .weekly ? weekly : session
            result = Self(indicator: center.map { .value($0, provider.glyph) } ?? .warning,
                          thresholds: options.thresholds, session: session, weekly: weekly)
        }
        return result
    }
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
        c.setLineCap(.round)
        func segment(start: Double, length: Double, value: Double?) {
            func stroke(_ from: Double, _ to: Double, radius: Double = 32) {
                let a = (90 - start - length * from / 100) * .pi / 180
                let b = (90 - start - length * to / 100) * .pi / 180
                c.addArc(center: center, radius: radius, startAngle: a, endAngle: b, clockwise: true)
                c.strokePath()
            }
            c.setLineWidth(7)
            c.setStrokeColor((value == nil ? NSColor.gray : NSColor(named: "border")!).withAlphaComponent(0.70).cgColor)
            stroke(0, 100)
            guard let value, value > 0 else { return }
            let end = snapshot.thresholds.color(value, sweep: true)
            c.saveGState()
            c.setShadow(offset: .zero, blur: 3, color: end.withAlphaComponent(0.5).cgColor)
            c.setStrokeColor(end.cgColor)
            stroke(0, value)
            c.restoreGState()
            var from = 0.0
            while from < value {
                let to = min(value, from + 0.75)
                c.setStrokeColor(snapshot.thresholds.color(to, sweep: true).cgColor)
                stroke(from, to)
                from = to
            }
            c.setLineWidth(0.6)
            c.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
            stroke(0, value, radius: 34.7)
        }
        // Rounded caps extend beyond the endpoints. Leave room for both at each break.
        segment(start: -50, length: 100, value: snapshot.session)
        segment(start: 70, length: 220, value: snapshot.weekly)
        guard case let .value(percent, glyph) = snapshot.indicator else {
            drawText("!", fontSize: 27, centerY: 50)
            return
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
