import Foundation

public struct WorkspaceSettings: Equatable, Sendable {
    public var projectRoots: [URL]
    public var exclusions: [URL]
    public var protectedProjects: [URL]
    /// Set when the user was sent to the Full Disk Access pane. macOS applies that grant only
    /// after a relaunch, so the next launch reports the outcome once and clears this.
    public var awaitingFullDiskAccess: Bool
    public init(projectRoots: [URL] = [], exclusions: [URL] = [], protectedProjects: [URL] = [], awaitingFullDiskAccess: Bool = false) {
        self.projectRoots = projectRoots; self.exclusions = exclusions; self.protectedProjects = protectedProjects
        self.awaitingFullDiskAccess = awaitingFullDiskAccess
    }
}

public struct DiskCapacity: Sendable {
    public let total: Int64
    public let free: Int64
    public init(total: Int64, free: Int64) { self.total = total; self.free = free }
    public static let unavailable = DiskCapacity(total: 0, free: 0)
}

public struct WorkspaceSnapshot: Sendable {
    public let settings: WorkspaceSettings
    public let history: [CleanupRecord]
    public let disk: DiskCapacity
    public let notices: [String]
    /// False when the stored history could not be read, which pauses cleanup. The view
    /// needs this as a flag rather than as notice prose so it can offer the recovery.
    public let historyAvailable: Bool
    public init(settings: WorkspaceSettings, history: [CleanupRecord], disk: DiskCapacity,
                notices: [String] = [], historyAvailable: Bool = true) {
        self.settings = settings; self.history = history; self.disk = disk
        self.notices = notices; self.historyAvailable = historyAvailable
    }
}

public struct CleanupBatchResult: Sendable {
    public let records: [CleanupRecord]
    public let history: [CleanupRecord]
    public let stoppedReason: String?
    public init(records: [CleanupRecord], history: [CleanupRecord], stoppedReason: String? = nil) {
        self.records = records; self.history = history; self.stoppedReason = stoppedReason
    }
}

/// Where a cleanup is. Reported before each item, because re-measuring a large item to
/// prove it did not change is the slow part, and a bare spinner gives no sense of the end.
public struct CleanupProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public let bytesCompleted: Int64
    public let bytesTotal: Int64
    /// The item being checked and moved now; nil once every item has been attempted.
    public let current: String?
    public let currentBytes: Int64
    public init(completed: Int, total: Int, bytesCompleted: Int64, bytesTotal: Int64, current: String?, currentBytes: Int64) {
        self.completed = completed; self.total = total; self.bytesCompleted = bytesCompleted
        self.bytesTotal = bytesTotal; self.current = current; self.currentBytes = currentBytes
    }
}

/// What happened after asking an app to quit. Only a normal quit is ever requested: the app
/// may show its own "save changes?" prompt, which is why `stillRunning` is an ordinary answer.
public enum AppQuitOutcome: Sendable, Equatable { case quit, stillRunning, notRunning }

// Ports describe capabilities. Implementations live in the app's Services folder.
public protocol ScanServicing: Sendable {
    func scan(configuration: ScanConfiguration, progress: @escaping @Sendable (String) -> Void) async throws -> ScanReport
}
public protocol CleanupServicing: Sendable {
    func moveToTrash(_ item: Candidate) async -> CleanupRecord
}
public protocol DiskInfoProviding: Sendable {
    func capacity() async throws -> DiskCapacity
}
@MainActor public protocol SettingsStoring {
    func load() -> WorkspaceSettings
    func save(_ settings: WorkspaceSettings) throws
}
public protocol HistoryStoring: Sendable {
    func load() async throws -> [CleanupRecord]
    func save(_ records: [CleanupRecord]) async throws
}
@MainActor public protocol DesktopInteracting {
    func chooseProjectFolders() async -> [URL]
    func runningApplicationIDs() -> Set<String>
    /// The name a person recognises, for "close Xcode first". Nil falls back to the ID.
    func applicationName(for bundleID: String) -> String?
    /// Ask a running app to quit normally and report whether it closed. Never force-quits.
    func quitApplication(_ bundleID: String) async -> AppQuitOutcome
    /// Opens the Full Disk Access pane. macOS offers no API to request that permission,
    /// so sending the user to the right pane is the most an app is permitted to do.
    func openFullDiskAccessSettings()
    func reveal(_ url: URL)
}
public protocol ProjectRootValidating: Sendable {
    func validate(_ url: URL) throws
}
/// Runs one catalogue command and returns its standard output. The only place the app
/// executes anything; implementations validate the executable before running it.
public protocol ToolRunning: Sendable {
    func run(_ command: ToolCommand) async throws -> Data
}
/// Removes a tool-managed candidate through its owning tool. Never a filesystem delete.
public protocol ToolRemoving: Sendable {
    func remove(_ item: Candidate) async -> CleanupRecord
}

