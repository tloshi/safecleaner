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

    /// A permission refusal from macOS must say so and point at the fix, not read "failed".
    func testTrashPermissionErrorIsReportedAsPermission() throws {
        try file("Caches/denied/data.bin")
        let item = try candidate("Caches/denied")
        let engine = CleanupEngine { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                          userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        }
        let record = engine.perform(item)
        XCTAssertEqual(record.failure, .permission)
        XCTAssertNil(record.trashPath)
        XCTAssertTrue(record.error?.contains("Full Disk Access") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path), "a refused move leaves the item in place")
    }

    func testPermissionIsFoundInTheUnderlyingErrorChain() {
        func wrapped(_ code: Int32, outer: Int = NSFileWriteUnknownError) -> NSError {
            NSError(domain: NSCocoaErrorDomain, code: outer,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(code))])
        }
        XCTAssertEqual(CleanupEngine.classify(wrapped(EPERM)), .permission)
        // The innermost POSIX code decides, even under a Cocoa "no permission" wrapper.
        XCTAssertEqual(CleanupEngine.classify(wrapped(EACCES, outer: NSFileWriteNoPermissionError)), .ownership)
        XCTAssertEqual(CleanupEngine.classify(wrapped(ENOENT)), .changed)
        XCTAssertEqual(CleanupEngine.classify(CocoaError(.fileNoSuchFile)), .changed)
        XCTAssertEqual(CleanupEngine.classify(CocoaError(.fileWriteOutOfSpace)), .other)
        // A bare Cocoa denial does not say which kind it is, so Full Disk Access is not implied.
        XCTAssertEqual(CleanupEngine.classify(CocoaError(.fileWriteNoPermission)), .other)
        // trashItem is a CoreServices move and may report Carbon OSStatus codes instead of POSIX.
        func status(_ code: Int) -> NSError {
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: code)])
        }
        XCTAssertEqual(CleanupEngine.classify(status(-5000)), .ownership)
        XCTAssertEqual(CleanupEngine.classify(status(-54)), .ownership)
        XCTAssertEqual(CleanupEngine.classify(status(-43)), .changed)
        XCTAssertEqual(CleanupEngine.classify(SafetyError.changedSinceScan), .changed)
    }

    /// EACCES is Unix ownership or mode. Pointing at Full Disk Access would send the user to
    /// a setting that cannot help.
    func testOwnershipErrorDoesNotPointAtFullDiskAccess() throws {
        try file("Caches/root-owned/data.bin")
        let item = try candidate("Caches/root-owned")
        let record = CleanupEngine { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                          userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])
        }.perform(item)
        XCTAssertEqual(record.failure, .ownership)
        XCTAssertFalse(record.error?.contains("Full Disk Access") == true)
        XCTAssertTrue(record.error?.contains("another user") == true)
    }

    func testCandidateDeletedAfterScanIsReportedAsChanged() throws {
        try file("Caches/gone/data.bin")
        let item = try candidate("Caches/gone")
        try FileManager.default.removeItem(at: item.url)
        var moved = false
        let record = CleanupEngine { _ in moved = true; return nil }.perform(item)
        XCTAssertFalse(moved)
        XCTAssertEqual(record.failure, .changed)
        XCTAssertTrue(record.error?.contains("Scan again") == true)
    }

    /// A file vanishing *inside* the item while it is re-measured must not be reported as
    /// the item itself being gone: the folder is still there in Finder.
    func testVanishedChildIsNotReportedAsAVanishedItem() throws {
        try file("Caches/busy/data.bin")
        let item = try candidate("Caches/busy")
        let inner = CocoaError(.fileReadNoSuchFile)
        let message = CleanupEngine.explain(inner, as: .changed, item: item.url)
        XCTAssertTrue(message.hasPrefix("Something inside it changed"))
        XCTAssertEqual(CleanupEngine.explain(inner, as: .changed, item: home.appendingPathComponent("Caches/absent")),
                       "It no longer exists where the scan found it. Scan again.")
    }

    func testIsSameIgnoresTrailingSlashButNotSiblings() {
        XCTAssertTrue(FileSafety.isSame(URL(fileURLWithPath: "/a/app/"), URL(fileURLWithPath: "/a/app")))
        XCTAssertTrue(FileSafety.isSame(URL(fileURLWithPath: "/a/x/../app"), URL(fileURLWithPath: "/a/app")))
        XCTAssertFalse(FileSafety.isSame(URL(fileURLWithPath: "/a/app2"), URL(fileURLWithPath: "/a/app")))
    }

    /// A protected project is passed to the scanner as an exclusion: none of its build
    /// output may be nominated and it must not be reported as a project, while a sibling is.
    func testProtectedProjectIsNotScannedOrListed() throws {
        try file("projects/app/build.gradle"); try file("projects/app/build/output.bin")
        try file("projects/web/build.gradle"); try file("projects/web/build/output.bin")
        let root = home.appendingPathComponent("projects")
        // Created after the folder exists, so it carries a trailing slash the scanner's URLs may not.
        let protected = URL(fileURLWithPath: root.appendingPathComponent("app").path + "/")
        let report = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [root], exclusions: [protected]))
        XCTAssertEqual(report.candidates.map { $0.url.deletingLastPathComponent().lastPathComponent }, ["web"])
        XCTAssertEqual(report.projects.map(\.lastPathComponent), ["web"])
    }

    func testChangedItemIsReportedAsChangedAndNotMoved() throws {
        try file("Caches/busy/data.bin")
        let item = try candidate("Caches/busy")
        try file("Caches/busy/new.bin")
        var moved = false
        let record = CleanupEngine { _ in moved = true; return nil }.perform(item)
        XCTAssertFalse(moved)
        XCTAssertEqual(record.failure, .changed)
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

    // MARK: Safety pack (0.5.3)

    /// A Trash operation that reports a destination while the source is still in place has
    /// freed nothing, so it must count as a failure rather than as bytes moved.
    func testAMoveThatLeavesTheSourceInPlaceIsNotCountedAsSuccess() throws {
        try file("cache/data")
        let item = try candidate("cache")
        let result = CleanupEngine(trash: { _ in self.home.appendingPathComponent("test-trash") }).perform(item)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.bytes, 0)
        XCTAssertNil(result.trashPath)
        XCTAssertEqual(result.failure, .other)
        XCTAssertTrue(result.error?.contains("still") == true, result.error ?? "")
    }

    func testSensitiveLocationsAreNamedRelativeToHomeAndMatchedByComponent() {
        let home = URL(fileURLWithPath: "/Users/someone")
        XCTAssertEqual(FileSafety.sensitiveLabel(for: home.appendingPathComponent(".ssh/node_modules"), home: home), "~/.ssh")
        XCTAssertEqual(FileSafety.sensitiveLabel(for: home.appendingPathComponent("Library/Keychains"), home: home), "~/Library/Keychains")
        XCTAssertEqual(FileSafety.sensitiveLabel(for: home.appendingPathComponent("Library/Application Support/MobileSync/Backup/x"), home: home),
                       "~/Library/Application Support/MobileSync")
        XCTAssertNil(FileSafety.sensitiveLabel(for: home.appendingPathComponent("Library/Caches/com.example"), home: home))
        XCTAssertNil(FileSafety.sensitiveLabel(for: home.appendingPathComponent("Documents/app/build"), home: home),
                     "project output under Documents stays cleanable")
        XCTAssertNil(FileSafety.sensitiveLabel(for: home.appendingPathComponent(".sshkeys"), home: home), "component-aware, not a prefix match")
    }

    /// The denylist is a floor under every rule, including a project root a user points at a
    /// credential folder by mistake. Checked before the snapshot, so it holds even when the
    /// path is unreadable or absent.
    func testEngineRefusesSensitiveLocationsBeforeTouchingThem() {
        let realHome = FileManager.default.homeDirectoryForCurrentUser
        let item = Candidate(url: realHome.appendingPathComponent(".ssh/node_modules"), title: "node_modules", category: .projects,
            reason: "Test", consequence: "Test", stamp: .init(digest: "x", logicalBytes: 1, allocatedBytes: 1, fileCount: 1),
            allowedRoot: realHome, canTrash: true, ownerBundleID: nil)
        var called = false
        let result = CleanupEngine(trash: { _ in called = true; return nil }).perform(item)
        XCTAssertFalse(called)
        XCTAssertTrue(result.error?.contains("~/.ssh") == true, result.error ?? "")
        XCTAssertEqual(result.failure, .other)
    }

    func testScannerNeverOffersAnythingInsideASensitiveLocation() throws {
        try file(".ssh/package.json", data: "{}")
        try file(".ssh/node_modules/left-pad/index.js")
        let report = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [home.appendingPathComponent(".ssh")]))
        XCTAssertFalse(report.candidates.contains { $0.url.path.contains(".ssh") })
        XCTAssertTrue(report.issues.contains { $0.message.contains("~/.ssh") }, "\(report.issues.map(\.message))")
    }

    /// An item the current user cannot write is listed, measured and explained, but never
    /// selectable, instead of failing at cleanup time with an ownership error.
    func testUnwritableItemIsListedButNotMovable() throws {
        try file("Library/Caches/com.example.locked/data")
        let locked = home.appendingPathComponent("Library/Caches/com.example.locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        try file("Library/Caches/com.example.fine/data")
        let report = try DiskScanner().scan(configuration: .init(home: home))
        let item = try XCTUnwrap(report.candidates.first { $0.url.lastPathComponent == "com.example.locked" })
        XCTAssertFalse(item.canTrash)
        XCTAssertTrue(item.blocker?.contains("administrator") == true, item.blocker ?? "nil")
        XCTAssertGreaterThan(item.bytes, 0)
        let fine = try XCTUnwrap(report.candidates.first { $0.url.lastPathComponent == "com.example.fine" })
        XCTAssertTrue(fine.canTrash); XCTAssertNil(fine.blocker)
    }

    // MARK: Hard-linked build output (0.5.10)

    /// pnpm-style installs hard-link files into a store. Moving such a folder to Trash removes
    /// names, not data, so it is safe, and the estimate must say that those bytes stay.
    private func hardLinkedProject() throws -> URL {
        try file("projects/app/package.json", data: "{}")
        let a = try file("projects/app/node_modules/pkg/a.js", data: String(repeating: "a", count: 8_192))
        try FileManager.default.linkItem(at: a, to: home.appendingPathComponent("projects/app/node_modules/pkg/b.js"))
        try file("projects/app/node_modules/plain.js", data: String(repeating: "p", count: 4_096))
        return home.appendingPathComponent("projects/app/node_modules")
    }

    func testHardLinkedBuildOutputIsListedWithUniqueBytesAndSaysSo() throws {
        let modules = try hardLinkedProject()
        let report = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [home.appendingPathComponent("projects")]))
        let item = try XCTUnwrap(report.candidates.first { FileSafety.isSame($0.url, modules) }, "\(report.issues.map(\.message))")
        XCTAssertTrue(item.allowsHardLinks)
        XCTAssertEqual(item.stamp.linkedBytes, 8_192)
        XCTAssertEqual(item.stamp.linkedFiles, 1, "one file under two names")
        XCTAssertEqual(item.stamp.logicalBytes, 12_288)
        XCTAssertGreaterThanOrEqual(item.bytes, 4_096)
        XCTAssertLessThan(item.bytes, 8_192, "the linked file frees nothing, so it is not in the allocated estimate")
        XCTAssertTrue(item.reason.contains("hard link"), item.reason)
        XCTAssertFalse(report.issues.contains { $0.path == modules.path })
    }

    func testHardLinksStayRefusedOutsideBuildOutput() throws {
        let a = try file("Library/Caches/com.example.store/a.bin", data: String(repeating: "a", count: 8_192))
        try FileManager.default.linkItem(at: a, to: home.appendingPathComponent("Library/Caches/com.example.store/b.bin"))
        let report = try DiskScanner().scan(configuration: .init(home: home))
        XCTAssertFalse(report.candidates.contains { $0.url.lastPathComponent == "com.example.store" })
        XCTAssertTrue(report.issues.contains { $0.message.contains("Hard-linked") }, "\(report.issues.map(\.message))")
        XCTAssertThrowsError(try FileSafety.snapshot(a.deletingLastPathComponent(), root: home), "the default policy is unchanged")
    }

    func testEngineUsesTheCandidatesPolicyAndRefusesAChangedLinkCount() throws {
        let modules = try hardLinkedProject()
        let report = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [home.appendingPathComponent("projects")]))
        let item = try XCTUnwrap(report.candidates.first { FileSafety.isSame($0.url, modules) })
        try FileManager.default.linkItem(at: modules.appendingPathComponent("pkg/a.js"), to: modules.appendingPathComponent("pkg/c.js"))
        var called = false
        let changed = CleanupEngine(trash: { _ in called = true; return nil }).perform(item)
        XCTAssertFalse(called)
        XCTAssertEqual(changed.failure, .changed, "a third link appeared since the scan")
        try FileManager.default.removeItem(at: modules.appendingPathComponent("pkg/c.js"))
        // Adding and removing a name changed the folder's date too, so a fresh scan is needed,
        // exactly as the app tells the user; the fresh candidate then moves with its policy.
        let rescan = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [home.appendingPathComponent("projects")]))
        let fresh = try XCTUnwrap(rescan.candidates.first { FileSafety.isSame($0.url, modules) })
        XCTAssertEqual(fresh.stamp.linkedFiles, 1)
        let target = home.appendingPathComponent("test-trash")
        let moved = CleanupEngine(trash: { source in try FileManager.default.moveItem(at: source, to: target); return target }).perform(fresh)
        XCTAssertNil(moved.error, moved.error ?? "")
        XCTAssertEqual(moved.bytes, fresh.bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modules.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("pkg/b.js").path))
    }

    func testTreeStampDecodesWithoutTheLinkFields() throws {
        let old = Data("{\"digest\":\"x\",\"logicalBytes\":10,\"allocatedBytes\":12,\"fileCount\":1}".utf8)
        let stamp = try JSONDecoder().decode(TreeStamp.self, from: old)
        XCTAssertEqual(stamp.linkedBytes, 0); XCTAssertEqual(stamp.linkedFiles, 0)
        XCTAssertEqual(stamp.allocatedBytes, 12)
    }
}
