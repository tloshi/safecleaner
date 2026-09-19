import Foundation

public struct WorkspaceSettings: Equatable, Sendable {
    public var projectRoots: [URL]
    public var exclusions: [URL]
    public init(projectRoots: [URL] = [], exclusions: [URL] = []) {
        self.projectRoots = projectRoots; self.exclusions = exclusions
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
    /// Opens the Full Disk Access pane. macOS offers no API to request that permission,
    /// so sending the user to the right pane is the most an app is permitted to do.
    func openFullDiskAccessSettings()
    func reveal(_ url: URL)
}
public protocol ProjectRootValidating: Sendable {
    func validate(_ url: URL) throws
}

@MainActor public protocol CleaningRepository: AnyObject {
    func load() async -> WorkspaceSnapshot
    func scan(progress: @escaping @Sendable (String) -> Void) async throws -> ScanReport
    func diskCapacity() async throws -> DiskCapacity
    func addProjectFolders() async throws -> WorkspaceSettings
    func removeProjectFolder(_ url: URL) throws -> WorkspaceSettings
    func exclude(_ url: URL) throws -> WorkspaceSettings
    func removeExclusion(_ url: URL) throws -> WorkspaceSettings
    func clean(_ items: [Candidate]) async throws -> CleanupBatchResult
    /// Discard the stored activity history and start a new one. The recovery path for a
    /// history file this build cannot read, which otherwise pauses cleanup permanently.
    func resetHistory() async throws -> [CleanupRecord]
    func reveal(_ url: URL)
    func openFullDiskAccessSettings()
}
