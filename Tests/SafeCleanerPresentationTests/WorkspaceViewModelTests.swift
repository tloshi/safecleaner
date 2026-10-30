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

    func testClaudeRequiresKeyAndExplicitActionAndNeverSelectsOrCleans() async {
        let candidate = fixture()
        let (vm, repository) = await ready([candidate])
        XCTAssertEqual(repository.aiCalls, 0)
        XCTAssertFalse(vm.state.canAnalyze)
        XCTAssertNil(vm.send(.analyzeWithClaude))
        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key"))
        await vm.send(.saveClaudeKey)?.value
        XCTAssertTrue(vm.state.hasClaudeKey)
        XCTAssertTrue(vm.state.claudeKeyDraft.isEmpty)
        XCTAssertEqual(repository.aiCalls, 0)
        await vm.send(.analyzeWithClaude)?.value
        XCTAssertEqual(repository.aiCalls, 1)
        XCTAssertEqual(vm.state.aiAdvice.count, 1)
        vm.send(.reviewAIGroup("g1"))
        XCTAssertEqual(vm.state.destination, .review)
        XCTAssertNotNil(vm.state.aiGroupFilterTitle)
        XCTAssertFalse(vm.state.canReviewSelection)
        XCTAssertEqual(repository.cleanCalls, 0)
    }

    func testClaudeFailurePreservesManualSelectionAndRecoversControls() async {
        let candidate = fixture()
        let (vm, repository) = await ready([candidate])
        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key")); await vm.send(.saveClaudeKey)?.value
        vm.send(.toggleCandidate(candidate.id))
        repository.aiError = SafetyError.refused("No credits")
        await vm.send(.analyzeWithClaude)?.value
        XCTAssertEqual(vm.state.message, "No credits")
        XCTAssertTrue(vm.state.candidates[0].isSelected)
        XCTAssertTrue(vm.state.canAnalyze)
        XCTAssertNil(vm.state.aiSummary)
    }

    func testClaudeCancellationAndBusyGuardPreventDuplicateCalls() async {
        let (vm, repository) = await ready([fixture()])
        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key")); await vm.send(.saveClaudeKey)?.value
        repository.delayAI = true
        let task = vm.send(.analyzeWithClaude)
        XCTAssertTrue(vm.state.isAnalyzing)
        XCTAssertNil(vm.send(.analyzeWithClaude))
        XCTAssertNil(vm.send(.scan))
        vm.send(.cancelClaude); await task?.value
        XCTAssertFalse(vm.state.isBusy)
        XCTAssertNil(vm.state.aiSummary)
        XCTAssertTrue(vm.state.message?.contains("cancelled") == true)
    }

    func testNewScanAndExclusionInvalidateClaudePlan() async {
        let candidate = fixture()
        let (vm, _) = await ready([candidate])
        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key")); await vm.send(.saveClaudeKey)?.value
        await vm.send(.analyzeWithClaude)?.value
        XCTAssertNotNil(vm.state.aiSummary)
        await vm.send(.scan)?.value
        XCTAssertNil(vm.state.aiSummary)
        await vm.send(.analyzeWithClaude)?.value
        vm.send(.excludeCandidate(candidate.id))
        XCTAssertNil(vm.state.aiSummary)
        XCTAssertFalse(vm.state.canAnalyze)
    }

    func testKeyDraftClearsOnNavigationAndFailedSaveDoesNotClaimSuccess() async {
        let (vm, repository) = await ready([fixture()])
        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key")); vm.send(.navigate(.overview))
        XCTAssertTrue(vm.state.claudeKeyDraft.isEmpty)
        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key"))
        repository.keyError = SafetyError.refused("Keychain locked")
        await vm.send(.saveClaudeKey)?.value
        XCTAssertFalse(vm.state.hasClaudeKey)
        XCTAssertTrue(vm.state.claudeKeyDraft.isEmpty)
        XCTAssertEqual(vm.state.message, "Keychain locked")
    }

    func testPreviewCannotUseClaudeOrKeychain() async {
        let repository = FakeRepository(); repository.hasKey = true
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "test",
                                    previewReport: .init(candidates: [fixture()]))
        await vm.start()
        for action: WorkspaceAction in [.claudeKeyChanged("sk-ant-synthetic-test-key"), .saveClaudeKey, .removeClaudeKey,
                                        .analyzeWithClaude, .verifyClaudeKey, .navigate(.settings), .navigate(.assistant)] {
            await vm.send(action)?.value
        }
        XCTAssertEqual(repository.aiCalls + repository.keyReads + repository.keyWrites + repository.verifyCalls, 0)
        XCTAssertFalse(vm.state.canVerifyClaudeKey)
    }

    /// “Saved in Keychain” never answered whether Anthropic accepts the key. The check must be
    /// visible, free of scan data, and must not lock the rest of the workspace.
    func testKeyTestReportsAcceptanceOrRejectionWithoutSendingScanData() async {
        let repository = FakeRepository()
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start()
        XCTAssertEqual(vm.state.claudeKeyTone, .missing)
        XCTAssertFalse(vm.state.canVerifyClaudeKey)
        XCTAssertNil(vm.send(.verifyClaudeKey))
        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key")); await vm.send(.saveClaudeKey)?.value
        XCTAssertEqual(vm.state.claudeKeyTone, .untested)
        XCTAssertTrue(vm.state.canVerifyClaudeKey)
        let check = vm.send(.verifyClaudeKey)
        XCTAssertEqual(vm.state.claudeKeyTone, .checking)
        XCTAssertTrue(vm.state.isVerifyingClaudeKey)
        XCTAssertFalse(vm.state.canEditClaudeKey, "the key cannot be removed mid-check")
        XCTAssertNil(vm.send(.verifyClaudeKey))
        XCTAssertTrue(vm.state.canScan, "a key check is not a workspace-wide busy state")
        await check?.value
        XCTAssertEqual(vm.state.claudeKeyTone, .verified)
        XCTAssertTrue(vm.state.claudeKeyStatus.contains("Claude Fixture"), vm.state.claudeKeyStatus)
        XCTAssertEqual(repository.verifyCalls, 1)
        XCTAssertEqual(repository.aiCalls, 0)
        repository.verifyError = ClaudeFailure(kind: .authentication, message: "Anthropic rejected the API key.")
        await vm.send(.verifyClaudeKey)?.value
        XCTAssertEqual(vm.state.claudeKeyTone, .failed)
        XCTAssertEqual(vm.state.claudeKeyDetail, "Anthropic rejected the API key.")
        XCTAssertEqual(vm.state.message, "Anthropic rejected the API key.")
        XCTAssertTrue(vm.state.hasClaudeKey, "a failed check does not remove the key")
        XCTAssertTrue(vm.state.canVerifyClaudeKey)
    }

    func testAnalysisOutcomeUpdatesKeyStatusAndSendHintExplainsDisabledButton() async {
        let repository = FakeRepository()
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start()
        XCTAssertEqual(vm.state.aiSendHint, "Add your Anthropic API key in Settings to enable this.")
        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key")); await vm.send(.saveClaudeKey)?.value
        XCTAssertEqual(vm.state.aiSendHint, "Scan first. Claude reviews the grouped scan results.")
        repository.report = ScanReport(candidates: [fixture()])
        await vm.send(.scan)?.value
        XCTAssertNil(vm.state.aiSendHint)
        XCTAssertTrue(vm.state.canAnalyze)
        repository.aiError = ClaudeFailure(kind: .rateLimit, message: "Rate limit")
        await vm.send(.analyzeWithClaude)?.value
        XCTAssertEqual(vm.state.claudeKeyTone, .untested, "a rate limit says nothing about the key")
        repository.aiError = ClaudeFailure(kind: .authentication, message: "Anthropic rejected the API key.")
        await vm.send(.analyzeWithClaude)?.value
        XCTAssertEqual(vm.state.claudeKeyTone, .failed)
        repository.aiError = nil
        await vm.send(.analyzeWithClaude)?.value
        XCTAssertEqual(vm.state.claudeKeyTone, .verified, "a successful paid request proves the key")
        XCTAssertNotNil(vm.state.aiSummary)
    }

    /// Simulator items are removed by simctl, not Trash. Every surface the user reads before
    /// and after a cleanup has to say so, or “Move to Trash” would be a lie.
    func testToolManagedItemsAreExplainedAsPermanentBeforeAndAfterCleanup() async {
        let sim = Candidate(url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes/iOS-26-2"), title: "iOS 26.2 simulator runtime",
            category: .simulators, reason: "Last used 45 days ago.", consequence: "Removed permanently by xcrun simctl.",
            stamp: .init(digest: "simctl", logicalBytes: 8_000, allocatedBytes: 8_000, fileCount: 0),
            allowedRoot: URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes"), canTrash: true,
            ownerBundleID: "com.apple.iphonesimulator", removal: .simulatorRuntime(identifier: "7108F245-A808-4DA6-BB9B-C870AA12AF8B"))
        let file = fixture()
        let (vm, repository) = await ready([sim, file])
        let row = vm.state.candidates.first { $0.id == sim.id }
        XCTAssertEqual(row?.badge, "Tool removal")
        XCTAssertTrue(row?.metadata.contains("not Trash") == true, row?.metadata ?? "")
        XCTAssertEqual(vm.state.categories.first { $0.category == .simulators }?.count, "1 item")
        vm.send(.toggleCandidate(sim.id))
        XCTAssertTrue(vm.state.selectionCaption.contains("Permanent"), vm.state.selectionCaption)
        XCTAssertEqual(vm.state.confirmButtonTitle, "Remove with simctl")
        XCTAssertNotNil(vm.state.confirmationToolNote)
        vm.send(.toggleCandidate(file.id))
        XCTAssertEqual(vm.state.confirmButtonTitle, "Move to Trash and remove")
        XCTAssertTrue(vm.state.selectionCaption.contains("1 removed by simctl"), vm.state.selectionCaption)
        vm.send(.toggleCandidate(sim.id))
        XCTAssertEqual(vm.state.confirmButtonTitle, "Move to Trash")
        XCTAssertNil(vm.state.confirmationToolNote)
        vm.send(.toggleCandidate(sim.id))
        let removed = CleanupRecord(originalPath: sim.id, trashPath: nil, bytes: sim.bytes, error: nil, method: .tool)
        let trashed = CleanupRecord(originalPath: file.id, trashPath: "/synthetic-trash/item", bytes: file.bytes, error: nil)
        repository.cleanupResult = .init(records: [removed, trashed], history: [removed, trashed])
        vm.send(.openConfirmation); vm.send(.acknowledge(true))
        await vm.send(.confirmCleanup)?.value
        XCTAssertEqual(vm.state.cleanupResult?.title, "1 moved to Trash · 1 removed with simctl")
        XCTAssertTrue(vm.state.cleanupResult?.subtitle.contains("freed by simctl") == true, vm.state.cleanupResult?.subtitle ?? "")
        XCTAssertTrue(vm.state.message?.contains("removed with simctl") == true, vm.state.message ?? "")
        XCTAssertEqual(vm.state.history.count, 2)
        XCTAssertTrue(vm.state.history[0].result.contains("Removed by xcrun simctl"), vm.state.history[0].result)
        XCTAssertFalse(vm.state.history[0].canReveal, "nothing in Trash to show")
        XCTAssertTrue(vm.state.history[1].result.contains("Moved to Trash"), vm.state.history[1].result)
    }

    func testOpeningSettingsOrClaudeReviewNoticesKeysChangedOutsideTheApp() async {
        let repository = FakeRepository()
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start()
        XCTAssertFalse(vm.state.hasClaudeKey)
        repository.hasKey = true
        vm.send(.navigate(.overview))
        XCTAssertFalse(vm.state.hasClaudeKey, "other screens do not touch Keychain")
        vm.send(.navigate(.assistant))
        XCTAssertTrue(vm.state.hasClaudeKey)
        XCTAssertEqual(vm.state.claudeKeyTone, .untested)
        repository.hasKey = false
        vm.send(.navigate(.settings))
        XCTAssertFalse(vm.state.hasClaudeKey)
        XCTAssertEqual(vm.state.claudeKeyTone, .missing)
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

    /// The Projects row said "Scan only" because the label was keyed off the category
    /// rather than the data. Build output became cleanable and the summary kept claiming it
    /// was not -- 30 GB on the author's Mac, reported as untouchable on the first screen.
    func testCategorySummaryCountsItemsRatherThanAssumingTheCategory() async {
        // Explicit rather than via `fixture`, whose `cleanable` flag also switches the
        // category -- which is exactly the conflation this test exists to rule out.
        let build = Candidate(url: URL(fileURLWithPath: "/fixture/app/build"), title: "app / build",
            category: .projects, reason: "Build output. Last built 61 days ago.", consequence: "Slower next build",
            stamp: .init(digest: "fixture", logicalBytes: 4096, allocatedBytes: 4096, fileCount: 1),
            allowedRoot: URL(fileURLWithPath: "/fixture"), canTrash: true, ownerBundleID: nil)
        let (vm, _) = await ready([build])
        let projects = vm.state.categories.first { $0.category == .projects }
        XCTAssertNotNil(projects)
        XCTAssertEqual(projects?.count, "1 item")
        XCTAssertNotEqual(projects?.count, "Scan only")
    }

    /// A genuinely scan-only category must still say so, or the fix would just invert the bug.
    func testCategorySummaryStillMarksAnEntirelyScanOnlyCategory() async {
        let locked = fixture("locked", cleanable: false)
        let (vm, _) = await ready([locked])
        let projects = vm.state.categories.first { $0.category == .projects }
        XCTAssertEqual(projects?.count, "Scan only")
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
        XCTAssertEqual(vm.state.categories.count, CleanCategory.allCases.count)
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
        // A refusal opens the result screen: a banner was easy to miss and read as a dead button.
        XCTAssertEqual(vm.state.cleanupResult?.title, "Nothing was moved to Trash")
        XCTAssertEqual(vm.state.cleanupResult?.issues.map(\.detail), ["App still running"])
        XCTAssertEqual(vm.state.cleanupResult?.subtitle, "1 item left in place")
        XCTAssertFalse(vm.state.showConfirmation)
        vm.send(.dismissResult)
        XCTAssertNil(vm.state.cleanupResult)
    }

    private func owned(_ name: String, by owner: String, bytes: Int64 = 4096) -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/fixture/\(name)"), title: name, category: .developer, reason: "Fixture",
            consequence: "Test only", stamp: .init(digest: "fixture", logicalBytes: bytes, allocatedBytes: bytes, fileCount: 1),
            allowedRoot: URL(fileURLWithPath: "/fixture"), canTrash: true, ownerBundleID: owner)
    }
    private func skipped(_ item: Candidate) -> CleanupRecord {
        CleanupRecord(originalPath: item.id, trashPath: nil, bytes: 0, error: "Skipped because it is open.", failure: .appRunning)
    }
    private func cleanAll(_ vm: WorkspaceViewModel) async {
        vm.send(.toggleSelectAll); vm.send(.openConfirmation); vm.send(.acknowledge(true))
        await vm.send(.confirmCleanup)?.value
    }

    func testPermissionFailureExplainsAndOffersFullDiskAccess() async {
        let denied = fixture("denied"), derived = owned("derived", by: "com.apple.dt.Xcode"), pods = owned("pods", by: "com.apple.dt.Xcode")
        let (vm, repository) = await ready([denied, derived, pods])
        repository.appNames = ["com.apple.dt.Xcode": "Xcode"]
        repository.cleanupResult = .init(records: [
            CleanupRecord(originalPath: denied.id, trashPath: nil, bytes: 0, error: "Operation not permitted", failure: .permission),
            skipped(derived), skipped(pods)
        ], history: [])
        await cleanAll(vm)
        let result = vm.state.cleanupResult
        XCTAssertEqual(result?.title, "Nothing was moved to Trash")
        XCTAssertEqual(result?.offersFullDiskAccess, true)
        XCTAssertEqual(result?.issues.map(\.kind), [.permission])
        XCTAssertTrue(result?.issues.first?.detail.contains("Full Disk Access") == true)
        XCTAssertEqual(result?.apps.map(\.name), ["Xcode"], "one row per app, not per item")
        XCTAssertEqual(result?.apps.first?.detail, "2 items · 8 KB")
        XCTAssertEqual(vm.state.candidates.count, 3, "nothing moved, so nothing leaves the list")
    }

    /// The reported request: a button per open app that quits it, then a way to put the
    /// items it kept back into Review — without skipping the review and confirmation.
    func testQuittingAnAppFromTheResultReleasesOnlyItsItems() async {
        let derived = owned("derived", by: "com.apple.dt.Xcode"), spotify = owned("spotify", by: "com.spotify.client")
        let free = fixture("free")
        let (vm, repository) = await ready([derived, spotify, free])
        repository.appNames = ["com.apple.dt.Xcode": "Xcode", "com.spotify.client": "Spotify"]
        let moved = CleanupRecord(originalPath: free.id, trashPath: "/synthetic-trash/free", bytes: free.bytes, error: nil)
        repository.cleanupResult = .init(records: [skipped(derived), skipped(spotify), moved], history: [moved])
        await cleanAll(vm)
        XCTAssertEqual(vm.state.cleanupResult?.title, "1 moved to Trash")
        XCTAssertEqual(vm.state.cleanupResult?.subtitle, "2 items left in place · 4 KB in Trash · Space returns when you empty it")
        XCTAssertEqual(vm.state.cleanupResult?.apps.map(\.status), [.open, .open])
        XCTAssertEqual(vm.state.cleanupResult?.canSelectRemaining, false)
        XCTAssertNotNil(vm.state.cleanupResult?.selectRemainingHint)
        XCTAssertNil(vm.send(.selectRemaining))

        repository.quitOutcomes = ["com.apple.dt.Xcode": .quit]
        let quitting = vm.send(.quitApp("com.apple.dt.Xcode"))
        XCTAssertEqual(vm.state.cleanupResult?.apps.first { $0.name == "Xcode" }?.status, .quitting)
        await quitting?.value
        XCTAssertEqual(repository.quitRequests, ["com.apple.dt.Xcode"])
        XCTAssertEqual(vm.state.cleanupResult?.apps.first { $0.name == "Xcode" }?.status, .closed)
        XCTAssertEqual(vm.state.cleanupResult?.selectRemainingLabel, "Select 1 remaining in Review")
        XCTAssertNil(vm.send(.quitApp("com.apple.dt.Xcode")), "a closed app is not asked again")

        vm.send(.selectRemaining)
        XCTAssertNil(vm.state.cleanupResult)
        XCTAssertEqual(vm.state.destination, .review)
        XCTAssertEqual(vm.state.candidates.filter(\.isSelected).map(\.id), [derived.id], "only the closed app's items")
        XCTAssertFalse(vm.state.showConfirmation, "it still goes through review and confirmation")
        XCTAssertEqual(repository.cleanCalls, 1)
    }

    func testAppThatDoesNotQuitSaysSoAndCanBeAskedAgain() async {
        let derived = owned("derived", by: "com.apple.dt.Xcode")
        let (vm, repository) = await ready([derived])
        repository.cleanupResult = .init(records: [skipped(derived)], history: [])
        await cleanAll(vm)
        XCTAssertEqual(vm.state.cleanupResult?.apps.first?.name, "com.apple.dt.Xcode", "falls back to the bundle ID")
        repository.quitOutcomes = ["com.apple.dt.Xcode": .stillRunning]
        await vm.send(.quitApp("com.apple.dt.Xcode"))?.value
        let app = vm.state.cleanupResult?.apps.first
        XCTAssertEqual(app?.status, .stillOpen)
        XCTAssertTrue(app?.note?.contains("asking you to save") == true)
        XCTAssertEqual(app?.canQuit, true)
        XCTAssertEqual(vm.state.cleanupResult?.canSelectRemaining, false)
        repository.quitOutcomes = ["com.apple.dt.Xcode": .notRunning]
        await vm.send(.quitApp("com.apple.dt.Xcode"))?.value
        XCTAssertEqual(vm.state.cleanupResult?.apps.first?.status, .closed, "already gone counts as closed")
    }

    func testQuitResultArrivingAfterTheSheetClosedChangesNothing() async {
        let derived = owned("derived", by: "com.apple.dt.Xcode")
        let (vm, repository) = await ready([derived])
        repository.cleanupResult = .init(records: [skipped(derived)], history: [])
        await cleanAll(vm)
        repository.quitOutcomes = ["com.apple.dt.Xcode": .quit]
        let quitting = vm.send(.quitApp("com.apple.dt.Xcode"))
        vm.send(.dismissResult)
        await quitting?.value
        XCTAssertNil(vm.state.cleanupResult)
    }

    func testPreviewCannotQuitApps() async {
        let repository = FakeRepository()
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9",
                                    previewReport: .init(candidates: [fixture()]))
        await vm.start()
        vm.send(.quitApp("com.apple.dt.Xcode"))
        XCTAssertTrue(repository.quitRequests.isEmpty)
    }

    /// A long cleanup must end on something unmistakable, not just a spinner that stops.
    func testSuccessfulCleanupEndsOnAResultWithNothingToFix() async {
        let candidate = fixture()
        let (vm, _) = await ready([candidate])
        vm.send(.toggleCandidate(candidate.id)); vm.send(.openConfirmation); vm.send(.acknowledge(true))
        await vm.send(.confirmCleanup)?.value
        let result = vm.state.cleanupResult
        XCTAssertEqual(result?.title, "All 1 moved to Trash")
        XCTAssertEqual(result?.subtitle, "4 KB in Trash · Space returns when you empty it")
        XCTAssertEqual(result?.issues.isEmpty, true)
        XCTAssertEqual(result?.apps.isEmpty, true)
        XCTAssertTrue(vm.state.showCleanupSheet)
        XCTAssertNil(vm.state.cleanupProgress)
        vm.send(.dismissResult)
        XCTAssertFalse(vm.state.showCleanupSheet)
    }

    func testCleanupShowsProgressInTheSameSheetAndCanStopBetweenItems() async {
        let first = fixture("first", bytes: 1000), second = fixture("second", bytes: 3000)
        let (vm, repository) = await ready([first, second])
        repository.delayClean = true
        vm.send(.toggleSelectAll); vm.send(.openConfirmation)
        XCTAssertTrue(vm.state.showCleanupSheet)
        vm.send(.acknowledge(true))
        let cleanup = vm.send(.confirmCleanup)
        XCTAssertFalse(vm.state.showConfirmation)
        XCTAssertTrue(vm.state.showCleanupSheet, "the sheet stays up and turns into the progress view")
        await Task.yield()
        let progress = vm.state.cleanupProgress
        XCTAssertEqual(progress?.countLabel, "0 of 2 items")
        XCTAssertEqual(progress?.bytesLabel, "Zero KB of 4 KB")
        XCTAssertEqual(progress?.current, "first")
        XCTAssertEqual(progress?.canStop, true)
        XCTAssertEqual(vm.state.busyStatus, "Moving to Trash · 0 of 2")

        vm.send(.stopCleanup)
        XCTAssertEqual(vm.state.cleanupProgress?.isStopping, true)
        XCTAssertEqual(vm.state.cleanupProgress?.canStop, false)
        XCTAssertEqual(vm.state.cleanupProgress?.currentDetail, "Stopping after this item…")
        XCTAssertNil(vm.send(.stopCleanup), "a second stop is ignored")
        await cleanup?.value
        XCTAssertNil(vm.state.cleanupProgress)
        XCTAssertEqual(vm.state.cleanupResult?.issues.first?.kind, .stopped)
        XCTAssertTrue(vm.state.cleanupResult?.issues.first?.detail.contains("2 items not attempted") == true)
        XCTAssertTrue(vm.state.showCleanupSheet)
    }

    func testStopIsIgnoredWhenNoCleanupIsRunning() async {
        let (vm, _) = await ready([fixture()])
        XCTAssertNil(vm.send(.stopCleanup))
        XCTAssertNil(vm.state.cleanupProgress)
    }

    /// Key editing is allowed during a cleanup now. Finishing the cleanup must not yank the
    /// user off Settings, which used to discard nothing and leave a half-typed key behind.
    func testCleanupDoesNotNavigateAwayFromAnotherScreen() async {
        let candidate = fixture()
        let (vm, repository) = await ready([candidate])
        repository.delayClean = true
        vm.send(.toggleCandidate(candidate.id)); vm.send(.openConfirmation); vm.send(.acknowledge(true))
        let cleanup = vm.send(.confirmCleanup)
        vm.send(.navigate(.settings)); vm.send(.claudeKeyChanged("sk-ant-half"))
        cleanup?.cancel(); await cleanup?.value
        XCTAssertEqual(vm.state.destination, .settings)
        XCTAssertEqual(vm.state.claudeKeyDraft, "sk-ant-half")
        vm.send(.navigate(.history))
        XCTAssertTrue(vm.state.claudeKeyDraft.isEmpty, "leaving Settings still discards the draft")
    }

    func testConfirmationExplainsWhyMoveToTrashIsDisabled() async {
        let candidate = fixture()
        let (vm, _) = await ready([candidate])
        vm.send(.toggleCandidate(candidate.id)); vm.send(.openConfirmation)
        XCTAssertNotNil(vm.state.confirmationHint)
        vm.send(.acknowledge(true))
        XCTAssertNil(vm.state.confirmationHint)
    }

    func testSelectAllSelectsEveryCleanableItemAndTogglesOff() async {
        let first = fixture("first"), second = fixture("second"), locked = fixture("locked", cleanable: false)
        let (vm, _) = await ready([first, second, locked])
        XCTAssertEqual(vm.state.selectAll, .none)
        XCTAssertEqual(vm.state.selectAllLabel, "Select all (2)")
        vm.send(.toggleSelectAll)
        XCTAssertEqual(vm.state.selectAll, .all)
        XCTAssertEqual(Set(vm.state.candidates.filter(\.isSelected).map(\.id)), [first.id, second.id],
                       "scan-only items are never selected")
        XCTAssertEqual(vm.state.selectedValue, 8192)
        vm.send(.toggleSelectAll)
        XCTAssertEqual(vm.state.selectAll, .none)
        XCTAssertFalse(vm.state.canReviewSelection)
    }

    func testSelectAllActsOnlyOnTheFilteredRows() async {
        let first = fixture("first"), second = fixture("second")
        let (vm, _) = await ready([first, second])
        vm.send(.queryChanged("second"))
        XCTAssertEqual(vm.state.selectAllLabel, "Select all shown (1)")
        vm.send(.toggleSelectAll)
        vm.send(.queryChanged(""))
        XCTAssertEqual(vm.state.selectAll, .some)
        XCTAssertEqual(vm.state.candidates.filter(\.isSelected).map(\.id), [second.id])
        vm.send(.toggleSelectAll)
        XCTAssertEqual(vm.state.selectAll, .all, "a partial selection completes rather than clears")
    }

    func testSelectAllIsUnavailableWhileBusyOrInPreview() async {
        let repository = FakeRepository()
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9",
                                    previewReport: .init(candidates: [fixture()]))
        await vm.start()
        XCTAssertFalse(vm.state.canSelectAll)
        vm.send(.toggleSelectAll)
        XCTAssertEqual(vm.state.selectAll, .none)

        // Busy: a rescan clears the list, but a cleanup keeps it on screen.
        let candidate = fixture()
        let (busy, fake) = await ready([candidate, fixture("other")])
        fake.delayClean = true
        busy.send(.toggleCandidate(candidate.id)); busy.send(.openConfirmation); busy.send(.acknowledge(true))
        let cleanup = busy.send(.confirmCleanup)
        XCTAssertTrue(busy.state.isCleaning)
        XCTAssertFalse(busy.state.canSelectAll)
        XCTAssertNil(busy.send(.toggleSelectAll))
        XCTAssertEqual(busy.state.selectAll, .some, "selection unchanged while busy")
        cleanup?.cancel(); await cleanup?.value
    }

    /// The reported bug: the key field was disabled for the whole length of a scan, with
    /// nothing on the Settings screen saying why.
    func testClaudeKeyCanBeSavedDuringAScanAndStopStillCancelsTheScan() async {
        let repository = FakeRepository()
        repository.delayScan = true
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start()
        let scan = vm.send(.scan)
        XCTAssertTrue(vm.state.isScanning)
        XCTAssertFalse(vm.state.canEditSettings)
        XCTAssertTrue(vm.state.canEditClaudeKey)
        XCTAssertEqual(vm.state.busyStatus?.hasPrefix("Scanning"), true)

        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key"))
        XCTAssertTrue(vm.state.canSaveClaudeKey)
        await vm.send(.saveClaudeKey)?.value
        XCTAssertTrue(vm.state.hasClaudeKey)
        XCTAssertTrue(vm.state.isScanning, "saving a key must not end or replace the scan")

        vm.send(.cancelScan); await scan?.value
        XCTAssertFalse(vm.state.isScanning)
        XCTAssertTrue(vm.state.message?.contains("cancelled") == true, "Stop still reaches the scan")
        XCTAssertNil(vm.state.busyStatus)
    }

    func testKeyFieldLocksOnlyWhileSavingAnalyzingOrInPreview() async {
        let (vm, repository) = await ready([fixture()])
        XCTAssertTrue(vm.state.canEditClaudeKey)
        vm.send(.claudeKeyChanged("sk-ant-synthetic-test-key")); await vm.send(.saveClaudeKey)?.value
        repository.delayAI = true
        let analysis = vm.send(.analyzeWithClaude)
        XCTAssertFalse(vm.state.canEditClaudeKey)
        XCTAssertNil(vm.send(.claudeKeyChanged("sk-ant-other-synthetic-key")))
        vm.send(.cancelClaude); await analysis?.value
        XCTAssertTrue(vm.state.canEditClaudeKey)

        let preview = WorkspaceViewModel(repository: FakeRepository(), homePath: "/fixture", version: "9.9.9",
                                         previewReport: .init(candidates: [fixture()]))
        await preview.start()
        XCTAssertFalse(preview.state.canEditClaudeKey)
    }

    private func build(_ project: String) -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/fixture/\(project)/build"), title: "\(project) / build", category: .projects,
            reason: "Build output", consequence: "Slower next build",
            stamp: .init(digest: "fixture", logicalBytes: 4096, allocatedBytes: 4096, fileCount: 1),
            allowedRoot: URL(fileURLWithPath: "/fixture"), canTrash: true, ownerBundleID: nil)
    }

    func testProtectingAProjectRemovesItsItemsAndKeepsTheOthers() async {
        let app = build("app"), web = build("web")
        let repository = FakeRepository()
        repository.settings.projectRoots = [URL(fileURLWithPath: "/fixture")]
        repository.report = ScanReport(candidates: [app, web],
            projects: [URL(fileURLWithPath: "/fixture/app"), URL(fileURLWithPath: "/fixture/web")])
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start(); await vm.send(.scan)?.value
        XCTAssertEqual(vm.state.projects.map(\.title), ["app", "web"])
        XCTAssertEqual(vm.state.projects.first?.detail, "1 build folder · 4 KB")
        vm.send(.toggleSelectAll)

        vm.send(.setProjectProtection("/fixture/app", true))
        XCTAssertEqual(repository.protected, [URL(fileURLWithPath: "/fixture/app")])
        XCTAssertEqual(vm.state.candidates.map(\.id), [web.id])
        XCTAssertEqual(vm.state.selectedValue, 4096, "the protected project's item is no longer selected")
        XCTAssertEqual(vm.state.projects.first { $0.title == "app" }?.isProtected, true)
        XCTAssertEqual(vm.state.projects.first { $0.title == "web" }?.isProtected, false)

        // A protected project is not scanned, so it must stay listed to be switched back on.
        repository.report = ScanReport(candidates: [web], projects: [URL(fileURLWithPath: "/fixture/web")])
        await vm.send(.scan)?.value
        XCTAssertEqual(vm.state.projects.map(\.title), ["app", "web"])
        vm.send(.setProjectProtection("/fixture/app", false))
        XCTAssertTrue(repository.protected.isEmpty)
        XCTAssertTrue(vm.state.message?.contains("Scan again") == true)
        // The scan skipped it, so without care the row would vanish with its switch.
        let row = vm.state.projects.first { $0.title == "app" }
        XCTAssertEqual(row?.isProtected, false)
        XCTAssertEqual(row?.detail, "Not scanned yet · Scan again to include its build folders")
        vm.send(.setProjectProtection("/fixture/app", true))
        XCTAssertEqual(repository.protected, [URL(fileURLWithPath: "/fixture/app")], "it can be switched back on")
        vm.send(.setProjectProtection("/fixture/app", false))
        repository.report = ScanReport(candidates: [app, web],
            projects: [URL(fileURLWithPath: "/fixture/app"), URL(fileURLWithPath: "/fixture/web")])
        await vm.send(.scan)?.value
        XCTAssertEqual(vm.state.projects.first { $0.title == "app" }?.detail, "1 build folder · 4 KB")
    }

    func testRemovingARootDropsOnlyProjectsNoRemainingRootCovers() async {
        let repository = FakeRepository()
        let solo = URL(fileURLWithPath: "/fixture/solo"), shared = URL(fileURLWithPath: "/fixture/all")
        repository.settings.projectRoots = [solo, shared]
        repository.report = ScanReport(projects: [solo, URL(fileURLWithPath: "/fixture/all/web")])
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start(); await vm.send(.scan)?.value
        XCTAssertEqual(vm.state.projects.map(\.title), ["solo", "web"])
        vm.send(.removeProjectFolder(solo.path))
        XCTAssertEqual(vm.state.projects.map(\.title), ["web"], "a root that is itself a project leaves with its root")
    }

    func testProjectsWithTheSameNameShowTheirParent() async {
        let repository = FakeRepository()
        repository.report = ScanReport(projects: [URL(fileURLWithPath: "/fixture/clientB/app"),
                                                  URL(fileURLWithPath: "/fixture/clientA/app"),
                                                  URL(fileURLWithPath: "/fixture/web")])
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start(); await vm.send(.scan)?.value
        XCTAssertEqual(vm.state.projects.map(\.title), ["clientA / app", "clientB / app", "web"])
    }

    func testProjectsEmptyMessageFollowsTheSituation() async {
        let repository = FakeRepository()
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start()
        XCTAssertEqual(vm.state.projectsEmptyMessage, "Add a project folder above, then scan.")
        repository.settings.projectRoots = [URL(fileURLWithPath: "/fixture")]
        let other = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await other.start()
        XCTAssertEqual(other.state.projectsEmptyMessage, "Scan to list the projects in your folders.")
        await other.send(.scan)?.value
        XCTAssertTrue(other.state.projectsEmptyMessage?.hasPrefix("No projects found") == true)
    }

    func testProtectionFailureChangesNothing() async {
        let app = build("app")
        let repository = FakeRepository()
        repository.settings.projectRoots = [URL(fileURLWithPath: "/fixture")]
        repository.report = ScanReport(candidates: [app], projects: [URL(fileURLWithPath: "/fixture/app")])
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start(); await vm.send(.scan)?.value
        vm.send(.toggleCandidate(app.id))
        repository.settingsError = SafetyError.refused("Storage unavailable")
        vm.send(.setProjectProtection("/fixture/app", true))
        XCTAssertEqual(vm.state.candidates.count, 1)
        XCTAssertTrue(vm.state.candidates[0].isSelected)
        XCTAssertEqual(vm.state.message, "Storage unavailable")

        repository.settingsError = nil
        let writes = repository.settingsWrites
        // Inside the root, so the repository would accept it: only the "listed" guard stops it.
        vm.send(.setProjectProtection("/fixture/unlisted", true))
        XCTAssertEqual(repository.settingsWrites, writes, "only listed projects can be protected")
        XCTAssertTrue(repository.protected.isEmpty)

        // Protected rows stay listed during a scan, so only the busy lock can stop this one.
        vm.send(.setProjectProtection("/fixture/app", true))
        XCTAssertEqual(repository.protected.count, 1)
        let protectedWrites = repository.settingsWrites
        repository.delayScan = true
        let scan = vm.send(.scan)
        XCTAssertTrue(vm.state.projects.contains { $0.id == "/fixture/app" })
        vm.send(.setProjectProtection("/fixture/app", false))
        XCTAssertEqual(repository.settingsWrites, protectedWrites, "protection is locked while a scan runs")
        XCTAssertEqual(repository.protected.count, 1)
        vm.send(.cancelScan); await scan?.value
    }

    func testUnprotectingAProjectNoRootCoversDropsItsRow() async {
        let repository = FakeRepository()
        repository.settings.protectedProjects = [URL(fileURLWithPath: "/elsewhere/app")]
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start()
        vm.send(.setProjectProtection("/elsewhere/app", false))
        XCTAssertTrue(vm.state.projects.isEmpty, "no scan reaches it, so no switch is promised")
        XCTAssertTrue(vm.state.message?.contains("outside your project folders") == true)
    }

    func testRemovingAnOverlappingRootMarksProjectsThatLostItemsForRescan() async {
        let repository = FakeRepository()
        let code = URL(fileURLWithPath: "/fixture/Code"), client = URL(fileURLWithPath: "/fixture/Code/clientA")
        repository.settings.projectRoots = [code, client]
        let build = Candidate(url: URL(fileURLWithPath: "/fixture/Code/clientA/app/build"), title: "app / build", category: .projects,
            reason: "Build output", consequence: "Slower next build",
            stamp: .init(digest: "fixture", logicalBytes: 4096, allocatedBytes: 4096, fileCount: 1),
            allowedRoot: code, canTrash: true, ownerBundleID: nil)
        repository.report = ScanReport(candidates: [build], projects: [URL(fileURLWithPath: "/fixture/Code/clientA/app")])
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start(); await vm.send(.scan)?.value
        vm.send(.removeProjectFolder(code.path))
        XCTAssertTrue(vm.state.candidates.isEmpty)
        XCTAssertEqual(vm.state.projects.first?.detail, "Not scanned yet · Scan again to include its build folders",
                       "not \"No build folders found\", which a rescan would contradict")
    }

    func testNewlyAddedRootIsNotDescribedAsHavingNoProjects() async {
        let repository = FakeRepository()
        repository.settings.projectRoots = [URL(fileURLWithPath: "/fixture/a")]
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start(); await vm.send(.scan)?.value
        XCTAssertTrue(vm.state.projectsEmptyMessage?.hasPrefix("No projects found") == true)
        repository.settings.projectRoots.append(URL(fileURLWithPath: "/fixture/b"))
        await vm.send(.addProjectFolder)?.value
        XCTAssertEqual(vm.state.projectsEmptyMessage, "Scan to list the projects in your folders.")
    }

    func testSameNamedProjectsWithSameParentFallBackToTheirPath() async {
        let repository = FakeRepository()
        repository.report = ScanReport(projects: [URL(fileURLWithPath: "/fixture/2024/acme/web"),
                                                  URL(fileURLWithPath: "/fixture/2025/acme/web")])
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9")
        await vm.start(); await vm.send(.scan)?.value
        XCTAssertEqual(vm.state.projects.map(\.title), ["~/2024/acme/web", "~/2025/acme/web"])
    }

    func testPreviewCannotChangeProjectProtection() async {
        let repository = FakeRepository()
        repository.settings.protectedProjects = [URL(fileURLWithPath: "/fixture/project")]
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9",
                                    previewReport: .init(candidates: [fixture()]))
        await vm.start()
        XCTAssertEqual(vm.state.projects.map(\.id), ["/fixture/project"], "listed, so only the preview guard can stop it")
        vm.send(.setProjectProtection("/fixture/project", false))
        XCTAssertEqual(repository.settingsWrites, 0)
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
        XCTAssertEqual(vm.state.cleanupResult?.title, "1 moved to Trash")
        XCTAssertEqual(vm.state.cleanupResult?.subtitle.hasPrefix("1 item left in place"), true)
        XCTAssertEqual(vm.state.message, "1 item moved to Trash. Space is not reclaimed until Trash is emptied.",
                       "the banner reports what moved; the dialog alone explains what did not")
    }

    func testStoppedCleanupCountsItemsThatWereNeverAttempted() async {
        let items = ["a", "b", "c"].map { fixture($0) }
        let (vm, repository) = await ready(items)
        let moved = CleanupRecord(originalPath: items[0].id, trashPath: "/synthetic-trash/a", bytes: 1, error: nil)
        repository.cleanupResult = .init(records: [moved], history: [moved], stoppedReason: "Cleanup stopped between items.")
        vm.send(.toggleSelectAll); vm.send(.openConfirmation); vm.send(.acknowledge(true))
        await vm.send(.confirmCleanup)?.value
        XCTAssertEqual(vm.state.cleanupResult?.title, "1 moved to Trash")
        XCTAssertEqual(vm.state.cleanupResult?.subtitle.hasPrefix("2 items left in place"), true)
        XCTAssertEqual(vm.state.cleanupResult?.issues.map(\.detail), ["Cleanup stopped between items. 2 items not attempted."])
    }

    func testChangedAndOwnershipFailuresDoNotOfferFullDiskAccess() async {
        let first = fixture("first"), second = fixture("second"), third = fixture("third")
        let (vm, repository) = await ready([first, second, third])
        repository.cleanupResult = .init(records: [
            CleanupRecord(originalPath: first.id, trashPath: nil, bytes: 0, error: "Changed", failure: .changed),
            CleanupRecord(originalPath: second.id, trashPath: nil, bytes: 0, error: "Root-owned", failure: .ownership),
            CleanupRecord(originalPath: third.id, trashPath: nil, bytes: 0, error: "Disk full")
        ], history: [])
        vm.send(.toggleSelectAll); vm.send(.openConfirmation); vm.send(.acknowledge(true))
        await vm.send(.confirmCleanup)?.value
        let result = vm.state.cleanupResult
        XCTAssertEqual(result?.offersFullDiskAccess, false)
        XCTAssertEqual(result?.issues.map(\.title), ["1 item owned by another user", "1 item changed after the scan", "1 item could not move"])
        XCTAssertEqual(result?.issues.first { $0.kind == .changed }?.detail, "It was left in place. Scan again to measure it fresh.")
        XCTAssertEqual(result?.issues.first { $0.kind == .other }?.detail, "Disk full", "a nil failure kind is reported, not dropped")
        XCTAssertNil(vm.state.message, "nothing moved, so there is no success banner")
    }

    func testPreviewCannotReachMutatingOrDesktopRepositoryMethods() async {
        let candidate = fixture()
        let repository = FakeRepository()
        repository.settings = .init(projectRoots: [URL(fileURLWithPath: "/fixture/project")], exclusions: [URL(fileURLWithPath: "/fixture/keep")])
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "9.9.9", previewReport: .init(candidates: [candidate]))
        await vm.start()
        let actions: [WorkspaceAction] = [.scan, .toggleCandidate(candidate.id), .openConfirmation, .acknowledge(true), .confirmCleanup,
            .excludeCandidate(candidate.id), .revealCandidate(candidate.id), .addProjectFolder,
            .removeProjectFolder("/fixture/project"), .removeExclusion("/fixture/keep"),
            .toggleSelectAll, .setProjectProtection("/fixture/project", true)]
        for action in actions { vm.send(action) }
        XCTAssertTrue(vm.state.isPreview)
        XCTAssertFalse(vm.state.canConfirmCleanup)
        XCTAssertEqual(repository.scans + repository.cleanCalls + repository.settingsWrites + repository.reveals, 0)
    }

    // MARK: Safety pack (0.5.3)

    /// macOS applies Full Disk Access only after a relaunch, so the follow-up happens at the
    /// next start: the grant is confirmed or its absence said, once, and the flag is cleared.
    func testFullDiskAccessOutcomeIsReportedOnTheNextLaunch() async {
        let repository = FakeRepository()
        repository.settings.awaitingFullDiskAccess = true
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "t")
        await vm.start()
        XCTAssertTrue(vm.state.message?.contains("Full Disk Access") == true, vm.state.message ?? "nil")
        XCTAssertEqual(repository.accessAcknowledged, 1)
        let quiet = FakeRepository()
        let second = WorkspaceViewModel(repository: quiet, homePath: "/fixture", version: "t")
        await second.start()
        XCTAssertNil(second.state.message)
        XCTAssertEqual(quiet.accessAcknowledged, 0)
    }

    func testItemsInUseGetTheirOwnResultRow() async {
        let first = fixture("first"), second = fixture("second")
        let (vm, repository) = await ready([first, second])
        repository.cleanupResult = .init(records: [
            CleanupRecord(originalPath: first.id, trashPath: nil, bytes: 0, error: "In use by java (pid 4242). Stop it, then clean again.", failure: .inUse),
            CleanupRecord(originalPath: second.id, trashPath: "/synthetic-trash/2", bytes: 100, error: nil)
        ], history: [])
        vm.send(.toggleSelectAll); vm.send(.openConfirmation); vm.send(.acknowledge(true))
        await vm.send(.confirmCleanup)?.value
        let result = vm.state.cleanupResult
        XCTAssertEqual(result?.issues.map(\.kind), [.inUse])
        XCTAssertEqual(result?.issues.first?.title, "1 item in use by a running process")
        XCTAssertTrue(result?.issues.first?.detail.contains("java") == true)
        XCTAssertEqual(result?.offersFullDiskAccess, false)
    }

    func testAnUnwritableItemIsShownAsNotMovableAndCannotBeSelected() async {
        var blocked = fixture("root-owned")
        blocked = Candidate(url: blocked.url, title: blocked.title, category: blocked.category, reason: blocked.reason,
            consequence: blocked.consequence, stamp: blocked.stamp, allowedRoot: blocked.allowedRoot, canTrash: false,
            ownerBundleID: nil, blocker: "Owned by another user.")
        let (vm, _) = await ready([blocked, fixture("fine")])
        let row = vm.state.candidates.first { $0.title == "root-owned" }
        XCTAssertEqual(row?.badge, "Not movable")
        XCTAssertEqual(row?.canSelect, false)
        XCTAssertTrue(row?.reason.hasPrefix("Owned by another user.") == true, row?.reason ?? "nil")
        XCTAssertNotEqual(vm.state.categories.first { $0.category == .developer }?.count, "Scan only",
                          "a category with one unmovable item and one cleanable item is not scan-only")
    }


    // MARK: Docker (0.5.7)

    /// A second tool means none of the surfaces may say "simctl" by assumption: each names
    /// the tool that removes the item, and a mixed selection names both.
    func testToolSurfacesNameTheToolThatRemovesEachItem() async {
        let image = Candidate(url: URL(fileURLWithPath: "/docker/images/python:3.12"), title: "python:3.12 image",
            category: .docker, reason: "No container uses it.", consequence: "Removed permanently by docker.",
            stamp: .init(digest: "docker-image:x:1GB", logicalBytes: 1_000_000_000, allocatedBytes: 1_000_000_000, fileCount: 0),
            allowedRoot: URL(fileURLWithPath: "/docker/images"), canTrash: true, ownerBundleID: DockerRules.owner,
            removal: .dockerImage(id: String(repeating: "c", count: 64)))
        let runtime = Candidate(url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes/iOS-26-2"), title: "iOS 26.2 simulator runtime",
            category: .simulators, reason: "Last used 45 days ago.", consequence: "Removed permanently by xcrun simctl.",
            stamp: .init(digest: "simctl", logicalBytes: 8_000, allocatedBytes: 8_000, fileCount: 0),
            allowedRoot: URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes"), canTrash: true,
            ownerBundleID: SimulatorRules.owner, removal: .simulatorRuntime(identifier: "7108F245-A808-4DA6-BB9B-C870AA12AF8B"))
        let (vm, repository) = await ready([image, runtime])
        vm.send(.toggleCandidate(image.id)); vm.send(.openConfirmation)
        XCTAssertEqual(vm.state.confirmButtonTitle, "Remove with docker")
        XCTAssertTrue(vm.state.selectionCaption.contains("Removed by docker"), vm.state.selectionCaption)
        XCTAssertTrue(vm.state.confirmationToolNote?.contains("docker") == true, vm.state.confirmationToolNote ?? "nil")
        XCTAssertFalse(vm.state.confirmationToolNote?.contains("simctl") == true, vm.state.confirmationToolNote ?? "nil")
        XCTAssertTrue(vm.state.candidates.first { $0.id == image.id }?.metadata.contains("docker") == true)
        vm.send(.dismissConfirmation); vm.send(.toggleCandidate(runtime.id)); vm.send(.openConfirmation)
        XCTAssertEqual(vm.state.confirmButtonTitle, "Remove with simctl and docker")
        XCTAssertTrue(vm.state.selectionCaption.contains("simctl and docker"), vm.state.selectionCaption)
        vm.send(.acknowledge(true))
        let records = [
            CleanupRecord(originalPath: image.id, trashPath: nil, bytes: image.bytes, error: nil, method: .tool, tool: "docker"),
            CleanupRecord(originalPath: runtime.id, trashPath: nil, bytes: runtime.bytes, error: nil, method: .tool, tool: "simctl")
        ]
        repository.cleanupResult = .init(records: records, history: records)
        await vm.send(.confirmCleanup)?.value
        XCTAssertEqual(vm.state.cleanupResult?.title, "All 2 removed with simctl and docker")
        XCTAssertTrue(vm.state.cleanupResult?.subtitle.contains("freed by simctl and docker") == true, vm.state.cleanupResult?.subtitle ?? "")
        XCTAssertTrue(vm.state.message?.contains("removed with simctl and docker") == true, vm.state.message ?? "")
        XCTAssertTrue(vm.state.history.contains { $0.result.contains("Removed by docker") }, "\(vm.state.history.map(\.result))")
        XCTAssertTrue(vm.state.history.contains { $0.result.contains("Removed by xcrun simctl") })
    }


    // MARK: Stale projects (0.5.8)

    private func output(_ project: String, _ name: String, bytes: Int64) -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/fixture/code/\(project)/\(name)"), title: "\(project) / \(name)", category: .projects,
            reason: "Build output.", consequence: "Rebuilds.", stamp: .init(digest: "b", logicalBytes: bytes, allocatedBytes: bytes, fileCount: 3),
            allowedRoot: URL(fileURLWithPath: "/fixture/code"), canTrash: true, ownerBundleID: nil)
    }

    func testStaleProjectsAreBadgedSummarizedAndSelectableInOneStep() async {
        let now = Date()
        func days(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }
        let old = URL(fileURLWithPath: "/fixture/code/old"), new = URL(fileURLWithPath: "/fixture/code/new"), locked = URL(fileURLWithPath: "/fixture/code/locked")
        let items = [output("old", "build", bytes: 3_000_000_000), output("old", "node_modules", bytes: 1_000_000_000),
                     output("new", "build", bytes: 2_000_000_000), output("locked", "build", bytes: 5_000_000_000), fixture("cache")]
        let activity = [
            ProjectActivity(project: old, lastSourceChange: days(90), lastCommit: days(95), lastBuildDays: 90, outputBytes: 4_000_000_000, outputItems: 2),
            ProjectActivity(project: new, lastSourceChange: days(2), lastCommit: days(5), lastBuildDays: 1, outputBytes: 2_000_000_000, outputItems: 1),
            ProjectActivity(project: locked, lastSourceChange: days(100), lastCommit: days(100), lastBuildDays: 100, outputBytes: 5_000_000_000, outputItems: 1)
        ]
        let repository = FakeRepository()
        repository.settings.projectRoots = [URL(fileURLWithPath: "/fixture/code")]
        repository.settings.protectedProjects = [locked]
        repository.report = ScanReport(candidates: items, projects: [old, new, locked], activity: activity)
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "t")
        await vm.start(); await vm.send(.scan)?.value

        XCTAssertEqual(vm.state.projects.map(\.title), ["old", "locked", "new"], "stale and unprotected first by size, then the rest by name")
        let row = vm.state.projects[0]
        XCTAssertEqual(row.badge, "Stale"); XCTAssertTrue(row.isStale)
        XCTAssertTrue(row.activity.contains("Edited 90 days ago") && row.activity.contains("Built 90 days ago"), row.activity)
        XCTAssertEqual(vm.state.projects[2].badge, "Active")
        XCTAssertTrue(vm.state.projects[2].activity.contains("Uncommitted"), "edited after the last commit: \(vm.state.projects[2].activity)")
        XCTAssertEqual(vm.state.staleSummary, "1 stale project holds 4 GB of build output", "the protected project is stale but not counted")
        XCTAssertTrue(vm.state.canSelectStaleBuildOutput)

        vm.send(.selectStaleBuildOutput)
        XCTAssertEqual(Set(vm.state.candidates.filter(\.isSelected).map(\.id)), ["/fixture/code/old/build", "/fixture/code/old/node_modules"])
        XCTAssertEqual(vm.state.destination, .review)
        XCTAssertTrue(vm.state.aiPayload.contains("\"projects\""))
        XCTAssertFalse(vm.state.aiPayload.contains("old") || vm.state.aiPayload.contains("/fixture"), vm.state.aiPayload)
    }

    func testWithoutStaleProjectsTheSummaryAndActionAreAbsent() async {
        let new = URL(fileURLWithPath: "/fixture/code/new")
        let repository = FakeRepository()
        repository.report = ScanReport(candidates: [output("new", "build", bytes: 1_000)], projects: [new],
            activity: [ProjectActivity(project: new, lastSourceChange: Date(), lastCommit: nil, lastBuildDays: 0, outputBytes: 1_000, outputItems: 1)])
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "t")
        await vm.start(); await vm.send(.scan)?.value
        XCTAssertNil(vm.state.staleSummary)
        XCTAssertFalse(vm.state.canSelectStaleBuildOutput)
        XCTAssertNil(vm.send(.selectStaleBuildOutput))
        XCTAssertTrue(vm.state.candidates.allSatisfy { !$0.isSelected })
    }


    // MARK: Duplicate folders (0.5.9)

    func testDuplicateFoldersAreListedAddedAndRemovedLikeProjectFolders() async {
        let repository = FakeRepository()
        repository.settings.duplicateRoots = [URL(fileURLWithPath: "/fixture/Downloads")]
        let vm = WorkspaceViewModel(repository: repository, homePath: "/fixture", version: "t")
        await vm.start()
        XCTAssertEqual(vm.state.duplicateRoots.map(\.title), ["Downloads"])
        await vm.send(.addDuplicateFolder)?.value
        XCTAssertEqual(repository.duplicateAdds, 1)
        vm.send(.removeDuplicateFolder("/fixture/Downloads"))
        XCTAssertEqual(repository.settingsWrites, 1)
        XCTAssertTrue(vm.state.duplicateRoots.isEmpty)
        XCTAssertNil(vm.send(.removeDuplicateFolder("/fixture/nope")), "an unknown folder is ignored")
    }

}

