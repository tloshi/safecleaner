import XCTest

/// The safety story rests on a few facts about the source tree that no runtime test can
/// prove: one place moves files, one place launches a process, one place talks to the
/// network, one place reads process tables, and nothing deletes. These read the tree so a
/// change that breaks one of them fails `swift test` instead of waiting for a code review.
final class StructuralTests: XCTestCase {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")

    /// Relative path → source text with line comments removed, so a sentence that mentions
    /// an API by name does not count as a call.
    private static let files: [String: String] = {
        var result: [String: String] = [:]
        let base = sources.path + "/"
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else { return result }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let code = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
                if let range = line.range(of: "//") { return line[..<range.lowerBound] }
                return line
            }.joined(separator: "\n")
            result[String(url.path.dropFirst(base.count))] = code
        }
        return result
    }()

    private func files(calling api: String) -> [String] {
        Self.files.filter { $0.value.contains(api) }.map(\.key).sorted()
    }

    func testTheTreeWasFound() {
        XCTAssertGreaterThan(Self.files.count, 20, "expected the Sources tree at \(Self.sources.path)")
    }

    func testOnlyTheCleanupEngineMovesFilesToTrash() {
        XCTAssertEqual(files(calling: "trashItem("), ["SafeCleanerCore/FileSafety.swift"])
        let engine = Self.files["SafeCleanerCore/FileSafety.swift"] ?? ""
        XCTAssertEqual(engine.components(separatedBy: "trashItem(").count - 1, 1, "exactly one call")
    }

    func testNothingDeletesFiles() {
        for api in ["removeItem(", "removeItemAtPath", "unlink(", "rmdir(", "remove(atPath", "deleteItem", "destroyItem"] {
            XCTAssertEqual(files(calling: api), [], api)
        }
    }

    func testOnlyTheToolRunnerLaunchesProcesses() {
        XCTAssertEqual(files(calling: "Process()"), ["SafeCleaner/Services/ToolRunner.swift"])
        for api in ["posix_spawn", "NSTask", "execv", "system(\"", "popen("] {
            XCTAssertEqual(files(calling: api), [], api)
        }
    }

    func testOnlyTheClaudeServiceTouchesTheNetwork() {
        XCTAssertEqual(files(calling: "URLSession"), ["SafeCleaner/Services/ClaudeService.swift"])
        for api in ["import Network", "NWConnection", "NSURLConnection", "CFStreamCreatePair", "CFSocket", "getaddrinfo"] {
            XCTAssertEqual(files(calling: api), [], api)
        }
    }

    func testOnlyTheOpenFileServiceReadsProcessTables() {
        for api in ["proc_pidfdinfo(", "proc_listallpids(", "proc_pidinfo("] {
            XCTAssertEqual(files(calling: api), ["SafeCleaner/Services/OpenFileService.swift"], api)
        }
    }

    func testViewsAndDesignSystemNeverTouchTheFilesystemOrDesktopServices() {
        for api in ["FileManager", "NSWorkspace", "NSOpenPanel", "UserDefaults", "Process(", "URLSession", "SecItem"] {
            let found = files(calling: api).filter { $0.hasPrefix("SafeCleaner/Views/") || $0.hasPrefix("SafeCleaner/DesignSystem/") }
            XCTAssertEqual(found, [], api)
        }
    }

    func testPresentationNeverImportsUIFrameworksOrTouchesStorage() {
        for api in ["import SwiftUI", "import AppKit", "UserDefaults", "NSWorkspace", "Process("] {
            let found = files(calling: api).filter { $0.hasPrefix("SafeCleanerPresentation/") }
            XCTAssertEqual(found, [], api)
        }
    }
}
