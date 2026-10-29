import XCTest
@testable import SafeCleanerCore

/// Simulator runtimes and devices are tool-managed: simctl reports them and simctl removes
/// them. These tests pin the guards that decide what may be offered, and the re-check that
/// runs right before a removal. No test touches simctl or the developer's simulators.
final class SimulatorTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-30T12:00:00Z")!
    private func iso(daysAgo: Int) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(-Double(daysAgo) * 86_400)) }

    private let newest = "41D370AB-06EE-4AE4-900B-B0F42BF7CFC9"
    private let recent = "830A20A7-93FB-4A9C-B995-E735BB6A42B7"
    private let stale = "7108F245-A808-4DA6-BB9B-C870AA12AF8B"
    private let locked = "11111111-2222-4333-8444-555555555555"
    private let tv = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
    private let staleDevice = "54218394-9D51-4C9C-9A9A-C725FE223202"
    private let busyDevice = "D6B2D1CB-1E4C-4A0B-9F5B-3F3B4F0E1D2A"
    private let emptyDevice = "0C3A0F0E-1B2C-4D3E-8F4A-5B6C7D8E9F0A"

    private func runtimesJSON(staleUsedDaysAgo: Int = 45) -> Data {
        func entry(_ id: String, _ rt: String, _ platform: String, _ version: String, _ size: Int64, used: String?, deletable: Bool = true, state: String = "Ready") -> [String: Any] {
            var e: [String: Any] = ["identifier": id, "runtimeIdentifier": rt, "platformIdentifier": platform, "version": version,
                "build": "B1", "sizeBytes": size, "deletable": deletable, "state": state, "kind": "Patchable Cryptex Disk Image",
                "mountPath": "/Library/Developer/CoreSimulator/Volumes/\(rt.split(separator: ".").last!)"]
            if let used { e["lastUsedAt"] = used }
            return e
        }
        let ios = "com.apple.platform.iphonesimulator", tvos = "com.apple.platform.appletvsimulator"
        return try! JSONSerialization.data(withJSONObject: [
            newest: entry(newest, "com.apple.CoreSimulator.SimRuntime.iOS-27-0", ios, "27.0", 8_067_000_161, used: iso(daysAgo: 12)),
            recent: entry(recent, "com.apple.CoreSimulator.SimRuntime.iOS-26-5", ios, "26.5", 8_400_000_000, used: iso(daysAgo: 2)),
            stale: entry(stale, "com.apple.CoreSimulator.SimRuntime.iOS-26-2", ios, "26.2", 8_500_000_000, used: iso(daysAgo: staleUsedDaysAgo)),
            locked: entry(locked, "com.apple.CoreSimulator.SimRuntime.iOS-25-0", ios, "25.0", 7_000_000_000, used: nil, deletable: false),
            tv: entry(tv, "com.apple.CoreSimulator.SimRuntime.tvOS-26-0", tvos, "26.0", 4_000_000_000, used: iso(daysAgo: 400))
        ])
    }

    private func devicesJSON(staleDeviceState: String = "Shutdown", busyOnStaleRuntime: Bool = false) -> Data {
        func entry(_ udid: String, _ name: String, size: Int64, used: String?, state: String = "Shutdown", available: Bool = true) -> [String: Any] {
            var e: [String: Any] = ["udid": udid, "name": name, "state": state, "isAvailable": available,
                "dataPath": "/Users/fixture/Library/Developer/CoreSimulator/Devices/\(udid)/data", "dataPathSize": size,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.\(name.replacingOccurrences(of: " ", with: "-"))"]
            if let used { e["lastUsedAt"] = used }
            return e
        }
        var ios262: [[String: Any]] = [entry(staleDevice, "iPhone 16e", size: 2_100_000_000, used: iso(daysAgo: 50), state: staleDeviceState)]
        if busyOnStaleRuntime { ios262.append(entry(busyDevice, "iPhone 16", size: 500_000_000, used: iso(daysAgo: 1))) }
        return try! JSONSerialization.data(withJSONObject: ["devices": [
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                entry(busyDevice, "iPhone 18 Pro", size: 4_100_894_720, used: iso(daysAgo: 1)),
                entry(emptyDevice, "iPhone Air", size: 0, used: nil),
                entry("E0E0E0E0-0000-4000-8000-000000000002", "Stub", size: 400_000, used: nil),
                entry("E0E0E0E0-0000-4000-8000-000000000001", "Broken", size: 900_000_000, used: iso(daysAgo: 90), available: false)
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": ios262
        ]])
    }

    private func candidates(runtimes: Data? = nil, devices: Data? = nil) throws -> [Candidate] {
        SimulatorRules.candidates(runtimes: try SimulatorInventory.runtimes(from: runtimes ?? runtimesJSON()),
                                  devices: try SimulatorInventory.devices(from: devices ?? devicesJSON()), now: now)
    }

    func testParsingReadsTheFieldsTheRulesNeedAndToleratesAbsentOnes() throws {
        let runtimes = try SimulatorInventory.runtimes(from: runtimesJSON())
        XCTAssertEqual(runtimes.count, 5)
        let staleRuntime = try XCTUnwrap(runtimes.first { $0.identifier == stale })
        XCTAssertEqual(staleRuntime.platformName, "iOS")
        XCTAssertEqual(staleRuntime.mountPath, "/Library/Developer/CoreSimulator/Volumes/iOS-26-2")
        XCTAssertNil(try XCTUnwrap(runtimes.first { $0.identifier == locked }).lastUsedAt)
        let devices = try SimulatorInventory.devices(from: devicesJSON())
        XCTAssertEqual(devices.count, 5)
        XCTAssertEqual(try XCTUnwrap(devices.first { $0.udid == staleDevice }).runtimeName, "iOS 26.2")
        XCTAssertThrowsError(try SimulatorInventory.devices(from: Data("not json".utf8)))
    }

    func testOnlyTheStaleNonNewestDeletableRuntimeAndTheIdleDeviceAreOffered() throws {
        let offered = try candidates()
        XCTAssertEqual(offered.map(\.removal), [.simulatorRuntime(identifier: stale), .simulatorDevice(udid: staleDevice)])
        let runtime = offered[0]
        XCTAssertEqual(runtime.category, .simulators)
        XCTAssertEqual(runtime.title, "iOS 26.2 simulator runtime")
        XCTAssertEqual(runtime.url.path, "/Library/Developer/CoreSimulator/Volumes/iOS-26-2")
        XCTAssertEqual(runtime.allowedRoot.path, "/Library/Developer/CoreSimulator/Volumes")
        XCTAssertEqual(runtime.bytes, 8_500_000_000)
        XCTAssertEqual(runtime.ownerBundleID, SimulatorRules.owner)
        XCTAssertTrue(runtime.canTrash, "selectable; the consequence says it is permanent")
        XCTAssertTrue(runtime.consequence.contains("permanently"), runtime.consequence)
        XCTAssertTrue(runtime.reason.contains("45 days ago"), runtime.reason)
        XCTAssertTrue(runtime.reason.contains("27.0"), "says which runtime is kept")
        let device = offered[1]
        XCTAssertEqual(device.url.path, "/Users/fixture/Library/Developer/CoreSimulator/Devices/\(staleDevice)")
        XCTAssertEqual(device.title, "iPhone 16e · iOS 26.2 simulator")
        XCTAssertTrue(device.consequence.contains("apps and their data"), device.consequence)
    }

    /// Each guard is a reason the item is still wanted. None of these may ever be offered.
    func testNewestRecentNonDeletableTVAndZeroSizeOrBusyOrUnavailableAreNeverOffered() throws {
        let ids = Set(try candidates().map(\.id))
        XCTAssertFalse(ids.contains("/Library/Developer/CoreSimulator/Volumes/iOS-27-0"), "newest iOS runtime")
        XCTAssertFalse(ids.contains("/Library/Developer/CoreSimulator/Volumes/iOS-26-5"), "used two days ago")
        XCTAssertFalse(ids.contains("/Library/Developer/CoreSimulator/Volumes/iOS-25-0"), "not deletable")
        XCTAssertFalse(ids.contains("/Library/Developer/CoreSimulator/Volumes/tvOS-26-0"), "only tvOS runtime, so the newest")
        XCTAssertFalse(ids.contains { $0.hasSuffix(busyDevice) }, "used yesterday")
        XCTAssertFalse(ids.contains { $0.hasSuffix(emptyDevice) }, "frees nothing")
        XCTAssertFalse(ids.contains { $0.hasSuffix("000000000002") }, "an auto-created device with only stubs is not worth a row")
        XCTAssertFalse(ids.contains { $0.hasSuffix("000000000001") }, "unavailable")
    }

    func testARuntimeWithABootedOrRecentlyUsedDeviceIsKeptEvenIfItsOwnStampIsOld() throws {
        XCTAssertFalse(try candidates(devices: devicesJSON(staleDeviceState: "Booted")).contains { $0.removal == .simulatorRuntime(identifier: stale) })
        XCTAssertFalse(try candidates(devices: devicesJSON(staleDeviceState: "Booted")).contains { $0.removal == .simulatorDevice(udid: staleDevice) }, "a booted device is never offered")
        XCTAssertFalse(try candidates(devices: devicesJSON(busyOnStaleRuntime: true)).contains { $0.removal == .simulatorRuntime(identifier: stale) })
        XCTAssertFalse(try candidates(runtimes: runtimesJSON(staleUsedDaysAgo: 29)).contains { $0.removal == .simulatorRuntime(identifier: stale) }, "29 days is not idle")
        XCTAssertTrue(try candidates(runtimes: runtimesJSON(staleUsedDaysAgo: 31)).contains { $0.removal == .simulatorRuntime(identifier: stale) })
    }

    func testRemoverReListsFirstAndRunsExactlyOneValidatedCommand() async throws {
        let runner = FakeRunner(runtimes: runtimesJSON(), devices: devicesJSON())
        let item = try XCTUnwrap(try candidates().first)
        let record = await SimulatorRemover(runner: runner).remove(item)
        XCTAssertNil(record.error, record.error ?? "")
        XCTAssertEqual(record.method, .tool)
        XCTAssertEqual(record.bytes, item.bytes)
        XCTAssertNil(record.trashPath)
        let commands = await runner.commands.map(\.arguments)
        XCTAssertEqual(commands, [["simctl", "runtime", "list", "-j"], ["simctl", "list", "devices", "-j"],
                                  ["simctl", "runtime", "delete", stale]])
    }

    func testRemoverLeavesAnItemUsedSinceTheScanInPlace() async throws {
        let item = try XCTUnwrap(try candidates().first)
        let runner = FakeRunner(runtimes: runtimesJSON(staleUsedDaysAgo: 3), devices: devicesJSON())
        let record = await SimulatorRemover(runner: runner).remove(item)
        XCTAssertEqual(record.failure, .changed)
        XCTAssertEqual(record.bytes, 0)
        let deletes = await runner.commands.filter { $0.arguments.contains("delete") }
        XCTAssertTrue(deletes.isEmpty, "nothing is removed once the re-check fails")
    }

    func testRemoverRefusesNonToolItemsForgedIdentifiersAndReportsToolFailures() async throws {
        let runner = FakeRunner(runtimes: runtimesJSON(), devices: devicesJSON())
        let plain = Candidate(url: URL(fileURLWithPath: "/fixture/cache"), title: "cache", category: .developer, reason: "", consequence: "",
            stamp: .init(digest: "d", logicalBytes: 1, allocatedBytes: 1, fileCount: 1), allowedRoot: URL(fileURLWithPath: "/fixture"), canTrash: true, ownerBundleID: nil)
        let plainRecord = await SimulatorRemover(runner: runner).remove(plain)
        XCTAssertNotNil(plainRecord.error)
        var forged = try XCTUnwrap(try candidates().first)
        forged = Candidate(url: forged.url, title: forged.title, category: forged.category, reason: forged.reason, consequence: forged.consequence,
            stamp: forged.stamp, allowedRoot: forged.allowedRoot, canTrash: true, ownerBundleID: forged.ownerBundleID,
            removal: .simulatorRuntime(identifier: "unavailable --all; rm -rf /"))
        let refused = await SimulatorRemover(runner: runner).remove(forged)
        XCTAssertNotNil(refused.error)
        var count = await runner.commands.count
        XCTAssertEqual(count, 0, "a forged identifier never reaches a command, not even the list")
        await runner.fail(on: "delete")
        let failed = await SimulatorRemover(runner: runner).remove(try XCTUnwrap(try candidates().first))
        XCTAssertTrue(failed.error?.contains("exited with code") == true, failed.error ?? "")
        XCTAssertEqual(failed.failure, .other)
        count = await runner.commands.count
        XCTAssertEqual(count, 3)
    }

    func testScanIsQuietWithoutXcodeReportsOtherFailuresAndHonoursExclusions() async throws {
        let missing = FakeRunner(runtimes: Data(), devices: Data()); await missing.fail(on: "list", with: .missing("/usr/bin/xcrun"))
        let none = await SimulatorScan(runner: missing).run(now: now)
        XCTAssertTrue(none.candidates.isEmpty); XCTAssertTrue(none.issues.isEmpty)
        let broken = FakeRunner(runtimes: Data("{".utf8), devices: devicesJSON())
        let issue = await SimulatorScan(runner: broken).run(now: now)
        XCTAssertTrue(issue.candidates.isEmpty); XCTAssertEqual(issue.issues.count, 1)
        let runner = FakeRunner(runtimes: runtimesJSON(), devices: devicesJSON())
        let excluded = await SimulatorScan(runner: runner).run(exclusions: [URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes")], now: now)
        XCTAssertEqual(excluded.candidates.map(\.removal), [.simulatorDevice(udid: staleDevice)])
    }
}

private actor FakeRunner: ToolRunning {
    var commands: [ToolCommand] = []
    private let runtimes: Data, devices: Data
    private var failure: (String, ToolCommand.ToolError)?
    init(runtimes: Data, devices: Data) { self.runtimes = runtimes; self.devices = devices }
    func fail(on word: String, with error: ToolCommand.ToolError? = nil) {
        failure = (word, error ?? .failed("simctl", 1, "Synthetic simctl failure"))
    }
    func run(_ command: ToolCommand) throws -> Data {
        commands.append(command)
        if let failure, command.arguments.contains(failure.0) { throw failure.1 }
        if command.arguments.starts(with: ["simctl", "runtime", "list"]) { return runtimes }
        if command.arguments.starts(with: ["simctl", "list", "devices"]) { return devices }
        return Data()
    }
}
