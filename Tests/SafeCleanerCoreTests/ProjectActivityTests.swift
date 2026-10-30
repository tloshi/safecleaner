import XCTest
@testable import SafeCleanerCore

/// A developer with ten projects works on a few at a time; the rest keep their build output
/// for months. Activity is read locally and exactly: the last commit from the git reflog, the
/// last source edit from file dates (never build output or dependencies), the last build
/// from the output's own date, and the output that belongs to the project, DerivedData included.
final class ProjectActivityTests: XCTestCase {
    var home: URL!
    private let now = Date()
    private let big = String(repeating: "x", count: 8_192)

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerActivity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private var projects: URL { home.appendingPathComponent("projects") }
    private func daysAgo(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: now)! }

    @discardableResult
    private func file(_ path: String, _ text: String = "synthetic source", modified: Date? = nil) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }
    private func touch(_ path: String, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: home.appendingPathComponent(path).path)
    }
    private func reflog(_ project: String, commitDaysAgo days: Int) throws {
        let stamp = Int(daysAgo(days).timeIntervalSince1970)
        let old = String(repeating: "0", count: 40), one = String(repeating: "1", count: 40), two = String(repeating: "2", count: 40)
        try file("projects/\(project)/.git/logs/HEAD",
                 "\(old) \(one) Dev Eloper <dev@example.com> \(stamp - 86_400 * 30) +0200\tcommit (initial): start\n"
                 + "\(one) \(two) Dev Eloper <dev@example.com> \(stamp) +0200\tcommit: later work\n")
    }

    private func fixture() throws {
        try file("projects/alpha/package.json", "{}", modified: daysAgo(80))
        try file("projects/alpha/src/index.js", modified: daysAgo(80))
        try file("projects/alpha/node_modules/left-pad/index.js", big, modified: daysAgo(1))
        try file("projects/alpha/build/out.js", big, modified: daysAgo(90))
        try reflog("alpha", commitDaysAgo: 70)
        try touch("projects/alpha/build", daysAgo(90)); try touch("projects/alpha/node_modules", daysAgo(1))
        try touch("projects/alpha/src", daysAgo(80))
        try file("projects/beta/package.json", "{}", modified: daysAgo(30))
        try file("projects/beta/src/app.js", modified: daysAgo(2))
        try file("projects/beta/build/x", big, modified: daysAgo(1))
        try reflog("beta", commitDaysAgo: 5)
        try touch("projects/beta/build", daysAgo(1)); try touch("projects/beta/src", daysAgo(2))
        try file("projects/gamma/pubspec.yaml", "name: gamma", modified: daysAgo(100))
        try file("projects/gamma/lib/main.dart", modified: daysAgo(100))
        try touch("projects/gamma/lib", daysAgo(100))
        try FileManager.default.createDirectory(at: projects.appendingPathComponent("delta/.git"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": projects.appendingPathComponent("alpha").path], format: .xml, options: 0)
        try file("Library/Developer/Xcode/DerivedData/alpha-abcdefghijklmnopqrstuvwxyzab/info.plist", data: plist)
        try file("Library/Developer/Xcode/DerivedData/alpha-abcdefghijklmnopqrstuvwxyzab/Build/Products/x", big, modified: daysAgo(85))
        try touch("Library/Developer/Xcode/DerivedData/alpha-abcdefghijklmnopqrstuvwxyzab", daysAgo(85))
    }
    @discardableResult
    private func file(_ path: String, data: Data) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func testLastCommitIsReadFromTheGitReflogWithoutAProcess() throws {
        try fixture()
        let alpha = try XCTUnwrap(ProjectActivityScan.lastCommit(in: projects.appendingPathComponent("alpha")))
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: alpha, to: now).day, 70)
        XCTAssertNil(ProjectActivityScan.lastCommit(in: projects.appendingPathComponent("gamma")), "no git")
        XCTAssertNil(ProjectActivityScan.lastCommit(in: projects.appendingPathComponent("delta")), "a .git with no reflog")
        try file("projects/epsilon/.git", "gitdir: /elsewhere/.git/worktrees/epsilon\n")
        XCTAssertNil(ProjectActivityScan.lastCommit(in: projects.appendingPathComponent("epsilon")), "a worktree pointer file is not read")
    }

    func testSourceChangeIgnoresBuildOutputDependenciesAndGit() throws {
        try fixture()
        let alpha = try XCTUnwrap(ProjectActivityScan.lastSourceChange(in: projects.appendingPathComponent("alpha")))
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: alpha, to: now).day, 80,
                       "node_modules was touched yesterday and the build 90 days ago; neither is a source change")
        XCTAssertNil(ProjectActivityScan.lastSourceChange(in: projects.appendingPathComponent("delta")), "only .git, so no source")
    }

    func testActivityLinksBuildOutputAndDerivedDataToTheProject() throws {
        try fixture()
        let report = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [projects]))
        let activity = ProjectActivityScan.activities(projects: report.projects, candidates: report.candidates, home: home, now: now)
        XCTAssertEqual(activity.map { $0.project.lastPathComponent }.sorted(), ["alpha", "beta", "delta", "gamma"])
        let alpha = try XCTUnwrap(activity.first { $0.project.lastPathComponent == "alpha" })
        XCTAssertEqual(alpha.outputItems, 3, "build, node_modules and the DerivedData folder: \(report.candidates.map(\.title))")
        XCTAssertEqual(alpha.lastBuildDays, 1, "the newest output date decides, here node_modules")
        XCTAssertGreaterThan(alpha.outputBytes, 16_000)
        XCTAssertEqual(alpha.daysSinceSourceChange(now: now), 80)
        XCTAssertEqual(alpha.daysSinceCommit(now: now), 70)
        XCTAssertFalse(alpha.hasChangesAfterCommit)
        let beta = try XCTUnwrap(activity.first { $0.project.lastPathComponent == "beta" })
        XCTAssertTrue(beta.hasChangesAfterCommit, "edited 2 days ago, committed 5 days ago")
        XCTAssertEqual(beta.lastBuildDays, 1)
        let gamma = try XCTUnwrap(activity.first { $0.project.lastPathComponent == "gamma" })
        XCTAssertEqual(gamma.outputItems, 0); XCTAssertNil(gamma.lastBuildDays)
        XCTAssertEqual(report.activity.count, 4, "the scanner reports activity for every detected project")
    }

    func testStaleMeansNoEditAndNoBuildForSixtyDaysWithAtLeastOneSignal() throws {
        func activity(edit: Int?, commit: Int?, build: Int?) -> ProjectActivity {
            ProjectActivity(project: projects, lastSourceChange: edit.map(daysAgo), lastCommit: commit.map(daysAgo),
                            lastBuildDays: build, outputBytes: 1, outputItems: 1)
        }
        XCTAssertTrue(activity(edit: 60, commit: 70, build: 60).isStale(now: now))
        XCTAssertFalse(activity(edit: 59, commit: 70, build: 60).isStale(now: now), "an edit 59 days ago is recent")
        XCTAssertFalse(activity(edit: 60, commit: 70, build: 59).isStale(now: now), "a build 59 days ago is recent")
        XCTAssertTrue(activity(edit: 100, commit: nil, build: nil).isStale(now: now), "a source-only signal still decides")
        XCTAssertTrue(activity(edit: nil, commit: nil, build: 90).isStale(now: now))
        XCTAssertFalse(activity(edit: nil, commit: nil, build: nil).isStale(now: now), "no signal is unknown, never stale")
        XCTAssertEqual(activity(edit: nil, commit: nil, build: nil).status(now: now), .unknown)
        XCTAssertEqual(activity(edit: 3, commit: 4, build: 2).status(now: now), .active)
        XCTAssertFalse(activity(edit: 100, commit: 3, build: nil).isStale(now: now), "a commit 3 days ago is activity even when file dates say otherwise")
    }
}
