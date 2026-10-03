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

    /// `failure` was added after 0.4. A record written before it has no such key and must still read,
    /// or adding it would have needed the schema bump this optional field avoids.
    func testReadsRecordsWrittenBeforeFailureKindExisted() throws {
        let old = """
        {"schemaVersion": 1, "records": [{"id": "\(UUID().uuidString)", "date": 0, "originalPath": "/a",
          "bytes": 0, "error": "Denied"}]}
        """
        let decoded = try HistoryFile.decode(Data(old.utf8))
        XCTAssertEqual(decoded.first?.error, "Denied")
        XCTAssertNil(decoded.first?.failure)
    }

    func testFailureKindRoundTrips() throws {
        let failed = CleanupRecord(originalPath: "/a", trashPath: nil, bytes: 0, error: "Denied", failure: .permission)
        XCTAssertEqual(try HistoryFile.decode(HistoryFile.encode([failed])).first?.failure, .permission)
    }

    /// A failure kind added by a later build must not make this build's whole history
    /// unreadable, because an unreadable history pauses cleanup.
    func testUnknownFailureKindFromANewerBuildReadsAsOther() throws {
        let newer = """
        {"schemaVersion": 1, "records": [{"id": "\(UUID().uuidString)", "date": 0, "originalPath": "/a",
          "bytes": 0, "error": "Quarantined", "failure": "quarantined"}]}
        """
        XCTAssertEqual(try HistoryFile.decode(Data(newer.utf8)).first?.failure, .other)
    }

    func testCorruptDataThrows() {
        XCTAssertThrowsError(try HistoryFile.decode(Data("not json".utf8)))
    }
}
