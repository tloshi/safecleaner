import XCTest
@testable import SafeCleanerCore

/// Duplicates are exact: same size, then the same partial hash, then the same full SHA-256.
/// The keeper is chosen deterministically and is never a candidate; every other copy is an
/// ordinary Trash row. Hard links, symlinks, packages, dependencies, build output and the
/// never-offer list are skipped, and the walk is capped with an issue, never silently.
final class DuplicatesTests: XCTestCase {
    var home: URL!
    private let now = Date()
    private let contentA = Data((0..<1_200_000).map { UInt8($0 % 251) })
    private var contentB: Data { var b = contentA; b[600_000] = 7; return b }

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerDuplicates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private var docs: URL { home.appendingPathComponent("Documents") }
    @discardableResult
    private func file(_ path: String, _ data: Data, modified: Date? = nil) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }

    private func fixture() throws {
        try file("Documents/a.bin", contentA, modified: now.addingTimeInterval(-86_400 * 10))
        try file("Documents/b.bin", contentA, modified: now.addingTimeInterval(-86_400 * 2))
        try file("Documents/sub/deep/a-copy.bin", contentA)
        try file("Documents/c.bin", contentB)
        try file("Documents/h1.bin", contentA + Data("hardlinked".utf8))
        try FileManager.default.linkItem(at: docs.appendingPathComponent("h1.bin"), to: docs.appendingPathComponent("h2.bin"))
        try FileManager.default.createSymbolicLink(at: docs.appendingPathComponent("link.bin"), withDestinationURL: docs.appendingPathComponent("a.bin"))
        try file("Documents/node_modules/pkg/a.bin", contentA)
        try file("Documents/app/build/a.bin", contentA)
        try file("Documents/app/package.json", Data("{}".utf8))
        try file("Documents/Photos Library.photoslibrary/originals/a.bin", contentA)
        try file("Documents/.hidden/a.bin", contentA)
        try file("Documents/small.txt", Data("tiny".utf8))
        try file("Documents/small-copy.txt", Data("tiny".utf8))
        try file(".ssh/a.bin", contentA)
    }

    func testIdenticalFilesFormASetWithADeterministicKeeper() throws {
        try fixture()
        let collected = try Duplicates.collect(roots: [docs], home: home, exclusions: [], limits: .init(), fm: .default)
        XCTAssertEqual(Set(collected.entries.map { $0.url.lastPathComponent }), ["a.bin", "b.bin", "a-copy.bin", "c.bin"],
                       "exactly the comparable files: \(collected.issues)")
        let result = try Duplicates.find(roots: [docs], home: home)
        XCTAssertEqual(result.sets.count, 1, "\(result.sets)")
        let set = try XCTUnwrap(result.sets.first)
        XCTAssertEqual(set.keeper.path, docs.appendingPathComponent("a.bin").path, "shallowest, then oldest")
        XCTAssertEqual(set.copies.map(\.path).sorted(), [docs.appendingPathComponent("b.bin").path, docs.appendingPathComponent("sub/deep/a-copy.bin").path])
        XCTAssertEqual(set.bytes, Int64(contentA.count))
        XCTAssertEqual(set.digest.count, 64)
        XCTAssertTrue(result.issues.isEmpty, "\(result.issues)")
    }

    func testSameSizeDifferentContentHardLinksSymlinksPackagesDependenciesAndSmallFilesAreNotDuplicates() throws {
        try fixture()
        let result = try Duplicates.find(roots: [docs], home: home)
        let all = result.sets.flatMap { [$0.keeper] + $0.copies }.map(\.path)
        for excluded in ["c.bin", "h1.bin", "h2.bin", "link.bin", "node_modules", "/build/", ".photoslibrary", ".hidden", "small"] {
            XCTAssertFalse(all.contains { $0.contains(excluded) }, "\(excluded) must not take part: \(all)")
        }
    }

    func testSensitiveAndOutsideHomeRootsAreSkippedWithAnIssue() throws {
        try fixture()
        let result = try Duplicates.find(roots: [home.appendingPathComponent(".ssh"), URL(fileURLWithPath: "/private/tmp")], home: home)
        XCTAssertTrue(result.sets.isEmpty)
        XCTAssertEqual(result.issues.count, 2, "\(result.issues)")
        XCTAssertTrue(result.issues.contains { $0.message.contains("~/.ssh") })
    }

    func testTheWalkIsCappedWithAnIssueNeverSilently() throws {
        try fixture()
        let result = try Duplicates.find(roots: [docs], home: home, limits: .init(maxFiles: 2, maxHashedBytes: 1_000_000_000))
        XCTAssertTrue(result.issues.contains { $0.message.contains("capped") }, "\(result.issues)")
        let budget = try Duplicates.find(roots: [docs], home: home, limits: .init(maxFiles: 10_000, maxHashedBytes: 100))
        XCTAssertTrue(budget.sets.isEmpty)
        XCTAssertTrue(budget.issues.contains { $0.message.contains("budget") }, "\(budget.issues)")
    }

    func testScannerOffersEveryCopyButTheKeeperAsATrashRowAndRespectsExclusions() throws {
        try fixture()
        let report = try DiskScanner().scan(configuration: .init(home: home, duplicateRoots: [docs]))
        let rows = report.candidates.filter { $0.category == .duplicates }
        XCTAssertEqual(rows.map { $0.url.path }.sorted(), [docs.appendingPathComponent("b.bin").path, docs.appendingPathComponent("sub/deep/a-copy.bin").path])
        for row in rows {
            XCTAssertTrue(row.canTrash); XCTAssertNil(row.removal)
            XCTAssertEqual(row.allowedRoot.path, docs.path)
            XCTAssertTrue(row.reason.contains("~/Documents/a.bin") && row.reason.contains("3 copies"), row.reason)
            XCTAssertTrue(row.consequence.contains("stays"), row.consequence)
            XCTAssertEqual(row.stamp.logicalBytes, Int64(contentA.count))
        }
        XCTAssertFalse(report.candidates.contains { $0.url.path == docs.appendingPathComponent("a.bin").path }, "the keeper is never a candidate")
        let excluded = try DiskScanner().scan(configuration: .init(home: home, exclusions: [docs.appendingPathComponent("sub")], duplicateRoots: [docs]))
        XCTAssertEqual(excluded.candidates.filter { $0.category == .duplicates }.map { $0.url.lastPathComponent }, ["b.bin"])
        let none = try DiskScanner().scan(configuration: .init(home: home))
        XCTAssertTrue(none.candidates.filter { $0.category == .duplicates }.isEmpty, "no duplicate roots, no hashing")
    }

    func testProjectRootsAreSearchedForDuplicatesToo() throws {
        try fixture()
        let report = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [docs]))
        XCTAssertEqual(report.candidates.filter { $0.category == .duplicates }.count, 2)
    }
}
