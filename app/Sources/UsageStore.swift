import AppKit
import Combine
import CoreServices

@MainActor
final class UsageStore: NSObject, ObservableObject {
    let providers: [any Provider]
    @Published private(set) var snapshots: [String: ProviderSnapshot] = [:]
    var onChange: (() -> Void)?
    @Published private(set) var active: Set<String> = []
    @Published private(set) var disabled: Set<String> = []
    var enabled: [any Provider] { providers.filter { !disabled.contains($0.id) } }
    var displayProviders: [any Provider] {
        enabled.filter {
            switch snapshots[$0.id]?.state {
            case .notInstalled, .signedOut, .nonSubscription, .noSessions: false
            default: true
            }
        }
    }

    var readingChanged: (() -> Void)?

    func setDisabled(_ ids: Set<String>) {
        guard ids != disabled else { return }
        let returning = disabled.subtracting(ids)
        disabled = ids
        snapshots = snapshots.filter { !ids.contains($0.key) }
        enabled.filter { returning.contains($0.id) }.forEach { refresh($0) }
    }
    private var lastRead: [String: Date] = [:]
    private var timer: Timer?
    private var expiry: Timer?
    private var streams: [FSEventStreamRef] = []
    private var watcherTimers: [String: Timer] = [:]
    private var retryTimers: [String: Timer] = [:]
    static let quickRetries = 3
    static var retryDelay: TimeInterval = 60

    /// Where the last good readings are kept between launches; nil (tests) keeps nothing.
    private let saved: UserDefaults?

    init(providers: [any Provider] = [ClaudeCodeProvider(), CodexProvider()], saved: UserDefaults? = nil) {
        self.providers = providers
        self.saved = saved
        super.init()
        if let saved { snapshots = SavedReading.load(from: saved).filter { id, _ in providers.contains { $0.id == id } } }
    }

    func start(minutes: Int = 5) {
        setInterval(minutes: minutes)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshAll), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(didLock), name: .init("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(didUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)
        for provider in providers {
            if let directory = provider.watchedDirectory { watch(directory) }
        }
        refreshAll()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        timer?.invalidate(); expiry?.invalidate()
        watcherTimers.values.forEach { $0.invalidate() }
        retryTimers.values.forEach { $0.invalidate() }
        for stream in streams {
            FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
        }
        streams.removeAll()
    }

    func setInterval(minutes: Int) {
        let interval = [2,5,10,15,30].contains(minutes) ? minutes : 5
        guard timer?.timeInterval != Double(interval * 60) || timer?.isValid != true else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: Double(interval * 60), target: self, selector: #selector(scheduledRefresh), userInfo: nil, repeats: true)
    }

    // MARK: Battery and lock

    /// Each Claude read starts Claude Code (about 430 MB and 3 s of CPU, measured 2026-11-23),
    /// so scheduled reads pause while the screen is locked and slow down in Low Power Mode.
    static let lowPowerMinutes = 15
    @Published private(set) var screenLocked = false
    private var missedWhileLocked = false
    var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    @objc private func scheduledRefresh() {
        if screenLocked { missedWhileLocked = true; return }
        let now = Date()
        for provider in providers {
            let last = lastRead[provider.id] ?? .distantPast
            if lowPower, provider.id == "claude", now.timeIntervalSince(last) < Double(Self.lowPowerMinutes * 60) - 5 { continue }
            refresh(provider)
        }
    }

    @objc private func didLock() { screenLocked = true }
    @objc private func didUnlock() {
        screenLocked = false
        if missedWhileLocked { missedWhileLocked = false; refreshAll() }
    }

    @objc func refreshAll() { providers.forEach { refresh($0) } }
    func opened(at now: Date = Date()) {
        for provider in providers where now.timeIntervalSince(lastRead[provider.id] ?? .distantPast) > 60 { refresh(provider) }
    }
    /// Starts a read unless one for this provider is already running (single flight).
    func refresh(_ provider: any Provider) {
        guard begin(provider) else { return }
        Task { _ = await finish(provider) }
    }

