import Foundation
import CryptoKit

/// A set of byte-identical files: one keeper that stays, and the copies that become Trash rows.
public struct DuplicateSet: Sendable, Equatable {
    public let digest: String
    public let bytes: Int64
    public let keeper: URL
    public let copies: [URL]
    /// The chosen folder each copy was found under, in `copies` order: its allowed root.
    public let copyRoots: [URL]
}

/// Exact duplicate detection in folders the user chooses: same size, then the same partial
/// hash, then the same full SHA-256. Nothing here guesses. Hard links are one file, not two;
/// symbolic links, packages, hidden entries, dependencies, build output and the never-offer
/// list are skipped; the walk and the bytes hashed are capped, and a cap is an issue, never a
/// silently shorter answer.
public enum Duplicates {
    public struct Limits: Sendable {
        public var maxFiles: Int
        public var maxHashedBytes: Int64
        public init(maxFiles: Int = 200_000, maxHashedBytes: Int64 = 50_000_000_000) {
            self.maxFiles = maxFiles; self.maxHashedBytes = maxHashedBytes
        }
    }
    public static let minimumBytes: Int64 = 1_000_000
    static let partialBytes = 65_536
    static let chunkBytes = 1 << 20
    static let skippedDirectories: Set<String> = Set(BuildOutput.rules.map(\.directory))
        .union(["node_modules", "Pods", "vendor", ".git", ".gradle", ".dart_tool", "DerivedData", "Library"])

    struct Entry {
        let url: URL
        let root: URL
        let bytes: Int64
        let modified: Date
    }

    public static func find(roots: [URL], home: URL, exclusions: [URL] = [], limits: Limits = .init(),
                            fm: FileManager = .default, progress: (String) -> Void = { _ in }) throws -> (sets: [DuplicateSet], issues: [ScanIssue]) {
        let collected = try collect(roots: roots, home: home, exclusions: exclusions, limits: limits, fm: fm)
        var issues = collected.issues
        let sets = try compare(collected.entries, limits: limits, issues: &issues, progress: progress)
        return (sets, issues)
    }

