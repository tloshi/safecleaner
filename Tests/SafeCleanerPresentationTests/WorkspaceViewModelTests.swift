import XCTest
import SafeCleanerCore
@testable import SafeCleanerPresentation

@MainActor final class WorkspaceViewModelTests: XCTestCase {
    private func fixture(_ name: String = "cache", cleanable: Bool = true, bytes: Int64 = 4096) -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/fixture/\(name)"), title: name, category: cleanable ? .developer : .projects,
            reason: "Fixture", consequence: "Test only", stamp: .init(digest: "fixture", logicalBytes: bytes, allocatedBytes: bytes, fileCount: 1),
            allowedRoot: URL(fileURLWithPath: "/fixture"), canTrash: cleanable, ownerBundleID: nil)
    }
    private func ready(_ items: [Candidate]) async -> (WorkspaceViewModel, FakeRepository) {
        let repository = FakeRepository()
        repository.report = ScanReport(candidates: items)
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start()
        await vm.send(.scan)?.value
        return (vm, repository)
    }

    /// A history the build cannot read pauses cleanup. The view needs a flag, not just the
    /// notice text, or there is nothing to attach a recovery control to.
    func testUnreadableHistoryOffersReset() async {
        let repository = FakeRepository()
        repository.historyAvailable = false
        repository.notices = ["Activity history could not be read."]
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start()
        XCTAssertTrue(vm.state.historyNeedsReset)

        await vm.send(.resetHistory)?.value
        XCTAssertEqual(repository.resetCalls, 1)
        XCTAssertFalse(vm.state.historyNeedsReset)
    }

    func testFailedResetKeepsTheOfferAndReportsWhy() async {
        let repository = FakeRepository()
        repository.historyAvailable = false
        repository.resetError = SafetyError.refused("Disk is read-only")
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start()

        await vm.send(.resetHistory)?.value
        XCTAssertTrue(vm.state.historyNeedsReset, "a failed reset must not look like a recovery")
        XCTAssertEqual(vm.state.message, "Disk is read-only")
    }

    func testVersionReachesViewState() async {
        let repository = FakeRepository()
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        XCTAssertEqual(vm.state.version, "9.9.9")
        await vm.start()
        XCTAssertEqual(vm.state.version, "9.9.9")
    }

    func testStartLoadsOnceWithoutScanning() async {
        let repository = FakeRepository()
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        XCTAssertTrue(vm.state.isBusy)
        await vm.start(); await vm.start()
        XCTAssertEqual(repository.loads, 1)
        XCTAssertEqual(repository.scans, 0)
        XCTAssertTrue(vm.state.canScan)
        XCTAssertEqual(vm.state.diskFraction, 0.8, accuracy: 0.001)
        XCTAssertEqual(vm.state.categories.count, 5)
    }

    func testScanBeginsWithNothingSelectedAndRejectsScanOnlyItems() async {
        let project = fixture("project", cleanable: false)
        let (vm, repository) = await ready([fixture(), project])
        XCTAssertEqual(vm.state.candidateCount, "2")
        XCTAssertFalse(vm.state.canReviewSelection)
        vm.send(.toggleCandidate(project.id)); vm.send(.openConfirmation); vm.send(.confirmCleanup)
        XCTAssertFalse(vm.state.showConfirmation)
        XCTAssertEqual(repository.cleanCalls, 0)
    }

    func testFilteringPreservesSelectionAndTotalsAcrossCategories() async {
        let first = fixture("first", bytes: 4096)
        let second = fixture("second", bytes: 8192)
        let (vm, _) = await ready([first, second])
        vm.send(.toggleCandidate(first.id)); vm.send(.queryChanged("second"))
        XCTAssertEqual(vm.state.candidates.map(\.id), [second.id])
        XCTAssertEqual(vm.state.selectedValue, 4096)
        XCTAssertTrue(vm.state.canReviewSelection)
        vm.send(.categoryChanged(.projects))
        XCTAssertTrue(vm.state.candidates.isEmpty)
        XCTAssertEqual(vm.state.selectedValue, 4096)
    }

    func testAcknowledgementAndOpenConfirmationAreRequiredByViewModel() async {
        let candidate = fixture()
        let (vm, repository) = await ready([candidate])
        vm.send(.toggleCandidate(candidate.id))
        vm.send(.acknowledge(true)); vm.send(.confirmCleanup)
        XCTAssertEqual(repository.cleanCalls, 0)
        vm.send(.openConfirmation); vm.send(.confirmCleanup)
        XCTAssertFalse(vm.state.canConfirmCleanup)
        XCTAssertEqual(repository.cleanCalls, 0)
        vm.send(.acknowledge(true))
        XCTAssertTrue(vm.state.canConfirmCleanup)
        await vm.send(.confirmCleanup)?.value
        XCTAssertEqual(repository.cleanedIDs, [candidate.id])
        XCTAssertEqual(vm.state.destination, .history)
        XCTAssertTrue(vm.state.candidates.isEmpty)
    }

    func testDismissAndSelectionChangesInvalidateAcknowledgement() async {
        let candidate = fixture()
        let (vm, _) = await ready([candidate])
        vm.send(.toggleCandidate(candidate.id)); vm.send(.openConfirmation); vm.send(.acknowledge(true))
        vm.send(.dismissConfirmation); vm.send(.openConfirmation)
        XCTAssertFalse(vm.state.confirmationAcknowledged)
        vm.send(.acknowledge(true)); vm.send(.clearSelection)
        XCTAssertFalse(vm.state.showConfirmation)
        XCTAssertFalse(vm.state.canConfirmCleanup)
    }

    func testScanFailureAndCancellationLeaveUIUsable() async {
        let repository = FakeRepository()
        repository.scanError = SafetyError.refused("Scan fixture error")
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start(); await vm.send(.scan)?.value
        XCTAssertTrue(vm.state.message?.contains("Scan fixture error") == true)
        XCTAssertTrue(vm.state.canScan)
        repository.scanError = nil; repository.delayScan = true
        let operation = vm.send(.scan)
        XCTAssertTrue(vm.state.isScanning)
        XCTAssertNil(vm.send(.scan))
        XCTAssertNil(vm.send(.addProjectFolder))
        vm.send(.cancelScan)
        await operation?.value
        XCTAssertFalse(vm.state.isScanning)
        XCTAssertFalse(vm.state.hasScanned)
        XCTAssertTrue(vm.state.message?.contains("cancelled") == true)
        let oldProgress = vm.state.progress
        repository.progress?("STALE CALLBACK")
        await Task.yield(); await Task.yield()
        XCTAssertEqual(vm.state.progress, oldProgress)
    }

    func testExclusionFailureDoesNotRemoveCandidateOrSelection() async {
        let candidate = fixture()
        let (vm, repository) = await ready([candidate])
        vm.send(.toggleCandidate(candidate.id))
        repository.settingsError = SafetyError.refused("Storage unavailable")
        vm.send(.excludeCandidate(candidate.id))
        XCTAssertEqual(vm.state.candidates.count, 1)
        XCTAssertTrue(vm.state.candidates[0].isSelected)
        XCTAssertEqual(vm.state.message, "Storage unavailable")
    }

    func testCleanupFailureKeepsCandidateAndResetsBusyState() async {
        let candidate = fixture()
        let (vm, repository) = await ready([candidate])
        repository.cleanupError = SafetyError.refused("App still running")
        vm.send(.toggleCandidate(candidate.id)); vm.send(.openConfirmation); vm.send(.acknowledge(true))
        await vm.send(.confirmCleanup)?.value
        XCTAssertFalse(vm.state.isBusy)
        XCTAssertEqual(vm.state.candidates.count, 1)
        XCTAssertEqual(vm.state.message, "App still running")
        XCTAssertFalse(vm.state.showConfirmation)
    }

    func testPartialCleanupOnlyRemovesSuccessfulItems() async {
        let first = fixture("first"), second = fixture("second")
        let (vm, repository) = await ready([first, second])
        let moved = CleanupRecord(originalPath: first.id, trashPath: "/synthetic-trash/first", bytes: first.bytes, error: nil)
        let failed = CleanupRecord(originalPath: second.id, trashPath: nil, bytes: 0, error: "Changed")
        repository.cleanupResult = .init(records: [moved, failed], history: [failed, moved])
        vm.send(.toggleCandidate(first.id)); vm.send(.toggleCandidate(second.id))
        vm.send(.openConfirmation); vm.send(.acknowledge(true)); await vm.send(.confirmCleanup)?.value
        XCTAssertEqual(vm.state.candidates.map(\.id), [second.id])
        XCTAssertEqual(vm.state.history.count, 2)
        XCTAssertFalse(vm.state.canReviewSelection)
        XCTAssertTrue(vm.state.message?.contains("1 failed") == true)
    }

    func testPreviewCannotReachMutatingOrDesktopRepositoryMethods() async {
        let candidate = fixture()
        let repository = FakeRepository()
        repository.settings = .init(projectRoots: [URL(fileURLWithPath: "/fixture/project")], exclusions: [URL(fileURLWithPath: "/fixture/keep")])
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9", previewReport: .init(candidates: [candidate]))
        await vm.start()
        let actions: [WorkspaceAction] = [.scan, .toggleCandidate(candidate.id), .openConfirmation, .acknowledge(true), .confirmCleanup,
            .excludeCandidate(candidate.id), .revealCandidate(candidate.id), .addProjectFolder,
            .removeProjectFolder("/fixture/project"), .removeExclusion("/fixture/keep")]
        for action in actions { vm.send(action) }
        XCTAssertTrue(vm.state.isPreview)
        XCTAssertFalse(vm.state.canConfirmCleanup)
        XCTAssertEqual(repository.scans + repository.cleanCalls + repository.settingsWrites + repository.reveals, 0)
    }
}

