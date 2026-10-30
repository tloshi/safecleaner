import XCTest
@testable import SafeCleanerCore

/// Docker's disk image is the second-largest tool-managed store on the author's Mac
/// (21 GB). Images, stopped containers and build cache are listed and removed through the
/// `docker` command one item at a time, in the simulator adapter's pattern. Volumes are never
/// touched and no bare prune exists. The daemon not running is a quiet skip.
final class DockerTests: XCTestCase {
    private let now = Date()
    private func daysAgo(_ days: Int) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: now.addingTimeInterval(-Double(days) * 86_400)) + " +0000 UTC"
    }
    private let usedID = "sha256:" + String(repeating: "a", count: 64)
    private let danglingID = "sha256:" + String(repeating: "b", count: 64)
    private let unusedID = "sha256:" + String(repeating: "c", count: 64)
    private let freshID = "sha256:" + String(repeating: "d", count: 64)
    private let stoppedOnlyID = "sha256:" + String(repeating: "9", count: 64)
    private let cacheID = String(repeating: "e", count: 64)
    private let liveCacheID = String(repeating: "f", count: 64)

    private var images: Data {
        Data("""
        {"Containers":"N/A","CreatedAt":"\(daysAgo(90))","CreatedSince":"3 months ago","Digest":"<none>","ID":"\(usedID)","Repository":"node","SharedSize":"N/A","Size":"1.1GB","Tag":"20","UniqueSize":"N/A","VirtualSize":"1.1GB"}
        {"Containers":"N/A","CreatedAt":"\(daysAgo(45))","CreatedSince":"6 weeks ago","Digest":"<none>","ID":"\(danglingID)","Repository":"<none>","SharedSize":"N/A","Size":"300MB","Tag":"<none>","UniqueSize":"N/A","VirtualSize":"300MB"}
        {"Containers":"N/A","CreatedAt":"\(daysAgo(60))","CreatedSince":"2 months ago","Digest":"<none>","ID":"\(unusedID)","Repository":"python","SharedSize":"N/A","Size":"1.02GB","Tag":"3.12","UniqueSize":"N/A","VirtualSize":"1.02GB"}
        {"Containers":"N/A","CreatedAt":"\(daysAgo(2))","CreatedSince":"2 days ago","Digest":"<none>","ID":"\(freshID)","Repository":"fresh","SharedSize":"N/A","Size":"812kB","Tag":"latest","UniqueSize":"N/A","VirtualSize":"812kB"}
        {"Containers":"N/A","CreatedAt":"\(daysAgo(120))","CreatedSince":"4 months ago","Digest":"<none>","ID":"\(stoppedOnlyID)","Repository":"alpine","SharedSize":"N/A","Size":"50MB","Tag":"3.19","UniqueSize":"N/A","VirtualSize":"50MB"}

        """.utf8)
    }
    private var containers: Data {
        Data("""
        {"Command":"\\"node app.js\\"","CreatedAt":"\(daysAgo(10))","ID":"\(String(repeating: "1", count: 64))","Image":"node:20","Labels":"","LocalVolumes":"1","Mounts":"data","Names":"api","Networks":"bridge","Ports":"","RunningFor":"10 days ago","Size":"5.2MB (virtual 1.1GB)","State":"running","Status":"Up 10 days"}
        {"Command":"\\"sh\\"","CreatedAt":"\(daysAgo(50))","ID":"\(String(repeating: "2", count: 64))","Image":"alpine:3.19","Labels":"","LocalVolumes":"0","Mounts":"","Names":"old_job","Networks":"bridge","Ports":"","RunningFor":"7 weeks ago","Size":"12.3MB (virtual 50MB)","State":"exited","Status":"Exited (0) 5 weeks ago"}
        {"Command":"\\"sh\\"","CreatedAt":"\(daysAgo(3))","ID":"\(String(repeating: "3", count: 64))","Image":"fresh","Labels":"","LocalVolumes":"0","Mounts":"","Names":"recent","Networks":"bridge","Ports":"","RunningFor":"3 days ago","Size":"2MB (virtual 812kB)","State":"exited","Status":"Exited (1) 2 days ago"}
        {"Command":"\\"sh\\"","CreatedAt":"\(daysAgo(40))","ID":"\(String(repeating: "4", count: 64))","Image":"alpine:3.19","Labels":"","LocalVolumes":"0","Mounts":"","Names":"empty_shell","Networks":"bridge","Ports":"","RunningFor":"6 weeks ago","Size":"0B (virtual 1.02GB)","State":"created","Status":"Created"}

        """.utf8)
    }
    private var cache: Data {
        Data("""
        ID:\t\t\(cacheID)
        Parent:\t\t\(String(repeating: "9", count: 64))
        Created at:\t\(daysAgo(50))
        Mutable:\tfalse
        Reclaimable:\ttrue
        Shared:\t\tfalse
        Size:\t\t512MB
        Description:\t[stage-0 2/5] RUN apt-get update && apt-get install -y build-essential
        Usage count:\t1
        Last used:\t6 weeks ago
        Type:\t\tregular

        ID:\t\t\(liveCacheID)
        Created at:\t\(daysAgo(1))
        Mutable:\tfalse
        Reclaimable:\ttrue
        Shared:\t\tfalse
        Size:\t\t90MB
        Description:\t[stage-0 3/5] COPY . .
        Usage count:\t4
        Last used:\t2 hours ago
        Type:\t\tregular

        Shared:\t\t0B
        Private:\t602MB
        Reclaimable:\t602MB
        Total:\t\t602MB

        """.utf8)
    }

    func testSizesDatesAndRelativeAgesAreParsedFromDockersOwnStrings() {
        XCTAssertEqual(DockerInventory.bytes("1.1GB"), 1_100_000_000)
        XCTAssertEqual(DockerInventory.bytes("812kB"), 812_000)
        XCTAssertEqual(DockerInventory.bytes("12.3MB (virtual 1.02GB)"), 12_300_000, "a container's own layer, not the virtual size")
        XCTAssertEqual(DockerInventory.bytes("0B"), 0)
        XCTAssertEqual(DockerInventory.bytes("garbage"), 0)
        XCTAssertEqual(DockerInventory.relativeDays("Exited (0) 5 weeks ago"), 35)
        XCTAssertEqual(DockerInventory.relativeDays("2 months ago"), 60)
        XCTAssertEqual(DockerInventory.relativeDays("About an hour ago"), 0)
        XCTAssertEqual(DockerInventory.relativeDays("3 days ago"), 3)
        XCTAssertNil(DockerInventory.relativeDays("Up 10 days"), "not an age in the past")
        XCTAssertNil(DockerInventory.relativeDays("Created"))
        XCTAssertNotNil(DockerInventory.date("2025-09-17 10:11:12 +0000 UTC"))
        XCTAssertNil(DockerInventory.date("yesterday"))
    }

    func testInventoryParsesJSONLinesAndBuildCacheBlocks() throws {
        let images = try DockerInventory.images(from: images)
        XCTAssertEqual(images.map(\.repository), ["node", "<none>", "python", "fresh", "alpine"])
        XCTAssertEqual(images[1].sizeBytes, 300_000_000)
        XCTAssertEqual(images[0].id, usedID)
        let containers = try DockerInventory.containers(from: containers)
        XCTAssertEqual(containers.map(\.names), ["api", "old_job", "recent", "empty_shell"])
        XCTAssertEqual(containers[1].sizeBytes, 12_300_000)
        XCTAssertEqual(containers[0].state, "running")
        let entries = try DockerInventory.cacheEntries(from: cache)
        XCTAssertEqual(entries.map(\.id), [cacheID, liveCacheID], "the totals block has no ID and is not an entry")
        XCTAssertEqual(entries[0].sizeBytes, 512_000_000)
        XCTAssertEqual(entries[0].lastUsedDays, 42)
        XCTAssertTrue(entries[0].reclaimable)
        XCTAssertTrue(entries[0].description.hasPrefix("[stage-0 2/5] RUN apt-get"))
        XCTAssertThrowsError(try DockerInventory.images(from: Data("not json".utf8)))
    }

    func testRulesOfferUnusedOldImagesStoppedOldContainersAndIdleCacheOnly() throws {
        let candidates = DockerRules.candidates(images: try DockerInventory.images(from: images),
                                                containers: try DockerInventory.containers(from: containers),
                                                cache: try DockerInventory.cacheEntries(from: cache), now: now)
        XCTAssertEqual(candidates.map(\.removal), [.dockerImage(id: unusedID), .dockerBuildCache(id: cacheID), .dockerImage(id: danglingID), .dockerContainer(id: String(repeating: "2", count: 64))],
                       "node:20 is used by a running container, alpine:3.19 by stopped ones (docker image rm would refuse it), fresh is 2 days old, recent stopped 2 days ago, empty_shell has no layer of its own, the live cache step was used 2 hours ago; sorted by size")
        XCTAssertEqual(candidates.map(\.title)[2], "Untagged image bbbbbbbbbbbb")
        XCTAssertTrue(candidates[1].title.hasPrefix("Build cache: [stage-0 2/5] RUN apt-get update") && candidates[1].title.hasSuffix("…"), candidates[1].title)
        let python = try XCTUnwrap(candidates.first { $0.title == "python:3.12 image" })
        XCTAssertEqual(python.removal, .dockerImage(id: unusedID))
        XCTAssertEqual(python.bytes, 1_020_000_000)
        XCTAssertEqual(python.category, .docker)
        XCTAssertEqual(python.ownerBundleID, DockerRules.owner)
        XCTAssertTrue(python.reason.contains("60 days"), python.reason)
        XCTAssertTrue(python.reason.contains("No container"), python.reason)
        XCTAssertTrue(python.consequence.contains("permanent") && python.consequence.contains("Docker.raw"), python.consequence)
        XCTAssertEqual(python.stamp.digest, "docker-image:\(unusedID):1.02GB")
        let job = try XCTUnwrap(candidates.first { $0.title == "old_job container" })
        XCTAssertEqual(job.removal, .dockerContainer(id: String(repeating: "2", count: 64)))
        XCTAssertTrue(job.consequence.contains("olume"), "says volumes are untouched: \(job.consequence)")
        XCTAssertTrue(job.reason.contains("Exited (0) 5 weeks ago"), job.reason)
        let step = try XCTUnwrap(candidates.first { $0.removal == .dockerBuildCache(id: cacheID) })
        XCTAssertEqual(step.bytes, 512_000_000)
        XCTAssertTrue(step.reason.contains("42 days"), step.reason)
        for item in candidates {
            XCTAssertTrue(item.canTrash); XCTAssertNotNil(item.removal)
            XCTAssertTrue(item.url.path.hasPrefix("/docker/"), item.url.path)
            XCTAssertFalse(item.url.path.contains("volume"))
        }
    }

    func testScanIsQuietWithoutTheDaemonOrTheCommandAndReportsOtherFailures() async throws {
        let down = FakeDockerRunner(images: images, containers: containers, cache: cache)
        await down.fail(on: "image", with: .failed("docker image ls", 1, "Cannot connect to the Docker daemon at unix:///Users/x/.docker/run/docker.sock. Is the docker daemon running?"))
        let quiet = await DockerScan(runner: down, executable: "/usr/local/bin/docker").run(now: now)
        XCTAssertTrue(quiet.candidates.isEmpty); XCTAssertTrue(quiet.issues.isEmpty, "\(quiet.issues)")
        let absent = FakeDockerRunner(images: images, containers: containers, cache: cache)
        await absent.fail(on: "image", with: .missing("/usr/local/bin/docker"))
        let none = await DockerScan(runner: absent, executable: "/usr/local/bin/docker").run(now: now)
        XCTAssertTrue(none.candidates.isEmpty); XCTAssertTrue(none.issues.isEmpty)
        let broken = FakeDockerRunner(images: images, containers: containers, cache: cache)
        await broken.fail(on: "container", with: .failed("docker container ls", 2, "permission denied"))
        let reported = await DockerScan(runner: broken, executable: "/usr/local/bin/docker").run(now: now)
        XCTAssertTrue(reported.candidates.isEmpty)
        XCTAssertEqual(reported.issues.count, 1)
        XCTAssertTrue(reported.issues[0].message.contains("permission denied"))
        let noBuildx = FakeDockerRunner(images: images, containers: containers, cache: cache)
        await noBuildx.fail(on: "buildx", with: .failed("docker buildx du", 1, "docker: 'buildx' is not a docker command"))
        let partial = await DockerScan(runner: noBuildx, executable: "/usr/local/bin/docker").run(now: now)
        XCTAssertEqual(partial.candidates.count, 3, "images and containers are still offered without a build cache inventory")
        XCTAssertEqual(partial.issues.count, 1)
        let ok = await DockerScan(runner: FakeDockerRunner(images: images, containers: containers, cache: cache), executable: "/usr/local/bin/docker").run(now: now)
        XCTAssertEqual(ok.candidates.count, 4)
        XCTAssertTrue(ok.issues.isEmpty)
    }

    func testRemoverReListsFirstRunsOnePerItemCommandAndLeavesAChangedItemInPlace() async throws {
        let runner = FakeDockerRunner(images: images, containers: containers, cache: cache)
        let candidates = DockerRules.candidates(images: try DockerInventory.images(from: images),
                                                containers: try DockerInventory.containers(from: containers),
                                                cache: try DockerInventory.cacheEntries(from: cache), now: now)
        let python = try XCTUnwrap(candidates.first { $0.title == "python:3.12 image" })
        let remover = DockerRemover(runner: runner, executable: "/usr/local/bin/docker")
        let record = await remover.remove(python)
        XCTAssertNil(record.error, record.error ?? "")
        XCTAssertEqual(record.method, .tool)
        XCTAssertEqual(record.tool, "docker")
        XCTAssertEqual(record.bytes, python.bytes)
        let commands = await runner.commands
        XCTAssertEqual(commands.last?.arguments, ["image", "rm", unusedID])
        XCTAssertEqual(commands.count, 4, "three list commands, then the one removal")
        XCTAssertFalse(commands.contains { $0.arguments.contains("-f") || $0.arguments.contains("prune") && !$0.arguments.contains("--filter") })

        let stale = Candidate(url: python.url, title: python.title, category: .docker, reason: python.reason, consequence: python.consequence,
            stamp: .init(digest: "docker-image:\(unusedID):2.0GB", logicalBytes: 2_000_000_000, allocatedBytes: 2_000_000_000, fileCount: 0),
            allowedRoot: python.allowedRoot, canTrash: true, ownerBundleID: python.ownerBundleID, removal: python.removal)
        let changed = await remover.remove(stale)
        XCTAssertEqual(changed.failure, .changed)
        XCTAssertEqual(changed.bytes, 0)
        let after = await runner.commands
        XCTAssertFalse(after.suffix(3).contains { $0.arguments.first == "image" && $0.arguments[1] == "rm" }, "nothing removed when the item changed")

        let job = try XCTUnwrap(candidates.first { $0.title == "old_job container" })
        _ = await remover.remove(job)
        let step = try XCTUnwrap(candidates.first { $0.removal == .dockerBuildCache(id: cacheID) })
        _ = await remover.remove(step)
        let all = await runner.commands
        XCTAssertTrue(all.contains { $0.arguments == ["container", "rm", String(repeating: "2", count: 64)] }, "no -v, so volumes stay")
        XCTAssertTrue(all.contains { $0.arguments == ["buildx", "prune", "--force", "--filter", "id=\(cacheID)"] })
    }

    func testDockerIDsAreValidatedBeforeTheyBecomeArguments() throws {
        XCTAssertEqual(try ToolCommand.Catalogue.dockerID(usedID), usedID)
        XCTAssertEqual(try ToolCommand.Catalogue.dockerID("0123456789ab"), "0123456789ab")
        for bad in ["node:20", "../x", "sha256:" + String(repeating: "A", count: 64), "0123456789a", "", "-f", "--all", String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try ToolCommand.Catalogue.dockerID(bad), bad)
        }
        XCTAssertThrowsError(try ToolCommand.Catalogue.dockerImageRemove("/usr/local/bin/docker", id: "latest"))
        let every = ToolCommand.Catalogue.every
        XCTAssertTrue(every.contains { $0.arguments.starts(with: ["image", "rm"]) })
        XCTAssertFalse(every.contains { $0.arguments.contains("prune") && !$0.arguments.contains("--filter") }, "no bare prune exists anywhere")
        XCTAssertFalse(every.contains { $0.arguments.contains("volume") })
        XCTAssertFalse(every.contains { $0.arguments.contains("-f") || $0.arguments.contains("-v") })
    }

    func testToolRemoversRouteByKind() async throws {
        let runner = FakeDockerRunner(images: images, containers: containers, cache: cache)
        let removers = ToolRemovers(simulators: SimulatorRemover(runner: runner), docker: DockerRemover(runner: runner, executable: "/usr/local/bin/docker"))
        let candidates = DockerRules.candidates(images: try DockerInventory.images(from: images), containers: try DockerInventory.containers(from: containers), cache: [], now: now)
        let record = await removers.remove(try XCTUnwrap(candidates.first))
        XCTAssertNil(record.error, record.error ?? "")
        let plain = Candidate(url: URL(fileURLWithPath: "/fixture/cache"), title: "cache", category: .developer, reason: "", consequence: "",
            stamp: .init(digest: "x", logicalBytes: 1, allocatedBytes: 1, fileCount: 1), allowedRoot: URL(fileURLWithPath: "/fixture"), canTrash: true, ownerBundleID: nil)
        let refused = await removers.remove(plain)
        XCTAssertNotNil(refused.error, "a Trash item never reaches a tool")
    }
}

private actor FakeDockerRunner: ToolRunning {
    var commands: [ToolCommand] = []
    private let images: Data, containers: Data, cache: Data
    private var failure: (String, ToolCommand.ToolError)?
    init(images: Data, containers: Data, cache: Data) { self.images = images; self.containers = containers; self.cache = cache }
    func fail(on word: String, with error: ToolCommand.ToolError) { failure = (word, error) }
    func run(_ command: ToolCommand) throws -> Data {
        commands.append(command)
        if let failure, command.arguments.first == failure.0 { throw failure.1 }
        if command.arguments.starts(with: ["image", "ls"]) { return images }
        if command.arguments.starts(with: ["container", "ls"]) { return containers }
        if command.arguments.starts(with: ["buildx", "du"]) { return cache }
        return Data()
    }
}
