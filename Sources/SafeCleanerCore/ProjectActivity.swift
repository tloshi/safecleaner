import Foundation

public enum ProjectStatus: Sendable, Equatable { case stale, active, unknown }

/// How alive a project is, read locally and exactly: the last commit from the git reflog
/// (no process), the last source edit from file dates with build output, dependencies and
/// `.git` left out, the last build from the output's own date, and the output that belongs to
/// the project, DerivedData included. Nothing here is a guess, which is why a model is only
/// ever asked to rank these numbers, never to invent them.
public struct ProjectActivity: Sendable, Equatable {
    /// No edit, no commit and no build for this long is stale.
    public static let staleDays = 60
    static let secondsPerDay = 86_400.0

    public let project: URL
    public let lastSourceChange: Date?
    public let lastCommit: Date?
    /// Fewest idle days among its build outputs, from `BuildOutput.idleDays`; nil without output.
    public let lastBuildDays: Int?
    public let outputBytes: Int64
    public let outputItems: Int
    /// Candidate IDs of its build output, so a stale project's output can be selected in one step.
    public let outputIDs: [String]

    public init(project: URL, lastSourceChange: Date?, lastCommit: Date?, lastBuildDays: Int?,
                outputBytes: Int64, outputItems: Int, outputIDs: [String] = []) {
        self.project = project; self.lastSourceChange = lastSourceChange; self.lastCommit = lastCommit
        self.lastBuildDays = lastBuildDays; self.outputBytes = outputBytes; self.outputItems = outputItems; self.outputIDs = outputIDs
    }

    public var hasChangesAfterCommit: Bool {
        guard let lastSourceChange, let lastCommit else { return false }
        return lastSourceChange > lastCommit
    }
    public func daysSinceSourceChange(now: Date = Date()) -> Int? { lastSourceChange.map { Self.days(since: $0, now: now) } }
    public func daysSinceCommit(now: Date = Date()) -> Int? { lastCommit.map { Self.days(since: $0, now: now) } }
    /// Days since the most recent edit or commit, whichever is newer.
    public func daysSinceActivity(now: Date = Date()) -> Int? {
        [daysSinceSourceChange(now: now), daysSinceCommit(now: now)].compactMap { $0 }.min()
    }
    public func status(now: Date = Date()) -> ProjectStatus {
        let edit = daysSinceActivity(now: now)
        guard edit != nil || lastBuildDays != nil else { return .unknown }
        let editStale = edit.map { $0 >= Self.staleDays } ?? true
        let buildStale = lastBuildDays.map { $0 >= Self.staleDays } ?? true
        return editStale && buildStale ? .stale : .active
    }
    public func isStale(now: Date = Date()) -> Bool { status(now: now) == .stale }

    /// Whole 24-hour days, so the number and the rule agree across daylight-saving changes.
    static func days(since date: Date, now: Date) -> Int { max(0, Int(now.timeIntervalSince(date) / secondsPerDay)) }
}

public enum ProjectActivityScan {
    static let maxEntries = 50_000
    static let reflogTailBytes: UInt64 = 4_096
    /// Folders whose dates say nothing about the person's work.
    static let skipped: Set<String> = Set(BuildOutput.rules.map(\.directory))
        .union([".git", "node_modules", "Pods", ".gradle", ".dart_tool", "vendor", "DerivedData", "dist", "out", ".next", ".build", "target"])

    public static func activities(projects: [URL], candidates: [Candidate], home: URL, now: Date = Date(),
                                  fm: FileManager = .default) -> [ProjectActivity] {
        let derivedRoot = DerivedData.root(home: home)
        // DerivedData rows name their workspace in info.plist; that is how they join a project.
        let derived: [(workspace: URL, candidate: Candidate)] = candidates.compactMap { candidate in
            guard FileSafety.isSame(candidate.url.deletingLastPathComponent(), derivedRoot),
                  let workspace = DerivedData.workspacePath(of: candidate.url, fm: fm) else { return nil }
            return (URL(fileURLWithPath: workspace), candidate)
        }
        return projects.map { project in
            var outputs = candidates.filter { $0.category == .projects && FileSafety.isInside($0.url, root: project) }
            outputs += derived.filter { FileSafety.isSame($0.workspace, project) || FileSafety.isInside($0.workspace, root: project) }.map(\.candidate)
            return ProjectActivity(project: project,
                lastSourceChange: lastSourceChange(in: project, fm: fm),
                lastCommit: lastCommit(in: project, fm: fm),
                lastBuildDays: outputs.compactMap { BuildOutput.idleDays($0.url, now: now) }.min(),
                outputBytes: outputs.reduce(Int64(0)) { $0 + $1.bytes }, outputItems: outputs.count,
                outputIDs: outputs.map(\.id).sorted())
        }
    }

    /// The timestamp on the last line of `.git/logs/HEAD`: "<old> <new> Name <email> <unix> <tz>\t<message>".
    /// A `.git` file (a worktree pointer) is not followed.
    public static func lastCommit(in project: URL, fm: FileManager = .default) -> Date? {
        let git = project.appendingPathComponent(".git")
        guard (try? git.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
        let reflog = git.appendingPathComponent("logs/HEAD")
        guard let handle = try? FileHandle(forReadingFrom: reflog) else { return nil }
        defer { try? handle.close() }
        guard let size = (try? fm.attributesOfItem(atPath: reflog.path))?[.size] as? NSNumber else { return nil }
        let start = size.uint64Value > reflogTailBytes ? size.uint64Value - reflogTailBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
        guard let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let head = last.split(separator: "\t", maxSplits: 1).first ?? last
        let tokens = head.split(separator: " ")
        guard tokens.count >= 4, let stamp = TimeInterval(tokens[tokens.count - 2]) else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    /// The newest file date under the project, skipping build output, dependencies, `.git`,
    /// hidden entries and package contents. Capped so a surprise tree cannot stall a scan.
    public static func lastSourceChange(in project: URL, fm: FileManager = .default) -> Date? {
        guard let enumerator = fm.enumerator(at: project, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                                             options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return nil }
        var newest: Date?
        var seen = 0
        for case let url as URL in enumerator {
            seen += 1
            if seen > maxEntries { break }
            let name = url.lastPathComponent
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { continue }
            // A symbolic link is never followed by the enumerator; skipDescendants would act on
            // the most recently obtained directory instead, so it is not called here.
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                if skipped.contains(name) || name.hasPrefix(".") { enumerator.skipDescendants() }
                continue
            }
            guard !name.hasPrefix("."), let date = values.contentModificationDate else { continue }
            if newest.map({ date > $0 }) ?? true { newest = date }
        }
        return newest
    }
}
