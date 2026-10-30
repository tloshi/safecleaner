import Foundation

/// Docker images, stopped containers and build cache, listed and removed through the
/// `docker` command one item at a time, in the simulator adapter's pattern: read-only
/// inventories at scan time, per-item removals by an ID docker itself reported, re-listed
/// immediately before each removal. Volumes are never touched and no bare prune exists.
///
/// Everything lives inside Docker Desktop's disk file (`Docker.raw`), which only shrinks after
/// Docker compacts it or restarts; every consequence says so.
public struct DockerImage: Sendable, Equatable {
    public let id: String
    public let repository: String
    public let tag: String
    public let createdAt: Date?
    public let sizeBytes: Int64
    public let sizeLabel: String
    public var isUntagged: Bool { repository == "<none>" }
    public var shortID: String { String((id.hasPrefix("sha256:") ? String(id.dropFirst(7)) : id).prefix(12)) }
    /// Whether a container's `Image` field refers to this image: by full or short ID, by
    /// `repository:tag`, or by repository alone for the `latest` tag.
    func matches(_ reference: String) -> Bool {
        let bare = id.hasPrefix("sha256:") ? String(id.dropFirst(7)) : id
        let ref = reference.hasPrefix("sha256:") ? String(reference.dropFirst(7)) : reference
        if bare == ref || (ref.count >= 12 && bare.hasPrefix(ref)) { return true }
        guard !isUntagged else { return false }
        return ref == "\(repository):\(tag)" || (tag == "latest" && ref == repository)
    }
}

public struct DockerContainer: Sendable, Equatable {
    public let id: String
    public let image: String
    public let names: String
    public let state: String
    public let status: String
    public let createdAt: Date?
    public let sizeBytes: Int64
    public let sizeLabel: String
}

public struct DockerCacheEntry: Sendable, Equatable {
    public let id: String
    public let sizeBytes: Int64
    public let sizeLabel: String
    public let createdAt: Date?
    public let lastUsedDays: Int?
    public let reclaimable: Bool
    public let shared: Bool
    public let description: String
}

public enum DockerInventory {
    public struct ParseError: LocalizedError { public var errorDescription: String? { "docker returned output that could not be read." } }

    /// `docker image ls --format json`: one JSON object per line.
    public static func images(from data: Data) throws -> [DockerImage] {
        try objects(from: data).map { object in
            DockerImage(id: object["ID"] ?? "", repository: object["Repository"] ?? "<none>", tag: object["Tag"] ?? "<none>",
                        createdAt: date(object["CreatedAt"] ?? ""), sizeBytes: bytes(object["Size"] ?? ""), sizeLabel: object["Size"] ?? "")
        }.filter { !$0.id.isEmpty }
    }

    /// `docker container ls --all --size --format json`.
    public static func containers(from data: Data) throws -> [DockerContainer] {
        try objects(from: data).map { object in
            DockerContainer(id: object["ID"] ?? "", image: object["Image"] ?? "", names: object["Names"] ?? "",
                            state: (object["State"] ?? "").lowercased(), status: object["Status"] ?? "",
                            createdAt: date(object["CreatedAt"] ?? ""), sizeBytes: bytes(object["Size"] ?? ""), sizeLabel: object["Size"] ?? "")
        }.filter { !$0.id.isEmpty }
    }

    /// `docker buildx du --verbose`: blank-line separated blocks of `Key:<tabs>value`; the
    /// final totals block has no ID and is not an entry.
    public static func cacheEntries(from data: Data) throws -> [DockerCacheEntry] {
        let text = String(decoding: data, as: UTF8.self)
        var entries: [DockerCacheEntry] = []
        for block in text.components(separatedBy: "\n\n") {
            var fields: [String: String] = [:]
            for line in block.split(separator: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            guard let id = fields["ID"], !id.isEmpty else { continue }
            entries.append(DockerCacheEntry(id: id, sizeBytes: bytes(fields["Size"] ?? ""), sizeLabel: fields["Size"] ?? "",
                createdAt: date(fields["Created at"] ?? ""), lastUsedDays: relativeDays(fields["Last used"] ?? ""),
                reclaimable: fields["Reclaimable"]?.lowercased() == "true", shared: fields["Shared"]?.lowercased() == "true",
                description: fields["Description"] ?? ""))
        }
        return entries
    }

    static func objects(from data: Data) throws -> [[String: String]] {
        var result: [[String: String]] = []
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else { throw ParseError() }
            result.append(object.compactMapValues { $0 as? String })
        }
        return result
    }

