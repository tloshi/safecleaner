import Foundation
import CryptoKit

public enum FileSafety {
    /// Component-aware containment, never a raw string prefix comparison.
    /// The same location regardless of a trailing slash, which `URL(fileURLWithPath:)` adds
    /// only when the folder exists at that moment. `URL ==` therefore stops matching once a
    /// folder is renamed or deleted, and a protection could no longer be found to remove.
    public static func isSame(_ a: URL, _ b: URL) -> Bool {
        a.standardized.pathComponents == b.standardized.pathComponents
    }

    public static func isInside(_ url: URL, root: URL) -> Bool {
        let path = url.standardized.pathComponents
        let base = root.standardized.pathComponents
        return path.count > base.count && Array(path.prefix(base.count)) == base
    }

    /// Check all ancestors as well as the selected leaf. Do not resolve links and
    /// then authorize their destination: the link itself must cause a refusal.
    public static func validate(_ url: URL, root: URL) throws {
        guard isInside(url, root: root) else {
            throw SafetyError.refused("The item is outside its approved scan folder.")
        }
        // standardizedFileURL may rewrite /private/var to the /var symlink on
        // macOS. URL.standardized only normalizes URL dot components instead.
        var current = url.standardized
        while current.path != "/" {
            let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw SafetyError.refused("Symbolic links are excluded from cleanup: \(current.path)")
            }
            current.deleteLastPathComponent()
        }
    }

    public static func snapshot(_ url: URL, root: URL) throws -> TreeStamp {
        try validate(url, root: root)
        let fm = FileManager.default
        let base = try fm.attributesOfItem(atPath: url.path)
        let device = base[.systemNumber] as? NSNumber
        var digest = SHA256()
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var count = 0
        var visited = Set<String>()

        /// Returns the entry's type so `walk` knows whether to descend. Never follows a
        /// symbolic link.
        ///
        /// The unit that moves is the whole subtree, because `trashItem` renames it. So the
        /// unit that is measured has to be the whole subtree too, or the estimate and the
        /// move describe different things. That is why interior symlinks and packages are
        /// *counted* here rather than skipped or refused:
        ///
        /// - A symbolic link is an entry in its own right. It moves; its target does not,
        ///   because a rename never dereferences it. Counting the link and refusing to walk
        ///   through it is both accurate and safe. Refusing the candidate outright guarded
        ///   nothing — see `testInteriorSymbolicLinkIsCountedAndItsTargetSurvivesCleanup`.
        /// - A package is an ordinary directory to a rename. Descending into it keeps the
        ///   estimate equal to what moves.
        ///
        /// What still refuses is what genuinely does not survive the move as described:
        /// another volume (a rename cannot cross one) and a special file. The ancestor
        /// symlink check in `validate` is the load-bearing guard and is unchanged.
        @discardableResult
        func record(_ entry: URL) throws -> FileAttributeType? {
            try Task.checkCancellation()
            let attrs = try fm.attributesOfItem(atPath: entry.path)
            let type = attrs[.type] as? FileAttributeType
            let inode = (attrs[.systemFileNumber] as? NSNumber)?.stringValue ?? "unknown"
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

            if type == .typeSymbolicLink {
                let line = "\(entry.path)\u{0}\(inode)\u{0}\(size)\u{0}\(modified)\u{0}link\n"
                digest.update(data: Data(line.utf8))
                logical += size
                allocated += size
                count += 1
                return type
            }
            guard type == .typeDirectory || type == .typeRegular else {
                throw SafetyError.refused("Contains a special file; manual review is required.")
            }
            guard attrs[.systemNumber] as? NSNumber == device else {
                throw SafetyError.refused("Cross-volume folders are excluded.")
            }
            let links = (attrs[.referenceCount] as? NSNumber)?.intValue ?? 1
            if type == .typeRegular && links > 1 {
                throw SafetyError.refused("Hard-linked files need manual review.")
            }
            let line = "\(entry.path)\u{0}\(inode)\u{0}\(size)\u{0}\(modified)\u{0}\(type?.rawValue ?? "")\n"
            digest.update(data: Data(line.utf8))
            if type == .typeRegular && visited.insert(inode).inserted {
                let values = try entry.resourceValues(forKeys: [.fileAllocatedSizeKey])
                logical += size
                allocated += Int64(values.fileAllocatedSize ?? Int(size))
                count += 1
            }
            return type
        }

        // Explicit traversal makes ordering stable and errors observable. No symlinks,
        // unreadable subtrees, or packages can silently disappear from an estimate.
        func walk(_ entry: URL) throws {
            // record reports the type it already stat'ed, so the directory check costs
            // nothing extra, and a symbolic link is never descended into.
            guard try record(entry) == .typeDirectory else { return }
            let children = try fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            // The per-child pool keeps peak memory flat on large trees. Without it the
            // autoreleased attribute dictionaries accumulate for the whole traversal.
            for child in children { try autoreleasepool { try walk(child) } }
        }
        try walk(url)
        return TreeStamp(digest: digest.finalize().map { String(format: "%02x", $0) }.joined(),
                         logicalBytes: logical, allocatedBytes: allocated, fileCount: count)
    }
}

