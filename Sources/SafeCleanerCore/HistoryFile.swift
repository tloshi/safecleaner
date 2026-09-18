import Foundation

/// On-disk shape of the activity history.
///
/// Cleanup is gated on the history being readable (`LocalCleaningRepository.clean`), so the
/// persisted format is load-bearing: a record shape that changes without a migration path
/// would pause cleanup for every existing install. The envelope carries a schema version so
/// a future change can migrate rather than fail closed.
///
/// 0.2 wrote a bare `[CleanupRecord]` array with no envelope, so decoding falls back to that.
public enum HistoryFile {
    public static let currentSchemaVersion = 1

    private struct Envelope: Codable {
        let schemaVersion: Int
        let records: [CleanupRecord]
    }

    public static func encode(_ records: [CleanupRecord]) throws -> Data {
        try JSONEncoder().encode(Envelope(schemaVersion: currentSchemaVersion, records: records))
    }

    public static func decode(_ data: Data) throws -> [CleanupRecord] {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            // Refuse rather than read what we may not understand. Reading a newer file
            // partially would let the next save overwrite it with a truncated history.
            guard envelope.schemaVersion <= currentSchemaVersion else {
                throw SafetyError.refused(
                    "The activity history was written by a newer version of SafeCleaner "
                    + "(format \(envelope.schemaVersion), this build understands \(currentSchemaVersion)).")
            }
            return envelope.records
        }
        // 0.2 and earlier: a bare array. Decoding it here migrates on the next save.
        return try decoder.decode([CleanupRecord].self, from: data)
    }
}
