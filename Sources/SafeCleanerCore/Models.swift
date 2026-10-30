import Foundation

public enum CleanCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case developer, applications, browsers, logs, projects, simulators, android, xcode, gradle, docker, duplicates
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .developer: return "Developer tools"
        case .applications: return "App caches"
        case .browsers: return "Browser caches"
        case .logs: return "Old logs"
        case .projects: return "Project builds"
        case .simulators: return "Simulators"
        case .android: return "Android SDK"
        case .xcode: return "Xcode stores"
        case .gradle: return "Gradle & Kotlin"
        case .docker: return "Docker"
        case .duplicates: return "Duplicates"
        }
    }
    public var symbol: String {
        switch self {
        case .developer: return "hammer"
        case .applications: return "square.stack.3d.up"
        case .browsers: return "globe"
        case .logs: return "doc.text"
        case .projects: return "folder.badge.gearshape"
        case .simulators: return "iphone"
        case .android: return "shippingbox"
        case .xcode: return "wrench.adjustable"
        case .gradle: return "cube.transparent"
        case .docker: return "server.rack"
        case .duplicates: return "doc.on.doc"
        }
    }
    public var detail: String {
        switch self {
        case .developer: return "Known build and package caches"
        case .applications: return "Third-party caches, reviewed individually"
        case .browsers: return "Cache folders only; your profiles stay put"
        case .logs: return "Inactive .log files older than 30 days"
        case .projects: return "Generated folders in projects you choose"
        case .simulators: return "Runtimes and devices unused for 30 days, removed by Xcode's simctl"
        case .android: return "NDK versions and system images nothing names, and emulator snapshots"
        case .xcode: return "Older device symbols, documentation indexes, idle device logs and archives over 180 days old"
        case .gradle: return "Gradle versions and Kotlin/Native compilers no project names; shared dependency caches stay"
        case .docker: return "Images no container uses, stopped containers and build cache idle for 30 days, removed by the docker command"
        case .duplicates: return "Byte-identical files in folders you choose; every copy but one, the original stays"
        }
    }
}

/// How a candidate leaves the disk when it is not a Trash move: the owning tool removes it.
/// The payload is only ever an identifier that tool reported itself, and the catalogue
/// re-validates it as a UUID before it becomes a command argument.
public enum ToolRemoval: Codable, Sendable, Equatable, Hashable {
    case simulatorRuntime(identifier: String)
    case simulatorDevice(udid: String)
    case dockerImage(id: String)
    case dockerContainer(id: String)
    case dockerBuildCache(id: String)
    /// The short tool name the UI uses in "removed with …".
    public var tool: String {
        switch self {
        case .simulatorRuntime, .simulatorDevice: return "simctl"
        case .dockerImage, .dockerContainer, .dockerBuildCache: return "docker"
        }
    }
    /// The command as a person would type it.
    public var command: String { tool == "simctl" ? "xcrun simctl" : tool }
}

/// Recorded with each history entry so the Activity list says what actually happened.
/// Absent in histories written before it existed, which means a Trash move.
public enum RemovalMethod: String, Codable, Sendable {
    case trash, tool
    public init(from decoder: Decoder) throws {
        self = RemovalMethod(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .trash
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
    /// Set when the owning tool removes the item instead of a Trash move. `canTrash` still
    /// means "selectable for cleanup"; the consequence text says it is permanent.
    public let removal: ToolRemoval?
    /// Why a measured item cannot be selected even though its rule matched: this user cannot
    /// write it, and the app does not ask for administrator rights. Listed so the bytes are
    /// not silently missing from the picture.
    public let blocker: String?
    public var bytes: Int64 { stamp.allocatedBytes }
    public init(url: URL, title: String, category: CleanCategory, reason: String,
                consequence: String, stamp: TreeStamp, allowedRoot: URL,
                canTrash: Bool, ownerBundleID: String?, removal: ToolRemoval? = nil, blocker: String? = nil) {
        self.url = url; self.title = title; self.category = category
        self.reason = reason; self.consequence = consequence; self.stamp = stamp
        self.allowedRoot = allowedRoot; self.canTrash = canTrash; self.ownerBundleID = ownerBundleID
        self.removal = removal; self.blocker = blocker
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
    /// One entry per detected project: how alive it is and what output belongs to it.
    public var activity: [ProjectActivity] = []
    public init(candidates: [Candidate] = [], issues: [ScanIssue] = [], finishedAt: Date = Date(), projects: [URL] = [],
                activity: [ProjectActivity] = []) {
        self.candidates = candidates; self.issues = issues; self.finishedAt = finishedAt; self.projects = projects
        self.activity = activity
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
    /// A process of this user holds something inside the item open, so it was left in place.
    case inUse
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
    /// Optional for the same reason; nil reads as a Trash move.
    public let method: RemovalMethod?
    /// The short name of the tool that removed it ("simctl", "docker"). Absent in histories
    /// written before Docker existed, when the only tool was simctl.
    public let tool: String?
    public init(originalPath: String, trashPath: String?, bytes: Int64, error: String?,
                failure: CleanupFailure? = nil, method: RemovalMethod? = nil, tool: String? = nil) {
        id = UUID(); date = Date(); self.originalPath = originalPath
        self.trashPath = trashPath; self.bytes = bytes; self.error = error
        self.failure = error == nil ? nil : (failure ?? .other)
        self.method = method; self.tool = tool
    }
    public var isToolRemoval: Bool { method == .tool }
    /// The tool a removal went through, defaulting to simctl for histories older than the field.
    public var toolName: String? { isToolRemoval ? (tool ?? "simctl") : nil }
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
