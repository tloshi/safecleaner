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
    private let advisor: (any ClaudeAdvising)?
    private let apiKeys: (any APIKeyStoring)?
    private var settings = WorkspaceSettings()
    private var history: [CleanupRecord] = []
    private var historyAvailable = false
    private var cleaning = false

    public init(scanner: any ScanServicing, cleaner: any CleanupServicing,
                disk: any DiskInfoProviding, settings: any SettingsStoring,
                history: any HistoryStoring, desktop: any DesktopInteracting,
                validator: any ProjectRootValidating, home: URL,
                advisor: (any ClaudeAdvising)? = nil, apiKeys: (any APIKeyStoring)? = nil) {
        self.scanner = scanner; self.cleaner = cleaner; self.disk = disk
        self.settingsStore = settings; self.historyStore = history
        self.desktop = desktop; self.validator = validator; self.home = home
        self.advisor = advisor; self.apiKeys = apiKeys
    }

    public func hasClaudeKey() throws -> Bool { try apiKeys?.hasKey() ?? false }
    public func saveClaudeKey(_ key: String) async throws {
        guard let apiKeys else { throw SafetyError.refused("Claude is unavailable in this workspace.") }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-ant-"), (20...512).contains(trimmed.utf8.count),
              trimmed.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else {
            throw SafetyError.refused("Enter a valid Anthropic API key beginning with sk-ant-.")
        }
        try apiKeys.save(trimmed)
        await advisor?.clearCache()
    }
    public func removeClaudeKey() async throws {
        guard let apiKeys else { return }
        try apiKeys.remove()
        await advisor?.clearCache()
    }
    public func analyzeWithClaude(_ packet: AIReviewPacket, model: ClaudeModel) async throws -> AIAnalysis {
        guard let advisor, let key = try apiKeys?.read(), !key.isEmpty else {
            throw SafetyError.refused("Save your Anthropic API key in Settings first.")
        }
        return try await advisor.analyze(packet, model: model, apiKey: key)
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
        try await scanner.scan(configuration: .init(home: home, projectRoots: settings.projectRoots,
            exclusions: settings.exclusions + settings.protectedProjects), progress: progress)
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
    public func setProjectProtection(_ url: URL, protected: Bool) throws -> WorkspaceSettings {
        guard !cleaning else { throw SafetyError.refused("Wait for cleanup to finish before changing project protection.") }
        var updated = settings
        let path = url.standardized
        if protected {
            try validator.validate(path)
            guard settings.projectRoots.contains(where: { FileSafety.isSame(path, $0) || FileSafety.isInside(path, root: $0) }) else {
                throw SafetyError.refused("Choose a project inside one of your project folders.")
            }
            if !updated.protectedProjects.contains(where: { FileSafety.isSame($0, path) }) { updated.protectedProjects.append(path) }
        } else { updated.protectedProjects.removeAll { FileSafety.isSame($0, path) } }
        return try persist(updated)
    }
    private func persist(_ updated: WorkspaceSettings) throws -> WorkspaceSettings {
        try settingsStore.save(updated)
        settings = updated
        return settings
    }

    public func clean(_ items: [Candidate], progress: @escaping @MainActor (CleanupProgress) -> Void = { _ in }) async throws -> CleanupBatchResult {
        guard !cleaning, historyAvailable else {
            throw SafetyError.refused("Cleanup unavailable. Wait for the current operation or resolve the activity-history error.")
        }
        guard !items.isEmpty, items.allSatisfy(\.canTrash) else {
            throw SafetyError.refused("Only reviewed, cleanable candidates can move to Trash.")
        }
        guard Set(items.map(\.id)).count == items.count else {
            throw SafetyError.refused("Duplicate cleanup candidates were refused.")
        }
        for item in items {
            guard !(settings.exclusions + settings.protectedProjects).contains(where: {
                FileSafety.isSame($0, item.url) || FileSafety.isInside(item.url, root: $0) || FileSafety.isInside($0, root: item.url)
            }) else { throw SafetyError.refused("An item contains or belongs to an excluded location. Scan again.") }
        }
        cleaning = true
        defer { cleaning = false }
        // Refuse to start if we cannot persist activity. Never overwrite unreadable history.
        try await historyStore.save(history)
        var completed: [CleanupRecord] = []
        let bytesTotal = items.reduce(Int64(0)) { $0 + $1.bytes }
        var bytesDone: Int64 = 0
        // An item whose app is open is left exactly where it is and reported, rather than
        // refusing the whole batch. Refusing everything made "select all" useless on a
        // developer's Mac, where Xcode, Android Studio or a browser is nearly always open.
        // Checked per item, immediately before it would move, not once up front.
        for item in items {
            if Task.isCancelled {
                return CleanupBatchResult(records: completed, history: history, stoppedReason: "Cleanup stopped between items.")
            }
            progress(CleanupProgress(completed: completed.count, total: items.count, bytesCompleted: bytesDone,
                                     bytesTotal: bytesTotal, current: item.title, currentBytes: item.bytes))
            let record: CleanupRecord
            if let owner = item.ownerBundleID, desktop.runningApplicationIDs().contains(owner) {
                let name = desktop.applicationName(for: owner) ?? owner
                record = CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: 0,
                    error: "Skipped because \(name) is open. Quit \(name), then scan again.", failure: .appRunning)
            } else {
                record = await cleaner.moveToTrash(item)
            }
            completed.append(record); history.insert(record, at: 0); bytesDone += item.bytes
            do { try await historyStore.save(history) }
            catch {
                historyAvailable = false
                return CleanupBatchResult(records: completed, history: history,
                    stoppedReason: "Cleanup stopped: activity could not be saved. The latest result is visible for this session. \(error.localizedDescription)")
            }
        }
        progress(CleanupProgress(completed: completed.count, total: items.count, bytesCompleted: bytesDone,
                                 bytesTotal: bytesTotal, current: nil, currentBytes: 0))
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

    public func applicationNames(for bundleIDs: [String]) -> [String: String] {
        Dictionary(bundleIDs.compactMap { id in desktop.applicationName(for: id).map { (id, $0) } }, uniquingKeysWith: { first, _ in first })
    }
    public func quitApplication(_ bundleID: String) async -> AppQuitOutcome {
        // Quitting mid-cleanup would race the per-item "is its app open" check.
        guard !cleaning else { return .stillRunning }
        return await desktop.quitApplication(bundleID)
    }

    public func reveal(_ url: URL) { desktop.reveal(url) }
    public func openFullDiskAccessSettings() { desktop.openFullDiskAccessSettings() }
}
