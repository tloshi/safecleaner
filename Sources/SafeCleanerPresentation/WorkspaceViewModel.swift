import Foundation
import Combine
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

/// Unidirectional MVVM: views send intents; this object owns state transitions.
/// Depends only on the repository contract, never on AppKit, SwiftUI or storage.
@MainActor public final class WorkspaceViewModel: ObservableObject {
    @Published public private(set) var state = WorkspaceViewState()
    private let repository: any CleaningRepository
    private let homePath: String
    private let version: String
    private let previewReport: ScanReport?
    private var session = WorkspaceSession()
    private var started = false
    private var activeTask: Task<Void, Never>?
    private var scanID: UUID?

    public init(repository: any CleaningRepository, homePath: String, version: String, previewReport: ScanReport? = nil) {
        self.repository = repository; self.homePath = homePath; self.version = version; self.previewReport = previewReport
        publish()
    }

    public func start() async {
        guard !started else { return }
        started = true
        let snapshot = await repository.load()
        session.settings = snapshot.settings; session.records = snapshot.history; session.disk = snapshot.disk
        session.historyAvailable = snapshot.historyAvailable
        if previewReport == nil {
            do { session.hasClaudeKey = try repository.hasClaudeKey() }
            catch { session.message = error.localizedDescription }
            session.access = DiskAccess.report(home: URL(fileURLWithPath: homePath),
                                               projectRoots: snapshot.settings.projectRoots)
        }
        if !snapshot.notices.isEmpty { session.message = snapshot.notices.joined(separator: "\n") }
        if let previewReport { apply(previewReport) }
        session.operation = .idle
        publish()
    }