@MainActor private final class FakeRepository: CleaningRepository {
    var loads = 0, scans = 0, cleanCalls = 0, settingsWrites = 0, reveals = 0, resetCalls = 0, settingsOpens = 0
    var cleanedIDs: [String] = []
    var settings = WorkspaceSettings()
    var report = ScanReport()
    var notices: [String] = []
    var historyAvailable = true
    var scanError: Error?, settingsError: Error?, cleanupError: Error?, resetError: Error?
    var cleanupResult: CleanupBatchResult?
    var delayScan = false
    var progress: (@Sendable (String) -> Void)?
    func load() async -> WorkspaceSnapshot {
        loads += 1
        return .init(settings: settings, history: [], disk: .init(total: 100, free: 20), notices: notices, historyAvailable: historyAvailable)
    }
    func scan(progress: @escaping @Sendable (String) -> Void) async throws -> ScanReport {
        scans += 1; self.progress = progress
        if let scanError { throw scanError }
        if delayScan { try await Task.sleep(nanoseconds: 60_000_000_000) }
        return report
    }
    func diskCapacity() async throws -> DiskCapacity { .init(total: 100, free: 20) }
    func addProjectFolders() async throws -> WorkspaceSettings { settingsWrites += 1; return settings }
    func removeProjectFolder(_ url: URL) throws -> WorkspaceSettings { settingsWrites += 1; return settings }
    func exclude(_ url: URL) throws -> WorkspaceSettings {
        if let settingsError { throw settingsError }
        settingsWrites += 1; settings.exclusions.append(url); return settings
    }
    func removeExclusion(_ url: URL) throws -> WorkspaceSettings { settingsWrites += 1; return settings }
    func resetHistory() async throws -> [CleanupRecord] {
        resetCalls += 1
        if let resetError { throw resetError }
        return []
    }
    func clean(_ items: [Candidate]) async throws -> CleanupBatchResult {
        cleanCalls += 1; cleanedIDs = items.map(\.id)
        if let cleanupError { throw cleanupError }
        if let cleanupResult { return cleanupResult }
        let records = items.map { CleanupRecord(originalPath: $0.id, trashPath: "/synthetic-trash/item", bytes: $0.bytes, error: nil) }
        return .init(records: records, history: records)
    }
    func reveal(_ url: URL) { reveals += 1 }
    func openFullDiskAccessSettings() { settingsOpens += 1 }
}
