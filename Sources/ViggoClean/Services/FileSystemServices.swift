import Foundation
#if SWIFT_PACKAGE
import ViggoCleanCore
#endif

struct LocalScanService: ScanServicing {
    func scan(configuration: ScanConfiguration, progress: @escaping @Sendable (String) -> Void) async throws -> ScanReport {
        let worker = Task.detached(priority: .userInitiated) {
            try DiskScanner().scan(configuration: configuration, progress: progress)
        }
        return try await withTaskCancellationHandler {
            let report = try await worker.value
            try Task.checkCancellation()
            return report
        } onCancel: { worker.cancel() }
    }
}

struct LocalCleanupService: CleanupServicing {
    func moveToTrash(_ item: Candidate) async -> CleanupRecord {
        await Task.detached(priority: .userInitiated) { CleanupEngine().perform(item) }.value
    }
}

struct LocalDiskInfoService: DiskInfoProviding {
    let home: URL
    func capacity() async throws -> DiskCapacity {
        try await Task.detached(priority: .utility) {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: home.path)
            return DiskCapacity(total: (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0,
                                free: (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
        }.value
    }
}

struct LocalProjectValidator: ProjectRootValidating {
    let home: URL
    func validate(_ url: URL) throws { try FileSafety.validate(url, root: home) }
}