    /// Returned task is useful to lifecycle owners and deterministic unit tests.
    @discardableResult public func send(_ action: WorkspaceAction) -> Task<Void, Never>? {
        switch action {
        case .navigate(let destination):
            session.destination = destination
            if destination != .settings { session.claudeKeyDraft = "" }
        case .dismissMessage: session.message = nil
        case .dismissResult: session.outcome = nil
        case .stopCleanup:
            // Cancellation is checked between items, so nothing is interrupted mid-move.
            guard session.operation == .cleaning, !session.stoppingCleanup else { return nil }
            session.stoppingCleanup = true; activeTask?.cancel()
        case .quitApp(let bundleID):
            guard previewReport == nil, let outcome = session.outcome,
                  let status = outcome.appStatus[bundleID], status == .open || status == .stillOpen else { return nil }
            session.outcome?.appStatus[bundleID] = .quitting; publish()
            // Not an `operation`: quitting another app does not lock this one, and it must not
            // take over `activeTask`, which Stop cancels.
            return Task<Void, Never> { [weak self] in
                guard let self else { return }
                let result = await self.repository.quitApplication(bundleID)
                // The sheet may have closed, or a new cleanup replaced it, while waiting.
                guard self.session.outcome?.id == outcome.id else { return }
                self.session.outcome?.appStatus[bundleID] = result == .stillRunning ? .stillOpen : .closed
                self.publish()
            }
        case .selectRemaining:
            guard state.cleanupResult?.canSelectRemaining == true, let outcome = session.outcome else { return nil }
            // Restores the user's own earlier choice, for items whose app they just closed.
            // It still goes through Review and the confirmation like any other selection.
            session.selected = Set(outcome.releasedItems(in: session.candidates))
            session.outcome = nil; session.query = ""; session.category = nil; session.aiGroupFilter = nil
            session.destination = .review; closeConfirmation()
        case .review(let category): session.category = category; session.query = ""; session.aiGroupFilter = nil; session.destination = .review
        case .queryChanged(let query): session.query = query
        case .categoryChanged(let category): session.category = category
        case .cancelScan:
            if session.operation == .scanning { activeTask?.cancel(); session.progress = "Stopping scan…" }
        case .scan:
            guard state.canScan else { return nil }
            session.operation = .scanning; session.progress = "Preparing your scan…"; session.message = nil
            session.selected.removeAll(); session.candidates = []; session.projects = []; session.issues = []; session.lastScan = nil
            invalidateAI()
            closeConfirmation()
            let id = UUID(); scanID = id
            publish()
            let task = Task<Void, Never> { [weak self] in await self?.runScan(id: id) }
            activeTask = task
            return task
        case .toggleCandidate(let id):
            guard state.canEditSettings, let candidate = item(id), candidate.canTrash else { return nil }
            if !session.selected.insert(id).inserted { session.selected.remove(id) }
            closeConfirmation()
        case .toggleSelectAll:
            guard state.canSelectAll else { return nil }
            let ids = Set(WorkspacePresenter.visible(session).filter(\.canTrash).map(\.id))
            if state.selectAll == .all { session.selected.subtract(ids) } else { session.selected.formUnion(ids) }
            closeConfirmation()
        case .setProjectProtection(let id, let protect):
            guard state.canEditSettings, state.projects.contains(where: { $0.id == id }) else { return nil }
            let project = URL(fileURLWithPath: id)
            handle {
                session.settings = try repository.setProjectProtection(project, protected: protect)
                if protect {
                    // Same containment rule as an exclusion: the project and everything in it.
                    session.candidates.removeAll { FileSafety.isSame($0.url, project) || FileSafety.isInside($0.url, root: project) }
                    session.selected.formIntersection(session.candidates.map(\.id))
                    session.rescanNeeded.removeAll { FileSafety.isSame($0, project) }
                    invalidateAI(); closeConfirmation()
                    session.message = "\(project.lastPathComponent) is protected. SafeCleaner will not scan or clean anything inside it."
                } else if session.settings.projectRoots.contains(where: { FileSafety.isSame(project, $0) || FileSafety.isInside(project, root: $0) }) {
                    // The last scan skipped it, so it is missing from `projects`. Keep its row,
                    // or the switch disappears the moment it is turned off.
                    if !session.projects.contains(where: { FileSafety.isSame($0, project) }) { session.projects.append(project) }
                    if !session.rescanNeeded.contains(where: { FileSafety.isSame($0, project) }) { session.rescanNeeded.append(project) }
                    session.message = "\(project.lastPathComponent) is no longer protected. Scan again to include its build folders."
                } else {
                    // Its folder was removed from the project list, so no scan will reach it
                    // and it could not be protected again. Drop the row rather than promise one.
                    session.projects.removeAll { FileSafety.isSame($0, project) }
                    session.message = "\(project.lastPathComponent) is no longer protected. It is outside your project folders, so it is not scanned."
                }
            }
        case .clearSelection:
            guard !state.isBusy else { return nil }
            session.selected.removeAll(); closeConfirmation()
        case .openConfirmation:
            guard state.canReviewSelection else { return nil }
            session.showConfirmation = true; session.acknowledged = false
        case .dismissConfirmation: closeConfirmation()
        case .acknowledge(let value):
            guard session.showConfirmation, !state.isBusy else { return nil }
            session.acknowledged = value
        case .confirmCleanup:
            guard state.canConfirmCleanup else { return nil }
            let items = session.candidates.filter { $0.canTrash && session.selected.contains($0.id) }
            session.operation = .cleaning; session.message = nil; session.outcome = nil
            session.cleanupProgress = nil; session.stoppingCleanup = false
            closeConfirmation(); publish()
            let origin = session.destination
            let task = Task<Void, Never> { [weak self] in await self?.runCleanup(items, from: origin) }
            activeTask = task
            return task
        case .excludeCandidate(let id):
            guard state.canEditSettings, let candidate = item(id) else { return nil }
            handle {
                session.settings = try repository.exclude(candidate.url)
                session.candidates.removeAll { $0.id == id || FileSafety.isInside($0.url, root: candidate.url) }
                session.selected.formIntersection(session.candidates.map(\.id))
                invalidateAI()
                closeConfirmation()
            }
        case .openFullDiskAccessSettings:
            if previewReport == nil { repository.openFullDiskAccessSettings() }
        case .resetHistory:
            // Only offered while the stored history is unreadable. Discarding a readable
            // activity log is not something this action should be able to do by mistake.
            guard !session.historyAvailable, !state.isBusy else { return nil }
            session.operation = .loading; session.message = nil; publish()
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                do {
                    self.session.records = try await self.repository.resetHistory()
                    self.session.historyAvailable = true
                } catch {
                    // Leave historyAvailable false: a failed reset is not a recovery.
                    self.session.message = error.localizedDescription
                }
                self.session.operation = .idle; self.activeTask = nil; self.publish()
            }
            activeTask = task
            return task
        case .revealCandidate(let id):
            if previewReport == nil, let candidate = item(id) { repository.reveal(candidate.url) }
        case .revealHistory(let id):
            if previewReport == nil, let record = session.records.first(where: { $0.id == id }), let path = record.trashPath {
                repository.reveal(URL(fileURLWithPath: path))
            }
        case .addProjectFolder:
            guard state.canEditSettings else { return nil }
            session.operation = .choosingFolder; publish()
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                do { self.session.settings = try await self.repository.addProjectFolders() }
                catch { self.session.message = error.localizedDescription }
                self.session.operation = .idle; self.activeTask = nil; self.publish()
            }
            activeTask = task
            return task
        case .removeProjectFolder(let id):
            guard state.canEditSettings, let root = session.settings.projectRoots.first(where: { $0.path == id }) else { return nil }
            handle {
                session.settings = try repository.removeProjectFolder(root)
                let dropped = session.candidates.filter { $0.category == .projects && $0.allowedRoot == root }
                session.candidates.removeAll { $0.category == .projects && $0.allowedRoot == root }
                // Roots can overlap, and the scanner credits each item to the first root that
                // reached it. Keep a project any remaining root still reaches, in either
                // direction, and mark it for a rescan if it just lost items it still has.
                let remaining = session.settings.projectRoots
                session.projects.removeAll { project in
                    !remaining.contains { FileSafety.isSame(project, $0) || FileSafety.isInside(project, root: $0) || FileSafety.isInside($0, root: project) }
                }
                for project in session.projects where dropped.contains(where: { FileSafety.isInside($0.url, root: project) })
                    && !session.rescanNeeded.contains(where: { FileSafety.isSame($0, project) }) {
                    session.rescanNeeded.append(project)
                }
                invalidateAI()
                session.selected.formIntersection(session.candidates.map(\.id)); closeConfirmation()
            }
        case .removeExclusion(let id):
            guard state.canEditSettings, let url = session.settings.exclusions.first(where: { $0.path == id }) else { return nil }
            handle { session.settings = try repository.removeExclusion(url) }
        case .claudeKeyChanged(let key):
            guard state.canEditClaudeKey else { return nil }
            session.claudeKeyDraft = String(key.prefix(512))
        case .saveClaudeKey, .removeClaudeKey:
            guard state.canEditClaudeKey else { return nil }
            let removing: Bool
            if case .removeClaudeKey = action { removing = true } else { removing = false }
            guard removing || state.canSaveClaudeKey else { return nil }
            let key = session.claudeKeyDraft
            // Not `operation` and not `activeTask`: a scan may be running, and Stop must still
            // cancel the scan rather than this save.
            session.claudeKeyDraft = ""; session.savingKey = true; session.message = nil; publish()
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                do {
                    if removing { try await self.repository.removeClaudeKey() }
                    else { try await self.repository.saveClaudeKey(key) }
                    self.session.hasClaudeKey = !removing
                    self.session.aiAnalysis = nil
                    self.session.message = removing ? "API key removed from Keychain." : "API key saved in Keychain. No request has been sent."
                } catch { self.session.message = error.localizedDescription }
                self.session.savingKey = false; self.publish()
            }
            return task
        case .claudeModelChanged(let model):
            guard state.canEditSettings else { return nil }
            session.claudeModel = model; session.aiAnalysis = nil
        case .analyzeWithClaude:
            guard state.canAnalyze, let packet = session.aiPacket else { return nil }
            session.operation = .analyzing; session.message = nil; session.aiAnalysis = nil
            closeConfirmation(); publish()
            let model = session.claudeModel
            let task = Task<Void, Never> { [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.repository.analyzeWithClaude(packet, model: model)
                    try Task.checkCancellation()
                    self.session.aiAnalysis = result
                } catch is CancellationError {
                    self.session.message = "Claude request cancelled. A request already submitted may still use credits. No files or selection changed."
                } catch { self.session.message = error.localizedDescription }
                self.session.operation = .idle; self.activeTask = nil; self.publish()
            }
            activeTask = task; return task
        case .cancelClaude:
            if session.operation == .analyzing { activeTask?.cancel() }
        case .reviewAIGroup(let id):
            guard !state.isBusy, !state.isPreview,
                  session.aiAnalysis?.recommendations.contains(where: { $0.groupID == id }) == true,
                  let group = session.aiPacket?.groups.first(where: { $0.id == id }) else { return nil }
            session.aiGroupFilter = group; session.query = ""; session.category = nil; session.destination = .review
        case .clearAIGroupFilter: session.aiGroupFilter = nil
        }
        publish()
        return nil
    }

    private func runScan(id: UUID) async {
        let roots = session.settings.projectRoots
        do {
            let report = try await repository.scan { [weak self] name in
                Task { @MainActor [weak self] in
                    guard let self, self.scanID == id, self.session.operation == .scanning else { return }
                    self.session.progress = name; self.publish()
                }
            }
            try Task.checkCancellation()
            apply(report)
            session.scannedRoots = roots
            if report.candidates.isEmpty { session.message = "Scan finished. No candidates were found in supported locations." }
        } catch is CancellationError { session.message = "Scan cancelled. No files were changed." }
        catch { session.message = "Scan failed: \(error.localizedDescription)" }
        scanID = nil
        await refreshDisk()
        session.operation = .idle; activeTask = nil; publish()
    }

    private func runCleanup(_ items: [Candidate], from origin: Destination) async {
        do {
            let result = try await repository.clean(items) { @MainActor [weak self] progress in
                guard let self else { return }
                self.session.cleanupProgress = progress; self.publish()
            }
            let moved = result.records.filter { $0.error == nil }
            let ids = Set(moved.map(\.originalPath))
            session.records = result.history
            session.candidates.removeAll { ids.contains($0.id) }
            invalidateAI()
            session.selected.removeAll()
            var outcome = CleanupOutcome.make(result, requested: items)
            outcome.appNames = repository.applicationNames(for: Array(outcome.heldByApp.keys))
            // Shown even when everything moved, so the end of a long cleanup is unmistakable.
            session.outcome = outcome
            // The result screen explains what did not move; the banner only reports what did.
            session.message = moved.isEmpty ? nil
                : "\(moved.count) \(moved.count == 1 ? "item" : "items") moved to Trash. Space is not reclaimed until Trash is emptied."
            // Move on to Activity only if the user stayed put. Someone who went elsewhere meanwhile
            // (say, Settings with a key half typed) is not pulled away; the result sheet appears
            // wherever they are.
            if session.destination == origin { session.destination = .history }
        } catch {
            // Nothing moved. A banner was easy to miss here, which read as a dead button.
            session.outcome = .refused(error.localizedDescription, requested: items.count)
        }
        session.cleanupProgress = nil; session.stoppingCleanup = false
        await refreshDisk()
        session.operation = .idle; activeTask = nil; publish()
    }
    private func refreshDisk() async {
        do { session.disk = try await repository.diskCapacity() }
        catch {
            let errorMessage = "Disk information unavailable: \(error.localizedDescription)"
            session.message = [session.message, errorMessage].compactMap { $0 }.joined(separator: "\n")
        }
    }
    private func apply(_ report: ScanReport) {
        session.candidates = report.candidates; session.projects = report.projects; session.rescanNeeded = []
        session.issues = report.issues; session.lastScan = report.finishedAt
        invalidateAI()
    }
    private func invalidateAI() {
        session.aiAnalysis = nil; session.aiGroupFilter = nil
        session.aiPacket = session.candidates.isEmpty ? nil : AIReviewPacket(candidates: session.candidates, skippedLocations: session.issues.count)
    }
    private func item(_ id: String) -> Candidate? { session.candidates.first { $0.id == id } }
    private func closeConfirmation() { session.showConfirmation = false; session.acknowledged = false }
    private func handle(_ operation: () throws -> Void) {
        do { try operation() } catch { session.message = error.localizedDescription }
    }
    private func publish() {
        state = WorkspacePresenter.make(session, preview: previewReport != nil, homePath: homePath, version: version)
    }
}
