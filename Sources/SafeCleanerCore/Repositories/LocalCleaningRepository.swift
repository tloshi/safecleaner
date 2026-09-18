import Foundation

/// Owns persistence and coordinates OS services. No UI, formatting or animations.
@MainActor public final class LocalCleaningRepository: CleaningRepository {
    private let scanner: any ScanServicing
    private let cleaner: any CleanupServicing
    private let disk: any DiskInfoProviding
    private let settingsStore: any SettingsStoring
    private let historyStore: any HistoryStoring
    private let desktop: any DesktopInteracting
    private let validator: any ProjectRootValidating
    private let home: URL
    private var settings = WorkspaceSettings()
    private var history: [CleanupRecord] = []
    private var historyAvailable = false
    private var cleaning = false

    public init(scanner: any ScanServicing, cleaner: any CleanupServicing,
                disk: any DiskInfoProviding, settings: any SettingsStoring,
                history: any HistoryStoring, desktop: any DesktopInteracting,
                validator: any ProjectRootValidating, home: URL) {
        self.scanner = scanner; self.cleaner = cleaner; self.disk = disk
        self.settingsStore = settings; self.historyStore = history
        self.desktop = desktop; self.validator = validator; self.home = home
    }

    public func load() async -> WorkspaceSnapshot {
        settings = settingsStore.load()
        var notices: [String] = []
        do { history = try await historyStore.load(); historyAvailable = true }
        catch { historyAvailable = false; notices.append("Activity history could not be read. Cleanup is paused: \(error.localizedDescription)") }
        var capacity = DiskCapacity.unavailable
        do { capacity = try await disk.capacity() }
        catch { notices.append("Disk information unavailable: \(error.localizedDescription)") }
        return WorkspaceSnapshot(settings: settings, history: history, disk: capacity,
                                 notices: notices, historyAvailable: historyAvailable)
    }

    public func scan(progress: @escaping @Sendable (String) -> Void) async throws -> ScanReport {
        try await scanner.scan(configuration: .init(home: home, projectRoots: settings.projectRoots, exclusions: settings.exclusions), progress: progress)
    }
    public func diskCapacity() async throws -> DiskCapacity { try await disk.capacity() }

    public func addProjectFolders() async throws -> WorkspaceSettings {
        let urls = await desktop.chooseProjectFolders()
        var updated = settings
        for url in urls {
            try validator.validate(url)
            if !updated.projectRoots.contains(url) { updated.projectRoots.append(url) }
        }
        return try persist(updated)
    }
    public func removeProjectFolder(_ url: URL) throws -> WorkspaceSettings {
        var updated = settings
        updated.projectRoots.removeAll { $0 == url }
        return try persist(updated)
    }
    public func exclude(_ url: URL) throws -> WorkspaceSettings {
        var updated = settings
        if !updated.exclusions.contains(url) { updated.exclusions.append(url) }
        return try persist(updated)
    }
    public func removeExclusion(_ url: URL) throws -> WorkspaceSettings {
        var updated = settings
        updated.exclusions.removeAll { $0 == url }
        return try persist(updated)
    }
    private func persist(_ updated: WorkspaceSettings) throws -> WorkspaceSettings {
        try settingsStore.save(updated)
        settings = updated
        return settings
    }

    public func clean(_ items: [Candidate]) async throws -> CleanupBatchResult {
        guard !cleaning, historyAvailable else {
            throw SafetyError.refused("Cleanup unavailable. Wait for the current operation or resolve the activity-history error.")
        }
        guard !items.isEmpty, items.allSatisfy(\.canTrash) else {
            throw SafetyError.refused("Only reviewed, cleanable candidates can move to Trash.")
        }
        guard Set(items.map(\.id)).count == items.count else {
            throw SafetyError.refused("Duplicate cleanup candidates were refused.")
        }
        let running = desktop.runningApplicationIDs()
        let blocked = items.filter { $0.ownerBundleID.map(running.contains) ?? false }
        guard blocked.isEmpty else {
            throw SafetyError.refused("Close the related apps first: " + blocked.map(\.title).joined(separator: ", "))
        }
        for item in items {
            guard !settings.exclusions.contains(where: {
                $0.standardized == item.url.standardized || FileSafety.isInside(item.url, root: $0) || FileSafety.isInside($0, root: item.url)
            }) else { throw SafetyError.refused("An item contains or belongs to an excluded location. Scan again.") }
        }
        cleaning = true
        defer { cleaning = false }
        // Refuse to start if we cannot persist activity. Never overwrite unreadable history.
        try await historyStore.save(history)
        var completed: [CleanupRecord] = []
        for item in items {
            if Task.isCancelled {
                return CleanupBatchResult(records: completed, history: history, stoppedReason: "Cleanup stopped between items.")
            }
            let record = await cleaner.moveToTrash(item)
            completed.append(record); history.insert(record, at: 0)
            do { try await historyStore.save(history) }
            catch {
                historyAvailable = false
                return CleanupBatchResult(records: completed, history: history,
                    stoppedReason: "Cleanup stopped: activity could not be saved. The latest result is visible for this session. \(error.localizedDescription)")
            }
        }
        return CleanupBatchResult(records: completed, history: history)
    }
    /// Discarding the history is destructive to the activity log, so it stays an explicit
    /// user action and never happens automatically on a read failure. The in-memory history
    /// is only cleared once the empty file is on disk: a failed write must leave the
    /// repository paused rather than claim a recovery that did not happen.
    public func resetHistory() async throws -> [CleanupRecord] {
        guard !cleaning else {
            throw SafetyError.refused("Wait for the current cleanup to finish.")
        }
        try await historyStore.save([])
        history = []
        historyAvailable = true
        return history
    }

    public func reveal(_ url: URL) { desktop.reveal(url) }
}
