import XCTest
@testable import SafeCleanerCore

/// Xcode keeps several stores side by side per OS version or per build and retires none of
/// them. These tests pin what is kept: every entry of the newest OS version per platform,
/// device logs touched in the last 30 days, archives younger than 180 days, and anything
/// whose name carries no version at all.
final class XcodeStoresTests: XCTestCase {
    var home: URL!
    private let now = Date()
    private let big = String(repeating: "x", count: 8_192)

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerXcode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private var xcode: URL { home.appendingPathComponent("Library/Developer/Xcode") }
    private func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

    @discardableResult
    private func file(_ path: String, data: Data, modified: Date? = nil) throws -> URL {
        let url = xcode.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }
    @discardableResult
    private func file(_ path: String, _ text: String = "synthetic xcode fixture", modified: Date? = nil) throws -> URL {
        try file(path, data: Data(text.utf8), modified: modified)
    }
    private func archivePlist(name: String, created: Date, bundleID: String, version: String, build: String) throws -> Data {
        let plist: [String: Any] = ["ArchiveVersion": 2, "Name": name, "CreationDate": created,
            "ApplicationProperties": ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version, "CFBundleVersion": build]]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    private func fixture() throws {
        try file("iOS DeviceSupport/iPhone15,3 26.5.2 (23F84)/Symbols/usr/lib/dyld", big)
        try file("iOS DeviceSupport/iPad14,1 26.5.2 (23F84)/Symbols/usr/lib/dyld", big)
        try file("iOS DeviceSupport/17.2 (21C62) arm64e/Symbols/usr/lib/dyld", big)
        try file("iOS DeviceSupport/16.7.10 (20H350) arm64e/Symbols/usr/lib/dyld", big)
        try file("iOS DeviceSupport/Unknown folder/Symbols/usr/lib/dyld", big)
        try file("iOS DeviceSupport/notes.txt")
        try file("watchOS DeviceSupport/10.2 (21S364)/Symbols/usr/lib/dyld", big)
        try file("DocumentationCache/v3/15F31d/index.db", big)
        try file("DocumentationCache/v3/16A242d/index.db", big)
        try file("DocumentationCache/v3/README")
        try file("DeviceLogs/Moza 14Pro Max-00008120-000C10EC3CA0C01E/Other Logs/backupd-2026-09-15.ips", big, modified: daysAgo(45))
        try file("DeviceLogs/Moza 14Pro Max-00008120-000C10EC3CA0C01E/Unsymbolicated Logs/app.ips", big, modified: daysAgo(60))
        try file("DeviceLogs/Fresh-00008130-001A2B3C4D5E6F70/Other Logs/today.ips", big, modified: daysAgo(2))
        try file("iOS Device Logs/iPhone-abcdef0123456789abcdef0123456789abcdef01/old.crash", big, modified: daysAgo(400))
        try file("Archives/2026-01-10/Quitty 10.01.26, 12.00.xcarchive/Info.plist",
                 data: try archivePlist(name: "Quitty", created: daysAgo(293), bundleID: "com.quitty", version: "1.4.2", build: "87"))
        try file("Archives/2026-01-10/Quitty 10.01.26, 12.00.xcarchive/Products/Applications/Quitty.app/Quitty", big)
        try file("Archives/2026-01-10/Quitty 10.01.26, 12.00.xcarchive/dSYMs/Quitty.app.dSYM/Contents/Resources/DWARF/Quitty", big)
        try file("Archives/2026-10-02/Fresh 02.10.26, 16.55.xcarchive/Info.plist",
                 data: try archivePlist(name: "Fresh", created: daysAgo(28), bundleID: "com.fresh", version: "2.0", build: "3"))
        try file("Archives/2026-10-02/Fresh 02.10.26, 16.55.xcarchive/Products/Applications/Fresh.app/Fresh", big)
        try file("Archives/2025-03-01/NoPlist 01.03.25, 09.00.xcarchive/Products/Applications/NoPlist.app/NoPlist", big)
        try file("Archives/notes.txt")
        try FileManager.default.createDirectory(at: xcode.appendingPathComponent("Archives/2026-07-15"), withIntermediateDirectories: true)
        try file("DerivedData/App-abc/Build/Products/Debug/App.app/App", big)
        try file("UserData/Provisioning Profiles/x.mobileprovision", big)
    }

    func testVersionAndBuildAreReadFromDeviceSupportFolderNames() {
        XCTAssertEqual(XcodeStores.version(in: "iPhone15,3 26.5.2 (23F84)"), [26, 5, 2])
        XCTAssertEqual(XcodeStores.version(in: "17.2 (21C62) arm64e"), [17, 2])
        XCTAssertEqual(XcodeStores.version(in: "16.7.10 (20H350) arm64e"), [16, 7, 10])
        XCTAssertNil(XcodeStores.version(in: "Unknown folder"))
        XCTAssertNil(XcodeStores.version(in: "iPhone15,3"), "a model identifier is not a version")
        XCTAssertEqual(XcodeStores.build(in: "iPhone15,3 26.5.2 (23F84)"), "23F84")
        XCTAssertNil(XcodeStores.build(in: "17.2 arm64e"))
    }

