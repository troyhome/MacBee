import AppKit
import CoreServices
import Foundation

/// Tells the library when a watched folder may have changed.
///
/// Three signals, because network drives need more than one:
/// - FSEvents: instant for changes made on this Mac (local or network folders).
/// - Drive mounted/unmounted: rescan when "2 Set Music" comes back online.
/// - A periodic timer: catches files added to the network drive from another computer,
///   which FSEvents can't see.
@MainActor
final class FolderMonitor {
    /// A watched folder (by root path) has changes to pick up.
    var onFolderChanged: (@MainActor (String) -> Void)?
    /// A drive was mounted or unmounted.
    var onVolumesChanged: (@MainActor () -> Void)?
    /// Time for a routine check of all folders.
    var onPeriodicCheck: (@MainActor () -> Void)?

    private var stream: FSEventStreamRef?
    private var roots: [String] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var periodicTask: Task<Void, Never>?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onVolumesChanged?() }
            }
            workspaceObservers.append(token)
        }
    }

    deinit {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        periodicTask?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Starts (or restarts) watching these folder paths.
    func watch(_ paths: [String]) {
        stopStream()
        roots = paths
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<FolderMonitor>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            // The stream is scheduled on the main queue.
            MainActor.assumeIsolated { monitor.handle(changed) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagIgnoreSelf)
        // 5-second latency: a burst of changes (copying an album) becomes one rescan.
        guard let newStream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                                  FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 5.0, flags)
        else { return }
        FSEventStreamSetDispatchQueue(newStream, .main)
        FSEventStreamStart(newStream)
        stream = newStream
    }

    /// Routine check interval; nil turns it off.
    func setPeriodicCheck(every interval: TimeInterval?) {
        periodicTask?.cancel()
        periodicTask = nil
        guard let interval, interval > 0 else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self?.onPeriodicCheck?()
            }
        }
    }

    private func handle(_ changedPaths: [String]) {
        var hit = Set<String>()
        for path in changedPaths {
            if let root = roots.first(where: { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) {
                hit.insert(root)
            }
        }
        hit.forEach { onFolderChanged?($0) }
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
