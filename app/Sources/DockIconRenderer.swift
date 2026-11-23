import AppKit
import CoreText

struct DockSnapshot: Equatable {
    var indicator: Indicator
    var thresholds: Thresholds
    var light = false
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
        let ink: NSColor = snapshot.light ? NSColor(srgbRed: 0.08, green: 0.09, blue: 0.16, alpha: 1) : .white
        let empty = snapshot.indicator == .absent
        NSImage(named: (empty ? "StaticIcon" : "DockBase") + (snapshot.light ? "Light" : ""))?.draw(in: bounds)
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
            c.setStrokeColor((value == nil ? NSColor.gray : NSColor(srgbRed: 0.21, green: 0.21, blue: 0.32, alpha: 1)).withAlphaComponent(snapshot.light ? 0.26 : 0.70).cgColor)
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
        guard let percent = snapshot.indicator.percent else {
            drawLabel("!", fontSize: 27, ink: ink, in: c)
            return
        }
        let compact = size < 128
        drawLabel(percent.usageNumber, fontSize: compact ? 27 : 20, ink: ink, in: c)
    }

    private static func drawLabel(_ digits: String, fontSize: CGFloat, ink: NSColor, in context: CGContext) {
        let descriptor = NSFont.systemFont(ofSize: fontSize, weight: .bold).fontDescriptor.withDesign(.rounded)!
        let label = NSAttributedString(string: digits, attributes: [
            .font: NSFont(descriptor: descriptor, size: fontSize)!,
            .foregroundColor: ink
        ])

        let line = CTLineCreateWithAttributedString(label)
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let scale = min(1, 47 / glyphBounds.width)
        context.saveGState()
        context.translateBy(x: 50, y: 50)
        context.scaleBy(x: scale, y: scale)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -glyphBounds.midX, y: -glyphBounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
