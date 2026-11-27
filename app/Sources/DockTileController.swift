import AppKit

/// Owns the live Dock tile: draws the usage ring into it, and redraws only when the
/// reading, thresholds or appearance actually change.
@MainActor
final class DockTileController {
    private(set) var rendered: DockSnapshot?
    private(set) var renderCount = 0

    func update(store: UsageStore, options: DisplayOptions, tile: NSDockTile = NSApp.dockTile) {
        guard options.placement.showsDock else {
            if rendered != nil { tile.contentView = nil; rendered = nil; tile.display() }
            return
        }
        var snapshot = DockSnapshot.resolve(providers: store.displayProviders, snapshots: store.snapshots, options: options, now: .now)
        snapshot.loading = snapshot.indicator == .absent && !store.active.isEmpty
        snapshot.light = (options.dockTheme.appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) == .aqua
        guard rendered != snapshot else { return }
        rendered = snapshot
        renderCount += 1
        if snapshot.indicator == .absent && !snapshot.loading && !snapshot.light {
            tile.contentView = nil
        } else {
            let view = NSImageView(frame: .init(origin: .zero, size: tile.size))
            view.imageScaling = .scaleProportionallyUpOrDown
            let pixels = Int(tile.size.width * (NSScreen.main?.backingScaleFactor ?? 1))
            view.image = DockIconRenderer.image(for: snapshot, size: max(32, pixels))
            tile.contentView = view
        }
        tile.display()
    }
}
