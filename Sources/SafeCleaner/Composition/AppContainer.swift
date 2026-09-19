import Foundation
#if SWIFT_PACKAGE
import SafeCleanerCore
import SafeCleanerPresentation
#endif

/// Composition root: the only place that assembles concrete dependencies.
@MainActor enum AppContainer {
    /// Single source of truth for the displayed version: Info.plist, written by
    /// scripts/generate-project.py. Views receive it through WorkspaceViewState.
    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static func makeViewModel(preview: Bool) -> WorkspaceViewModel {
        if preview {
            return WorkspaceViewModel(repository: PreviewRepository(), homePath: "/preview", version: bundleVersion, previewReport: PreviewFixtures.report)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let repository = LocalCleaningRepository(
            scanner: LocalScanService(), cleaner: LocalCleanupService(), disk: LocalDiskInfoService(home: home),
            settings: UserDefaultsSettingsStore(defaults: .standard),
            history: JSONHistoryStore(url: home.appendingPathComponent("Library/Application Support/SafeCleaner/history.json")),
            desktop: MacDesktopService(), validator: LocalProjectValidator(home: home), home: home)
        return WorkspaceViewModel(repository: repository, homePath: home.path, version: bundleVersion)
    }
}

private enum PreviewFixtures {
    static var report: ScanReport {
        let samples: [(String, CleanCategory, Int64)] = [
            ("Xcode DerivedData", .developer, 29_300_000_000), ("Gradle build cache", .developer, 21_300_000_000),
            ("npm package cache", .developer, 3_800_000_000), ("Chrome cache", .browsers, 1_350_000_000),
            ("Application caches", .applications, 1_570_000_000), ("Diagnostic logs", .logs, 486_000_000),
            ("website / .next", .projects, 1_190_000_000)
        ]
        return ScanReport(candidates: samples.map { title, category, bytes in
            Candidate(url: URL(fileURLWithPath: "/preview/\(title)"), title: title, category: category,
                reason: "Illustrative preview, not a scan result.", consequence: "Cleaning is disabled in preview mode.",
                stamp: .init(digest: "preview", logicalBytes: bytes, allocatedBytes: bytes, fileCount: 100),
                allowedRoot: URL(fileURLWithPath: "/preview"), canTrash: false, ownerBundleID: nil)
        })
    }
}

/// No live services are created in preview mode, even if an action leaks through.
@MainActor private final class PreviewRepository: CleaningRepository {
    func load() async -> WorkspaceSnapshot {
        .init(settings: .init(), history: [], disk: .init(total: 500_000_000_000, free: 95_000_000_000))
    }
    func diskCapacity() async throws -> DiskCapacity { .init(total: 500_000_000_000, free: 95_000_000_000) }
    func scan(progress: @escaping @Sendable (String) -> Void) async throws -> ScanReport { throw disabled }
    func addProjectFolders() async throws -> WorkspaceSettings { throw disabled }
    func removeProjectFolder(_ url: URL) throws -> WorkspaceSettings { throw disabled }
    func exclude(_ url: URL) throws -> WorkspaceSettings { throw disabled }
    func removeExclusion(_ url: URL) throws -> WorkspaceSettings { throw disabled }
    func clean(_ items: [Candidate]) async throws -> CleanupBatchResult { throw disabled }
    func resetHistory() async throws -> [CleanupRecord] { throw disabled }
    func reveal(_ url: URL) {}
    func openFullDiskAccessSettings() {}
    private var disabled: SafetyError { .refused("Preview mode cannot change files or preferences.") }
}
