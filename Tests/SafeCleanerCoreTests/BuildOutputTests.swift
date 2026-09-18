import XCTest
@testable import SafeCleanerCore

/// Build output is the category the author actually needs: 32 GB regrew across 108
/// directories in a single month. It was previously scan-only and mostly undetected.
final class BuildOutputTests: XCTestCase {
    func testRequiresAManifestBesideTheDirectory() {
        XCTAssertNotNil(BuildOutput.rule(for: "node_modules", siblings: ["package.json"]))
        XCTAssertNil(BuildOutput.rule(for: "node_modules", siblings: ["README.md"]),
                     "a folder named node_modules with no package.json is not ours to nominate")
    }

    func testBuildMatchesAnyOfSeveralBuildSystems() {
        for manifest in ["build.gradle", "build.gradle.kts", "pubspec.yaml", "package.json", "CMakeLists.txt"] {
            XCTAssertNotNil(BuildOutput.rule(for: "build", siblings: [manifest]), "expected \(manifest) to qualify")
        }
        XCTAssertNil(BuildOutput.rule(for: "build", siblings: ["notes.txt"]))
    }

    /// Both are regenerable in most projects and committed source in others, with no local
    /// signal separating them. They held 0,01 GB on the author's machine, so the ambiguity
    /// is not worth buying.
    func testAmbiguousNamesAreNotNominated() {
        XCTAssertNil(BuildOutput.rule(for: "dist", siblings: ["package.json"]))
        XCTAssertNil(BuildOutput.rule(for: "out", siblings: ["package.json"]))
        XCTAssertNil(BuildOutput.rule(for: "src", siblings: ["package.json"]))
    }

    /// Xcode names its manifest after the project, so there is no fixed filename to match.
    /// Missing this hid the single largest item on the author's machine — a 4,14 GB
    /// `iosApp/build` — and made the scanner descend into it instead, producing 2,359
    /// depth-limit issues that buried every real finding.
    func testXcodeProjectsQualifyByExtension() {
        XCTAssertNotNil(BuildOutput.rule(for: "build", siblings: ["iosApp.xcodeproj"]))
        XCTAssertNotNil(BuildOutput.rule(for: "build", siblings: ["iosApp.xcworkspace"]))
        XCTAssertNotNil(BuildOutput.rule(for: "Pods", siblings: ["iosApp.xcworkspace"]))
        XCTAssertNil(BuildOutput.rule(for: "build", siblings: ["notes.xcodeproj.bak"]))
    }

    func testPycacheNeedsNoManifest() {
        XCTAssertNotNil(BuildOutput.rule(for: "__pycache__", siblings: []))
    }

    func testIdleLabelSeparatesFreshFromAbandoned() {
        XCTAssertEqual(BuildOutput.idleLabel(0), "Last built today.")
        XCTAssertEqual(BuildOutput.idleLabel(1), "Last built yesterday.")
        XCTAssertTrue(BuildOutput.idleLabel(12).contains("12 days ago"))
        XCTAssertTrue(BuildOutput.idleLabel(61).contains("unused for over a month"))
        XCTAssertFalse(BuildOutput.idleLabel(nil).isEmpty)
    }

    func testIdleDaysReadsTheDirectoryModificationDate() throws {
        let dir = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("SafeCleanerBuildOutput-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fortyDaysAgo = Date().addingTimeInterval(-40 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: fortyDaysAgo], ofItemAtPath: dir.path)
        XCTAssertEqual(BuildOutput.idleDays(dir), 40)
    }
}
