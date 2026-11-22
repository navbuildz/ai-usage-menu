import AppKit
import Combine
import CoreServices

@MainActor
final class UsageStore: NSObject, ObservableObject {
    let providers: [any Provider]
    @Published private(set) var snapshots: [String: ProviderSnapshot] = [:]
    var onChange: (() -> Void)?
    private var active: Set<String> = []
    private var lastRead: [String: Date] = [:]
    private var timer: Timer?
    private var expiry: Timer?
    private var streams: [FSEventStreamRef] = []
    private var watcherTimers: [String: Timer] = [:]

    init(providers: [any Provider] = [ClaudeCodeProvider(), CodexProvider()]) {
        self.providers = providers
    }

    func start() {
        setInterval(minutes: 5)
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
        timer?.invalidate()
        let interval = [2,5,10,15,30].contains(minutes) ? minutes : 5
        timer = Timer.scheduledTimer(timeInterval: Double(interval * 60), target: self, selector: #selector(refreshAll), userInfo: nil, repeats: true)
    }

    @objc func refreshAll() { providers.forEach { refresh($0) } }
    func opened(at now: Date = Date()) {
        for provider in providers where now.timeIntervalSince(lastRead[provider.id] ?? .distantPast) > 60 { refresh(provider) }
    }
    func refresh(_ provider: any Provider) {
        guard active.insert(provider.id).inserted else { return }
        Task {
            let snapshot = await provider.read()
            snapshots[provider.id] = snapshot
            lastRead[provider.id] = Date()
            active.remove(provider.id)
            scheduleExpiry()
            onChange?()
        }
    }

    @objc private func expire() {
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
