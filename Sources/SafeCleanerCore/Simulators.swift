import Foundation

/// One installed simulator runtime, as `xcrun simctl runtime list -j` reports it.
public struct SimulatorRuntime: Sendable, Equatable {
    public let identifier: String
    public let runtimeIdentifier: String
    public let platform: String
    public let version: String
    public let build: String
    public let sizeBytes: Int64
    public let lastUsedAt: Date?
    public let deletable: Bool
    public let state: String
    public let mountPath: String
    public init(identifier: String, runtimeIdentifier: String, platform: String, version: String, build: String,
                sizeBytes: Int64, lastUsedAt: Date?, deletable: Bool, state: String, mountPath: String) {
        self.identifier = identifier; self.runtimeIdentifier = runtimeIdentifier; self.platform = platform
        self.version = version; self.build = build; self.sizeBytes = sizeBytes; self.lastUsedAt = lastUsedAt
        self.deletable = deletable; self.state = state; self.mountPath = mountPath
    }
    /// "iOS" from `com.apple.platform.iphonesimulator`.
    public var platformName: String { SimulatorInventory.platformName(platform) }
}

/// One simulator device, as `xcrun simctl list devices -j` reports it.
public struct SimulatorDevice: Sendable, Equatable {
    public let udid: String
    public let name: String
    public let runtimeIdentifier: String
    public let state: String
    public let isAvailable: Bool
    public let dataPath: String
    public let dataPathSize: Int64
    public let lastUsedAt: Date?
    public init(udid: String, name: String, runtimeIdentifier: String, state: String, isAvailable: Bool,
                dataPath: String, dataPathSize: Int64, lastUsedAt: Date?) {
        self.udid = udid; self.name = name; self.runtimeIdentifier = runtimeIdentifier; self.state = state
        self.isAvailable = isAvailable; self.dataPath = dataPath; self.dataPathSize = dataPathSize; self.lastUsedAt = lastUsedAt
    }
    /// "iOS 27.0" from `com.apple.CoreSimulator.SimRuntime.iOS-27-0`.
    public var runtimeName: String { SimulatorInventory.runtimeName(runtimeIdentifier) }
}

/// Parses simctl's JSON. Fields the rules need are required; everything else is ignored, so
/// a newer Xcode adding keys cannot break the scan.
public enum SimulatorInventory {
    public static func runtimes(from data: Data) throws -> [SimulatorRuntime] {
        struct Entry: Decodable {
            let identifier: String, runtimeIdentifier: String, platformIdentifier: String
            let version: String, build: String?, sizeBytes: Int64?, lastUsedAt: String?
            let deletable: Bool?, state: String?, mountPath: String?
        }
        let entries = try JSONDecoder().decode([String: Entry].self, from: data)
        return entries.values.map {
            SimulatorRuntime(identifier: $0.identifier, runtimeIdentifier: $0.runtimeIdentifier,
                platform: $0.platformIdentifier, version: $0.version, build: $0.build ?? "",
                sizeBytes: $0.sizeBytes ?? 0, lastUsedAt: $0.lastUsedAt.flatMap(date),
                deletable: $0.deletable ?? false, state: $0.state ?? "", mountPath: $0.mountPath ?? "")
        }.sorted { $0.identifier < $1.identifier }
    }

