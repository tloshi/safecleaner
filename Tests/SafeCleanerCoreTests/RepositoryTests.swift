import XCTest
@testable import SafeCleanerCore

@MainActor final class RepositoryTests: XCTestCase {
    private func fixture(_ name: String = "cache", owner: String? = nil) -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/fixture/\(name)"), title: name, category: .developer,
            reason: "Fixture", consequence: "Test", stamp: .init(digest: "fixture", logicalBytes: 100, allocatedBytes: 100, fileCount: 1),
            allowedRoot: URL(fileURLWithPath: "/fixture"), canTrash: true, ownerBundleID: owner)
    }
    private func make(settings: FakeSettings? = nil, history: FakeHistory = FakeHistory(),
                      desktop: FakeDesktop? = nil, cleaner: FakeCleaner = FakeCleaner(),
                      tools: (any ToolRemoving)? = nil, openFiles: (any OpenFileChecking)? = nil) -> LocalCleaningRepository {
        .init(scanner: FakeScanner(), cleaner: cleaner, disk: FakeDisk(), settings: settings ?? FakeSettings(),
            history: history, desktop: desktop ?? FakeDesktop(), validator: FakeValidator(), home: URL(fileURLWithPath: "/fixture"),
            tools: tools, openFiles: openFiles)
    }
    private func simulator() -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes/iOS-26-2"), title: "iOS 26.2 simulator runtime",
            category: .simulators, reason: "Fixture", consequence: "Permanent",
            stamp: .init(digest: "simctl-runtime:fixture", logicalBytes: 8_000, allocatedBytes: 8_000, fileCount: 0),
            allowedRoot: URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes"), canTrash: true,
            ownerBundleID: SimulatorRules.owner, removal: .simulatorRuntime(identifier: "7108F245-A808-4DA6-BB9B-C870AA12AF8B"))
    }

    /// Tool-managed items never reach the Trash path, and without a tool service they are
    /// left in place with a reason rather than silently skipped.
    func testToolManagedItemsGoToTheirToolNeverToTrash() async throws {
        let cleaner = FakeCleaner(), tools = FakeTools()
        let repository = make(cleaner: cleaner, tools: tools)
        _ = await repository.load()
        let result = try await repository.clean([simulator(), fixture()])
        let removed = await tools.items, moves = await cleaner.calls
        XCTAssertEqual(removed.map(\.id), [simulator().id])
        XCTAssertEqual(moves, 1)
        XCTAssertEqual(result.records.map(\.method), [.tool, nil])
        XCTAssertNil(result.records[0].error)

        let bare = make(cleaner: FakeCleaner())
        _ = await bare.load()
        let left = try await bare.clean([simulator()])
        XCTAssertTrue(left.records[0].error?.contains("unavailable") == true)
        XCTAssertEqual(left.records[0].failure, .other)
        XCTAssertEqual(left.records[0].method, .tool)
    }

    func testOpenSimulatorAppKeepsToolManagedItemsInPlaceAndTheEngineRefusesThem() async throws {
        let desktop = FakeDesktop(); desktop.running = [SimulatorRules.owner]
        let tools = FakeTools()
        let repository = make(desktop: desktop, tools: tools)
        _ = await repository.load()
        let result = try await repository.clean([simulator()])
        XCTAssertEqual(result.records[0].failure, .appRunning)
        let removed = await tools.items
        XCTAssertTrue(removed.isEmpty)
        let engine = CleanupEngine(trash: { _ in XCTFail("a tool-managed item must never be trashed"); return nil })
        XCTAssertNotNil(engine.perform(simulator()).error)
    }


    func testClaudeCredentialsAreValidatedStoredSeparatelyAndNeverSentOnSave() async throws {
        let keys = FakeAPIKeys(), advisor = FakeAdvisor(), settings = FakeSettings()
        let repository = LocalCleaningRepository(scanner: FakeScanner(), cleaner: FakeCleaner(), disk: FakeDisk(),
            settings: settings, history: FakeHistory(), desktop: FakeDesktop(), validator: FakeValidator(),
            home: URL(fileURLWithPath: "/fixture"), advisor: advisor, apiKeys: keys)
        for invalid in ["", "not-an-api-key", "sk-ant-header\r\ninjection-too-long"] {
            do { try await repository.saveClaudeKey(invalid); XCTFail("Invalid key accepted") } catch {}
        }
        XCTAssertNil(keys.key)
        try await repository.saveClaudeKey(" sk-ant-synthetic-test-key ")
        XCTAssertEqual(keys.key, "sk-ant-synthetic-test-key")
        XCTAssertTrue(try repository.hasClaudeKey())
        var calls = await advisor.calls
        XCTAssertEqual(calls, 0)
        let packet = AIReviewPacket(candidates: [fixture()], skippedLocations: 0)
        _ = try await repository.analyzeWithClaude(packet, model: .haiku)
        calls = await advisor.calls; XCTAssertEqual(calls, 1)
        try await repository.removeClaudeKey()
        XCTAssertNil(keys.key)
        do { _ = try await repository.analyzeWithClaude(packet, model: .haiku); XCTFail("Missing key accepted") } catch {}
        calls = await advisor.calls; XCTAssertEqual(calls, 1)
        let cleared = await advisor.cleared
        XCTAssertEqual(cleared, 2)
    }

    func testKeyCheckReadsTheSavedKeyAndAdminKeysAreRefusedBeforeStorage() async throws {
        let keys = FakeAPIKeys(), advisor = FakeAdvisor()
        let repository = LocalCleaningRepository(scanner: FakeScanner(), cleaner: FakeCleaner(), disk: FakeDisk(),
            settings: FakeSettings(), history: FakeHistory(), desktop: FakeDesktop(), validator: FakeValidator(),
            home: URL(fileURLWithPath: "/fixture"), advisor: advisor, apiKeys: keys)
        do { _ = try await repository.verifyClaudeKey(model: .haiku); XCTFail("Missing key accepted") } catch {}
        do { try await repository.saveClaudeKey("sk-ant-admin01-synthetic-test-key"); XCTFail("Admin key accepted") } catch {}
        XCTAssertNil(keys.key)
        try await repository.saveClaudeKey("sk-ant-synthetic-test-key")
        let check = try await repository.verifyClaudeKey(model: .sonnet)
        XCTAssertEqual(check.modelID, "claude-sonnet-5-5")
        let verifications = await advisor.verifications, calls = await advisor.calls
        XCTAssertEqual(verifications, 1)
        XCTAssertEqual(calls, 0, "a key check never sends scan data")
    }

    func testUnavailableHistoryBlocksCleanupWithoutOverwritingIt() async {
        let history = FakeHistory(), cleaner = FakeCleaner()
        await history.setLoadFailure()
        let repository = make(history: history, cleaner: cleaner)
        let snapshot = await repository.load()
        XCTAssertFalse(snapshot.notices.isEmpty)
        do { _ = try await repository.clean([fixture()]); XCTFail("Should refuse") } catch {}
        let moves = await cleaner.calls, saves = await history.saves
        XCTAssertEqual(moves, 0); XCTAssertEqual(saves, 0)
    }

    /// An unreadable history pauses cleanup (testUnavailableHistoryBlocksCleanupWithoutOverwritingIt).
    /// Without a way back that pause is permanent and the only fix is deleting a file by hand.
    func testResetHistoryRestoresCleanupAfterAnUnreadableFile() async throws {
        let history = FakeHistory(), cleaner = FakeCleaner()
        await history.setLoadFailure()
        let repository = make(history: history, cleaner: cleaner)
        _ = await repository.load()
        do { _ = try await repository.clean([fixture()]); XCTFail("Should refuse") } catch {}

        let recovered = try await repository.resetHistory()
        XCTAssertTrue(recovered.isEmpty)
        _ = try await repository.clean([fixture()])
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 1, "cleanup should work again after the reset")
    }

    /// Reset writes an empty history. If that write fails the file is untouched, so the
    /// repository must stay paused rather than report a recovery that did not happen.
    func testFailedResetLeavesCleanupPaused() async {
        let history = FakeHistory(), cleaner = FakeCleaner()
        await history.setLoadFailure()
        await history.failSave(number: 1)
        let repository = make(history: history, cleaner: cleaner)
        _ = await repository.load()

        do { _ = try await repository.resetHistory(); XCTFail("Should propagate") } catch {}
        do { _ = try await repository.clean([fixture()]); XCTFail("Should still refuse") } catch {}
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 0)
    }

    func testPreflightSaveFailurePreventsAnyMove() async {
        let history = FakeHistory(), cleaner = FakeCleaner()
        await history.failSave(number: 1)
        let repository = make(history: history, cleaner: cleaner)
        _ = await repository.load()
        do { _ = try await repository.clean([fixture()]); XCTFail("Should refuse") } catch {}
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 0)
    }

    func testJournalFailureAfterMoveStopsBatchAndKeepsResultInMemory() async throws {
        let history = FakeHistory(), cleaner = FakeCleaner()
        await history.failSave(number: 2)
        let repository = make(history: history, cleaner: cleaner)
        _ = await repository.load()
        let result = try await repository.clean([fixture("first"), fixture("second")])
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.history.count, 1)
        XCTAssertNotNil(result.stoppedReason)
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 1)
        do { _ = try await repository.clean([fixture("second")]); XCTFail("History is not writable") } catch {}
    }

    /// POLICY CHANGE: an open app used to refuse the *whole* batch. On a developer's
    /// Mac Xcode, Android Studio or a browser is nearly always open, so "select all" could
    /// never move anything, and no activity was ever written. The open app's own items are
    /// still never touched; they are now skipped and reported instead of blocking the rest.
    func testRunningOwnerSkipsOnlyItsOwnItems() async throws {
        let desktop = FakeDesktop(), cleaner = FakeCleaner()
        desktop.running = ["test.app"]; desktop.names = ["test.app": "Test App"]
        let repository = make(desktop: desktop, cleaner: cleaner)
        _ = await repository.load()
        let result = try await repository.clean([fixture("owned", owner: "test.app"), fixture("free")])
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 1, "only the item whose app is closed may move")
        XCTAssertEqual(result.records.map(\.originalPath), ["/fixture/owned", "/fixture/free"])
        XCTAssertEqual(result.records[0].failure, .appRunning)
        XCTAssertNil(result.records[0].trashPath)
        XCTAssertTrue(result.records[0].error?.contains("Test App is open") == true)
        XCTAssertNil(result.records[1].error)
    }

    func testRunningOwnerOfEveryItemMovesNothing() async throws {
        let desktop = FakeDesktop(), cleaner = FakeCleaner()
        desktop.running = ["test.app"]
        let repository = make(desktop: desktop, cleaner: cleaner)
        _ = await repository.load()
        let result = try await repository.clean([fixture(owner: "test.app")])
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 0)
        XCTAssertEqual(result.records.first?.failure, .appRunning)
        XCTAssertTrue(result.records.first?.error?.contains("test.app") == true, "falls back to the bundle ID")
    }

    func testProtectedProjectMustBeInsideAProjectRootAndBlocksCleanup() async throws {
        let settings = FakeSettings(), cleaner = FakeCleaner()
        settings.settings = .init(projectRoots: [URL(fileURLWithPath: "/fixture/projects")])
        let repository = make(settings: settings, cleaner: cleaner)
        _ = await repository.load()
        XCTAssertThrowsError(try repository.setProjectProtection(URL(fileURLWithPath: "/elsewhere/app"), protected: true))
        let app = URL(fileURLWithPath: "/fixture/projects/app")
        _ = try repository.setProjectProtection(app, protected: true)
        XCTAssertEqual(settings.settings.protectedProjects, [app])
        do { _ = try await repository.clean([fixture("projects/app/build")]); XCTFail("Protected project must refuse") } catch {}
        var moves = await cleaner.calls
        XCTAssertEqual(moves, 0)
        _ = try repository.setProjectProtection(app, protected: false)
        XCTAssertTrue(settings.settings.protectedProjects.isEmpty)
        _ = try await repository.clean([fixture("projects/app/build")])
        moves = await cleaner.calls
        XCTAssertEqual(moves, 1)
    }

    func testNewDescendantExclusionBlocksPreviouslyScannedParent() async throws {
        let cleaner = FakeCleaner()
        let repository = make(cleaner: cleaner)
        _ = await repository.load()
        _ = try repository.exclude(URL(fileURLWithPath: "/fixture/cache/keep"))
        do { _ = try await repository.clean([fixture()]); XCTFail("Should refuse") } catch {}
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 0)
    }

    func testFailedSettingsSaveDoesNotChangeRepositoryConfiguration() async throws {
        let settings = FakeSettings()
        let repository = make(settings: settings)
        _ = await repository.load()
        settings.fail = true
        XCTAssertThrowsError(try repository.exclude(URL(fileURLWithPath: "/fixture/cache")))
        settings.fail = false
        let result = try await repository.clean([fixture()])
        XCTAssertEqual(result.records.count, 1)
    }

    /// `URL(fileURLWithPath:)` adds a trailing slash only while the folder exists. A project
    /// protected while it existed and then renamed must still be found to unprotect.
    func testProtectionIsRemovedRegardlessOfTrailingSlash() async throws {
        let settings = FakeSettings()
        settings.settings = .init(projectRoots: [URL(fileURLWithPath: "/fixture/projects")])
        let repository = make(settings: settings)
        _ = await repository.load()
        _ = try repository.setProjectProtection(URL(fileURLWithPath: "/fixture/projects/app/"), protected: true)
        _ = try repository.setProjectProtection(URL(fileURLWithPath: "/fixture/projects/app/"), protected: true)
        XCTAssertEqual(settings.settings.protectedProjects.count, 1, "protecting twice must not duplicate")
        _ = try repository.setProjectProtection(URL(fileURLWithPath: "/fixture/projects/app"), protected: false)
        XCTAssertTrue(settings.settings.protectedProjects.isEmpty)
    }

    func testProgressIsReportedBeforeEachItemAndAtTheEnd() async throws {
        let repository = make()
        _ = await repository.load()
        var reports: [CleanupProgress] = []
        _ = try await repository.clean([fixture("first"), fixture("second")]) { reports.append($0) }
        XCTAssertEqual(reports.map(\.completed), [0, 1, 2])
        XCTAssertEqual(reports.map(\.current), ["first", "second", nil])
        XCTAssertEqual(reports.map(\.bytesCompleted), [0, 100, 200])
        XCTAssertEqual(Set(reports.map(\.bytesTotal)), [200])
    }

    func testQuitIsDelegatedAndNamesAreResolved() async {
        let desktop = FakeDesktop()
        desktop.names = ["test.app": "Test App"]; desktop.quitOutcome = .quit
        let repository = make(desktop: desktop)
        _ = await repository.load()
        XCTAssertEqual(repository.applicationNames(for: ["test.app", "unknown.app"]), ["test.app": "Test App"])
        let outcome = await repository.quitApplication("test.app")
        XCTAssertEqual(outcome, .quit)
        XCTAssertEqual(desktop.quitRequests, ["test.app"])
    }

    func testDuplicateCandidatesCannotMoveTwice() async {
        let cleaner = FakeCleaner()
        let repository = make(cleaner: cleaner)
        _ = await repository.load()
        let item = fixture()
        do { _ = try await repository.clean([item, item]); XCTFail("Should refuse") } catch {}
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 0)
    }

    // MARK: Open-file check (0.5.3)

    /// A process holding something inside an item open would have files pulled out from
    /// under it. The item is left in place with the process named; the rest proceed.
    func testItemsWithOpenFilesAreLeftInPlaceAndNameTheProcess() async throws {
        let cleaner = FakeCleaner()
        let busy = fixture("gradle"), idle = fixture("npm")
        let openFiles = FakeOpenFiles(uses: [ProcessUse(pid: 4242, name: "java", path: busy.url.appendingPathComponent("daemon.lock").path)])
        let repository = make(cleaner: cleaner, openFiles: openFiles)
        _ = await repository.load()
        let result = try await repository.clean([busy, idle])
        XCTAssertEqual(result.records.map(\.failure), [.inUse, nil])
        XCTAssertTrue(result.records[0].error?.contains("java") == true, result.records[0].error ?? "")
        XCTAssertTrue(result.records[0].error?.contains("4242") == true, result.records[0].error ?? "")
        XCTAssertEqual(result.records[0].bytes, 0)
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 1)
        let builds = await openFiles.builds
        XCTAssertEqual(builds, 1, "one index per batch, not one per item")
    }

    func testOpenFileIndexMatchesByContainmentAndReportsEachProcessOnce() {
        let index = OpenFileIndex(uses: [
            ProcessUse(pid: 1, name: "java", path: "/fixture/gradle/a"), ProcessUse(pid: 1, name: "java", path: "/fixture/gradle/b"),
            ProcessUse(pid: 2, name: "node", path: "/fixture/gradle-other/x"), ProcessUse(pid: 3, name: "zsh", path: "/fixture/gradle")])
        let hits = index.uses(inside: URL(fileURLWithPath: "/fixture/gradle"))
        XCTAssertEqual(hits.map(\.pid), [1, 3], "a sibling sharing a prefix is not a match; the folder itself is")
    }

    func testFullDiskAccessRequestIsRememberedUntilAcknowledged() async throws {
        let settings = FakeSettings()
        let repository = make(settings: settings)
        _ = await repository.load()
        repository.openFullDiskAccessSettings()
        XCTAssertTrue(settings.saved.last?.awaitingFullDiskAccess == true)
        repository.acknowledgeFullDiskAccessOutcome()
        XCTAssertFalse(settings.saved.last?.awaitingFullDiskAccess ?? true)
        let writes = settings.saved.count
        repository.acknowledgeFullDiskAccessOutcome()
        XCTAssertEqual(settings.saved.count, writes, "nothing to acknowledge, nothing written")
    }

}

