import XCTest
@testable import SafeCleanerCore

/// Running external tools is the one place this app executes anything. These tests pin the
/// properties that make that acceptable — they are the safety argument, not a formality.
final class ToolCommandTests: XCTestCase {

    /// The strongest guarantee, and the cheapest: nothing outside this file can build a
    /// command, so no scan result, preference or filename can ever become one. If the
    /// private `init` were ever relaxed, this suite would keep passing and the guarantee
    /// would be gone — so it is asserted structurally instead, by checking every reachable
    /// command is one of the known literals.
    func testEveryReachableCommandIsFromTheCatalogue() {
        for action in ToolAction.all() {
            XCTAssertTrue(ToolCommand.Catalogue.every.contains(action.preview), "preview \(action.id) escaped the catalogue")
            XCTAssertTrue(ToolCommand.Catalogue.every.contains(action.apply), "apply \(action.id) escaped the catalogue")
        }
    }

    func testNoCommandInvokesAShell() {
        for command in ToolCommand.Catalogue.every {
            XCTAssertFalse(ToolCommand.forbidden.contains(command.executable),
                           "\(command.executable) is a shell or an interpreter")
            XCTAssertFalse(command.arguments.contains { $0.contains("&&") || $0.contains("|") || $0.contains(";") || $0.contains("$(") },
                           "\(command.executable) carries shell metacharacters, which means someone built a string")
        }
    }

    func testEveryExecutableIsAnAbsolutePath() {
        for command in ToolCommand.Catalogue.every {
            XCTAssertTrue(command.executable.hasPrefix("/"),
                          "\(command.executable) would be resolved through PATH")
        }
    }

    /// Membership is the check, not plausibility: /bin/ls exists on every Mac and is
    /// entirely harmless, and is still refused because nobody listed it.
    func testAnUnlistedBinaryIsRefusedEvenThoughItIsHarmless() {
        let allowed = Set(ToolCommand.Catalogue.every.map(\.executable))
        XCTAssertThrowsError(try ToolCommand.validate(executable: "/bin/ls", allowed: allowed, fm: .default)) {
            XCTAssertEqual($0 as? ToolCommand.ToolError, .notAllowed("/bin/ls"))
        }
    }

    func testAShellIsRefusedEvenIfSomehowAllowed() {
        // Belt and braces: if a shell ever reached the catalogue, it is still refused.
        XCTAssertThrowsError(try ToolCommand.validate(executable: "/bin/sh", allowed: ["/bin/sh"], fm: .default)) {
            XCTAssertEqual($0 as? ToolCommand.ToolError, .notAllowed("/bin/sh"))
        }
        XCTAssertThrowsError(try ToolCommand.validate(executable: "/usr/bin/env", allowed: ["/usr/bin/env"], fm: .default))
    }

    func testRelativePathIsRefusedSoPathCannotBeHijacked() {
        XCTAssertThrowsError(try ToolCommand.validate(executable: "brew", allowed: ["brew"], fm: .default))
    }

    /// A binary other users can rewrite is a binary someone else chooses the behaviour of.
    func testWorldWritableBinaryIsRefused() throws {
        let dir = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerTool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("tool")
        try Data("x".utf8).write(to: fake)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        XCTAssertNoThrow(try ToolCommand.validate(executable: fake.path, allowed: [fake.path], fm: .default),
                         "0755 is the normal case and must pass")

        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: fake.path)
        XCTAssertThrowsError(try ToolCommand.validate(executable: fake.path, allowed: [fake.path], fm: .default)) {
            XCTAssertEqual($0 as? ToolCommand.ToolError, .writableByOthers(fake.path))
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o775], ofItemAtPath: fake.path)
        XCTAssertThrowsError(try ToolCommand.validate(executable: fake.path, allowed: [fake.path], fm: .default),
                             "group-writable is refused too")
    }

    func testMissingBinaryIsReportedAsMissingNotAsRefused() {
        let ghost = "/private/tmp/SafeCleanerNotThere-\(UUID().uuidString)"
        XCTAssertThrowsError(try ToolCommand.validate(executable: ghost, allowed: [ghost], fm: .default)) {
            XCTAssertEqual($0 as? ToolCommand.ToolError, .missing(ghost))
        }
    }

    /// Every real tool on this machine must pass its own check, or the feature is theatre.
    func testTheRealToolsOnThisMachineValidate() {
        let allowed = Set(ToolCommand.Catalogue.every.map(\.executable))
        for path in allowed where FileManager.default.fileExists(atPath: path) {
            XCTAssertNoThrow(try ToolCommand.validate(executable: path, allowed: allowed, fm: .default),
                             "\(path) is installed but would be refused")
        }
    }

    func testPreviewCommandsDoNotMutate() {
        // Each preview must be a listing or an explicit dry run. A "preview" that deletes
        // would make the confirmation screen a lie.
        for action in ToolAction.all() {
            let args = action.preview.arguments
            let isReadOnly = args.contains("--dry-run") || args.contains("list") || args.contains("df")
            XCTAssertTrue(isReadOnly, "\(action.id) preview is not read-only: \(args)")
        }
    }

    func testApplyCommandsNeverTargetEverything() {
        // `simctl delete all` and `--prune=all` are valid flags and are deliberately absent:
        // automation should remove what is provably stale, never the lot.
        for action in ToolAction.all() {
            XCTAssertFalse(action.apply.arguments.contains("all"), "\(action.id) deletes everything")
            XCTAssertFalse(action.apply.arguments.contains("--prune=all"), "\(action.id) prunes everything")
        }
    }

    func testStalenessThresholdIsExplicitNotImplied() {
        let runtimes = ToolCommand.Catalogue.simulatorRuntimesApply()
        XCTAssertEqual(runtimes.arguments, ["simctl", "runtime", "delete", "--notUsedSinceDays", "30"])
    }

    func testEveryActionExplainsWhatBreaks() {
        for action in ToolAction.all() {
            XCTAssertFalse(action.consequence.isEmpty, "\(action.id) does not say what it costs")
            XCTAssertFalse(action.detail.isEmpty)
        }
    }
}
