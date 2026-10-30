import XCTest
@testable import SafeCleanerCore

/// DerivedData was one all-or-nothing item: 31 GB in nine folders on the author's Mac, all
/// but two live. Per project, the user keeps what is being built and drops the rest. These
/// pin what each row says: the workspace it was built for, whether that still exists, when
/// it was last built, and that shared caches are named while unknown folders are left alone.
final class DerivedDataTests: XCTestCase {
    var home: URL!
    private let now = Date()
    private let big = String(repeating: "x", count: 8_192)
    private let quittyHash = "Quitty-abcdefghijklmnopqrstuvwxyzab"
    private let goneHash = "Gone-bcdefghijklmnopqrstuvwxyzabc"
    private let namelessHash = "Nameless-cdefghijklmnopqrstuvwxyzabcd"
    private let emptyHash = "Empty-defghijklmnopqrstuvwxyzabcde"

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerDerived-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private var derived: URL { home.appendingPathComponent("Library/Developer/Xcode/DerivedData") }
    private func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

    @discardableResult
    private func file(_ path: String, _ text: String = "synthetic derived data", modified: Date? = nil) throws -> URL {
        let url = derived.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path) }
        return url
    }
    private func plist(_ folder: String, workspace: String) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": workspace, "LastAccessedDate": now], format: .xml, options: 0)
        try FileManager.default.createDirectory(at: derived.appendingPathComponent(folder), withIntermediateDirectories: true)
        try data.write(to: derived.appendingPathComponent("\(folder)/info.plist"))
    }

    private func fixture() throws {
        let quitty = home.appendingPathComponent("projects/quitty/iosApp.xcodeproj")
        try FileManager.default.createDirectory(at: quitty, withIntermediateDirectories: true)
        try plist(quittyHash, workspace: quitty.path)
        try file("\(quittyHash)/Build/Products/Debug/iosApp.app/iosApp", big, modified: daysAgo(11))
        try file("\(quittyHash)/Logs/Build/latest.xcactivitylog", big, modified: daysAgo(3))
        try file("\(quittyHash)/Index.noindex/DataStore/units/x", big, modified: daysAgo(1))
        try plist(goneHash, workspace: home.appendingPathComponent("projects/gone/App.xcworkspace").path)
        try file("\(goneHash)/Build/Products/Debug/App", big, modified: daysAgo(40))
        try file("\(namelessHash)/Build/Products/Debug/Nameless", big, modified: daysAgo(5))
        try FileManager.default.createDirectory(at: derived.appendingPathComponent(emptyHash), withIntermediateDirectories: true)
        try file("ModuleCache.noindex/ABCDEF/Foundation.pcm", big)
        try file("SDKExplicitPrecompiledModules/x.pcm", big)
        try file("SymbolCache.noindex/x/y", big)
        try file("Unknown.noindex/data", big)
        try file("notes.txt")
    }

    func testProjectFoldersAreRecognisedByTheirHashSuffix() {
        XCTAssertTrue(DerivedData.isProjectFolder("iosApp-azaccffsrlnhjihdatilcgpznoub"))
        XCTAssertTrue(DerivedData.isProjectFolder("Pods-buxtyvknhruaoldtcxevhxedvknx"))
        XCTAssertTrue(DerivedData.isProjectFolder("my-app-azaccffsrlnhjihdatilcgpznoub"), "a project name may itself contain dashes")
        XCTAssertFalse(DerivedData.isProjectFolder("ModuleCache.noindex"))
        XCTAssertFalse(DerivedData.isProjectFolder("App-abc"), "a short suffix is not Xcode's hash")
        XCTAssertFalse(DerivedData.isProjectFolder("App-ABCDEFGHIJKLMNOPQRSTUVWXYZAB"), "Xcode's hash is lowercase")
        XCTAssertEqual(DerivedData.projectName("my-app-azaccffsrlnhjihdatilcgpznoub"), "my-app")
    }

    func testEachProjectFolderIsItsOwnFindingNamingWorkspaceExistenceAndLastBuild() throws {
        try fixture()
        let projects = DerivedData.findings(home: home, now: now).filter { $0.kind == .project }
        XCTAssertEqual(projects.map { $0.url.lastPathComponent }.sorted(), [emptyHash, goneHash, namelessHash, quittyHash].sorted())
        let quitty = try XCTUnwrap(projects.first { $0.url.lastPathComponent == quittyHash })
        XCTAssertEqual(quitty.title, "iosApp.xcodeproj build data")
        XCTAssertTrue(quitty.reason.contains("~/projects/quitty/iosApp.xcodeproj"), quitty.reason)
        XCTAssertTrue(quitty.reason.contains("3 days ago"), "the newest of Build and Logs decides, not the index: \(quitty.reason)")
        XCTAssertTrue(quitty.consequence.contains("iosApp.xcodeproj") && quitty.consequence.contains("Xcode"), quitty.consequence)
        XCTAssertEqual(quitty.root.path, derived.path)
        let gone = try XCTUnwrap(projects.first { $0.url.lastPathComponent == goneHash })
        XCTAssertEqual(gone.title, "App.xcworkspace build data")
        XCTAssertTrue(gone.reason.contains("no longer exists"), gone.reason)
        XCTAssertTrue(gone.reason.contains("40 days"), gone.reason)
        let nameless = try XCTUnwrap(projects.first { $0.url.lastPathComponent == namelessHash })
        XCTAssertEqual(nameless.title, "Nameless build data")
        XCTAssertTrue(nameless.reason.contains("info.plist"), nameless.reason)
        XCTAssertTrue(nameless.reason.contains("5 days ago"), nameless.reason)
        let empty = try XCTUnwrap(projects.first { $0.url.lastPathComponent == emptyHash })
        XCTAssertTrue(empty.reason.contains("No build products"), empty.reason)
    }

    func testSharedCachesAreOfferedByNameAndUnknownFoldersAreNot() throws {
        try fixture()
        let shared = DerivedData.findings(home: home, now: now).filter { $0.kind == .shared }
        XCTAssertEqual(shared.map { $0.url.lastPathComponent }.sorted(), ["ModuleCache.noindex", "SDKExplicitPrecompiledModules", "SymbolCache.noindex"])
        XCTAssertEqual(shared.first { $0.url.lastPathComponent == "ModuleCache.noindex" }?.title, "Xcode module cache")
        XCTAssertTrue(shared.allSatisfy { $0.consequence.contains("Xcode") })
        XCTAssertFalse(DerivedData.findings(home: home, now: now).contains { $0.url.lastPathComponent == "Unknown.noindex" })
        XCTAssertFalse(DerivedData.findings(home: home, now: now).contains { $0.url.lastPathComponent == "notes.txt" })
    }

    func testScannerOffersPerProjectItemsInsteadOfTheWholeFolder() throws {
        try fixture()
        let report = try DiskScanner().scan(configuration: .init(home: home))
        XCTAssertFalse(report.candidates.contains { FileSafety.isSame($0.url, derived) }, "the whole folder is no longer one item")
        let items = report.candidates.filter { FileSafety.isInside($0.url, root: derived) }
        XCTAssertEqual(Set(items.map(\.title)), ["iosApp.xcodeproj build data", "App.xcworkspace build data", "Nameless build data",
                                                 "Xcode module cache", "Xcode precompiled SDK modules", "Xcode symbol cache"],
                       "the empty project folder measures nothing and is not listed")
        for item in items {
            XCTAssertEqual(item.category, .developer)
            XCTAssertEqual(item.ownerBundleID, DerivedData.owner)
            XCTAssertEqual(item.allowedRoot.path, derived.path)
            XCTAssertTrue(item.canTrash); XCTAssertNil(item.removal)
        }
        let excluded = try DiskScanner().scan(configuration: .init(home: home, exclusions: [derived]))
        XCTAssertFalse(excluded.candidates.contains { FileSafety.isInside($0.url, root: derived) })
    }

    func testNothingIsOfferedWithoutADerivedDataFolder() {
        XCTAssertTrue(DerivedData.findings(home: home, now: now).isEmpty)
    }
}