@MainActor private final class FakeRepository: CleaningRepository {
    var hasKey = false, delayAI = false
    var aiCalls = 0, keyReads = 0, keyWrites = 0
    var aiError: Error?, keyError: Error?
    func hasClaudeKey() throws -> Bool { keyReads += 1; return hasKey }
    func saveClaudeKey(_ key: String) async throws {
        if let keyError { throw keyError }
        keyWrites += 1; hasKey = true
    }
    func removeClaudeKey() async throws { keyWrites += 1; hasKey = false }
    var verifyCalls = 0
    var verifyError: Error?
    func verifyClaudeKey(model: ClaudeModel) async throws -> ClaudeKeyCheck {
        verifyCalls += 1
        if let verifyError { throw verifyError }
        return .init(modelID: model.rawValue, modelName: "Claude Fixture")
    }
    func analyzeWithClaude(_ packet: AIReviewPacket, model: ClaudeModel) async throws -> AIAnalysis {
        aiCalls += 1
        if let aiError { throw aiError }
        if delayAI { try await Task.sleep(nanoseconds: 60_000_000_000) }
        return .init(summary: "Review this cache.", recommendations: [
            .init(groupID: packet.groups[0].id, disposition: .review, reason: "Cache", caution: "Stop builds")
        ], inputTokens: 500, outputTokens: 80)
    }
    var loads = 0, scans = 0, cleanCalls = 0, settingsWrites = 0, reveals = 0, resetCalls = 0, settingsOpens = 0
    var cleanedIDs: [String] = []
    var settings = WorkspaceSettings()
    var report = ScanReport()
    var notices: [String] = []
    var historyAvailable = true
    var scanError: Error?, settingsError: Error?, cleanupError: Error?, resetError: Error?
    var cleanupResult: CleanupBatchResult?
    var delayScan = false, delayClean = false
    var appNames: [String: String] = [:]
    var quitOutcomes: [String: AppQuitOutcome] = [:]
    var quitRequests: [String] = []
    func applicationNames(for bundleIDs: [String]) -> [String: String] { appNames.filter { bundleIDs.contains($0.key) } }
    func quitApplication(_ bundleID: String) async -> AppQuitOutcome {
        quitRequests.append(bundleID); return quitOutcomes[bundleID] ?? .stillRunning
    }
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
    var duplicateAdds = 0
    func addDuplicateFolders() async throws -> WorkspaceSettings { duplicateAdds += 1; return settings }
    func removeDuplicateFolder(_ url: URL) throws -> WorkspaceSettings {
        settingsWrites += 1; settings.duplicateRoots.removeAll { $0 == url }; return settings
    }
    func removeProjectFolder(_ url: URL) throws -> WorkspaceSettings {
        settingsWrites += 1; settings.projectRoots.removeAll { $0 == url }; return settings
    }
    func exclude(_ url: URL) throws -> WorkspaceSettings {
        if let settingsError { throw settingsError }
        settingsWrites += 1; settings.exclusions.append(url); return settings
    }
    func removeExclusion(_ url: URL) throws -> WorkspaceSettings { settingsWrites += 1; return settings }
    var protected: [URL] { settings.protectedProjects }
    func setProjectProtection(_ url: URL, protected: Bool) throws -> WorkspaceSettings {
        if let settingsError { throw settingsError }
        // Same containment rule as LocalCleaningRepository, so a test cannot pass by
        // protecting something the real repository would refuse.
        if protected, !settings.projectRoots.contains(where: { FileSafety.isSame(url, $0) || FileSafety.isInside(url, root: $0) }) {
            throw SafetyError.refused("Choose a project inside one of your project folders.")
        }
        settingsWrites += 1
        if protected { settings.protectedProjects.append(url) } else { settings.protectedProjects.removeAll { $0 == url } }
        return settings
    }
    func resetHistory() async throws -> [CleanupRecord] {
        resetCalls += 1
        if let resetError { throw resetError }
        return []
    }
    func clean(_ items: [Candidate], progress: @escaping @MainActor (CleanupProgress) -> Void) async throws -> CleanupBatchResult {
        cleanCalls += 1; cleanedIDs = items.map(\.id)
        if let cleanupError { throw cleanupError }
        let total = items.reduce(Int64(0)) { $0 + $1.bytes }
        progress(CleanupProgress(completed: 0, total: items.count, bytesCompleted: 0, bytesTotal: total,
                                 current: items.first?.title, currentBytes: items.first?.bytes ?? 0))
        if delayClean {
            // Like the real repository: a stop lands between items and is reported, not thrown.
            do { try await Task.sleep(nanoseconds: 60_000_000_000) }
            catch { return .init(records: [], history: [], stoppedReason: "Cleanup stopped between items.") }
        }
        if let cleanupResult { return cleanupResult }
        let records = items.map { CleanupRecord(originalPath: $0.id, trashPath: "/synthetic-trash/item", bytes: $0.bytes, error: nil) }
        return .init(records: records, history: records)
    }
    func reveal(_ url: URL) { reveals += 1 }
    func openFullDiskAccessSettings() { settingsOpens += 1 }
    var accessAcknowledged = 0
    func acknowledgeFullDiskAccessOutcome() { accessAcknowledged += 1 }
}
