import XCTest
@testable import SafeCleanerCore

/// Android SDK stores are plain directories that SDK Manager "uninstalls" by deleting, so
/// they take the Trash path. These tests pin what is kept: anything a project or a virtual
/// device still names, the newest NDK, a running emulator's snapshots, and user data always.
final class AndroidSDKTests: XCTestCase {
    var home: URL!
    private var outside: URL?
    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerAndroid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: home)
        if let outside { try? FileManager.default.removeItem(at: outside) }
    }
    @discardableResult private func file(_ path: String, data: String = "synthetic android fixture") throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(data.utf8).write(to: url)
        return url
    }
    private var sdk: URL { home.appendingPathComponent("Library/Android/sdk") }
    private var projects: URL { home.appendingPathComponent("projects") }
    private let big = String(repeating: "x", count: 8_192)

    private func fixture() throws {
        try file("Library/Android/sdk/ndk/25.1.8937393/source.properties", data: "Pkg.Revision = 25.1.8937393")
        try file("Library/Android/sdk/ndk/25.1.8937393/toolchains/llvm/bin/clang", data: big)
        try file("Library/Android/sdk/ndk/27.0.12077973/source.properties", data: big)
        try file("Library/Android/sdk/ndk/28.2.13676358/source.properties", data: big)
        try file("Library/Android/sdk/system-images/android-35/google_apis_playstore_tablet/arm64-v8a/system.img", data: big)
        try file("Library/Android/sdk/system-images/android-37.0/google_apis_playstore_ps16k/arm64-v8a/system.img", data: big)
        try file("Library/Android/sdk/system-images/android-36/google_apis/arm64-v8a/notes.txt", data: "no system.img here")
        try file(".android/avd/Pixel_9_Pro.avd/config.ini", data: "avd.ini.encoding=UTF-8\nimage.sysdir.1=system-images/android-37.0/google_apis_playstore_ps16k/arm64-v8a/\n")
        try file(".android/avd/Pixel_9_Pro.avd/snapshots/default_boot/ram.img", data: big)
        try file(".android/avd/Pixel_9_Pro.avd/userdata-qemu.img.qcow2", data: big)
        try file(".android/avd/Pixel_9_Pro.avd/sdcard.img", data: big)
        try file(".android/avd/Pixel_9_Pro.avd/multiinstance.lock", data: "")
        try file(".android/avd/Wear.avd/config.ini", data: "image.sysdir.1=system-images/android-37.0/google_apis_playstore_ps16k/arm64-v8a/\n")
        try file(".android/avd/Wear.avd/snapshots/default_boot/ram.img", data: big)
        try file(".android/avd/Wear.avd/hardware-qemu.ini.lock", data: "4242")
        try file(".android/avd/Fresh.avd/config.ini", data: "image.sysdir.1=system-images/android-35/google_apis/x86_64/\n")
        try file("projects/app/build.gradle.kts", data: "android {\n    ndkVersion = \"27.0.12077973\"\n    // ndkVersion = \"25.1.8937393\" (old)\n}\n")
        try file("projects/app/local.properties", data: "sdk.dir=\(home.path)/Library/Android/sdk\n")
        try file("projects/app/build/intermediates/build.gradle", data: "ndkVersion \"25.1.8937393\"")
        try file("projects/flutterapp/pubspec.yaml", data: "name: flutterapp")
        try file("projects/flutterapp/android/app/build.gradle.kts", data: "android {\n    ndkVersion = flutter.ndkVersion\n}\n")
    }

    func testReferencesComeFromGradleFilesLocalPropertiesAndDeviceConfigs() throws {
        try fixture()
        let refs = AndroidSDK.references(projects: [projects.appendingPathComponent("app"), projects.appendingPathComponent("flutterapp")],
                                         avdRoot: AndroidSDK.avdRoot(home: home))
        XCTAssertEqual(refs.ndkVersions, ["27.0.12077973"], "the commented and the build/-nested versions are not references")
        XCTAssertTrue(refs.unresolvedNDK, "flutter.ndkVersion cannot be resolved and must be said so")
        XCTAssertEqual(refs.imageDirectories, ["android-37.0/google_apis_playstore_ps16k/arm64-v8a", "android-35/google_apis/x86_64"])
        XCTAssertEqual(refs.sdkRoots.map(\.path), [sdk.path])
    }

    func testNDKKeepsTheNewestAndEveryNamedVersionAndOffersTheRest() throws {
        try fixture()
        var issues: [ScanIssue] = []
        let refs = AndroidSDK.references(projects: [projects.appendingPathComponent("app"), projects.appendingPathComponent("flutterapp")], avdRoot: AndroidSDK.avdRoot(home: home))
        let ndk = AndroidSDK.findings(home: home, references: refs, issues: &issues).filter { $0.kind == .ndk }
        XCTAssertEqual(ndk.map { $0.url.lastPathComponent }, ["25.1.8937393"])
        XCTAssertEqual(ndk.first?.root.path, sdk.path)
        XCTAssertTrue(ndk.first?.reason.contains("28.2.13676358") == true, "says which version is kept")
        XCTAssertTrue(ndk.first?.reason.contains("Flutter") == true, "says a version was not resolved")
        XCTAssertTrue(ndk.first?.consequence.contains("Trash") == true)
        var named = refs; named.ndkVersions.insert("25.1")
        XCTAssertTrue(AndroidSDK.findings(home: home, references: named, issues: &issues).filter { $0.kind == .ndk }.isEmpty, "a prefix reference keeps the version")
    }

    func testSystemImagesAreOfferedOnlyWhenNoDeviceUsesThemAndOnlyRealImages() throws {
        try fixture()
        var issues: [ScanIssue] = []
        let refs = AndroidSDK.references(projects: [], avdRoot: AndroidSDK.avdRoot(home: home))
        let images = AndroidSDK.findings(home: home, references: refs, issues: &issues).filter { $0.kind == .systemImage }
        XCTAssertEqual(images.map { $0.url.path.replacingOccurrences(of: sdk.path + "/system-images/", with: "") },
                       ["android-35/google_apis_playstore_tablet/arm64-v8a"])
        XCTAssertTrue(images.first?.title.contains("android-35") == true)
    }

    func testSnapshotsAreOfferedOnlyForStoppedEmulatorsAndUserDataIsNeverListed() throws {
        try fixture()
        var issues: [ScanIssue] = []
        let findings = AndroidSDK.findings(home: home, references: .init(), issues: &issues)
        let snapshots = findings.filter { $0.kind == .snapshots }
        XCTAssertEqual(snapshots.map(\.title), ["Pixel_9_Pro emulator snapshots"])
        XCTAssertEqual(snapshots.first?.url.path, home.appendingPathComponent(".android/avd/Pixel_9_Pro.avd/snapshots").path)
        XCTAssertEqual(snapshots.first?.root.path, home.appendingPathComponent(".android/avd/Pixel_9_Pro.avd").path)
        XCTAssertTrue(issues.contains { $0.message.contains("Wear") && $0.message.contains("running") }, "\(issues)")
        for finding in findings {
            XCTAssertFalse(finding.url.path.contains("userdata"), finding.url.path)
            XCTAssertFalse(finding.url.path.contains("sdcard"), finding.url.path)
            XCTAssertFalse(finding.url.path.hasSuffix(".avd"), "never the device itself")
        }
    }

    func testScannerListsAndroidItemsAsCleanableWithStudioAsOwnerAndRespectsExclusions() throws {
        try fixture()
        let report = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [projects]))
        let android = report.candidates.filter { $0.category == .android }
        XCTAssertEqual(Set(android.map(\.title)), ["Android NDK 25.1.8937393",
            "Android system image android-35 · google_apis_playstore_tablet · arm64-v8a", "Pixel_9_Pro emulator snapshots"])
        for item in android {
            XCTAssertTrue(item.canTrash); XCTAssertNil(item.removal)
            XCTAssertEqual(item.ownerBundleID, AndroidSDK.owner)
            XCTAssertGreaterThan(item.bytes, 0)
        }
        XCTAssertEqual(android.first { $0.title.hasPrefix("Android NDK") }?.allowedRoot.path, sdk.path)
        XCTAssertFalse(report.candidates.contains { $0.url.path.contains("userdata") })
        let excluded = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [projects],
                                                                    exclusions: [sdk.appendingPathComponent("ndk")]))
        XCTAssertFalse(excluded.candidates.contains { $0.category == .android && $0.title.hasPrefix("Android NDK") })
    }

    func testAnSDKOutsideHomeIsReportedNotScanned() throws {
        let other = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerAndroidOutside-\(UUID().uuidString)")
        outside = other
        try FileManager.default.createDirectory(at: other.appendingPathComponent("ndk/26.1.10909125"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other.appendingPathComponent("ndk/27.0.12077973"), withIntermediateDirectories: true)
        var refs = AndroidSDK.References(); refs.sdkRoots = [other]
        var issues: [ScanIssue] = []
        XCTAssertTrue(AndroidSDK.findings(home: home, references: refs, issues: &issues).isEmpty)
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].message.contains("outside"))
    }
}
