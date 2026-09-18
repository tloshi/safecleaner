import XCTest
@testable import ViggoCleanCore

final class SafetyTests: XCTestCase {
    var home: URL!
    override func setUpWithError() throws {
        // /tmp and /var are symlink aliases on macOS. Fixtures deliberately use
        // the real path because the production policy rejects symlink ancestors.
        home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("ViggoCleanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        // Only synthetic files owned by this test. No real cache or Trash access.
        try FileManager.default.removeItem(at: home)
    }
    @discardableResult func file(_ path: String, data: String = "synthetic cache fixture") throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(data.utf8).write(to: url)
        return url
    }
    func candidate(_ path: String, canTrash: Bool = true) throws -> Candidate {
        let url = home.appendingPathComponent(path)
        return Candidate(url: url, title: path, category: .developer, reason: "Test", consequence: "Test",
                         stamp: try FileSafety.snapshot(url, root: home), allowedRoot: home,
                         canTrash: canTrash, ownerBundleID: nil)
    }

    func testContainmentIsComponentAware() {
        let root = URL(fileURLWithPath: "/Users/test/cache")
        XCTAssertTrue(FileSafety.isInside(root.appendingPathComponent("data"), root: root))
        XCTAssertFalse(FileSafety.isInside(root, root: root))
        XCTAssertFalse(FileSafety.isInside(URL(fileURLWithPath: "/Users/test/cache-other/data"), root: root))
        XCTAssertFalse(FileSafety.isInside(root.appendingPathComponent("../secret"), root: root))
    }
    func testRejectsSymbolicLinkInsideTree() throws {
        let secret = try file("personal/secret.txt")
        try file("cache/normal")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("cache/link"), withDestinationURL: secret)
        XCTAssertThrowsError(try FileSafety.snapshot(home.appendingPathComponent("cache"), root: home))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secret.path))
    }
    func testRejectsSymbolicLinkAncestor() throws {
        try file("real/cache/data")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("alias"), withDestinationURL: home.appendingPathComponent("real"))
        XCTAssertThrowsError(try FileSafety.snapshot(home.appendingPathComponent("alias/cache"), root: home))
    }
    func testRejectsHardLinks() throws {
        let original = try file("personal/data")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("cache"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: original, to: home.appendingPathComponent("cache/link"))
        XCTAssertThrowsError(try FileSafety.snapshot(home.appendingPathComponent("cache"), root: home))
    }
    func testChangedFilesNeverReachTrashOperation() throws {
        let url = try file("cache/data")
        let item = try candidate("cache")
        try Data("changed contents and size".utf8).write(to: url)
        var called = false
        let result = CleanupEngine(trash: { _ in called = true; return nil }).perform(item)
        XCTAssertFalse(called)
        XCTAssertNotNil(result.error)
    }
    func testMovedDirectoryReplacedWithLinkIsRefused() throws {
        try file("cache/data")
        let item = try candidate("cache")
        try FileManager.default.moveItem(at: home.appendingPathComponent("cache"), to: home.appendingPathComponent("original"))
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("cache"), withDestinationURL: home.appendingPathComponent("original"))
        var called = false
        let result = CleanupEngine(trash: { _ in called = true; return nil }).perform(item)
        XCTAssertFalse(called)
        XCTAssertNotNil(result.error)
    }
    func testTrashFailureDoesNotFallBackToDeletion() throws {
        let url = try file("cache/data")
        let item = try candidate("cache")
        let result = CleanupEngine(trash: { _ in throw SafetyError.refused("Simulated Trash failure") }).perform(item)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.bytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testSuccessfulMoveRecordsDestinationUsingSyntheticTrash() throws {
        try file("cache/data")
        let item = try candidate("cache")
        let target = home.appendingPathComponent("test-trash")
        let result = CleanupEngine(trash: { source in
            try FileManager.default.moveItem(at: source, to: target)
            return target
        }).perform(item)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.trashPath, target.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("data").path))
    }
    func testScanOnlyCandidateCannotBeCleaned() throws {
        try file("project/build/data")
        var called = false
        let result = CleanupEngine(trash: { _ in called = true; return nil })
            .perform(try candidate("project/build", canTrash: false))
        XCTAssertFalse(called)
        XCTAssertNotNil(result.error)
    }
    func testScannerTargetsCacheNotToolConfiguration() throws {
        try file(".npm/_cacache/data")
        try file(".npm/config")
        try file(".gradle/caches/build-cache-1/data")
        try file(".gradle/gradle.properties")
        let report = try DiskScanner().scan(configuration: .init(home: home))
        XCTAssertEqual(report.candidates.count, 2)
        XCTAssertFalse(report.candidates.contains { $0.url.lastPathComponent == ".npm" || $0.url.lastPathComponent == ".gradle" })
        XCTAssertTrue(report.issues.isEmpty)
    }
    func testExclusionIsRespected() throws {
        try file("Library/Caches/example.app/data")
        let excluded = home.appendingPathComponent("Library/Caches/example.app")
        let report = try DiskScanner().scan(configuration: .init(home: home, exclusions: [excluded]))
        XCTAssertTrue(report.candidates.isEmpty)
    }
    func testExcludedChildPreventsParentCleanup() throws {
        try file("Library/Caches/example.app/keep/data")
        try file("Library/Caches/example.app/disposable/data")
        let excluded = home.appendingPathComponent("Library/Caches/example.app/keep")
        let report = try DiskScanner().scan(configuration: .init(home: home, exclusions: [excluded]))
        XCTAssertTrue(report.candidates.isEmpty)
        XCTAssertTrue(report.issues.contains { $0.message.contains("excluded") })
    }
    func testProjectDetectionNeedsManifestAndDoesNotDuplicateRoots() throws {
        try file("projects/web/package.json", data: "{}")
        try file("projects/web/.next/data")
        try file("projects/important/build/my-document.txt")
        let report = try DiskScanner().scan(configuration: .init(home: home,
            projectRoots: [home.appendingPathComponent("projects"), home.appendingPathComponent("projects/web")]))
        XCTAssertEqual(report.candidates.count, 1)
        XCTAssertEqual(report.candidates.first?.url.lastPathComponent, ".next")
        XCTAssertEqual(report.candidates.first?.canTrash, false)
    }
    func testRecentLogsAreKeptAndOldLogsAreCandidates() throws {
        try file("Library/Logs/recent.log")
        let old = try file("Library/Logs/old.log")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-40 * 86400)], ofItemAtPath: old.path)
        let report = try DiskScanner().scan(configuration: .init(home: home))
        XCTAssertEqual(report.candidates.map(\.title), ["old.log"])
    }
    func testPreCancelledScanStops() async throws {
        try file(".npm/_cacache/data")
        let config = ScanConfiguration(home: home)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try DiskScanner().scan(configuration: config)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
