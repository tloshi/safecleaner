import Foundation

public enum CleanCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case developer, applications, browsers, logs, projects
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .developer: return "Developer tools"
        case .applications: return "App caches"
        case .browsers: return "Browser caches"
        case .logs: return "Old logs"
        case .projects: return "Project builds"
        }
    }
    public var symbol: String {
        switch self {
        case .developer: return "hammer"
        case .applications: return "square.stack.3d.up"
        case .browsers: return "globe"
        case .logs: return "doc.text"
        case .projects: return "folder.badge.gearshape"
        }
    }
    public var detail: String {
        switch self {
        case .developer: return "Known build and package caches"
        case .applications: return "Third-party caches, reviewed individually"
        case .browsers: return "Cache folders only; your profiles stay put"
        case .logs: return "Inactive .log files older than 30 days"
        case .projects: return "Generated folders in projects you choose"
        }
    }
}

public struct TreeStamp: Codable, Equatable, Sendable {
    public let digest: String
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let fileCount: Int
    public init(digest: String, logicalBytes: Int64, allocatedBytes: Int64, fileCount: Int) {
        self.digest = digest; self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes; self.fileCount = fileCount
    }
}

public struct Candidate: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let title: String
    public let category: CleanCategory
    public let reason: String
    public let consequence: String
    public let stamp: TreeStamp
    public let allowedRoot: URL
    public let canTrash: Bool
    public let ownerBundleID: String?
    public var bytes: Int64 { stamp.allocatedBytes }
    public init(url: URL, title: String, category: CleanCategory, reason: String,
                consequence: String, stamp: TreeStamp, allowedRoot: URL,
                canTrash: Bool, ownerBundleID: String?) {
        self.url = url; self.title = title; self.category = category
        self.reason = reason; self.consequence = consequence; self.stamp = stamp
        self.allowedRoot = allowedRoot; self.canTrash = canTrash; self.ownerBundleID = ownerBundleID
    }
}

public struct ScanIssue: Identifiable, Codable, Sendable {
    public let id: UUID
    public let path: String
    public let message: String
    public init(path: String, message: String) {
        id = UUID(); self.path = path; self.message = message
    }
}

public struct ScanReport: Sendable {
    public var projects: [URL] = []
    public var candidates: [Candidate] = []
    public var issues: [ScanIssue] = []
    public var finishedAt = Date()
    public init(candidates: [Candidate] = [], issues: [ScanIssue] = [], finishedAt: Date = Date(), projects: [URL] = []) {
        self.candidates = candidates; self.issues = issues; self.finishedAt = finishedAt; self.projects = projects
    }
}

/// Why an item did not move. The prose in `CleanupRecord.error` is for the Activity list;
/// this is what lets the app say *what to do about it* instead of "N failed".
public enum CleanupFailure: String, Codable, Sendable {
    /// macOS refused the operation (EPERM). Often privacy protection, which Full Disk
    /// Access fixes; locked or system-protected files stay refused regardless.
    case permission
    /// Unix permissions refused it (EACCES): owned by another user or read-only, typically
    /// left by an install run with sudo. Full Disk Access does not change this.
    case ownership
    /// The owning app is open, so the item was left untouched.
    case appRunning
    /// The item no longer matches what the scan measured.
    case changed
    case other

    /// An unknown value from a newer build must not make the whole history unreadable,
    /// because an unreadable history pauses cleanup.
    public init(from decoder: Decoder) throws {
        self = CleanupFailure(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
}

public struct CleanupRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let originalPath: String
    public let trashPath: String?
    public let bytes: Int64
    public let error: String?
    /// Optional so histories written before this field existed still decode without a schema bump.
    public let failure: CleanupFailure?
    public init(originalPath: String, trashPath: String?, bytes: Int64, error: String?, failure: CleanupFailure? = nil) {
        id = UUID(); date = Date(); self.originalPath = originalPath
        self.trashPath = trashPath; self.bytes = bytes; self.error = error
        self.failure = error == nil ? nil : (failure ?? .other)
    }
}

public enum SafetyError: LocalizedError {
    case refused(String)
    /// An item that no longer matches its scan. Distinct so it is not reported as a refusal.
    case changedSinceScan
    public var errorDescription: String? {
        switch self {
        case .refused(let message): return message
        case .changedSinceScan: return "The item changed since scanning. Scan again before cleaning."
        }
    }
}

public func byteLabel(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}
