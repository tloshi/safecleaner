import Foundation
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

@MainActor final class UserDefaultsSettingsStore: SettingsStoring {
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    func load() -> WorkspaceSettings {
        WorkspaceSettings(
            projectRoots: (defaults.stringArray(forKey: "projectRoots") ?? []).map { URL(fileURLWithPath: $0) },
            exclusions: (defaults.stringArray(forKey: "exclusions") ?? []).map { URL(fileURLWithPath: $0) })
    }
    func save(_ settings: WorkspaceSettings) throws {
        defaults.set(settings.projectRoots.map(\.path), forKey: "projectRoots")
        defaults.set(settings.exclusions.map(\.path), forKey: "exclusions")
    }
}

actor JSONHistoryStore: HistoryStoring {
    private let url: URL
    init(url: URL) { self.url = url }
    // File I/O only. The format, its version and the 0.2 fallback live in HistoryFile,
    // in Core, where they are testable without a bundle.
    func load() throws -> [CleanupRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try HistoryFile.decode(Data(contentsOf: url))
    }
    func save(_ records: [CleanupRecord]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HistoryFile.encode(records).write(to: url, options: .atomic)
    }
}
