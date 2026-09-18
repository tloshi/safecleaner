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
        session.message = snapshot.notices.isEmpty ? nil : snapshot.notices.joined(separator: "\n")
        if let previewReport { apply(previewReport) }
        session.operation = .idle
        publish()
    }

    /// Returned task is useful to lifecycle owners and deterministic unit tests.
    @discardableResult public func send(_ action: WorkspaceAction) -> Task<Void, Never>? {
        switch action {
        case .navigate(let destination): session.destination = destination
        case .dismissMessage: session.message = nil
        case .review(let category): session.category = category; session.query = ""; session.destination = .review
        case .queryChanged(let query): session.query = query
        case .categoryChanged(let category): session.category = category
        case .cancelScan:
            if session.operation == .scanning { activeTask?.cancel(); session.progress = "Stopping scan…" }
        case .scan:
            guard state.canScan else { return nil }
            session.operation = .scanning; session.progress = "Preparing your scan…"; session.message = nil
            session.selected.removeAll(); session.candidates = []; session.issues = []; session.lastScan = nil
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
            session.operation = .cleaning; session.message = nil; closeConfirmation(); publish()
            let task = Task<Void, Never> { [weak self] in await self?.runCleanup(items) }
            activeTask = task
            return task
        case .excludeCandidate(let id):
            guard state.canEditSettings, let candidate = item(id) else { return nil }
            handle {
                session.settings = try repository.exclude(candidate.url)
                session.candidates.removeAll { $0.id == id || FileSafety.isInside($0.url, root: candidate.url) }
                session.selected.formIntersection(session.candidates.map(\.id))
                closeConfirmation()
            }
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
                session.candidates.removeAll { $0.category == .projects && $0.allowedRoot == root }
                session.selected.formIntersection(session.candidates.map(\.id)); closeConfirmation()
            }
        case .removeExclusion(let id):
            guard state.canEditSettings, let url = session.settings.exclusions.first(where: { $0.path == id }) else { return nil }
            handle { session.settings = try repository.removeExclusion(url) }
        }
        publish()
        return nil
    }

    private func runScan(id: UUID) async {
        do {
            let report = try await repository.scan { [weak self] name in
                Task { @MainActor [weak self] in
                    guard let self, self.scanID == id, self.session.operation == .scanning else { return }
                    self.session.progress = name; self.publish()
                }
            }
            try Task.checkCancellation()
            apply(report)
            if report.candidates.isEmpty { session.message = "Scan finished. No candidates were found in supported locations." }
        } catch is CancellationError { session.message = "Scan cancelled. No files were changed." }
        catch { session.message = "Scan failed: \(error.localizedDescription)" }
        scanID = nil
        await refreshDisk()
        session.operation = .idle; activeTask = nil; publish()
    }

    private func runCleanup(_ items: [Candidate]) async {
        do {
            let result = try await repository.clean(items)
            let moved = result.records.filter { $0.error == nil }
            let ids = Set(moved.map(\.originalPath))
            session.records = result.history
            session.candidates.removeAll { ids.contains($0.id) }
            session.selected.removeAll()
            session.message = result.stoppedReason ?? "\(moved.count) items moved to Trash. \(result.records.count - moved.count) failed. Space is not reclaimed until Trash is emptied."
            session.destination = .history
        } catch { session.message = error.localizedDescription }
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
        session.candidates = report.candidates; session.issues = report.issues; session.lastScan = report.finishedAt
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