public struct CleanupEngine {
    public typealias TrashOperation = (URL) throws -> URL?
    private let trash: TrashOperation

    public init(trash: @escaping TrashOperation = { url in
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }) { self.trash = trash }

    public func perform(_ candidate: Candidate) -> CleanupRecord {
        do {
            guard candidate.canTrash else {
                throw SafetyError.refused("This category is scan-only in this release.")
            }
            let current = try FileSafety.snapshot(candidate.url, root: candidate.allowedRoot)
            guard current == candidate.stamp else { throw SafetyError.changedSinceScan }
            // Recheck the root chain immediately before moving. This is best-effort
            // protection against ordinary changes, not a hostile-process sandbox.
            try FileSafety.validate(candidate.url, root: candidate.allowedRoot)
            let destination = try trash(candidate.url)
            return CleanupRecord(originalPath: candidate.url.path, trashPath: destination?.path,
                                 bytes: candidate.bytes, error: nil)
        } catch {
            let failure = Self.classify(error)
            return CleanupRecord(originalPath: candidate.url.path, trashPath: nil,
                                 bytes: 0, error: Self.explain(error, as: failure, item: candidate.url), failure: failure)
        }
    }

    /// Failures arrive as Cocoa errors wrapping POSIX ones, so the whole underlying chain is
    /// read and the innermost POSIX code decides: EPERM and EACCES have different remedies,
    /// and only one of them is something Full Disk Access can change.
    static func classify(_ error: Error) -> CleanupFailure {
        if case SafetyError.changedSinceScan = error { return .changed }
        var posix: Int32?
        var cocoaMissing = false
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == NSPOSIXErrorDomain { posix = Int32(nsError.code) }
            // trashItem is a CoreServices move and can report Carbon OSStatus codes instead.
            if nsError.domain == NSOSStatusErrorDomain {
                switch nsError.code {
                case -5000, -54, -61: posix = posix ?? EACCES   // afpAccessDenied, permErr, wrPermErr
                case -43, -120: posix = posix ?? ENOENT         // fnfErr, dirNFErr
                default: break
                }
            }
            if nsError.domain == NSCocoaErrorDomain {
                switch nsError.code {
                case NSFileNoSuchFileError, NSFileReadNoSuchFileError: cocoaMissing = true
                default: break
                }
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        switch posix {
        case EACCES?: return .ownership
        case EPERM?: return .permission
        case ENOENT?: return .changed
        // A Cocoa "no permission" with no detail does not say which kind it is, so it is not
        // labelled as one that Full Disk Access fixes. Its own description is shown instead.
        default: return cocoaMissing ? .changed : .other
        }
    }

    static func explain(_ error: Error, as failure: CleanupFailure, item: URL? = nil) -> String {
        switch failure {
        case .permission:
            return "\(error.localizedDescription) macOS blocked the move. If privacy protection is the cause, Full Disk Access fixes it; locked or system-protected files stay blocked either way."
        case .ownership:
            return "\(error.localizedDescription) It, or something inside it, belongs to another user or is read-only, often from an install run with sudo. SafeCleaner does not ask for administrator rights."
        case .changed:
            if case SafetyError.changedSinceScan = error { return error.localizedDescription }
            // A file can vanish *inside* the item while it is re-measured; the item is still there.
            if let item, (try? FileManager.default.attributesOfItem(atPath: item.path)) != nil {
                return "Something inside it changed during cleanup: \(error.localizedDescription) Scan again."
            }
            return "It no longer exists where the scan found it. Scan again."
        case .appRunning, .other:
            return error.localizedDescription
        }
    }
}
