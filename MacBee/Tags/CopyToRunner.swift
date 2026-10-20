import Foundation
import MacBeeLibrary
import Observation

/// Runs Copy To in the background (Troy): scan the device and report, then copy with the chosen options one file
/// at a time, so the window stays responsive and the copy can be paused, stopped, or picked up later. A paused
/// copy is saved (Application Support > MacBee > copy-to-job.json), so it survives unplugging the device or
/// quitting MacBee. It belongs to the app, not the page, so copying carries on while you browse.
@MainActor
@Observable
final class CopyToRunner {
    enum Phase: Equatable {
        case idle
        case scanning
        /// The scan's report is ready and waits for "Start Copy".
        case ready
        case running
        case paused(String)
        case finished
    }

    private(set) var phase = Phase.idle
    private(set) var scan: DeviceSync.Scan?
    /// The device the scan or copy is for.
    private(set) var device: String?
    private(set) var job: DeviceSync.Job?
    private(set) var currentFile: String?
    /// The last finished (or stopped) copy.
    private(set) var report: DeviceSync.Report?
    var choices: DeviceSync.Choices = CopyToRunner.loadChoices() {
        didSet { if let data = try? JSONEncoder().encode(choices) { UserDefaults.standard.set(data, forKey: "copyToChoices") } }
    }

    @ObservationIgnored private let control = Control()
    @ObservationIgnored private static let jobURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacBee/copy-to-job.json")

    init() {
        if let data = try? Data(contentsOf: Self.jobURL), let saved = try? JSONDecoder().decode(DeviceSync.Job.self, from: data) {
            job = saved
            device = saved.device
            phase = .paused("A copy was paused before. Plug the device in and press Resume to carry on.")
        }
    }

    var isBusy: Bool { phase == .scanning || phase == .running }
    var hasUnfinishedCopy: Bool { if case .paused = phase { return true }; return phase == .running }

    // MARK: - Scan

    func scan(sources: [DeviceSync.Source], device: String) async {
        guard !isBusy, !hasUnfinishedCopy else { return }
        phase = .scanning
        scan = nil
        self.device = device
        let dates = Dictionary(sources.flatMap(\.tracks).map { ($0.path, $0.modifiedAt) }, uniquingKeysWith: { a, _ in a })
        let root = URL(fileURLWithPath: device)
        let result = await Task.detached(priority: .userInitiated) {
            let state = DeviceSync.inspect(root)
            return DeviceSync.scan(sources: sources, existing: state.existing, previousManifest: state.manifest,
                                   sourceDate: { dates[$0] },
                                   identify: { DeviceSync.identify(fileAt: root.appendingPathComponent($0)) })
        }.value
        scan = result
        phase = .ready
    }

    /// The selection or device changed: the old report no longer applies.
    func forgetScan() {
        guard phase == .ready || phase == .finished || phase == .idle else { return }
        scan = nil
        phase = .idle
    }

    // MARK: - Copy

    func start() {
        guard phase == .ready, let scan, let device else { return }
        job = DeviceSync.job(for: scan, choices: choices, device: device)
        self.scan = nil
        run()
    }

    func pause() { control.set(pause: true) }

    func resume() {
        guard case .paused = phase, let job else { return }
        guard FileManager.default.fileExists(atPath: job.device) else {
            phase = .paused("The device isn't connected. Plug it in, then press Resume.")
            return
        }
        run()
    }

    func stop() {
        if phase == .running {
            control.set(stop: true)
        } else if case .paused = phase, var job {
            // Stopped while paused: keep MacBee's record of what's already on the device, and report.
            if FileManager.default.fileExists(atPath: job.device) { DeviceSync.saveManifest(job) }
            job.report.stoppedEarly = true
            job.report.finished = Date()
            end(with: job)
        }
    }

    func dismissReport() {
        report = nil
        phase = .idle
    }

    private func run() {
        guard var job else { return }
        phase = .running
        control.reset()
        let control = control
        let jobURL = Self.jobURL
        Task.detached(priority: .utility) { [weak self] in
            var pausedReason: String?
            var stopped = false
            var lastSave = Date()
            while job.next < job.operations.count {
                if control.stopRequested { stopped = true; break }
                if control.pauseRequested { pausedReason = "Paused. Press Resume to carry on, now or later."; break }
                let operation = job.operations[job.next]
                await self?.show(Self.name(of: operation), done: job.next, bytes: job.report.bytes)
                do {
                    try DeviceSync.perform(operation, in: &job)
                } catch {
                    if !FileManager.default.fileExists(atPath: job.device) {
                        pausedReason = "The device was disconnected. Plug it back in and press Resume."
                        break
                    }
                    if (error as NSError).code == NSFileWriteOutOfSpaceError {
                        pausedReason = "The device is full. Make room on it, then press Resume."
                        break
                    }
                    job.report.failed.append(.init(path: Self.name(of: operation), reason: error.localizedDescription))
                }
                job.next += 1
                if Date().timeIntervalSince(lastSave) > 5 {
                    Self.save(job, to: jobURL)
                    DeviceSync.saveManifest(job)
                    lastSave = Date()
                }
            }
            if let pausedReason {
                Self.save(job, to: jobURL)
                if FileManager.default.fileExists(atPath: job.device) { DeviceSync.saveManifest(job) }
                await self?.paused(job, reason: pausedReason)
                return
            }
            if stopped {
                DeviceSync.saveManifest(job)
                job.report.stoppedEarly = true
            } else {
                DeviceSync.finish(job)
            }
            job.report.finished = Date()
            await self?.end(with: job)
        }
    }

    private func show(_ file: String, done: Int, bytes: Int64) {
        currentFile = file
        job?.next = done
        job?.report.bytes = bytes
    }

    private func paused(_ job: DeviceSync.Job, reason: String) {
        self.job = job
        currentFile = nil
        phase = .paused(reason)
    }

    private func end(with job: DeviceSync.Job) {
        report = job.report
        self.job = nil
        currentFile = nil
        try? FileManager.default.removeItem(at: Self.jobURL)
        phase = .finished
    }

    nonisolated private static func save(_ job: DeviceSync.Job, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(job).write(to: url, options: .atomic)
    }

    nonisolated private static func name(of operation: DeviceSync.Operation) -> String {
        switch operation {
        case let .copy(item, _): item.destination
        case let .remove(path): path
        }
    }

    private static func loadChoices() -> DeviceSync.Choices {
        UserDefaults.standard.data(forKey: "copyToChoices").flatMap { try? JSONDecoder().decode(DeviceSync.Choices.self, from: $0) }
            ?? DeviceSync.Choices()
    }

    /// Pause and stop requests, read by the copying task between files.
    private final class Control: @unchecked Sendable {
        private let lock = NSLock()
        private var pause = false
        private var stop = false
        var pauseRequested: Bool { lock.withLock { pause } }
        var stopRequested: Bool { lock.withLock { stop } }
        func set(pause value: Bool) { lock.withLock { pause = value } }
        func set(stop value: Bool) { lock.withLock { stop = value } }
        func reset() { lock.withLock { pause = false; stop = false } }
    }
}
