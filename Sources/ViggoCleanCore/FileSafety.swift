import Foundation
import CryptoKit

public enum FileSafety {
    /// Component-aware containment, never a raw string prefix comparison.
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

        func record(_ entry: URL) throws {
            try Task.checkCancellation()
            let attrs = try fm.attributesOfItem(atPath: entry.path)
            let type = attrs[.type] as? FileAttributeType
            guard type == .typeDirectory || type == .typeRegular else {
                throw SafetyError.refused("Contains a link or special file; manual review is required.")
            }
            guard attrs[.systemNumber] as? NSNumber == device else {
                throw SafetyError.refused("Cross-volume folders are excluded.")
            }
            let values = try entry.resourceValues(forKeys: [.fileAllocatedSizeKey, .isPackageKey])
            if values.isPackage == true {
                throw SafetyError.refused("Contains a package; this version leaves it untouched.")
            }
            let inode = (attrs[.systemFileNumber] as? NSNumber)?.stringValue ?? "unknown"
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let links = (attrs[.referenceCount] as? NSNumber)?.intValue ?? 1
            if type == .typeRegular && links > 1 {
                throw SafetyError.refused("Hard-linked files need manual review.")
            }
            let line = "\(entry.path)\u{0}\(inode)\u{0}\(size)\u{0}\(modified)\u{0}\(type?.rawValue ?? "")\n"
            digest.update(data: Data(line.utf8))
            if type == .typeRegular && visited.insert(inode).inserted {
                logical += size
                allocated += Int64(values.fileAllocatedSize ?? Int(size))
                count += 1
            }
        }

        // Explicit traversal makes ordering stable and errors observable. No symlinks,
        // unreadable subtrees, or packages can silently disappear from an estimate.
        func walk(_ entry: URL) throws {
            try record(entry)
            let attrs = try fm.attributesOfItem(atPath: entry.path)
            if attrs[.type] as? FileAttributeType == .typeDirectory {
                let children = try fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                for child in children { try walk(child) }
            }
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
            guard current == candidate.stamp else {
                throw SafetyError.refused("The item changed since scanning. Scan again before cleaning.")
            }
            // Recheck the root chain immediately before moving. This is best-effort
            // protection against ordinary changes, not a hostile-process sandbox.
            try FileSafety.validate(candidate.url, root: candidate.allowedRoot)
            let destination = try trash(candidate.url)
            return CleanupRecord(originalPath: candidate.url.path, trashPath: destination?.path,
                                 bytes: candidate.bytes, error: nil)
        } catch {
            return CleanupRecord(originalPath: candidate.url.path, trashPath: nil,
                                 bytes: 0, error: error.localizedDescription)
        }
    }
}
