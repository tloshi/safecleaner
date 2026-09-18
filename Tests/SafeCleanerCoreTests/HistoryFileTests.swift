import XCTest
@testable import SafeCleanerCore

/// The activity history fails closed: an unreadable file pauses cleanup entirely
/// (LocalCleaningRepository.clean). That is the right default, but it means the on-disk
/// format is load-bearing — a shape change with no migration path would pause cleanup
/// for every existing user, permanently and with no in-app recovery.
final class HistoryFileTests: XCTestCase {
    private func record(_ path: String) -> CleanupRecord {
        CleanupRecord(originalPath: path, trashPath: "/Trash/\(path)", bytes: 10, error: nil)
    }

    func testRoundTripPreservesRecords() throws {
        let records = [record("a"), record("b")]
        let decoded = try HistoryFile.decode(HistoryFile.encode(records))
        XCTAssertEqual(decoded.map(\.originalPath), ["a", "b"])
        XCTAssertEqual(decoded.map(\.id), records.map(\.id))
    }

    func testWritesTheCurrentSchemaVersion() throws {
        let object = try JSONSerialization.jsonObject(with: HistoryFile.encode([record("a")]))
        let version = (object as? [String: Any])?["schemaVersion"] as? Int
        XCTAssertEqual(version, HistoryFile.currentSchemaVersion)
    }

    /// 0.2 wrote a bare array with no envelope. Reading it has to keep working, or the
    /// upgrade is exactly the silent brick this envelope exists to prevent.
    func testReadsLegacyBareArrayFromZeroTwo() throws {
        let legacy = try JSONEncoder().encode([record("old")])
        let decoded = try HistoryFile.decode(legacy)
        XCTAssertEqual(decoded.map(\.originalPath), ["old"])
    }

    /// A downgrade must not silently truncate history the newer build wrote. Refusing to
    /// read is what keeps the repository from overwriting it with an empty array.
    func testRefusesAFileFromANewerSchema() throws {
        let future = """
        {"schemaVersion": \(HistoryFile.currentSchemaVersion + 1), "records": []}
        """
        XCTAssertThrowsError(try HistoryFile.decode(Data(future.utf8)))
    }

    func testCorruptDataThrows() {
        XCTAssertThrowsError(try HistoryFile.decode(Data("not json".utf8)))
    }
}
