import XCTest
import SafeCleanerCore
@testable import SafeCleaner

/// libproc is read-only: it lists what this user's processes hold open. The test process
/// opens a synthetic file and must find itself, then not find that file once it is closed.
final class OpenFileServiceTests: XCTestCase {
    func testFindsOwnOpenFileAndForgetsItOnceClosed() async throws {
        let dir = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerOpenFiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("inner"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("inner/held.bin")
        try Data("held".utf8).write(to: file)
        let handle = try FileHandle(forReadingFrom: file)
        let service = LibprocOpenFileService()

        let held = await service.index().uses(inside: dir)
        XCTAssertTrue(held.contains { $0.pid == getpid() && $0.path == file.path }, "\(held)")
        XCTAssertTrue(held.allSatisfy { !$0.name.isEmpty })

        try handle.close()
        let released = await service.index().uses(inside: dir)
        XCTAssertFalse(released.contains { $0.pid == getpid() && $0.path == file.path }, "\(released)")
        let elsewhere = await service.index().uses(inside: dir.appendingPathComponent("absent"))
        XCTAssertTrue(elsewhere.isEmpty)
    }

    /// The index covers more than descriptors: a process whose executable or working
    /// directory sits inside an item would be pulled out from under itself too.
    func testOwnExecutableIsListedAsAUse() async {
        let exe = URL(fileURLWithPath: Bundle.main.executablePath ?? "/nonexistent").resolvingSymlinksInPath()
        let uses = await LibprocOpenFileService().index().uses(inside: exe.deletingLastPathComponent())
        XCTAssertTrue(uses.contains { $0.pid == getpid() }, "\(uses.prefix(5))")
    }
}
