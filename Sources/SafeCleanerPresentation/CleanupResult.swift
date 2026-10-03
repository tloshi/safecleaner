import Foundation
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

public enum AppQuitStatus: Sendable, Equatable { case open, quitting, closed, stillOpen }

/// An open app that kept some selected items in place, with a way to quit it from here.
public struct BlockingAppState: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let initial: String
    public let detail: String
    public let status: AppQuitStatus
    public let canQuit: Bool
    /// Why a quit did not finish. A normal quit can wait on the app's own save prompt.
    public let note: String?
}

public enum CleanupIssueKind: Sendable, Equatable { case permission, ownership, changed, stopped, other }

public struct CleanupIssueState: Identifiable, Equatable {
    public let id: String
    public let kind: CleanupIssueKind
    public let title: String
    public let detail: String
}

/// The screen shown when a cleanup left anything in place. One row per cause and one per
/// open app, each with its remedy — "N failed" told the user nothing they could act on.
public struct CleanupResultState: Equatable {
    public let title: String
    public let subtitle: String
    public let movedAnything: Bool
    public let apps: [BlockingAppState]
    public let issues: [CleanupIssueState]
    public let offersFullDiskAccess: Bool
    public let selectRemainingLabel: String
    public let canSelectRemaining: Bool
    public let selectRemainingHint: String?
}

/// What one cleanup did, kept in the session so the result screen can follow apps the user
/// quits from it. Items an app kept stay in the candidate list, so they can be selected again.
struct CleanupOutcome {
    let id = UUID()
    let requested: Int
    let moved: Int
    let movedBytes: Int64
    let failed: [CleanupRecord]
    let stoppedReason: String?
    let refusal: String?
    /// Owner bundle ID → IDs of the items that app kept in place.
    let heldByApp: [String: [String]]
    var appNames: [String: String] = [:]
    var appStatus: [String: AppQuitStatus] = [:]

    var leftInPlace: Int { requested - moved }
    var notAttempted: Int { refusal == nil ? max(0, requested - moved - failed.count) : 0 }
    var needsAttention: Bool { refusal != nil || !failed.isEmpty || stoppedReason != nil || notAttempted > 0 }

    static func make(_ result: CleanupBatchResult, requested: [Candidate]) -> CleanupOutcome {
        let moved = result.records.filter { $0.error == nil }
        let owners = Dictionary(requested.map { ($0.id, $0.ownerBundleID) }, uniquingKeysWith: { first, _ in first })
        var held: [String: [String]] = [:]
        for record in result.records where record.failure == .appRunning {
            if let owner = owners[record.originalPath] ?? nil { held[owner, default: []].append(record.originalPath) }
        }
        var outcome = CleanupOutcome(requested: requested.count, moved: moved.count,
            movedBytes: moved.reduce(Int64(0)) { $0 + $1.bytes },
            failed: result.records.filter { $0.error != nil }, stoppedReason: result.stoppedReason,
            refusal: nil, heldByApp: held)
        outcome.appStatus = held.mapValues { _ in .open }
        return outcome
    }

    static func refused(_ message: String, requested: Int) -> CleanupOutcome {
        CleanupOutcome(requested: requested, moved: 0, movedBytes: 0, failed: [], stoppedReason: nil,
                       refusal: message, heldByApp: [:])
    }

    /// Items whose app has since been closed and that are still listed for review.
    func releasedItems(in candidates: [Candidate]) -> [String] {
        let listed = Set(candidates.map(\.id))
        return heldByApp.filter { appStatus[$0.key] == .closed }.flatMap(\.value).filter(listed.contains)
    }
}

