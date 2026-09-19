import Foundation
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

/// Converts domain values to immutable display values. Views never aggregate,
/// format file paths/dates, decide eligibility, or read operating-system state.
enum WorkspacePresenter {
    static func make(_ session: WorkspaceSession, preview: Bool, homePath: String, version: String) -> WorkspaceViewState {
        var state = WorkspaceViewState()
        state.version = version
        let busy = session.operation != .idle
        let selected = session.candidates.filter { $0.canTrash && session.selected.contains($0.id) }
        let found = session.candidates.reduce(Int64(0)) { $0 + $1.bytes }
        let selectedBytes = selected.reduce(Int64(0)) { $0 + $1.bytes }
        state.destination = session.destination; state.isPreview = preview; state.isBusy = busy
        state.isScanning = session.operation == .scanning; state.isCleaning = session.operation == .cleaning
        state.progress = session.progress; state.hasScanned = session.lastScan != nil
        state.canScan = !busy && !preview; state.canEditSettings = !busy && !preview
        state.canReviewSelection = !busy && !preview && !selected.isEmpty
        state.message = session.message; state.query = session.query; state.categoryFilter = session.category
        let used = max(0, session.disk.total - session.disk.free)
        state.diskFraction = session.disk.total > 0 ? min(1, Double(used) / Double(session.disk.total)) : 0
        state.diskPercent = session.disk.total > 0 ? "\(Int(state.diskFraction * 100))%" : "—"
        state.freeSpace = session.disk.total > 0 ? byteLabel(session.disk.free) : "—"
        state.usedSpace = session.disk.total > 0 ? "\(byteLabel(used)) used" : "Disk information unavailable"
        state.foundSize = state.hasScanned ? byteLabel(found) : "Let’s find out."
        state.foundValue = Double(found)
        state.candidateCount = String(session.candidates.count)
        if state.hasScanned { state.foundCaption = "\(session.candidates.count) candidates · You choose what goes" }
        state.scanDate = session.lastScan.map { "Scanned \($0.formatted(date: .omitted, time: .shortened))" } ?? "Awaiting first scan"
        state.selectedSize = byteLabel(selectedBytes); state.selectedValue = Double(selectedBytes)
        state.selectionCaption = "\(selected.count) \(selected.count == 1 ? "item" : "items") · Moves to Trash, not permanent deletion"
        state.categories = CleanCategory.allCases.map { category in
            let items = session.candidates.filter { $0.category == category }
            let bytes = items.reduce(Int64(0)) { $0 + $1.bytes }
            return CategorySummary(category: category, title: category.title, detail: category.detail,
                size: state.hasScanned ? byteLabel(bytes) : "—",
                // Derived from the candidates, not assumed from the category. Projects were
                // scan-only once and this label kept saying so after they became cleanable.
                count: !items.isEmpty && items.allSatisfy { !$0.canTrash }
                    ? "Scan only"
                    : "\(items.count) \(items.count == 1 ? "item" : "items")",
                fraction: found > 0 ? Double(bytes) / Double(found) : 0)
        }
        func row(_ item: Candidate) -> CandidateRowState {
            let abbreviated = item.url.path.hasPrefix(homePath + "/") ? "~" + item.url.path.dropFirst(homePath.count) : item.url.path
            return CandidateRowState(id: item.id, title: item.title, path: abbreviated, fullPath: item.url.path, size: byteLabel(item.bytes),
                category: item.category, badge: item.canTrash ? "Review first" : "Scan only", reason: item.reason,
                consequence: item.consequence,
                metadata: "\(item.stamp.fileCount) files · \(byteLabel(item.stamp.logicalBytes)) logical · \(byteLabel(item.bytes)) allocated estimate",
                isSelected: session.selected.contains(item.id), canSelect: item.canTrash && !busy && !preview,
                canReveal: !preview, canExclude: !busy && !preview)
        }
        state.candidates = session.candidates.filter {
            (session.category == nil || $0.category == session.category) &&
            (session.query.isEmpty || $0.title.localizedCaseInsensitiveContains(session.query) || $0.url.path.localizedCaseInsensitiveContains(session.query))
        }.map(row)
        state.issues = session.issues
        func location(_ url: URL) -> LocationRowState { .init(id: url.path, title: url.lastPathComponent, path: url.path) }
        state.projectRoots = session.settings.projectRoots.map(location)
        state.exclusions = session.settings.exclusions.map(location)
        state.history = session.records.map { record in
            HistoryRowState(id: record.id, title: URL(fileURLWithPath: record.originalPath).lastPathComponent,
                path: record.originalPath, date: record.date.formatted(date: .abbreviated, time: .shortened),
                result: record.error ?? "Moved to Trash · \(byteLabel(record.bytes)) · Space not yet reclaimed",
                failed: record.error != nil, canReveal: record.trashPath != nil && !preview)
        }
        state.historyNeedsReset = !session.historyAvailable
        state.blockedAreas = session.access.blocked.map(\.label)
        state.needsFullDiskAccess = session.access.needsSystemSettings
        state.noProjectRootsYet = session.settings.projectRoots.isEmpty
        state.showConfirmation = session.showConfirmation
        state.confirmationItems = selected.map(row)
        state.confirmationAcknowledged = session.acknowledged
        state.canConfirmCleanup = state.canReviewSelection && session.showConfirmation && session.acknowledged
        return state
    }
}
