import XCTest
@testable import SafeCleanerCore

/// JetBrains IDEs and Android Studio keep one cache folder per version and retire none: three
/// Android Studio versions held 12 GB on the author's Mac. These pin that the newest version
/// of each product is kept, older ones are offered one by one, siblings that are not
/// versioned (Chrome's cache lives in the same Google folder) keep their own rows so nothing
/// disappears from the picture, and editor caches are offered without ever touching settings.
final class IDECachesTests: XCTestCase {
    var home: URL!
    private let big = String(repeating: "x", count: 8_192)

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerIDE-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private var caches: URL { home.appendingPathComponent("Library/Caches") }
    private var support: URL { home.appendingPathComponent("Library/Application Support") }

    @discardableResult
    private func file(_ path: String, _ text: String = "synthetic ide cache") throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func fixture() throws {
        try file("Library/Caches/Google/AndroidStudio2025.3.4/caches/x", big)
        try file("Library/Caches/Google/AndroidStudio2026.1.4/caches/x", big)
        try file("Library/Caches/Google/AndroidStudio2026.2.1/caches/x", big)
        try file("Library/Caches/Google/AndroidStudioPreview2026.3/caches/x", big)
        try file("Library/Caches/Google/Chrome/Default/Cache/x", big)
        try file("Library/Caches/Google/notes.txt")
        try file("Library/Caches/JetBrains/IntelliJIdea2024.3/x", big)
        try file("Library/Caches/JetBrains/IntelliJIdea2025.3/x", big)
        try file("Library/Caches/JetBrains/WebStorm2025.1/x", big)
        try file("Library/Caches/JetBrains/Toolbox/x", big)
        try file("Library/Caches/com.example.other/x", big)
        try file("Library/Application Support/Code/Cache/x", big)
        try file("Library/Application Support/Code/CachedData/x", big)
        try file("Library/Application Support/Code/Service Worker/CacheStorage/x", big)
        try file("Library/Application Support/Code/User/settings.json", "{}")
        try file("Library/Application Support/Code/workspaceStorage/a/state.vscdb", big)
        try file("Library/Application Support/Code/extensions/ext/x", big)
        try file("Library/Application Support/Cursor/GPUCache/x", big)
        try file("Library/Application Support/Cursor/User/settings.json", "{}")
    }

    func testProductAndVersionAreParsedFromFolderNames() throws {
        let studio = try XCTUnwrap(IDECaches.productVersion("AndroidStudio2025.3.4"))
        XCTAssertEqual(studio.product.name, "Android Studio"); XCTAssertEqual(studio.version, [2025, 3, 4])
        XCTAssertEqual(studio.product.owner, "com.google.android.studio")
        XCTAssertEqual(IDECaches.productVersion("AndroidStudioPreview2026.3")?.product.name, "Android Studio Preview",
                       "the preview is its own product, not an older Android Studio")
        XCTAssertEqual(IDECaches.productVersion("IntelliJIdea2025.3")?.product.owner, "com.jetbrains.intellij")
        XCTAssertEqual(IDECaches.productVersion("PyCharmCE2025.1")?.product.name, "PyCharm CE", "longest prefix wins")
        XCTAssertNil(IDECaches.productVersion("Chrome"))
        XCTAssertNil(IDECaches.productVersion("AndroidStudio"), "no version, not a per-version cache")
        XCTAssertNil(IDECaches.productVersion("WebStorm2025.1-backup"), "a suffix after the version is not Xcode's naming")
    }

    func testOlderVersionsAreOfferedAndTheNewestPerProductIsKept() throws {
        try fixture()
        let older = IDECaches.findings(home: home).filter { $0.kind == .olderVersion }
        XCTAssertEqual(older.map { $0.url.lastPathComponent }.sorted(), ["AndroidStudio2025.3.4", "AndroidStudio2026.1.4", "IntelliJIdea2024.3"],
                       "2026.2.1, the preview, 2025.3 and WebStorm are each the newest of their product")
        let studio = try XCTUnwrap(older.first { $0.url.lastPathComponent == "AndroidStudio2025.3.4" })
        XCTAssertEqual(studio.title, "Android Studio 2025.3.4 cache")
        XCTAssertTrue(studio.reason.contains("2026.2.1"), "names the version that is kept: \(studio.reason)")
        XCTAssertEqual(studio.owner, "com.google.android.studio")
        XCTAssertEqual(studio.category, .applications)
        XCTAssertEqual(studio.vendor, "Google")
        XCTAssertEqual(studio.root.path, caches.path)
        XCTAssertTrue(studio.consequence.contains("Android Studio"))
    }

