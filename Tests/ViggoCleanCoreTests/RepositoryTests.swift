import XCTest
@testable import ViggoCleanCore

@MainActor final class RepositoryTests: XCTestCase {
    private func fixture(_ name: String = "cache", owner: String? = nil) -> Candidate {
        Candidate(url: URL(fileURLWithPath: "/fixture/\(name)"), title: name, category: .developer,
            reason: "Fixture", consequence: "Test", stamp: .init(digest: "fixture", logicalBytes: 100, allocatedBytes: 100, fileCount: 1),
            allowedRoot: URL(fileURLWithPath: "/fixture"), canTrash: true, ownerBundleID: owner)
    }
    private func make(settings: FakeSettings? = nil, history: FakeHistory = FakeHistory(),
                      desktop: FakeDesktop? = nil, cleaner: FakeCleaner = FakeCleaner()) -> LocalCleaningRepository {
        .init(scanner: FakeScanner(), cleaner: cleaner, disk: FakeDisk(), settings: settings ?? FakeSettings(),
            history: history, desktop: desktop ?? FakeDesktop(), validator: FakeValidator(), home: URL(fileURLWithPath: "/fixture"))
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

    func testRunningOwnerBlocksBatch() async {
        let desktop = FakeDesktop(), cleaner = FakeCleaner()
        desktop.running = ["test.app"]
        let repository = make(desktop: desktop, cleaner: cleaner)
        _ = await repository.load()
        do { _ = try await repository.clean([fixture(owner: "test.app")]); XCTFail("Should refuse") } catch {}
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 0)
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

    func testDuplicateCandidatesCannotMoveTwice() async {
        let cleaner = FakeCleaner()
        let repository = make(cleaner: cleaner)
        _ = await repository.load()
        let item = fixture()
        do { _ = try await repository.clean([item, item]); XCTFail("Should refuse") } catch {}
        let moves = await cleaner.calls
        XCTAssertEqual(moves, 0)
    }
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
    var fail = false
    func load() -> WorkspaceSettings { settings }
    func save(_ settings: WorkspaceSettings) throws {
        if fail { throw SafetyError.refused("Injected settings error") }
        self.settings = settings
    }
}
@MainActor private final class FakeDesktop: DesktopInteracting {
    var running: Set<String> = []
    func chooseProjectFolders() async -> [URL] { [] }
    func runningApplicationIDs() -> Set<String> { running }
    func reveal(_ url: URL) {}
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
private actor FakeCleaner: CleanupServicing {
    var calls = 0
    func moveToTrash(_ item: Candidate) async -> CleanupRecord {
        calls += 1
        return .init(originalPath: item.id, trashPath: "/synthetic-trash/\(calls)", bytes: item.bytes, error: nil)
    }
}
