import XCTest
import SafeCleanerCore
@testable import SafeCleaner

final class ToolRunnerTests: XCTestCase {
    /// Read-only: lists devices through the real runner so the process path is exercised at
    /// least once. Skipped where Xcode's simctl is not installed. Nothing is removed.
    func testListCommandRunsReadOnlyAndParses() async throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun"), "xcrun is not installed")
        do {
            let data = try await ToolRunner().run(ToolCommand.Catalogue.simulatorDeviceList())
            _ = try SimulatorInventory.devices(from: data)
        } catch ToolCommand.ToolError.failed(_, _, _) {
            throw XCTSkip("simctl is unavailable on this Mac (Command Line Tools without Xcode)")
        }
    }
}