/// One thing a process holds: an open file, its working directory or its executable.
public struct ProcessUse: Sendable, Equatable, Hashable {
    public let pid: Int32
    public let name: String
    public let path: String
    public init(pid: Int32, name: String, path: String) { self.pid = pid; self.name = name; self.path = path }
}
/// A point-in-time table of what this user's processes hold, read once per cleanup batch.
public struct OpenFileIndex: Sendable {
    public let uses: [ProcessUse]
    public init(uses: [ProcessUse]) { self.uses = uses }
    /// Processes holding anything at or inside `url`, once each, in pid order.
    public func uses(inside url: URL) -> [ProcessUse] {
        var seen = Set<Int32>()
        return uses.filter { use in
            let path = URL(fileURLWithPath: use.path)
            guard FileSafety.isSame(path, url) || FileSafety.isInside(path, root: url) else { return false }
            return seen.insert(use.pid).inserted
        }.sorted { $0.pid < $1.pid }
    }
}
/// Reads the process table. Read-only by contract; the implementation lives in Services.
public protocol OpenFileChecking: Sendable {
    func index() async -> OpenFileIndex
}

@MainActor public protocol CleaningRepository: AnyObject {
    func setProjectProtection(_ url: URL, protected: Bool) throws -> WorkspaceSettings
    func hasClaudeKey() throws -> Bool
    func saveClaudeKey(_ key: String) async throws
    func removeClaudeKey() async throws
    func verifyClaudeKey(model: ClaudeModel) async throws -> ClaudeKeyCheck
    func analyzeWithClaude(_ packet: AIReviewPacket, model: ClaudeModel) async throws -> AIAnalysis
    func load() async -> WorkspaceSnapshot
    func scan(progress: @escaping @Sendable (String) -> Void) async throws -> ScanReport
    func diskCapacity() async throws -> DiskCapacity
    func addProjectFolders() async throws -> WorkspaceSettings
    func removeProjectFolder(_ url: URL) throws -> WorkspaceSettings
    func exclude(_ url: URL) throws -> WorkspaceSettings
    func removeExclusion(_ url: URL) throws -> WorkspaceSettings
    func clean(_ items: [Candidate], progress: @escaping @MainActor (CleanupProgress) -> Void) async throws -> CleanupBatchResult
    /// Discard the stored activity history and start a new one. The recovery path for a
    /// history file this build cannot read, which otherwise pauses cleanup permanently.
    func resetHistory() async throws -> [CleanupRecord]
    func reveal(_ url: URL)
    func openFullDiskAccessSettings()
    /// The launch after a Full Disk Access request has reported its outcome; forget the request.
    func acknowledgeFullDiskAccessOutcome()
    func applicationNames(for bundleIDs: [String]) -> [String: String]
    func quitApplication(_ bundleID: String) async -> AppQuitOutcome
}

extension DesktopInteracting {
    public func applicationName(for bundleID: String) -> String? { nil }
    public func quitApplication(_ bundleID: String) async -> AppQuitOutcome { .stillRunning }
}

// Optional capability so inert previews and offline repositories never construct a client.
extension CleaningRepository {
    public func setProjectProtection(_ url: URL, protected: Bool) throws -> WorkspaceSettings {
        throw SafetyError.refused("Project protection is unavailable in this workspace.")
    }
    public func hasClaudeKey() throws -> Bool { false }
    public func acknowledgeFullDiskAccessOutcome() {}
    public func applicationNames(for bundleIDs: [String]) -> [String: String] { [:] }
    public func quitApplication(_ bundleID: String) async -> AppQuitOutcome { .stillRunning }
    public func saveClaudeKey(_ key: String) async throws { throw SafetyError.refused("Claude is unavailable in this workspace.") }
    public func removeClaudeKey() async throws { throw SafetyError.refused("Claude is unavailable in this workspace.") }
    public func verifyClaudeKey(model: ClaudeModel) async throws -> ClaudeKeyCheck {
        throw SafetyError.refused("Claude is unavailable in this workspace.")
    }
    public func analyzeWithClaude(_ packet: AIReviewPacket, model: ClaudeModel) async throws -> AIAnalysis {
        throw SafetyError.refused("Claude is unavailable in this workspace.")
    }
}
