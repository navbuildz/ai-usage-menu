import AppKit
import CoreText

struct DockSnapshot: Equatable {
    var indicator: Indicator
    var thresholds: Thresholds
    var light = false
    var session: Double?
    var weekly: Double?
    var twoNumbers = false
    /// No number yet and a read is running: draw empty rings and dots instead of the plain icon.
    var loading = false
    /// Seconds until a full window resets, to the minute. While set, that ring counts down the time
    /// left instead of showing 100, so you can see when you can work again (Nav, 2026-11-26).
    var sessionLeft: TimeInterval?
    var weeklyLeft: TimeInterval?
    /// Which ring the single number belongs to.
    var centerIsWeekly = false
    /// Rings show what is left (full ring, shrinking) and the numbers show percent left.
    var countsDown = false

    static let sessionSpan: TimeInterval = 5 * 3600
    static let weeklySpan: TimeInterval = 7 * 86_400

    /// "3d", "2h", "47m": the largest whole unit, so it fits the Dock; minutes round up so it never reads 0m.
    static func countdown(_ left: TimeInterval) -> String {
        if left >= 86_400 { return "\(Int(left / 86_400))d" }
        if left >= 3600 { return "\(Int(left / 3600))h" }
        return "\(max(1, Int((left / 60).rounded(.up))))m"
    }

    /// Time left in the full window `choice` picks for this provider, or nil when it isn't full.
    static func timeLeft(_ snapshot: ProviderSnapshot?, _ choice: WindowChoice, weeklyModel: String, at now: Date) -> TimeInterval? {
        guard let snapshot, snapshot.state == .ready || { if case .limitReached = snapshot.state { return true }; return false }() else { return nil }
        var limits = snapshot.limits.filter(choice.includes)
        if choice == .weekly, !weeklyModel.isEmpty {
            let model = snapshot.limits.filter { $0.weeklyModel?.lowercased() == weeklyModel.lowercased() }
            if !model.isEmpty { limits = model }
        }
        let left = limits.compactMap { limit -> TimeInterval? in
            guard let reset = limit.resetsAt, reset > now, (limit.percent(at: now) ?? 0) >= 100 else { return nil }
            return reset.timeIntervalSince(now)
        }.max()
        return left.map { ($0 / 60).rounded(.up) * 60 }
    }

