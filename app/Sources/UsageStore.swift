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

    init(providers: [any Provider] = [ClaudeCodeProvider(), CodexProvider()]) {
        self.providers = providers
    }

    func start(minutes: Int = 5) {
        setInterval(minutes: minutes)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshAll), name: NSWorkspace.didWakeNotification, object: nil)
        for provider in providers {
            if let directory = provider.watchedDirectory { watch(directory) }
        }
        refreshAll()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timer?.invalidate(); expiry?.invalidate()
        watcherTimers.values.forEach { $0.invalidate() }
        for stream in streams {
            FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
        }
        streams.removeAll()
    }

    func setInterval(minutes: Int) {
        let interval = [2,5,10,15,30].contains(minutes) ? minutes : 5
        guard timer?.timeInterval != Double(interval * 60) || timer?.isValid != true else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: Double(interval * 60), target: self, selector: #selector(refreshAll), userInfo: nil, repeats: true)
    }

    @objc func refreshAll() { providers.forEach { refresh($0) } }
    func opened(at now: Date = Date()) {
        for provider in providers where now.timeIntervalSince(lastRead[provider.id] ?? .distantPast) > 60 { refresh(provider) }
    }
    func refresh(_ provider: any Provider) {
        guard !disabled.contains(provider.id), active.insert(provider.id).inserted else { return }
        readingChanged?()
        Task {
            let snapshot = await provider.read()
            if !disabled.contains(provider.id) { snapshots[provider.id] = snapshot }
            lastRead[provider.id] = Date()
            active.remove(provider.id)
            readingChanged?()
            scheduleExpiry()
            onChange?()
        }
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

    private func filesChanged() {
        for provider in providers where provider.watchedDirectory != nil && watcherTimers[provider.id] == nil {
            watcherTimers[provider.id] = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.watcherTimers.removeValue(forKey: provider.id)
                    self?.refresh(provider)
                }
            }
        }
    }
}
