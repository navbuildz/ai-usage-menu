import AppKit

// Drawing for the menu bar item: the three-bar gauge, the provider glyph and the
// one- or two-number label. Pure functions of the current reading and options.

@MainActor
enum MenuGauge {
    static func image(percent: Double, thresholds: Thresholds, appearance: NSAppearance) -> NSImage {
        let tier = thresholds.tier(percent)
        let ink = thresholds.color(percent)
        let light = appearance.bestMatch(from: [.darkAqua,.aqua]) == .aqua
        let rects = [CGRect(x: 8.9,y: 18.2,width: 4.8,height: 7.8), CGRect(x: 15,y: 14.5,width: 4.8,height: 11.5), CGRect(x: 21.1,y: 10.7,width: 4.8,height: 15.3)]
        return NSImage(size: .init(width: 18,height: 18), flipped: true) { bounds in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.saveGState()
            c.scaleBy(x: bounds.width / 32, y: bounds.height / 32)
            let template = NSImage(named: "UsageTemplate")!
            template.draw(in: .init(x: 0,y: 0,width: 32,height: 32), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            (light ? NSColor.black : NSColor.white).setFill()
            NSRect(x: 0,y: 0,width: 32,height: 32).fill(using: .sourceAtop)
            for (index, rect) in rects.enumerated() {
                let path = NSBezierPath(roundedRect: rect, xRadius: 1.8, yRadius: 1.8)
                (index < tier ? ink : (light ? NSColor.lightGray : NSColor.darkGray)).setFill()
                path.fill()
            }
            c.restoreGState()
            return true
        }
    }
}

extension UsageStore {
    func menuValue(_ key: String, options: DisplayOptions) -> Indicator {
        let choice = key == "auto" ? options.menuProvider : key
        let id = displayProviders.contains { $0.id == choice } ? choice : "auto"
        if options.twoMenuNumbers && options.showPercent {
            let pair = menuPair(key, options: options)
            if case let .value(_, glyph) = pair.indicator, let peak = [pair.session, pair.weekly].compactMap({ $0 }).max() { return .value(peak, glyph) }
            return pair.indicator
        }
        return Indicator.select(providers: displayProviders, snapshots: snapshots, providerID: id, window: options.menuWindow, at: .now)
    }

    func menuPair(_ key: String, options: DisplayOptions) -> DockSnapshot {
        var selection = options
        selection.dockProvider = key == "auto" ? options.menuProvider : key
        selection.dockWindow = .session
        var pair = DockSnapshot.resolve(providers: displayProviders, snapshots: snapshots, options: selection, now: .now)
        if pair.session == nil, pair.weekly != nil {
            selection.dockWindow = .weekly
            pair = DockSnapshot.resolve(providers: displayProviders, snapshots: snapshots, options: selection, now: .now)
        }
        return pair
    }
}

@MainActor
struct MenuItemVisual {
    let title: String
    let image: NSImage?
    let iconTint: NSColor?

    var usageDescription: String?

    init(value: Indicator, pair: DockSnapshot? = nil, provider: (any Provider)?, options: DisplayOptions, appearance: NSAppearance) {
        let singleTitle = value.percent.flatMap { options.showPercent ? $0.compactUsage + "%" : nil } ?? (value == .warning ? "⚠" : "")
        let ink = value.percent.map { options.thresholds.color($0) }
        iconTint = provider != nil && !options.showPercent ? ink : nil
        let symbol: NSImage?
        if provider == nil, let percent = value.percent {
            symbol = MenuGauge.image(percent: percent, thresholds: options.thresholds, appearance: appearance)
        } else {
            symbol = NSImage(named: provider?.glyph ?? "UsageTemplate")?.copy() as? NSImage
            symbol?.size = .init(width: 18, height: 18)
            symbol?.isTemplate = true
        }
        guard let pair, pair.session != nil || pair.weekly != nil else {
            title = singleTitle
            image = symbol
            return
        }
        let labels = [pair.session, pair.weekly].map { $0.map { $0.compactUsage + "%" } ?? "–" }
        usageDescription = "5-hour " + labels[0] + ", weekly " + labels[1]
        title = ""
        let light = appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        let foreground: NSColor = light ? .black : .white
        let strings = labels.enumerated().map { index, text in
            NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: index == 0 ? 9 : 10, weight: .semibold), .foregroundColor: foreground])
        }
        let width = ceil(strings.map { $0.size().width }.max() ?? 0)
        image = NSImage(size: NSSize(width: 21 + width, height: 22), flipped: false) { _ in
            let rect = NSRect(x: 0, y: 2, width: 18, height: 18)
            symbol?.draw(in: rect)
            if symbol?.isTemplate == true { foreground.setFill(); rect.fill(using: .sourceAtop) }
            for (index, string) in strings.enumerated() {
                string.draw(at: NSPoint(x: 21 + (width - string.size().width) / 2, y: index == 0 ? 10 : -1))
            }
            return true
        }
        image?.isTemplate = provider != nil
    }
}