    /// Docker's own size strings, decimal units: "1.1GB", "812kB", "12.3MB (virtual 1.02GB)"
    /// gives the container's own layer. Anything unreadable is 0, never a guess.
    public static func bytes(_ label: String) -> Int64 {
        guard let token = label.split(separator: " ").first else { return 0 }
        let digits = token.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits) else { return 0 }
        let unit = token.dropFirst(digits.count).lowercased()
        let factor: Double
        switch unit {
        case "b", "": factor = 1
        case "kb": factor = 1_000
        case "kib": factor = 1_024
        case "mb": factor = 1_000_000
        case "mib": factor = 1_048_576
        case "gb": factor = 1_000_000_000
        case "gib": factor = 1_073_741_824
        case "tb": factor = 1_000_000_000_000
        case "tib": factor = 1_099_511_627_776
        default: return 0
        }
        return Int64((value * factor).rounded())
    }

    /// "Exited (0) 5 weeks ago" → 35; "About an hour ago" → 0; "Up 10 days" → nil (not an age).
    public static func relativeDays(_ text: String) -> Int? {
        let tokens = text.split(separator: " ").map { $0.lowercased() }
        guard let ago = tokens.lastIndex(of: "ago"), ago >= 2 else { return nil }
        var unit = tokens[ago - 1]
        if unit.hasSuffix("s") { unit.removeLast() }
        let countToken = tokens[ago - 2]
        let count = Int(countToken) ?? (["a", "an", "one"].contains(countToken) ? 1 : nil)
        guard let count else { return nil }
        switch unit {
        case "second", "minute", "hour": return 0
        case "day": return count
        case "week": return count * 7
        case "month": return count * 30
        case "year": return count * 365
        default: return nil
        }
    }

    /// "2025-09-17 10:11:12 +0000 UTC"
    public static func date(_ text: String) -> Date? {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasSuffix(" UTC") { value.removeLast(4) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: value)
    }
}

public enum DockerRules {
    public static let owner = "com.docker.docker"
    public static let idleDays = 30
    /// Below this an item is noise in a list about disk space.
    public static let minimumBytes: Int64 = 1_000_000
    static let maxDescription = 60
    static let stoppedStates: Set<String> = ["exited", "created", "dead"]
    static let diskNote = "Docker.raw, Docker's disk file, shrinks only after Docker Desktop compacts it or restarts."