    func testVendorChildrenThatAreNotVersionedKeepTheirOwnRows() throws {
        try fixture()
        let children = IDECaches.findings(home: home).filter { $0.kind == .vendorChild }
        XCTAssertEqual(children.map(\.title).sorted(), ["Google/Chrome", "JetBrains/Toolbox"], "the loose file is not a row")
        let chrome = try XCTUnwrap(children.first { $0.title == "Google/Chrome" })
        XCTAssertEqual(chrome.category, .browsers); XCTAssertEqual(chrome.owner, "com.google.Chrome"); XCTAssertEqual(chrome.vendor, "Google")
        let toolbox = try XCTUnwrap(children.first { $0.title == "JetBrains/Toolbox" })
        XCTAssertEqual(toolbox.category, .applications); XCTAssertNil(toolbox.owner); XCTAssertEqual(toolbox.vendor, "JetBrains")
    }

    func testEditorCachesAreOfferedAndSettingsExtensionsAndWorkspaceStateNever() throws {
        try fixture()
        let editors = IDECaches.findings(home: home).filter { $0.kind == .editorCache }
        XCTAssertEqual(editors.map(\.title).sorted(), ["Cursor GPUCache", "VS Code Cache", "VS Code CachedData", "VS Code Service Worker/CacheStorage"])
        for finding in editors {
            XCTAssertFalse(finding.url.path.contains("/User"), finding.url.path)
            XCTAssertFalse(finding.url.path.contains("workspaceStorage"), finding.url.path)
            XCTAssertFalse(finding.url.path.contains("extensions"), finding.url.path)
            XCTAssertNil(finding.vendor)
            XCTAssertEqual(finding.category, .applications)
        }
        XCTAssertEqual(editors.first { $0.title == "VS Code Cache" }?.owner, "com.microsoft.VSCode")
        XCTAssertEqual(editors.first { $0.title == "VS Code Cache" }?.root.path, support.appendingPathComponent("Code").path)
        XCTAssertEqual(editors.first { $0.title == "Cursor GPUCache" }?.owner, "com.todesktop.230313mzl4w4u92")
    }

    func testScannerReplacesVendorFoldersWithTheirChildrenAndKeepsOtherCaches() throws {
        try fixture()
        let report = try DiskScanner().scan(configuration: .init(home: home))
        for vendor in ["Google", "JetBrains"] {
            XCTAssertFalse(report.candidates.contains { FileSafety.isSame($0.url, caches.appendingPathComponent(vendor)) }, "\(vendor) is no longer one item")
        }
        let titles = Set(report.candidates.map(\.title))
        for expected in ["Android Studio 2025.3.4 cache", "Android Studio 2026.1.4 cache", "IntelliJ IDEA 2024.3 cache",
                         "Google/Chrome", "JetBrains/Toolbox", "VS Code CachedData", "Cursor GPUCache", "com.example.other"] {
            XCTAssertTrue(titles.contains(expected), "missing \(expected) in \(titles.sorted())")
        }
        XCTAssertFalse(report.candidates.contains { $0.url.lastPathComponent == "AndroidStudio2026.2.1" }, "the newest version is kept")
        XCTAssertEqual(report.candidates.first { $0.title == "Google/Chrome" }?.category, .browsers)
        XCTAssertEqual(report.candidates.first { $0.title == "Android Studio 2025.3.4 cache" }?.ownerBundleID, "com.google.android.studio")
        XCTAssertEqual(report.candidates.first { $0.title == "Android Studio 2025.3.4 cache" }?.allowedRoot.path, caches.path)
        let excluded = try DiskScanner().scan(configuration: .init(home: home, exclusions: [caches.appendingPathComponent("Google")]))
        XCTAssertFalse(excluded.candidates.contains { FileSafety.isInside($0.url, root: caches.appendingPathComponent("Google")) })
    }

    func testAVendorFolderWithOnlyOneVersionAndNoOtherChildrenStaysASingleRow() throws {
        try file("Library/Caches/JetBrains/IntelliJIdea2025.3/x", big)
        XCTAssertTrue(IDECaches.findings(home: home).isEmpty, "nothing to split: the newest version is kept and there is nothing else")
        let report = try DiskScanner().scan(configuration: .init(home: home))
        XCTAssertTrue(report.candidates.contains { FileSafety.isSame($0.url, caches.appendingPathComponent("JetBrains")) },
                      "with no per-version finding the folder keeps its ordinary row, so the bytes stay visible")
    }
}