    func testDeviceSupportKeepsEveryEntryOfTheNewestVersionPerPlatform() throws {
        try fixture()
        let symbols = XcodeStores.findings(home: home, now: now).filter { $0.kind == .deviceSupport }
        XCTAssertEqual(symbols.map { $0.url.lastPathComponent }.sorted(), ["16.7.10 (20H350) arm64e", "17.2 (21C62) arm64e"],
                       "both 26.5.2 entries are the newest version and stay; watchOS has a single version; unversioned names are skipped")
        let seventeen = try XCTUnwrap(symbols.first { $0.url.lastPathComponent.hasPrefix("17.2") })
        XCTAssertEqual(seventeen.title, "iOS 17.2 device symbols")
        XCTAssertTrue(seventeen.reason.contains("26.5.2"), "names the version that is kept: \(seventeen.reason)")
        XCTAssertTrue(seventeen.reason.contains("21C62"))
        XCTAssertTrue(seventeen.consequence.contains("Xcode"))
        XCTAssertEqual(seventeen.root.path, xcode.path)
    }

    func testDocumentationIndexesAreAllOfferedAndFilesBesideThemAreNot() throws {
        try fixture()
        let docs = XcodeStores.findings(home: home, now: now).filter { $0.kind == .documentation }
        XCTAssertEqual(docs.map { $0.url.lastPathComponent }.sorted(), ["15F31d", "16A242d"])
        XCTAssertTrue(docs.allSatisfy { $0.title.contains("documentation") })
        XCTAssertTrue(docs.allSatisfy { $0.consequence.contains("rebuilds") }, "\(docs.map(\.consequence))")
    }

    func testDeviceLogsAreOfferedPerDeviceOnceIdleForThirtyDays() throws {
        try fixture()
        let logs = XcodeStores.findings(home: home, now: now).filter { $0.kind == .deviceLogs }
        XCTAssertEqual(logs.map(\.title).sorted(), ["Moza 14Pro Max device logs", "iPhone device logs"],
                       "the device with a two-day-old report is kept; the UDID suffix is stripped from the name")
        let moza = try XCTUnwrap(logs.first { $0.title.hasPrefix("Moza") })
        XCTAssertTrue(moza.reason.contains("45 days"), "the newest report decides: \(moza.reason)")
        XCTAssertEqual(moza.url.lastPathComponent, "Moza 14Pro Max-00008120-000C10EC3CA0C01E")
    }

    func testArchivesAreOfferedOnlyAfterTheKeepPeriodAndNameTheirBuild() throws {
        try fixture()
        let archives = XcodeStores.findings(home: home, now: now).filter { $0.kind == .archive }
        XCTAssertEqual(archives.map { $0.url.lastPathComponent }.sorted(),
                       ["NoPlist 01.03.25, 09.00.xcarchive", "Quitty 10.01.26, 12.00.xcarchive"],
                       "the 28-day-old archive is kept; the empty date folder and the loose file are not findings")
        let quitty = try XCTUnwrap(archives.first { $0.url.lastPathComponent.hasPrefix("Quitty") })
        XCTAssertEqual(quitty.title, "Xcode archive Quitty 10.01.26, 12.00")
        XCTAssertTrue(quitty.reason.contains("Quitty 1.4.2 (87)"), quitty.reason)
        XCTAssertTrue(quitty.reason.contains("com.quitty"), quitty.reason)
        XCTAssertTrue(quitty.reason.contains("293 days"), quitty.reason)
        XCTAssertTrue(quitty.consequence.contains("symbolicat"), "says what is lost: \(quitty.consequence)")
        let noPlist = try XCTUnwrap(archives.first { $0.url.lastPathComponent.hasPrefix("NoPlist") })
        XCTAssertTrue(noPlist.reason.contains("days ago"), "the date comes from the folder name: \(noPlist.reason)")
        XCTAssertFalse(archives.contains { $0.url.lastPathComponent.hasPrefix("2026-") }, "never a whole date folder")
    }

    func testScannerListsXcodeStoresAsTrashCandidatesOwnedByXcodeAndRespectsExclusions() throws {
        try fixture()
        let report = try DiskScanner().scan(configuration: .init(home: home))
        let items = report.candidates.filter { $0.category == .xcode }
        XCTAssertEqual(Set(items.map(\.title)), ["iOS 17.2 device symbols", "iOS 16.7.10 device symbols",
            "Xcode documentation cache 15F31d", "Xcode documentation cache 16A242d",
            "Moza 14Pro Max device logs", "iPhone device logs",
            "Xcode archive Quitty 10.01.26, 12.00", "Xcode archive NoPlist 01.03.25, 09.00"])
        for item in items {
            XCTAssertTrue(item.canTrash); XCTAssertNil(item.removal)
            XCTAssertEqual(item.ownerBundleID, XcodeStores.owner)
            XCTAssertEqual(item.allowedRoot.path, xcode.path)
            XCTAssertGreaterThan(item.bytes, 0)
        }
        XCTAssertTrue(report.candidates.contains { $0.title == "Xcode DerivedData" }, "the existing rule is untouched")
        XCTAssertFalse(report.candidates.contains { $0.url.path.contains("Provisioning Profiles") })
        let excluded = try DiskScanner().scan(configuration: .init(home: home, exclusions: [xcode.appendingPathComponent("iOS DeviceSupport")]))
        XCTAssertFalse(excluded.candidates.contains { $0.title.hasSuffix("device symbols") })
    }

    func testNothingIsOfferedWithoutAnXcodeFolderOrWithAnEmptyOne() throws {
        XCTAssertTrue(XcodeStores.findings(home: home, now: now).isEmpty)
        try FileManager.default.createDirectory(at: xcode.appendingPathComponent("iOS DeviceSupport"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xcode.appendingPathComponent("Archives/2026-07-15"), withIntermediateDirectories: true)
        XCTAssertTrue(XcodeStores.findings(home: home, now: now).isEmpty)
        XCTAssertTrue(try DiskScanner().scan(configuration: .init(home: home)).candidates.filter { $0.category == .xcode }.isEmpty)
    }
}