    public static func devices(from data: Data) throws -> [SimulatorDevice] {
        struct Entry: Decodable {
            let udid: String, name: String, state: String?, isAvailable: Bool?
            let dataPath: String?, dataPathSize: Int64?, lastUsedAt: String?
        }
        struct Envelope: Decodable { let devices: [String: [Entry]] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        return envelope.devices.flatMap { runtime, entries in
            entries.map {
                SimulatorDevice(udid: $0.udid, name: $0.name, runtimeIdentifier: runtime, state: $0.state ?? "",
                    isAvailable: $0.isAvailable ?? false, dataPath: $0.dataPath ?? "",
                    dataPathSize: $0.dataPathSize ?? 0, lastUsedAt: $0.lastUsedAt.flatMap(date))
            }
        }.sorted { $0.udid < $1.udid }
    }

    static func date(_ text: String) -> Date? { ISO8601DateFormatter().date(from: text) }

    static func platformName(_ identifier: String) -> String {
        switch identifier.split(separator: ".").last.map(String.init) ?? identifier {
        case "iphonesimulator": return "iOS"
        case "appletvsimulator": return "tvOS"
        case "watchsimulator": return "watchOS"
        case "xrsimulator": return "visionOS"
        case let other: return other
        }
    }

    static func runtimeName(_ identifier: String) -> String {
        let tail = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = tail.split(separator: "-").map(String.init)
        guard parts.count > 1 else { return tail }
        return "\(parts[0]) \(parts.dropFirst().joined(separator: "."))"
    }

    static func versionParts(_ version: String) -> [Int] { version.split(separator: ".").map { Int($0) ?? 0 } }
}

/// Which runtimes and devices may be offered for removal, and the candidate each becomes.
/// Every guard here is a reason the item might still be wanted; the newest runtime per
/// platform is never offered because Xcode needs one to build against.
public enum SimulatorRules {
    public static let idleDays = 30
    public static let owner = "com.apple.iphonesimulator"
    /// Xcode creates a device per model for every runtime; each holds a few hundred KB of
    /// stubs. Only a device with real app data is worth a row.
    public static let minimumDeviceBytes: Int64 = 50_000_000

    public static func candidates(runtimes: [SimulatorRuntime], devices: [SimulatorDevice], now: Date = Date()) -> [Candidate] {
        let cutoff = now.addingTimeInterval(-Double(idleDays) * 86_400)
        func idle(_ date: Date?) -> Bool { date.map { $0 < cutoff } ?? true }
        let newest = Dictionary(grouping: runtimes, by: \.platform).compactMapValues { group in
            group.max { SimulatorInventory.versionParts($0.version).lexicographicallyPrecedes(SimulatorInventory.versionParts($1.version)) }?.version
        }
        let activeRuntimes = Set(devices.filter { $0.state != "Shutdown" || !idle($0.lastUsedAt) }.map(\.runtimeIdentifier))
        var result: [Candidate] = []
        for runtime in runtimes where runtime.deletable && runtime.state == "Ready" && runtime.sizeBytes > 0
            && !runtime.mountPath.isEmpty && newest[runtime.platform] != runtime.version
            && idle(runtime.lastUsedAt) && !activeRuntimes.contains(runtime.runtimeIdentifier) {
            let url = URL(fileURLWithPath: runtime.mountPath)
            let name = "\(runtime.platformName) \(runtime.version)"
            result.append(Candidate(url: url, title: "\(name) simulator runtime", category: .simulators,
                reason: "\(usage(runtime.lastUsedAt, now: now)) The newest \(runtime.platformName) runtime (\(newest[runtime.platform] ?? "")) is kept.",
                consequence: "Removed permanently by xcrun simctl, not moved to Trash. Simulators on \(name) stop working until Xcode downloads the runtime again from Settings > Components.",
                stamp: .init(digest: "simctl-runtime:\(runtime.identifier):\(runtime.build):\(runtime.sizeBytes)",
                             logicalBytes: runtime.sizeBytes, allocatedBytes: runtime.sizeBytes, fileCount: 0),
                allowedRoot: url.deletingLastPathComponent(), canTrash: true, ownerBundleID: owner,
                removal: .simulatorRuntime(identifier: runtime.identifier)))
        }
        for device in devices where device.isAvailable && device.state == "Shutdown" && device.dataPathSize >= minimumDeviceBytes
            && !device.dataPath.isEmpty && idle(device.lastUsedAt) {
            let url = URL(fileURLWithPath: device.dataPath).deletingLastPathComponent()
            result.append(Candidate(url: url, title: "\(device.name) · \(device.runtimeName) simulator", category: .simulators,
                reason: "\(usage(device.lastUsedAt, now: now)) Shut down.",
                consequence: "Removed permanently by xcrun simctl, not moved to Trash. Its installed apps and their data are deleted. Xcode can create a new \(device.name) at any time.",
                stamp: .init(digest: "simctl-device:\(device.udid):\(device.dataPathSize)",
                             logicalBytes: device.dataPathSize, allocatedBytes: device.dataPathSize, fileCount: 0),
                allowedRoot: url.deletingLastPathComponent(), canTrash: true, ownerBundleID: owner,
                removal: .simulatorDevice(udid: device.udid)))
        }
        return result.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
    }