    /// Stage one: every regular file worth comparing, with the folder it was found under.
    static func collect(roots: [URL], home: URL, exclusions: [URL], limits: Limits, fm: FileManager) throws -> (entries: [Entry], issues: [ScanIssue]) {
        var issues: [ScanIssue] = []
        var entries: [Entry] = []
        var capped = false
        var unique: [URL] = []
        for root in roots where !unique.contains(where: { FileSafety.isSame($0, root) }) { unique.append(root) }
        func excluded(_ url: URL) -> Bool { exclusions.contains { FileSafety.isSame(url, $0) || FileSafety.isInside(url, root: $0) } }

        walk: for root in unique {
            if let label = FileSafety.sensitiveLabel(for: root, home: home) {
                issues.append(.init(path: root.path, message: "Inside \(label), which SafeCleaner never searches for duplicates."))
                continue
            }
            do { try FileSafety.validate(root, root: home) } catch {
                issues.append(.init(path: root.path, message: "Not searched for duplicates: \(error.localizedDescription)"))
                continue
            }
            guard !excluded(root) else { continue }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants],
                                                 errorHandler: { url, error in issues.append(.init(path: url.path, message: error.localizedDescription)); return true }) else { continue }
            for case let url as URL in enumerator {
                try Task.checkCancellation()
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                let name = url.lastPathComponent
                // skipDescendants applies to the most recently obtained directory, so it is only
                // called for a directory: calling it for a symlink file would skip its neighbour.
                if values.isSymbolicLink == true { continue }
                if excluded(url) { if values.isDirectory == true { enumerator.skipDescendants() }; continue }
                if values.isDirectory == true {
                    if values.isPackage == true || skippedDirectories.contains(name) || name.hasPrefix(".")
                        || FileSafety.sensitiveLabel(for: url, home: home) != nil { enumerator.skipDescendants() }
                    continue
                }
                guard values.isRegularFile == true, values.isPackage != true, !name.hasPrefix("."),
                      let size = values.fileSize, Int64(size) >= minimumBytes else { continue }
                // A hard link is the same file under two names: moving one would not free a byte.
                guard let attributes = try? fm.attributesOfItem(atPath: url.path),
                      ((attributes[.referenceCount] as? NSNumber)?.intValue ?? 1) == 1 else { continue }
                if entries.count >= limits.maxFiles { capped = true; break walk }
                entries.append(Entry(url: url, root: root, bytes: Int64(size), modified: values.contentModificationDate ?? .distantPast))
            }
        }
        if capped {
            issues.append(.init(path: unique.first?.path ?? "", message: "Duplicate search capped at \(limits.maxFiles) files; folders past that were not compared. Choose a narrower folder."))
        }
        return (entries, issues)
    }

    /// Stage two: size, then partial hash, then full hash, within the byte budget.
    static func compare(_ entries: [Entry], limits: Limits, issues: inout [ScanIssue], progress: (String) -> Void) throws -> [DuplicateSet] {
        var hashed: Int64 = 0
        var budgetHit = false
        var sets: [DuplicateSet] = []
        let bySize = Dictionary(grouping: entries, by: \.bytes).values.filter { $0.count > 1 }
            .sorted { $0[0].bytes > $1[0].bytes }
        for group in bySize where !budgetHit {
            progress("Duplicates: comparing \(group.count) files of \(byteLabel(group[0].bytes))")
            var partial: [String: [Entry]] = [:]
            for entry in group {
                try Task.checkCancellation()
                let cost = Int64(min(entry.bytes, Int64(partialBytes * 2)))
                guard hashed + cost <= limits.maxHashedBytes else { budgetHit = true; break }
                hashed += cost
                do { partial[try partialDigest(entry.url), default: []].append(entry) }
                catch is CancellationError { throw CancellationError() }
                catch { issues.append(.init(path: entry.url.path, message: "Not compared: \(error.localizedDescription)")) }
            }
            guard !budgetHit else { break }
            for near in partial.values where near.count > 1 {
                var full: [String: [Entry]] = [:]
                for entry in near {
                    try Task.checkCancellation()
                    guard hashed + entry.bytes <= limits.maxHashedBytes else { budgetHit = true; break }
                    hashed += entry.bytes
                    do { full[try fullDigest(entry.url), default: []].append(entry) }
                    catch is CancellationError { throw CancellationError() }
                    catch { issues.append(.init(path: entry.url.path, message: "Not compared: \(error.localizedDescription)")) }
                }
                guard !budgetHit else { break }
                for (digest, same) in full where same.count > 1 {
                    let keeper = chooseKeeper(same)
                    let copies = same.filter { $0.url.path != keeper.url.path }.sorted { $0.url.path < $1.url.path }
                    sets.append(DuplicateSet(digest: digest, bytes: keeper.bytes, keeper: keeper.url,
                                             copies: copies.map(\.url), copyRoots: copies.map(\.root)))
                }
            }
        }
        if budgetHit {
            issues.append(.init(path: entries.first?.root.path ?? "", message: "Duplicate hashing stopped at its byte budget (\(byteLabel(limits.maxHashedBytes))); the remaining files were not compared."))
        }
        return sets.sorted { $0.bytes == $1.bytes ? $0.keeper.path < $1.keeper.path : $0.bytes > $1.bytes }
    }

    /// The shallowest path, then the oldest file, then the first by name: deterministic, and
    /// biased toward the original over a later copy in a subfolder.
    static func chooseKeeper(_ entries: [Entry]) -> Entry {
        entries.min { a, b in
            let depthA = a.url.pathComponents.count, depthB = b.url.pathComponents.count
            if depthA != depthB { return depthA < depthB }
            if a.modified != b.modified { return a.modified < b.modified }
            return a.url.path < b.url.path
        }!
    }

    /// Size plus the first and last 64 KB: cheap, and enough to split most same-size files.
    static func partialDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let size = try handle.seekToEnd()
        hasher.update(data: Data("\(size)\u{0}".utf8))
        try handle.seek(toOffset: 0)
        if let head = try handle.read(upToCount: partialBytes) { hasher.update(data: head) }
        if size > UInt64(partialBytes) {
            try handle.seek(toOffset: size - UInt64(partialBytes))
            if let tail = try handle.read(upToCount: partialBytes) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkBytes), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
