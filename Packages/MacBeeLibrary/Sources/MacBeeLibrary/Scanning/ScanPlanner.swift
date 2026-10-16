import Foundation

/// File size + modification date. Used to tell whether a file changed since the last scan.
public struct FileStamp: Sendable, Equatable {
    public var size: Int64
    public var modified: Date

    public init(size: Int64, modified: Date) {
        self.size = size
        self.modified = modified
    }

    /// Network drives often round timestamps, so allow up to 2 seconds of difference.
    public func matches(_ other: FileStamp) -> Bool {
        size == other.size && abs(modified.timeIntervalSince(other.modified)) <= 2
    }
}

public struct ExistingFile: Sendable, Equatable {
    public var id: Int64
    public var stamp: FileStamp
    public var isMissing: Bool

    public init(id: Int64, stamp: FileStamp, isMissing: Bool) {
        self.id = id
        self.stamp = stamp
        self.isMissing = isMissing
    }
}

/// Decides what a scan needs to do. Pure logic, so it's fully unit-tested.
public enum ScanPlanner {
    public struct Plan: Sendable, Equatable {
        /// New or changed files whose tags must be read.
        public var toRead: [String] = []
        /// Previously missing tracks that are back, unchanged.
        public var restored: [Int64] = []
        /// Known tracks no longer found.
        public var missing: [Int64] = []
        public var unchanged = 0
        /// The folder came back empty while the library expected tracks there.
        /// Usually a drive glitch, so nothing is marked missing.
        public var skippedRemovals = false
    }

    public static func plan(existing: [String: ExistingFile], found: [String: FileStamp]) -> Plan {
        var plan = Plan()

        for (path, stamp) in found {
            guard let known = existing[path] else {
                plan.toRead.append(path)
                continue
            }
            if !known.stamp.matches(stamp) {
                plan.toRead.append(path)
            } else if known.isMissing {
                plan.restored.append(known.id)
            } else {
                plan.unchanged += 1
            }
        }

        let present = existing.filter { !$0.value.isMissing }
        if found.isEmpty && !present.isEmpty {
            plan.skippedRemovals = true
        } else {
            plan.missing = present.filter { found[$0.key] == nil }.map(\.value.id)
        }

        plan.toRead.sort() // read in folder order: friendlier to network drives and caches
        plan.restored.sort()
        plan.missing.sort()
        return plan
    }
}