    /// Whole 24-hour days, the same unit as the idle cutoff, so the text and the rule agree
    /// across daylight-saving changes.
    static func usage(_ date: Date?, now: Date) -> String {
        guard let date else { return "No recorded use." }
        let days = max(0, Int(now.timeIntervalSince(date) / 86_400))
        return "Last used \(days) days ago."
    }
}

/// The scan-side pass: two read-only list commands, then the rules. Missing Xcode means no
/// simulators and no issue; any other failure is reported, never hidden.
public struct SimulatorScan: Sendable {
    private let runner: any ToolRunning
    public init(runner: any ToolRunning) { self.runner = runner }

    public func run(exclusions: [URL] = [], now: Date = Date()) async -> (candidates: [Candidate], issues: [ScanIssue]) {
        do {
            let (runtimes, devices) = try await inventory()
            let candidates = SimulatorRules.candidates(runtimes: runtimes, devices: devices, now: now).filter { item in
                !exclusions.contains { FileSafety.isSame(item.url, $0) || FileSafety.isInside(item.url, root: $0) || FileSafety.isInside($0, root: item.url) }
            }
            return (candidates, [])
        } catch is CancellationError {
            return ([], [])
        } catch ToolCommand.ToolError.missing {
            return ([], [])
        } catch {
            return ([], [ScanIssue(path: "xcrun simctl", message: "Simulators were not inventoried: \(error.localizedDescription)")])
        }
    }

    func inventory() async throws -> ([SimulatorRuntime], [SimulatorDevice]) {
        let runtimes = try SimulatorInventory.runtimes(from: try await runner.run(ToolCommand.Catalogue.simulatorRuntimeList()))
        try Task.checkCancellation()
        let devices = try SimulatorInventory.devices(from: try await runner.run(ToolCommand.Catalogue.simulatorDeviceList()))
        try Task.checkCancellation()
        return (runtimes, devices)
    }
}

/// Removes one simulator candidate through simctl. Like the Trash path re-checks a snapshot,
/// this re-lists first: if the runtime or device was used since the scan, or no longer
/// qualifies under the rules, it is left in place and reported as changed.
public struct SimulatorRemover: ToolRemoving {
    private let runner: any ToolRunning
    public init(runner: any ToolRunning) { self.runner = runner }

    public func remove(_ item: Candidate) async -> CleanupRecord {
        do {
            guard let removal = item.removal else { throw SafetyError.refused("This item is not tool-managed.") }
            let command: ToolCommand
            switch removal {
            case .simulatorRuntime(let identifier): command = try ToolCommand.Catalogue.simulatorRuntimeDelete(identifier: identifier)
            case .simulatorDevice(let udid): command = try ToolCommand.Catalogue.simulatorDeviceDelete(udid: udid)
            default: throw SafetyError.refused("This item is not a simulator.")
            }
            let (runtimes, devices) = try await SimulatorScan(runner: runner).inventory()
            let current = SimulatorRules.candidates(runtimes: runtimes, devices: devices)
            guard let fresh = current.first(where: { $0.removal == removal }), fresh.stamp == item.stamp else {
                throw SafetyError.changedSinceScan
            }
            _ = try await runner.run(command)
            return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: item.bytes, error: nil, method: .tool, tool: "simctl")
        } catch is CancellationError {
            return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: 0,
                error: "Cleanup stopped before this item was removed.", failure: .other, method: .tool, tool: "simctl")
        } catch SafetyError.changedSinceScan {
            return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: 0,
                error: "The simulator was used or changed since the scan, so it was left in place. Scan again.",
                failure: .changed, method: .tool, tool: "simctl")
        } catch {
            return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: 0,
                error: "\(error.localizedDescription) The item was left in place.", failure: .other, method: .tool, tool: "simctl")
        }
    }
}
