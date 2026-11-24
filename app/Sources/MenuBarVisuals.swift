import AppKit

// Drawing for the menu bar item: the three-bar gauge, the provider glyph and the
// one- or two-number label. Pure functions of the current reading and options.

@MainActor
enum MenuGauge {
    /// Three rising bars, one color. Solid bars show the usage tier (1 low, 2 medium, 3 high,
    /// from the health thresholds); the rest are faint. It is a template image, so macOS draws it
    /// black or white to match the menu bar, in light, dark and tinted wallpapers alike.
    static func image(percent: Double, thresholds: Thresholds, appearance: NSAppearance? = nil) -> NSImage {
        let tier = thresholds.tier(percent)
        let image = NSImage(size: .init(width: 18, height: 18), flipped: false) { _ in
            let heights: [CGFloat] = [6, 10, 14]
            for (index, height) in heights.enumerated() {
                let rect = NSRect(x: 2 + CGFloat(index) * 5, y: 2, width: 3.6, height: height)
                NSColor.black.withAlphaComponent(index < tier ? 1 : 0.28).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = ["low", "medium", "high"][tier - 1] + " usage"
        return image
    }
}

extension UsageStore {
    func menuValue(_ key: String, options: DisplayOptions) -> Indicator {
        let choice = key == "auto" ? options.menuProvider : key
        // Keep the provider the user chose, even while it has no reading (it then shows its warning).
        // Fall back to Auto only when that provider is turned off or not installed.
        let chosenUsable = enabled.contains { $0.id == choice } && snapshots[choice]?.state != .notInstalled
        let id = chosenUsable ? choice : "auto"
        let pool: [any Provider] = chosenUsable ? enabled.filter { $0.id == choice } : displayProviders
        if options.twoMenuNumbers && options.showPercent {
            let pair = menuPair(key, options: options)
            if case let .value(_, glyph) = pair.indicator, let peak = [pair.session, pair.weekly].compactMap({ $0 }).max() { return .value(peak, glyph) }
            return pair.indicator
        }
        return Indicator.select(providers: pool, snapshots: snapshots, providerID: id, window: options.menuWindow, at: .now)
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
        image?.isTemplate = true
    }
}