    public static func candidates(images: [DockerImage], containers: [DockerContainer], cache: [DockerCacheEntry], now: Date = Date()) -> [Candidate] {
        func days(_ date: Date?) -> Int? { date.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) } }
        var result: [Candidate] = []
        let references = containers.map(\.image)
        for image in images where image.sizeBytes >= minimumBytes {
            guard !references.contains(where: image.matches), let age = days(image.createdAt), age >= idleDays else { continue }
            let path = image.isUntagged ? image.shortID : "\(image.repository):\(image.tag)"
            let url = URL(fileURLWithPath: "/docker/images/\(path)")
            result.append(Candidate(url: url, title: image.isUntagged ? "Untagged image \(image.shortID)" : "\(path) image", category: .docker,
                reason: "No container uses it. Created \(age) days ago." + (image.isUntagged ? " Untagged: a build left it behind." : ""),
                consequence: "Removed permanently by docker image rm, not moved to Trash. The next build or run that needs it pulls it again, which needs internet. \(diskNote)",
                stamp: .init(digest: "docker-image:\(image.id):\(image.sizeLabel)", logicalBytes: image.sizeBytes, allocatedBytes: image.sizeBytes, fileCount: 0),
                allowedRoot: url.deletingLastPathComponent(), canTrash: true, ownerBundleID: owner, removal: .dockerImage(id: image.id)))
        }
        for container in containers where stoppedStates.contains(container.state) && container.sizeBytes >= minimumBytes {
            guard let age = DockerInventory.relativeDays(container.status) ?? days(container.createdAt), age >= idleDays else { continue }
            let url = URL(fileURLWithPath: "/docker/containers/\(container.names.isEmpty ? container.id : container.names)")
            result.append(Candidate(url: url, title: "\(container.names.isEmpty ? String(container.id.prefix(12)) : container.names) container", category: .docker,
                reason: "\(container.status.isEmpty ? "Stopped" : container.status). A stopped container keeps its writable layer and logs.",
                consequence: "Removed permanently by docker container rm, not moved to Trash. Its writable layer and logs are gone; volumes are never touched and stay. Running it again creates a new container. \(diskNote)",
                stamp: .init(digest: "docker-container:\(container.id):\(container.sizeLabel)", logicalBytes: container.sizeBytes, allocatedBytes: container.sizeBytes, fileCount: 0),
                allowedRoot: url.deletingLastPathComponent(), canTrash: true, ownerBundleID: owner, removal: .dockerContainer(id: container.id)))
        }
        for entry in cache where entry.reclaimable && entry.sizeBytes >= minimumBytes {
            guard let age = entry.lastUsedDays ?? days(entry.createdAt), age >= idleDays else { continue }
            let description = entry.description.isEmpty ? entry.id.prefix(12) : entry.description.prefix(maxDescription)
            let title = "Build cache: \(description)" + (entry.description.count > maxDescription ? "…" : "")
            let url = URL(fileURLWithPath: "/docker/build-cache/\(entry.id.prefix(12))")
            result.append(Candidate(url: url, title: title, category: .docker,
                reason: "A build step's cache, last used \(age) days ago." + (entry.shared ? " Shared with an image." : ""),
                consequence: "Removed permanently by docker buildx prune for this one entry, not moved to Trash. The next build recomputes that step. \(diskNote)",
                stamp: .init(digest: "docker-cache:\(entry.id):\(entry.sizeLabel)", logicalBytes: entry.sizeBytes, allocatedBytes: entry.sizeBytes, fileCount: 0),
                allowedRoot: url.deletingLastPathComponent(), canTrash: true, ownerBundleID: owner, removal: .dockerBuildCache(id: entry.id)))
        }
        return result.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes }
    }
}

/// Runs the three read-only inventories. The daemon not running, or docker not installed, is
/// a quiet skip: nothing to offer, nothing to warn about.
public struct DockerScan: Sendable {
    private let runner: any ToolRunning
    private let executable: String
    public init(runner: any ToolRunning, executable: String) { self.runner = runner; self.executable = executable }

    public func run(exclusions: [URL] = [], now: Date = Date()) async -> (candidates: [Candidate], issues: [ScanIssue]) {
        do {
            let inventory = try await inventory()
            let candidates = DockerRules.candidates(images: inventory.images, containers: inventory.containers, cache: inventory.cache, now: now)
                .filter { item in !exclusions.contains { FileSafety.isSame(item.url, $0) || FileSafety.isInside(item.url, root: $0) } }
            return (candidates, inventory.issues)
        } catch is CancellationError {
            return ([], [])
        } catch ToolCommand.ToolError.missing, ToolCommand.ToolError.toolUnavailable {
            return ([], [])
        } catch let ToolCommand.ToolError.failed(_, _, output) where Self.isDaemonDown(output) {
            return ([], [])
        } catch {
            return ([], [ScanIssue(path: "docker", message: "Docker was not inventoried: \(error.localizedDescription)")])
        }
    }

