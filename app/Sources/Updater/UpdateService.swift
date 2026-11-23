import Sparkle

@MainActor
final class UpdateService {
    private var updater: SPUStandardUpdaterController?
    private func controller() -> SPUStandardUpdaterController {
        if let updater { return updater }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updater = controller
        return controller
    }

    func setAutomatic(_ enabled: Bool) { controller().updater.automaticallyChecksForUpdates = enabled }
    func check() { controller().checkForUpdates(nil) }
}