enum CleanupResultPresenter {
    static func make(_ outcome: CleanupOutcome, candidates: [Candidate], busy: Bool, preview: Bool) -> CleanupResultState {
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let apps = outcome.heldByApp.map { bundleID, ids -> BlockingAppState in
            let name = outcome.appNames[bundleID] ?? bundleID
            let bytes = ids.compactMap { byID[$0]?.bytes }.reduce(Int64(0), +)
            let status = outcome.appStatus[bundleID] ?? .open
            return BlockingAppState(id: bundleID, name: name, initial: String(name.prefix(1)).uppercased(),
                detail: "\(items(ids.count)) · \(byteLabel(bytes))", status: status,
                canQuit: !preview && (status == .open || status == .stillOpen),
                note: status == .stillOpen ? "Still open. It may be asking you to save: switch to it, or quit it yourself." : nil)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let released = outcome.releasedItems(in: candidates).count
        let left = outcome.leftInPlace
        let title = outcome.moved == 0 ? "Nothing was moved to Trash"
            : left == 0 ? "All \(outcome.moved) moved to Trash" : "\(outcome.moved) moved to Trash"
        var subtitle: [String] = []
        if left > 0 { subtitle.append("\(items(left)) left in place") }
        if outcome.moved > 0 { subtitle.append("\(byteLabel(outcome.movedBytes)) in Trash · Space returns when you empty it") }

        return CleanupResultState(title: title, subtitle: subtitle.joined(separator: " · "),
            movedAnything: outcome.moved > 0, apps: apps, issues: issues(outcome),
            offersFullDiskAccess: !preview && outcome.failed.contains { $0.failure == .permission },
            selectRemainingLabel: released == 0 ? "Select remaining in Review" : "Select \(released) remaining in Review",
            canSelectRemaining: released > 0 && !busy && !preview,
            selectRemainingHint: apps.isEmpty || released > 0 ? nil : "Quit an app above, then put its items back in Review.")
    }

    private static func issues(_ outcome: CleanupOutcome) -> [CleanupIssueState] {
        var rows: [CleanupIssueState] = []
        if let refusal = outcome.refusal {
            rows.append(.init(id: "refused", kind: .other, title: "Cleanup did not start", detail: refusal))
        }
        if let reason = outcome.stoppedReason {
            let skipped = outcome.notAttempted > 0 ? " \(items(outcome.notAttempted)) not attempted." : ""
            rows.append(.init(id: "stopped", kind: .stopped, title: "Cleanup stopped early", detail: reason + skipped))
        } else if outcome.notAttempted > 0 {
            rows.append(.init(id: "stopped", kind: .stopped, title: "\(items(outcome.notAttempted)) not attempted",
                              detail: "They were left in place."))
        }
        let held = Set(outcome.heldByApp.values.flatMap { $0 })
        func count(_ kind: CleanupFailure) -> Int { outcome.failed.filter { $0.failure == kind }.count }
        let denied = count(.permission)
        if denied > 0 {
            rows.append(.init(id: "permission", kind: .permission, title: "\(items(denied)) blocked by macOS",
                detail: "If privacy protection is the cause, Full Disk Access fixes it: grant it, reopen SafeCleaner and scan again. Locked or system-protected files stay blocked either way."))
        }
        let owned = count(.ownership)
        if owned > 0 {
            rows.append(.init(id: "ownership", kind: .ownership, title: "\(items(owned)) owned by another user",
                detail: "Usually left by an install run with sudo. Full Disk Access does not change this, and SafeCleaner does not ask for administrator rights."))
        }
        let changed = count(.changed)
        if changed > 0 {
            rows.append(.init(id: "changed", kind: .changed, title: "\(items(changed)) changed after the scan",
                detail: "\(changed == 1 ? "It was" : "They were") left in place. Scan again to measure \(changed == 1 ? "it" : "them") fresh."))
        }
        // `.appRunning` with no known owner cannot get an app row, so it is reported here.
        let other = outcome.failed.filter {
            $0.failure == nil || $0.failure == .other || ($0.failure == .appRunning && !held.contains($0.originalPath))
        }.compactMap(\.error)
        if !other.isEmpty {
            rows.append(.init(id: "other", kind: .other, title: "\(items(other.count)) could not move",
                              detail: unique(other).prefix(3).joined(separator: " ")))
        }
        return rows
    }

    private static func items(_ n: Int) -> String { "\(n) \(n == 1 ? "item" : "items")" }
    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