@MainActor private final class FakeAPIKeys: APIKeyStoring {
    var key: String?
    func hasKey() throws -> Bool { key != nil }
    func read() throws -> String? { key }
    func save(_ key: String) throws { self.key = key }
    func remove() throws { key = nil }
}

private actor FakeAdvisor: ClaudeAdvising {
    var calls = 0, cleared = 0, verifications = 0
    func analyze(_ packet: AIReviewPacket, model: ClaudeModel, apiKey: String) async throws -> AIAnalysis {
        calls += 1
        return .init(summary: "Fixture", recommendations: [], inputTokens: 1, outputTokens: 1)
    }
    func verify(apiKey: String, model: ClaudeModel) async throws -> ClaudeKeyCheck {
        verifications += 1
        return .init(modelID: model.rawValue, modelName: "Fixture \(model.rawValue)")
    }
    func clearCache() { cleared += 1 }
}

private struct FakeScanner: ScanServicing {
    func scan(configuration: ScanConfiguration, progress: @escaping @Sendable (String) -> Void) async throws -> ScanReport { ScanReport() }
}
private struct FakeDisk: DiskInfoProviding {
    func capacity() async throws -> DiskCapacity { .init(total: 1000, free: 200) }
}
private struct FakeValidator: ProjectRootValidating { func validate(_ url: URL) throws {} }
@MainActor private final class FakeSettings: SettingsStoring {
    var settings = WorkspaceSettings()
    var saved: [WorkspaceSettings] = []
    var fail = false
    func load() -> WorkspaceSettings { settings }
    func save(_ settings: WorkspaceSettings) throws {
        if fail { throw SafetyError.refused("Injected settings error") }
        self.settings = settings; saved.append(settings)
    }
}
@MainActor private final class FakeDesktop: DesktopInteracting {
    var running: Set<String> = []
    var names: [String: String] = [:]
    func chooseProjectFolders() async -> [URL] { [] }
    func runningApplicationIDs() -> Set<String> { running }
    func applicationName(for bundleID: String) -> String? { names[bundleID] }
    var quitOutcome: AppQuitOutcome = .stillRunning
    var quitRequests: [String] = []
    func quitApplication(_ bundleID: String) async -> AppQuitOutcome { quitRequests.append(bundleID); return quitOutcome }
    func reveal(_ url: URL) {}
    func openFullDiskAccessSettings() {}
}
private actor FakeHistory: HistoryStoring {
    var saves = 0
    var failLoad = false
    var failingSave: Int?
    func setLoadFailure() { failLoad = true }
    func failSave(number: Int) { failingSave = number }
    func load() throws -> [CleanupRecord] {
        if failLoad { throw SafetyError.refused("Injected corrupt history") }; return []
    }
    func save(_ records: [CleanupRecord]) throws {
        saves += 1
        if saves == failingSave { throw SafetyError.refused("Injected disk error") }
    }
}
private actor FakeTools: ToolRemoving {
    var items: [Candidate] = []
    func remove(_ item: Candidate) async -> CleanupRecord {
        items.append(item)
        return .init(originalPath: item.id, trashPath: nil, bytes: item.bytes, error: nil, method: .tool)
    }
}

private actor FakeCleaner: CleanupServicing {
    var calls = 0
    func moveToTrash(_ item: Candidate) async -> CleanupRecord {
        calls += 1
        return .init(originalPath: item.id, trashPath: "/synthetic-trash/\(calls)", bytes: item.bytes, error: nil)
    }
}

private actor FakeOpenFiles: OpenFileChecking {
    let uses: [ProcessUse]
    var builds = 0
    init(uses: [ProcessUse]) { self.uses = uses }
    func index() async -> OpenFileIndex { builds += 1; return OpenFileIndex(uses: uses) }
}
