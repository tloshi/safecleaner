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
        let busy = session.operation != .idle || session.savingKey
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
        let toolItems = selected.filter { $0.removal != nil }
        let count = "\(selected.count) \(selected.count == 1 ? "item" : "items")"
        state.selectionCaption = toolItems.isEmpty ? "\(count) · Moves to Trash, not permanent deletion"
            : toolItems.count == selected.count ? "\(count) · Removed by xcrun simctl · Permanent, not Trash"
            : "\(count) · \(toolItems.count) removed by simctl (permanent), the rest move to Trash"
        state.categories = CleanCategory.allCases.map { category in
            let items = session.candidates.filter { $0.category == category }
            let bytes = items.reduce(Int64(0)) { $0 + $1.bytes }
            return CategorySummary(category: category, title: category.title, detail: category.detail,
                size: state.hasScanned ? byteLabel(bytes) : "—",
                // Derived from the candidates, not assumed from the category. Projects were
                // scan-only once and this label kept saying so after they became cleanable.
                count: !items.isEmpty && items.allSatisfy { !$0.canTrash && $0.blocker == nil }
                    ? "Scan only"
                    : "\(items.count) \(items.count == 1 ? "item" : "items")",
                fraction: found > 0 ? Double(bytes) / Double(found) : 0)
        }
        func row(_ item: Candidate) -> CandidateRowState {
            let abbreviated = item.url.path.hasPrefix(homePath + "/") ? "~" + item.url.path.dropFirst(homePath.count) : item.url.path
            return CandidateRowState(id: item.id, title: item.title, path: abbreviated, fullPath: item.url.path, size: byteLabel(item.bytes),
                category: item.category, badge: item.removal != nil ? "Tool removal" : item.blocker != nil ? "Not movable" : item.canTrash ? "Review first" : "Scan only",
                reason: item.blocker.map { "\($0) \(item.reason)" } ?? item.reason, consequence: item.consequence,
                metadata: item.removal != nil
                    ? "Tool-managed · \(byteLabel(item.bytes)) reported by xcrun simctl · Removed by simctl, not Trash"
                    : "\(item.stamp.fileCount) files · \(byteLabel(item.stamp.logicalBytes)) logical · \(byteLabel(item.bytes)) allocated estimate",
                isSelected: session.selected.contains(item.id), canSelect: item.canTrash && !busy && !preview,
                canReveal: !preview, canExclude: !busy && !preview)
        }
        let shown = visible(session)
        state.candidates = shown.map(row)
        // "Select all" acts on what is on screen, so a search or category narrows it. It
        // never reaches scan-only items, the same rule a single checkbox follows.
        let selectable = shown.filter(\.canTrash)
        let chosen = selectable.filter { session.selected.contains($0.id) }.count
        state.canSelectAll = !busy && !preview && !selectable.isEmpty
        state.selectAll = chosen == 0 ? .none : chosen == selectable.count ? .all : .some
        state.selectAllAccessibilityValue = "\(chosen) of \(selectable.count) selected"
        state.selectAllLabel = session.category == nil && session.query.isEmpty && session.aiGroupFilter == nil
            ? "Select all (\(selectable.count))" : "Select all shown (\(selectable.count))"
        state.cleanupResult = session.outcome.map {
            CleanupResultPresenter.make($0, candidates: session.candidates, busy: busy, preview: preview)
        }
        state.cleanupProgress = session.operation == .cleaning ? progress(session) : nil
        state.projects = projectRows(session, homePath: homePath)
        state.projectsEmptyMessage = !state.projects.isEmpty ? nil
            : session.settings.projectRoots.isEmpty ? "Add a project folder above, then scan."
            : session.operation == .scanning ? "Scanning your project folders…"
            : state.hasScanned && session.settings.projectRoots.allSatisfy({ root in session.scannedRoots.contains { FileSafety.isSame($0, root) } })
                ? "No projects found. A project is a folder with .git or a build manifest such as package.json or build.gradle."
            : "Scan to list the projects in your folders."
        state.busyStatus = busyStatus(session)
        state.issues = session.issues
        func location(_ url: URL) -> LocationRowState { .init(id: url.path, title: url.lastPathComponent, path: url.path) }
        state.projectRoots = session.settings.projectRoots.map(location)
        state.exclusions = session.settings.exclusions.map(location)
        state.history = session.records.map { record in
            HistoryRowState(id: record.id, title: URL(fileURLWithPath: record.originalPath).lastPathComponent,
                path: record.originalPath, date: record.date.formatted(date: .abbreviated, time: .shortened),
                result: record.error ?? (record.isToolRemoval
                    ? "Removed by xcrun simctl · \(byteLabel(record.bytes)) · Space freed, nothing in Trash"
                    : "Moved to Trash · \(byteLabel(record.bytes)) · Space not yet reclaimed"),
                failed: record.error != nil, canReveal: record.trashPath != nil && !preview)
        }
        state.historyNeedsReset = !session.historyAvailable
        state.blockedAreas = session.access.blocked.map(\.label)
        state.needsFullDiskAccess = session.access.needsSystemSettings
        state.noProjectRootsYet = session.settings.projectRoots.isEmpty
        state.showConfirmation = session.showConfirmation
        state.confirmationItems = selected.map(row)
        (state.confirmationTitle, state.confirmationDetail, state.confirmButtonTitle, state.confirmationToolNote)
            = confirmation(selected: selected, toolItems: toolItems, size: state.selectedSize)
        state.confirmationAcknowledged = session.acknowledged
        state.canConfirmCleanup = state.canReviewSelection && session.showConfirmation && session.acknowledged
        state.showCleanupSheet = state.showConfirmation || state.isCleaning || state.cleanupResult != nil
        // A disabled button with no explanation reads as a broken one.
        state.confirmationHint = state.canReviewSelection && !session.acknowledged
            ? "Tick the box above to enable Move to Trash." : nil
        state.claudeKeyDraft = session.claudeKeyDraft; state.hasClaudeKey = session.hasClaudeKey
        state.claudeModel = session.claudeModel; state.isAnalyzing = session.operation == .analyzing
        let checkingKey = session.keyCheck == .checking
        state.canAnalyze = !busy && !preview && !checkingKey && session.hasClaudeKey && session.aiPacket != nil
        state.canEditClaudeKey = !preview && !session.savingKey && !checkingKey
            && session.operation != .loading && session.operation != .analyzing
        state.canSaveClaudeKey = state.canEditClaudeKey && !session.claudeKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        state.isVerifyingClaudeKey = checkingKey
        state.canVerifyClaudeKey = state.canEditClaudeKey && session.hasClaudeKey
        (state.claudeKeyStatus, state.claudeKeyDetail, state.claudeKeyTone) = keyStatus(session)
        state.aiSendHint = state.canAnalyze ? nil : sendHint(session, busy: busy, preview: preview)
        state.aiGroupFilterTitle = session.aiGroupFilter?.kind
        if let packet = session.aiPacket {
            state.aiPayload = packet.json
            state.aiScope = "\(packet.groups.count) groups · \(packet.omittedGroups) groups omitted · \(packet.skippedLocations) scan issues · At most \(ClaudeMessages.maxOutputTokens) output tokens"
        }
        if let analysis = session.aiAnalysis, let packet = session.aiPacket {
            state.aiSummary = analysis.summary
            state.aiUsage = analysis.cached
                ? "Reused in memory · No new API request or tokens"
                : "\(analysis.inputTokens) input + \(analysis.outputTokens) output tokens · \(session.claudeModel.title)"
            state.aiAdvice = analysis.recommendations.compactMap { recommendation in
                guard let group = packet.groups.first(where: { $0.id == recommendation.groupID }) else { return nil }
                return AIAdviceRowState(id: group.id, title: group.kind,
                    detail: "\(group.items) items · About \(byteLabel(group.allocatedMB * 1_000_000))\(group.scanOnly ? " · Scan only" : "")",
                    disposition: recommendation.disposition.title, reason: recommendation.reason, caution: recommendation.caution)
            }
        }
        return state
    }

    /// The candidates the Review list shows. Shared with the ViewModel so "Select all"
    /// selects exactly the rows the user is looking at.
    static func visible(_ session: WorkspaceSession) -> [Candidate] {
        session.candidates.filter {
            (session.aiGroupFilter == nil || session.aiGroupFilter!.candidateIDs.contains($0.id)) &&
            (session.category == nil || $0.category == session.category) &&
            (session.query.isEmpty || $0.title.localizedCaseInsensitiveContains(session.query) || $0.url.path.localizedCaseInsensitiveContains(session.query))
        }
    }

    private static func keyStatus(_ session: WorkspaceSession) -> (String, String?, ClaudeKeyTone) {
        guard session.hasClaudeKey else {
            return ("No API key saved", "Create a key in the Anthropic Console and save it to Keychain in Settings.", .missing)
        }
        func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
        switch session.keyCheck {
        case .untested:
            return ("Saved in Keychain · Not tested yet",
                    "Test key asks Anthropic whether it accepts the key. The check is free and sends no scan data.", .untested)
        case .checking:
            return ("Testing the key with Anthropic…", nil, .checking)
        case .verified(let model, let at):
            return ("Key accepted · \(model) · \(time(at))",
                    "Checked without using tokens. Credits are only confirmed by a real request.", .verified)
        case .failed(let reason, let at):
            return ("Key check failed · \(time(at))", reason, .failed)
        }
    }

    private static func sendHint(_ session: WorkspaceSession, busy: Bool, preview: Bool) -> String? {
        if preview { return "Preview mode never contacts Anthropic." }
        if !session.hasClaudeKey { return "Add your Anthropic API key in Settings to enable this." }
        if session.keyCheck == .checking { return "Wait for the key test to finish." }
        if session.operation == .analyzing || busy { return nil }
        if session.aiPacket == nil {
            return session.lastScan == nil ? "Scan first. Claude reviews the grouped scan results." : "The last scan found nothing to review."
        }
        return nil
    }

    private static func confirmation(selected: [Candidate], toolItems: [Candidate], size: String) -> (String, String, String, String?) {
        let toolBytes = byteLabel(toolItems.reduce(Int64(0)) { $0 + $1.bytes })
        let toolCount = "\(toolItems.count) \(toolItems.count == 1 ? "item" : "items")"
        if toolItems.isEmpty {
            return ("Move \(size) to Trash?",
                    "These exact items will move to Trash. You can restore them in Finder until the Trash is emptied.",
                    "Move to Trash", nil)
        }
        let note = "\(toolCount) (\(toolBytes)) are simulator runtimes or devices. xcrun simctl removes them permanently: they never reach Trash and cannot be restored. Xcode can download a runtime or create a device again."
        if toolItems.count == selected.count {
            return ("Remove \(size) with simctl?",
                    "These exact simulator items will be removed by Xcode's simctl. Each is re-checked first and left in place if it was used since the scan.",
                    "Remove with simctl", note)
        }
        return ("Move \(size) to Trash and remove simulators?",
                "Files move to Trash, where you can restore them in Finder. Simulator items are removed by Xcode's simctl.",
                "Move to Trash and remove", note)
    }

    private static func busyStatus(_ session: WorkspaceSession) -> String? {
        if session.savingKey { return "Saving your API key…" }
        switch session.operation {
        case .idle: return nil
        case .loading: return "Preparing your workspace…"
        case .scanning: return "Scanning · Folders and project protection unlock when it finishes"
        case .cleaning:
            guard let progress = session.cleanupProgress else { return "Moving items to Trash…" }
            return "Moving to Trash · \(progress.completed) of \(progress.total)"
        case .choosingFolder: return "Choose a folder in the open panel"
        case .analyzing: return "Waiting for Claude…"
        }
    }

    private static func progress(_ session: WorkspaceSession) -> CleanupProgressState {
        guard let p = session.cleanupProgress else {
            return CleanupProgressState(fraction: 0, countLabel: "Preparing…", bytesLabel: "",
                current: "Writing the activity record", currentDetail: "Nothing moves until it is saved.",
                isStopping: session.stoppingCleanup, canStop: false)
        }
        // Bytes, not item count: time goes into re-measuring, which follows size, and one
        // 9 GB folder among 200 small caches would otherwise sit at "1%" for most of the run.
        let fraction = p.bytesTotal > 0 ? Double(p.bytesCompleted) / Double(p.bytesTotal)
            : p.total > 0 ? Double(p.completed) / Double(p.total) : 0
        let detail = session.stoppingCleanup ? "Stopping after this item…"
            : p.current == nil ? "Finishing…"
            : "\(byteLabel(p.currentBytes)) · Checking nothing changed since the scan, then moving it"
        return CleanupProgressState(fraction: min(1, fraction), countLabel: "\(p.completed) of \(p.total) items",
            bytesLabel: "\(byteLabel(p.bytesCompleted)) of \(byteLabel(p.bytesTotal))",
            current: p.current ?? "All items attempted", currentDetail: detail,
            isStopping: session.stoppingCleanup, canStop: !session.stoppingCleanup && p.current != nil)
    }

    private static func projectRows(_ session: WorkspaceSession, homePath: String) -> [ProjectRowState] {
        let protected = session.settings.protectedProjects
        var urls = protected.map(\.standardized)
        for url in session.projects where !urls.contains(where: { FileSafety.isSame($0, url) }) { urls.append(url.standardized) }
        // Two projects can share a folder name (clientA/app, clientB/app); the parent tells them
        // apart, and the home-relative path does when the parents match too.
        func qualified(_ url: URL) -> String { "\(url.deletingLastPathComponent().lastPathComponent) / \(url.lastPathComponent)" }
        let names = urls.map(\.lastPathComponent), parents = urls.map(qualified)
        func title(_ url: URL) -> String {
            let name = url.lastPathComponent
            guard names.filter({ $0 == name }).count > 1 else { return name }
            let parent = qualified(url)
            guard parents.filter({ $0 == parent }).count > 1 else { return parent }
            return url.path.hasPrefix(homePath + "/") ? "~" + url.path.dropFirst(homePath.count) : url.path
        }
        return urls.map { url in
            let isProtected = protected.contains { FileSafety.isSame($0, url) }
            let builds = session.candidates.filter { $0.category == .projects && FileSafety.isInside($0.url, root: url) }
            let bytes = builds.reduce(Int64(0)) { $0 + $1.bytes }
            let detail = isProtected ? "Protected · Never scanned or cleaned"
                : session.rescanNeeded.contains(where: { FileSafety.isSame($0, url) }) ? "Not scanned yet · Scan again to include its build folders"
                : builds.isEmpty ? "No build folders found"
                : "\(builds.count) build \(builds.count == 1 ? "folder" : "folders") · \(byteLabel(bytes))"
            return ProjectRowState(id: url.path, title: title(url), path: url.path, detail: detail, isProtected: isProtected)
        }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }
}