    /// Reads one provider through the same single-flight guard and returns the result.
    /// Returns nil when the provider is disabled or a read is already in progress.
    @discardableResult
    func read(_ provider: any Provider) async -> ProviderSnapshot? {
        guard begin(provider) else { return nil }
        return await finish(provider)
    }

    /// Marks the provider as reading, synchronously, so a second call in the same turn is refused.
    private func begin(_ provider: any Provider) -> Bool {
        guard !disabled.contains(provider.id), active.insert(provider.id).inserted else { return false }
        readingChanged?()
        return true
    }

    private func finish(_ provider: any Provider) async -> ProviderSnapshot {
        var snapshot = await provider.read()
        if let kept = snapshots[provider.id]?.keepingReading(after: snapshot) { snapshot = kept }
        else if snapshot.refreshError != nil, snapshot.failedReads == 0 {
            // A reading of last-known numbers shows, but counts as a failed read so it is retried.
            snapshot.failedReads = (snapshots[provider.id]?.failedReads ?? 0) + 1
        }
        if !disabled.contains(provider.id) { snapshots[provider.id] = snapshot }
        if let saved, snapshot.failedReads == 0 { SavedReading.save(snapshots, to: saved) }
        lastRead[provider.id] = Date()
        // A failed read tries again in a minute instead of waiting for the next scheduled read,
        // a few times, so a one-off failure clears on its own (Nav had to press Refresh, 2026-11-25).
        if (1...Self.quickRetries).contains(snapshot.failedReads) {
            retryTimers[provider.id]?.invalidate()
            retryTimers[provider.id] = Timer.scheduledTimer(withTimeInterval: Self.retryDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.retryTimers.removeValue(forKey: provider.id)
                    guard self?.screenLocked == false else { return }
                    self?.refresh(provider)
                }
            }
        }
        active.remove(provider.id)
        readingChanged?()
        scheduleExpiry()
        onChange?()
        return snapshot
    }

    @objc private func expire() {
        objectWillChange.send()
        onChange?()
        scheduleExpiry()
    }
    private func scheduleExpiry() {
        expiry?.invalidate()
        let now = Date()
        guard let date = snapshots.values.flatMap(\.limits).compactMap(\.resetsAt).filter({ $0 > now }).min() else { return }
        expiry = Timer(fireAt: date, interval: 0, target: self, selector: #selector(expire), userInfo: nil, repeats: false)
        RunLoop.main.add(expiry!, forMode: .common)
    }

    private func watch(_ directory: URL) {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            MainActor.assumeIsolated { Unmanaged<UsageStore>.fromOpaque(info).takeUnretainedValue().filesChanged() }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [directory.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, UInt32(kFSEventStreamCreateFlagWatchRoot)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        if FSEventStreamStart(stream) { streams.append(stream) }
        else { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }

    /// Minimum gap between two file-triggered reads of one provider. Codex appends to its
    /// session log constantly while it works, so without this the app would re-read every second.
    static let watcherInterval: TimeInterval = 5
    private var lastWatcherRead: [String: Date] = [:]

    private func filesChanged() {
        for provider in providers where provider.watchedDirectory != nil && watcherTimers[provider.id] == nil {
            // Debounce 0.5 s, and keep at least watcherInterval since the last file-triggered read.
            // A change during the wait is picked up by the read that ends it (trailing read).
            let since = Date().timeIntervalSince(lastWatcherRead[provider.id] ?? .distantPast)
            let delay = max(0.5, Self.watcherInterval - since)
            watcherTimers[provider.id] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.watcherTimers.removeValue(forKey: provider.id)
                    self?.lastWatcherRead[provider.id] = Date()
                    self?.refresh(provider)
                }
            }
        }
    }
}