    static func resolve(providers: [any Provider], snapshots: [String: ProviderSnapshot], options: DisplayOptions, now: Date) -> Self {
        let available = providers.filter { snapshots[$0.id]?.state != .notInstalled && snapshots[$0.id] != nil }
        var choices = available
        // A chosen provider stays chosen while it has no reading yet; it then shows its own warning
        // instead of another provider's number.
        if let selected = providers.first(where: { $0.id == options.dockProvider }), snapshots[selected.id]?.state != .notInstalled {
            choices = [selected]
        }
        var result = Self(indicator: .absent, thresholds: options.thresholds)
        var best = -2.0
        for provider in choices {
            func value(_ window: WindowChoice) -> Double? {
                Indicator.select(providers: [provider], snapshots: snapshots, window: window, weeklyModel: options.dockWeeklyModel, at: now).percent
            }
            let session = value(.session), weekly = value(.weekly)
            let score = max(session ?? -1, weekly ?? -1)
            guard score > best else { continue }
            best = score
            // When the chosen window has no number (it just reset, or Claude Code printed last-known
            // usage without it), show the other one instead of the plain icon, as the menu bar does.
            let centerIsWeekly = options.dockWindow == .weekly ? weekly != nil : session == nil
            let center = centerIsWeekly ? weekly : session
            let problem = snapshots[provider.id]?.state.isProblem == true
            result = Self(indicator: center.map { .value($0, provider.glyph) } ?? (problem ? .warning : .absent),
                          thresholds: options.thresholds, session: session, weekly: weekly, twoNumbers: options.twoDockNumbers)
            result.countsDown = options.dockRingsCountDown
            result.centerIsWeekly = centerIsWeekly
            result.sessionLeft = timeLeft(snapshots[provider.id], .session, weeklyModel: "", at: now)
            result.weeklyLeft = timeLeft(snapshots[provider.id], .weekly, weeklyModel: options.dockWeeklyModel, at: now)
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
        let ink: NSColor = snapshot.light ? NSColor(white: 0.10, alpha: 1) : .white
        let empty = snapshot.indicator == .absent && !snapshot.loading
        NSImage(named: (empty ? "StaticIcon" : "DockBase") + (snapshot.light ? "Light" : ""))?.draw(in: bounds)
        guard !empty else { return }
        let center = CGPoint(x: 50, y: 50)
        c.setLineCap(.round)
        /// Percent used as the ring and number show it: used, or left when the rings count down.
        func shown(_ used: Double) -> Double { snapshot.countsDown ? max(0, 100 - used) : used }
        func segment(start: Double, length: Double, value: Double?, countdown: Bool = false) {
            func stroke(_ from: Double, _ to: Double, radius: Double = 32) {
                let a = (90 - start - length * from / 100) * .pi / 180
                let b = (90 - start - length * to / 100) * .pi / 180
                c.addArc(center: center, radius: radius, startAngle: a, endAngle: b, clockwise: true)
                c.strokePath()
            }
            c.setLineWidth(7)
            if countdown, let value {
                // Waiting for a reset: the ring is the time left, shrinking toward the reset, in a calm
                // blue to violet instead of the red of a full window.
                c.setStrokeColor((snapshot.light ? NSColor(white: 0.68, alpha: 1) : NSColor(srgbRed: 0.21, green: 0.21, blue: 0.32, alpha: 1).withAlphaComponent(0.70)).cgColor)
                stroke(0, 100)
                guard value > 0 else { return }
                if snapshot.light {
                    // The light style stays all gray (Nav, 2026-11-27).
                    c.setStrokeColor(NSColor(white: 0.18, alpha: 1).cgColor)
                    stroke(0, value)
                    return
                }
                let blue = NSColor(srgbRed: 0.27, green: 0.56, blue: 1.0, alpha: 1), violet = NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1)
                var from = 0.0
                while from < value {
                    let to = min(value, from + 0.75)
                    c.setStrokeColor((blue.blended(withFraction: to / 100, of: violet) ?? violet).cgColor)
                    stroke(from, to)
                    from = to
                }
                return
            }
            if snapshot.light {
                c.setStrokeColor(NSColor(white: value == nil ? 0.58 : 0.68, alpha: 1).cgColor)
                stroke(0, 100)
                if let value, shown(value) > 0 {
                    c.setStrokeColor(NSColor(white: 0.18, alpha: 1).cgColor)
                    stroke(0, shown(value))
                }
                return
            }
            c.setStrokeColor((value == nil ? NSColor.gray : NSColor(srgbRed: 0.21, green: 0.21, blue: 0.32, alpha: 1)).withAlphaComponent(0.70).cgColor)
            stroke(0, 100)
            guard let value, shown(value) > 0 else { return }
            // One solid color for the level the window is at now, always by how much is used: a full
            // ring is all red, and a counting-down ring turns red as it runs out (Nav, 2026-11-26).
            let end = snapshot.thresholds.color(value)
            c.saveGState()
            c.setShadow(offset: .zero, blur: 3, color: end.withAlphaComponent(0.5).cgColor)
            c.setStrokeColor(end.cgColor)
            stroke(0, shown(value))
            c.restoreGState()
            c.setLineWidth(0.6)
            c.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
            stroke(0, shown(value), radius: 34.7)
        }
        // Rounded caps extend beyond the endpoints. Leave room for both at each break.
        segment(start: -50, length: 100, value: snapshot.sessionLeft.map { 100 * $0 / DockSnapshot.sessionSpan } ?? snapshot.session, countdown: snapshot.sessionLeft != nil)
        segment(start: 70, length: 220, value: snapshot.weeklyLeft.map { 100 * $0 / DockSnapshot.weeklySpan } ?? snapshot.weekly, countdown: snapshot.weeklyLeft != nil)
        if snapshot.indicator == .absent {
            drawLabel("•••", fontSize: 20, ink: ink.withAlphaComponent(0.75), in: c)
            return
        }
        if snapshot.twoNumbers && (snapshot.session != nil || snapshot.weekly != nil) {
            drawLabel(snapshot.sessionLeft.map(DockSnapshot.countdown) ?? snapshot.session.map { shown($0).compactUsage } ?? "–", fontSize: 17, ink: ink, y: 63, in: c)
            drawLabel(snapshot.weeklyLeft.map(DockSnapshot.countdown) ?? snapshot.weekly.map { shown($0).compactUsage } ?? "–", fontSize: 23, ink: ink, y: 40, in: c)
            return
        }
        guard let percent = snapshot.indicator.percent else {
            drawLabel("!", fontSize: 27, ink: ink, in: c)
            return
        }
        let compact = size < 128
        let left = snapshot.centerIsWeekly ? snapshot.weeklyLeft : snapshot.sessionLeft
        drawLabel(left.map(DockSnapshot.countdown) ?? shown(percent).compactUsage, fontSize: compact ? 27 : 20, ink: ink, in: c)
    }

    private static func drawLabel(_ digits: String, fontSize: CGFloat, ink: NSColor, y: CGFloat = 50, in context: CGContext) {
        let descriptor = NSFont.systemFont(ofSize: fontSize, weight: .bold).fontDescriptor.withDesign(.rounded)!
        let label = NSAttributedString(string: digits, attributes: [
            .font: NSFont(descriptor: descriptor, size: fontSize)!,
            .foregroundColor: ink
        ])

        let line = CTLineCreateWithAttributedString(label)
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let scale = min(1, 47 / glyphBounds.width)
        context.saveGState()
        context.translateBy(x: 50, y: y)
        context.scaleBy(x: scale, y: scale)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -glyphBounds.midX, y: -glyphBounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