    func inventory() async throws -> (images: [DockerImage], containers: [DockerContainer], cache: [DockerCacheEntry], issues: [ScanIssue]) {
        let images = try DockerInventory.images(from: try await runner.run(ToolCommand.Catalogue.dockerImageList(executable)))
        try Task.checkCancellation()
        let containers = try DockerInventory.containers(from: try await runner.run(ToolCommand.Catalogue.dockerContainerList(executable)))
        try Task.checkCancellation()
        var cache: [DockerCacheEntry] = []
        var issues: [ScanIssue] = []
        do {
            cache = try DockerInventory.cacheEntries(from: try await runner.run(ToolCommand.Catalogue.dockerBuildCacheList(executable)))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            issues.append(ScanIssue(path: "docker buildx du", message: "Docker's build cache was not inventoried: \(error.localizedDescription)"))
        }
        return (images, containers, cache, issues)
    }

    static func isDaemonDown(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("cannot connect to the docker daemon") || text.contains("is the docker daemon running")
            || text.contains("error during connect")
    }
}

/// Removes one Docker candidate through docker. Re-lists first: if the item changed since the
/// scan, or no longer qualifies under the rules, it is left in place and reported as changed.
public struct DockerRemover: ToolRemoving {
    public static let tool = "docker"
    private let runner: any ToolRunning
    private let executable: String
    public init(runner: any ToolRunning, executable: String) { self.runner = runner; self.executable = executable }

    public func remove(_ item: Candidate) async -> CleanupRecord {
        do {
            guard let removal = item.removal else { throw SafetyError.refused("This item is not tool-managed.") }
            let command: ToolCommand
            switch removal {
            case .dockerImage(let id): command = try ToolCommand.Catalogue.dockerImageRemove(executable, id: id)
            case .dockerContainer(let id): command = try ToolCommand.Catalogue.dockerContainerRemove(executable, id: id)
            case .dockerBuildCache(let id): command = try ToolCommand.Catalogue.dockerBuildCacheRemove(executable, id: id)
            default: throw SafetyError.refused("This item is not a Docker item.")
            }
            let inventory = try await DockerScan(runner: runner, executable: executable).inventory()
            let current = DockerRules.candidates(images: inventory.images, containers: inventory.containers, cache: inventory.cache)
            guard let fresh = current.first(where: { $0.removal == removal }), fresh.stamp == item.stamp else {
                throw SafetyError.changedSinceScan
            }
            _ = try await runner.run(command)
            return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: item.bytes, error: nil, method: .tool, tool: Self.tool)
        } catch is CancellationError {
            return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: 0,
                error: "Cleanup stopped before this item was removed.", failure: .other, method: .tool, tool: Self.tool)
        } catch SafetyError.changedSinceScan {
            return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: 0,
                error: "The Docker item was used or changed since the scan, so it was left in place. Scan again.",
                failure: .changed, method: .tool, tool: Self.tool)
        } catch {
            return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: 0,
                error: "\(error.localizedDescription) The item was left in place.", failure: .other, method: .tool, tool: Self.tool)
        }
    }
}

/// Routes a tool-managed item to the tool that owns it. A Trash item never reaches a tool.
public struct ToolRemovers: ToolRemoving {
    private let simulators: SimulatorRemover
    private let docker: DockerRemover?
    public init(simulators: SimulatorRemover, docker: DockerRemover?) { self.simulators = simulators; self.docker = docker }

    public func remove(_ item: Candidate) async -> CleanupRecord {
        switch item.removal {
        case .simulatorRuntime, .simulatorDevice:
            return await simulators.remove(item)
        case .dockerImage, .dockerContainer, .dockerBuildCache:
            guard let docker else {
                return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: 0,
                    error: "Docker is not installed, so the item was left in place.", failure: .other, method: .tool, tool: DockerRemover.tool)
            }
            return await docker.remove(item)
        case nil:
            return CleanupRecord(originalPath: item.url.path, trashPath: nil, bytes: 0,
                error: "This item is not tool-managed, so no tool was asked to remove it.", failure: .other)
        }
    }
}
