import XCTest
@testable import SafeCleanerCore

/// A scan that cannot read a folder reports fewer bytes with no error, which presents as
/// "your Mac is clean" — the worst thing a cleaner can say. These cover the distinction
/// that makes the warning trustworthy: refused is not the same as absent.
final class DiskAccessTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerAccess-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try FileManager.default.removeItem(at: root)
    }

    func testReadableDirectoryIsNotDenied() throws {
        XCTAssertFalse(DiskAccess.isDenied(root))
    }

    /// The trap that hid ~30 GB in the earlier ground truth: a denial read as an empty
    /// folder because the error was discarded.
    func testUnreadableDirectoryIsDenied() throws {
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertTrue(DiskAccess.isDenied(locked))
    }

    func testMissingDirectoryIsNotDeniedItIsSimplyAbsent() {
        XCTAssertFalse(DiskAccess.isDenied(root.appendingPathComponent("nope")),
                       "absent must not be reported as a permission problem")
    }

    /// A permission warning is only honest if granting it would change the result. The app
    /// never reads Trash -- it is on the scanner's permanently protected list -- so asking
    /// for access to it produced a warning no grant could clear, and it returned after every
    /// launch. Probe only what the scanner actually reads.
    func testProbesOnlyCoverWhatTheScannerReads() {
        let labels = DiskAccess.probes(home: root).map(\.0.lastPathComponent)
        XCTAssertEqual(labels, ["Caches", "Logs"])
        for forbidden in [".Trash", "Desktop", "Documents", "Downloads"] {
            XCTAssertFalse(labels.contains(forbidden), "\(forbidden) is never read by the scanner")
        }
    }

    func testProjectRootsAreProbedBecauseTheScannerDoesReadThem() {
        let added = URL(fileURLWithPath: "/tmp/MyProjects")
        let probes = DiskAccess.probes(home: root, projectRoots: [added])
        XCTAssertTrue(probes.contains { $0.0 == added })
    }

    func testAllClearReportNeedsNothing() {
        let clear = DiskAccessReport(blocked: [])
        XCTAssertTrue(clear.hasFullDiskAccess)
        XCTAssertFalse(clear.needsSystemSettings)
    }

    func testAPromptableBlockAloneDoesNotDemandSystemSettings() {
        let report = DiskAccessReport(blocked: [
            .init(path: "/x/Downloads", label: "Downloads", isPromptable: true)
        ])
        XCTAssertFalse(report.needsSystemSettings, "macOS will prompt for this one itself")
        XCTAssertTrue(report.hasFullDiskAccess)
    }

    func testANonPromptableBlockDemandsSystemSettings() {
        let report = DiskAccessReport(blocked: [
            .init(path: "/x/.Trash", label: "Trash", isPromptable: false)
        ])
        XCTAssertTrue(report.needsSystemSettings)
        XCTAssertFalse(report.hasFullDiskAccess)
    }
}
