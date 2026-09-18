import XCTest
@testable import SafeCleanerCore

final class SafetyTests: XCTestCase {
    var home: URL!
    override func setUpWithError() throws {
        // /tmp and /var are symlink aliases on macOS. Fixtures deliberately use
        // the real path because the production policy rejects symlink ancestors.
        home = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("SafeCleanerTests-\(UUID().uuidString)")
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
    /// POLICY CHANGE: an interior symbolic link no longer refuses the whole candidate.
    ///
    /// The refusal guarded a threat a rename-based move does not have. `trashItem` renames
    /// the subtree and never dereferences a link inside it, so the link's target was never
    /// at risk — the old test asserted the target survived a snapshot that had already
    /// refused, which proved nothing about the move. This asserts the property that
    /// actually matters: the target survives an executed cleanup. The ancestor check in
    /// `validate` is the load-bearing one and is unchanged (see the next test).
    ///
    /// On the author's machine this refusal alone blocked 12,13 GB of build output.
    func testInteriorSymbolicLinkIsCountedAndItsTargetSurvivesCleanup() throws {
        let secret = try file("personal/secret.txt")
        try file("cache/normal")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("cache/link"), withDestinationURL: secret)

        let item = try candidate("cache")
        XCTAssertGreaterThan(item.stamp.logicalBytes, 0)

        let target = home.appendingPathComponent("test-trash")
        let result = CleanupEngine(trash: { source in
            try FileManager.default.moveItem(at: source, to: target)
            return target
        }).perform(item)

        XCTAssertNil(result.error)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secret.path),
                      "the link moved; its target must not")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(
            atPath: target.appendingPathComponent("link").path), secret.path,
                       "the link itself should move intact, not be resolved")
    }
    /// The link is an entry in its own right and must never be walked through, or the
    /// estimate would count a tree that is not going to move.
    func testInteriorSymbolicLinkIsNotFollowedWhenMeasuring() throws {
        try file("payload/big.bin", data: String(repeating: "x", count: 50_000))
        try file("cache/small")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("cache/link"),
                                                   withDestinationURL: home.appendingPathComponent("payload"))
        let stamp = try FileSafety.snapshot(home.appendingPathComponent("cache"), root: home)
        XCTAssertLessThan(stamp.logicalBytes, 50_000, "the link's target must not be counted")
    }
    /// A package inside a candidate is an ordinary directory as far as a rename goes.
    /// Descending into it keeps the estimate equal to what actually moves. On the
    /// author's machine this refusal blocked a further 10,44 GB of build output.
    func testInteriorPackageIsMeasuredRatherThanRefused() throws {
        try file("cache/normal")
        try file("cache/Some.app/Contents/payload.bin", data: String(repeating: "y", count: 20_000))
        let stamp = try FileSafety.snapshot(home.appendingPathComponent("cache"), root: home)
        XCTAssertGreaterThan(stamp.logicalBytes, 20_000, "package contents must be counted, not skipped")
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
    // ~/Library/Caches/org.swift.swiftpm carries a .swiftpm extension, so the candidate
    // ROOT reports isPackage. Refusing it there made the Swift package cache rule dead on
    // every Mac. The root is the unit the rule nominates and the user confirms, and it is
    // also the unit trashItem moves whole, so measuring it is coherent.
    func testCandidateRootMayItselfBeAPackage() throws {
        try file("org.swift.swiftpm/repositories/pkg/data")
        let root = home.appendingPathComponent("org.swift.swiftpm")
        XCTAssertTrue(try root.resourceValues(forKeys: [.isPackageKey]).isPackage == true,
                      "fixture precondition: .swiftpm must register as a package")
        let stamp = try FileSafety.snapshot(root, root: home)
        XCTAssertGreaterThan(stamp.logicalBytes, 0)
        XCTAssertEqual(stamp.fileCount, 1)
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
    /// `projects/important/build` holds a real document and has no manifest beside it, so it
    /// must stay invisible. That the manifest is required is the whole guarantee now that
    /// build output is cleanable rather than scan-only.
    func testProjectDetectionNeedsManifestAndDoesNotDuplicateRoots() throws {
        try file("projects/web/package.json", data: "{}")
        try file("projects/web/.next/data")
        try file("projects/important/build/my-document.txt")
        let report = try DiskScanner().scan(configuration: .init(home: home,
            projectRoots: [home.appendingPathComponent("projects"), home.appendingPathComponent("projects/web")]))
        XCTAssertEqual(report.candidates.count, 1)
        XCTAssertEqual(report.candidates.first?.url.lastPathComponent, ".next")
        // POLICY CHANGE: build output was scan-only ("cleanup will arrive after tool-specific
        // validation"). It is regenerable by definition, so the worst case is a slower next
        // build, and it still goes to Trash. Leaving it scan-only meant the app reclaimed
        // none of the 32 GB that regrew in the author's project folders in one month.
        XCTAssertEqual(report.candidates.first?.canTrash, true)
        XCTAssertTrue(report.candidates[0].reason.contains("Last built"), "staleness should be on the candidate")
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
