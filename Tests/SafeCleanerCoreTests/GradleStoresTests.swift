import XCTest
@testable import SafeCleanerCore

/// Gradle and Kotlin/Native keep one store per version and retire none of them. These tests
/// pin what is kept: every version a project under the chosen folders names, the newest
/// installed version, the shared dependency caches (`modules-2`, `build-cache-1`, `jars-*`),
/// configuration, provisioned JDKs, and the tool homes themselves. A project outside the
/// chosen folders is never consulted, so its versions are offered.
final class GradleStoresTests: XCTestCase {
    var home: URL!
    private let big = String(repeating: "x", count: 8_192)

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("SafeCleanerGradle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private var gradle: URL { home.appendingPathComponent(".gradle") }
    private var konan: URL { home.appendingPathComponent(".konan") }
    private var projects: URL { home.appendingPathComponent("projects") }
    private var roots: [URL] { ["appA", "appB", "appC", "appD"].map { projects.appendingPathComponent($0) } }

    @discardableResult
    private func file(_ path: String, _ text: String = "synthetic gradle fixture") throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
    private func directory(_ path: String) throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    private func wrapper(_ version: String, type: String = "bin") -> String {
        "distributionBase=GRADLE_USER_HOME\ndistributionPath=wrapper/dists\ndistributionUrl=https\\://services.gradle.org/distributions/gradle-\(version)-\(type).zip\nzipStoreBase=GRADLE_USER_HOME\n"
    }
    private func konanProperties(llvm: String) -> String {
        "# synthetic\nllvm.macos_arm64.dev=\(llvm.replacingOccurrences(of: "essentials", with: "dev"))\nllvm.macos_arm64.user=\(llvm)\nllvmHome.macos_arm64 = $llvm.macos_arm64.user\nlibffiDir.macos_arm64 = libffi-3.3-1-macos-arm64\ndependencies.macos_arm64 = \\\n    lldb-4-macos\n"
    }

    /// Installed: Gradle 8.14, 8.14.3, 9.0.0-rc-1, 9.2.1, 9.5.1 (caches), 8.14, 8.14.3, 9.7.1 (distributions),
    /// 5.4.1, 8.14.3, 9.0.0, 9.2.1 (daemons); Kotlin/Native 2.2.0, 2.2.10, 2.2.20, 2.3.0, 2.3.20, 2.4.0, 2.4.10
    /// for Apple silicon and 1.9.24 for Intel. Projects in the roots name Gradle 8.14 and 9.2.1 and
    /// Kotlin 2.2.10, 2.3.0, 2.3.20 and 2.4.0. The project outside the roots names Gradle 9.5.1 and Kotlin 2.2.20.
    private func fixture() throws {
        // Gradle user home.
        try file(".gradle/caches/8.14/fileHashes/fileHashes.bin", big)
        try file(".gradle/caches/8.14.3/transforms/abc/transformed/lib.jar", big)
        try file(".gradle/caches/9.0.0-rc-1/kotlin-dsl/scripts/x.bin", big)
        try file(".gradle/caches/9.2.1/fileHashes/fileHashes.bin", big)
        try file(".gradle/caches/9.5.1/fileHashes/fileHashes.bin", big)
        try file(".gradle/caches/modules-2/files-2.1/org.example/lib/1.0/lib.jar", big)
        try file(".gradle/caches/build-cache-1/0123456789abcdef", big)
        try file(".gradle/caches/jars-9/abc/lib.jar", big)
        try file(".gradle/caches/journal-1/file-access.bin", big)
        try file(".gradle/caches/CACHEDIR.TAG", "Signature: 8a477f597d28d172789f06886806bc55")
        try file(".gradle/wrapper/dists/gradle-8.14-all/abc123/gradle-8.14/lib/gradle-core.jar", big)
        try file(".gradle/wrapper/dists/gradle-8.14.3-bin/def456/gradle-8.14.3/lib/gradle-core.jar", big)
        try file(".gradle/wrapper/dists/gradle-9.7.1-bin/ghi789/gradle-9.7.1/lib/gradle-core.jar", big)
        try file(".gradle/wrapper/dists/gradle-9.7.1-all/jkl012/gradle-9.7.1/lib/gradle-core.jar", big)
        try file(".gradle/wrapper/dists/CACHEDIR.TAG", "Signature: 8a477f597d28d172789f06886806bc55")
        try file(".gradle/daemon/5.4.1/registry.bin", big)
        try file(".gradle/daemon/8.14.3/daemon-4242.out.log", big)
        try directory(".gradle/daemon/9.0.0")
        try file(".gradle/daemon/9.2.1/daemon-1.out.log", big)
        try file(".gradle/.tmp/configuration-cache-report1.html", big)
        try file(".gradle/gradle.properties", "org.gradle.jvmargs=-Xmx4g\n")
        try file(".gradle/init.d/common.gradle", "allprojects {}\n")
        try file(".gradle/jdks/jdk-17.0.2/Contents/Home/bin/java", big)
        try file(".gradle/kotlin-profile/2026-10-30.profile", big)
        try file(".gradle/native/25/osx-aarch64/libnative.dylib", big)
        try file(".gradle/notifications/9.7.1/release-features.rendered", "")
        // Kotlin/Native home.
        for (version, llvm) in [("2.2.0", "llvm-19-aarch64-macos-essentials-74"), ("2.2.10", "llvm-19-aarch64-macos-essentials-79"),
                                ("2.2.20", "llvm-19-aarch64-macos-essentials-79"), ("2.3.0", "llvm-19-aarch64-macos-essentials-81"),
                                ("2.3.20", "llvm-19-aarch64-macos-essentials-81"), ("2.4.0", "llvm-21-aarch64-macos-essentials-97"),
                                ("2.4.10", "llvm-21-aarch64-macos-essentials-97")] {
            try file(".konan/kotlin-native-prebuilt-macos-aarch64-\(version)/konan/konan.properties", konanProperties(llvm: llvm))
            try file(".konan/kotlin-native-prebuilt-macos-aarch64-\(version)/bin/kotlinc-native", big)
        }
        try file(".konan/kotlin-native-prebuilt-macos-x86_64-1.9.24/konan/konan.properties", konanProperties(llvm: "llvm-11-x86_64-macos-essentials-50"))
        try file(".konan/kotlin-native-prebuilt-macos-x86_64-1.9.24/bin/kotlinc-native", big)
        for dependency in ["llvm-19-aarch64-macos-essentials-74", "llvm-19-aarch64-macos-essentials-79", "llvm-19-aarch64-macos-essentials-81",
                           "llvm-21-aarch64-macos-essentials-97", "libffi-3.3-1-macos-arm64", "lldb-4-macos", "target-sysroot-xcode_15.0_15A240d-macosx"] {
            try file(".konan/dependencies/\(dependency)/bin/tool", big)
        }
        try file(".konan/dependencies/cache/llvm-19-aarch64-macos-essentials-74.tar.gz", big)
        try file(".konan/dependencies/.extracted", "llvm-19-aarch64-macos-essentials-74\nlibffi-3.3-1-macos-arm64\n")
        // Projects inside the roots.
        try file("projects/appA/build.gradle.kts", "plugins { id(\"com.android.application\") }\n")
        try file("projects/appA/gradle/wrapper/gradle-wrapper.properties", wrapper("8.14", type: "all"))
        try file("projects/appB/build.gradle.kts", "plugins {\n    kotlin(\"multiplatform\") version \"2.3.0\"\n    // kotlin(\"multiplatform\") version \"2.2.0\"\n}\n")
        try file("projects/appB/gradle/wrapper/gradle-wrapper.properties", wrapper("9.2.1"))
        try file("projects/appB/gradle/libs.versions.toml", "[versions]\nkotlin = \"2.4.0\"\nkotlinx-coroutines = \"1.10.2\"\nagp = \"9.0.0\"\n\n[libraries]\ncoroutines = { module = \"org.jetbrains.kotlinx:kotlinx-coroutines-core\", version.ref = \"kotlinx-coroutines\" }\n")
        try file("projects/appB/build/generated/gradle/wrapper/gradle-wrapper.properties", wrapper("8.14.3"))
        try file("projects/appC/build.gradle", "plugins {\n    id 'org.jetbrains.kotlin.jvm' version '2.3.20' apply false\n}\n")
        try file("projects/appC/gradle.properties", "kotlin.version=2.2.10\nkotlin.code.style=official\nkotlin.incremental=true\norg.gradle.jvmargs=-Xmx2g\n")
        try file("projects/appD/build.gradle.kts", "plugins {\n    kotlin(\"jvm\") version kotlinVersion\n}\n")
        try file("projects/appD/gradle/wrapper/gradle-wrapper.properties", "distributionUrl=https\\://example.com/internal/gradle-enterprise.zip\n")
        // A project outside the roots is never consulted.
        try file("outside/appX/build.gradle.kts", "plugins { kotlin(\"multiplatform\") version \"2.2.20\" }\n")
        try file("outside/appX/gradle/wrapper/gradle-wrapper.properties", wrapper("9.5.1"))
    }

    private func findings(_ refs: GradleStores.References? = nil) throws -> (findings: [GradleStores.Finding], issues: [ScanIssue]) {
        var issues: [ScanIssue] = []
        let references = refs ?? GradleStores.references(projects: roots)
        return (GradleStores.findings(home: home, references: references, issues: &issues), issues)
    }
    private func relative(_ url: URL, to root: URL) -> String {
        url.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    // MARK: Names

    func testVersionsAreReadFromStoreNamesAndSharedCachesNeverLookLikeOne() {
        XCTAssertEqual(GradleStores.version(in: "8.14.3"), "8.14.3")
        XCTAssertEqual(GradleStores.version(in: "9.0.0-rc-1"), "9.0.0-rc-1")
        XCTAssertEqual(GradleStores.version(in: "8.14"), "8.14")
        for name in ["modules-2", "build-cache-1", "jars-9", "journal-1", "CACHEDIR.TAG", "9", "", "v9.1", "8..14", ".tmp"] {
            XCTAssertNil(GradleStores.version(in: name), name)
        }
        XCTAssertEqual(GradleStores.distribution(in: "gradle-8.14.3-bin")?.version, "8.14.3")
        XCTAssertEqual(GradleStores.distribution(in: "gradle-8.14.3-bin")?.type, "bin")
        XCTAssertEqual(GradleStores.distribution(in: "gradle-8.14-all")?.version, "8.14")
        XCTAssertEqual(GradleStores.distribution(in: "gradle-9.0.0-rc-1-all")?.version, "9.0.0-rc-1")
        XCTAssertNil(GradleStores.distribution(in: "CACHEDIR.TAG"))
        XCTAssertNil(GradleStores.distribution(in: "gradle-enterprise"))
        XCTAssertEqual(GradleStores.distributionVersion(inURL: "https\\://services.gradle.org/distributions/gradle-8.14.3-all.zip"), "8.14.3")
        XCTAssertEqual(GradleStores.distributionVersion(inURL: "https://mirror.example.com/gradle/gradle-9.2.1-bin.zip"), "9.2.1")
        XCTAssertNil(GradleStores.distributionVersion(inURL: "https\\://example.com/internal/gradle-enterprise.zip"))
        XCTAssertEqual(GradleStores.prebuilt(in: "kotlin-native-prebuilt-macos-aarch64-2.4.10")?.version, "2.4.10")
        XCTAssertEqual(GradleStores.prebuilt(in: "kotlin-native-prebuilt-macos-aarch64-2.4.10")?.architecture, "aarch64")
        XCTAssertEqual(GradleStores.prebuilt(in: "kotlin-native-prebuilt-macos-x86_64-1.9.24")?.architecture, "x86_64")
        XCTAssertEqual(GradleStores.prebuilt(in: "kotlin-native-prebuilt-macos-aarch64-2.5.0-RC2")?.version, "2.5.0-RC2")
        XCTAssertNil(GradleStores.prebuilt(in: "dependencies"))
        XCTAssertNil(GradleStores.prebuilt(in: "kotlin-native-prebuilt-linux-x86_64-2.4.10"), "another OS is not this Mac's compiler")
        XCTAssertTrue(GradleStores.versionParts("9.7.1").lexicographicallyPrecedes(GradleStores.versionParts("9.8.0-rc-1")))
        XCTAssertTrue(GradleStores.versionParts("9.0.0-rc-1").lexicographicallyPrecedes(GradleStores.versionParts("9.0.0")), "a release beats its own pre-release")
        XCTAssertTrue(GradleStores.versionParts("8.14").lexicographicallyPrecedes(GradleStores.versionParts("8.14.3")))
    }

    // MARK: References

    func testReferencesComeFromWrapperPropertiesCatalogsBuildFilesAndGradlePropertiesInsideTheRootsOnly() throws {
        try fixture()
        let refs = GradleStores.references(projects: roots)
        XCTAssertEqual(refs.gradleVersions, ["8.14", "9.2.1"], "build/-nested wrappers and the project outside the roots are not references")
        XCTAssertTrue(refs.unresolvedGradle, "a wrapper URL whose version cannot be read must be said so")
        XCTAssertEqual(refs.kotlinVersions, ["2.2.10", "2.3.0", "2.3.20", "2.4.0"], "comments, kotlinx libraries and the project outside the roots are not references")
        XCTAssertTrue(refs.unresolvedKotlin, "kotlin(\"jvm\") version kotlinVersion cannot be resolved and must be said so")
        let outside = GradleStores.references(projects: [home.appendingPathComponent("outside/appX")])
        XCTAssertEqual(outside.gradleVersions, ["9.5.1"])
        XCTAssertEqual(outside.kotlinVersions, ["2.2.20"])
        XCTAssertFalse(outside.unresolvedGradle); XCTAssertFalse(outside.unresolvedKotlin)
        XCTAssertEqual(GradleStores.references(projects: []), GradleStores.References())
    }

    func testKotlinReferencesAcceptEveryDeclarationStyle() {
        var refs = GradleStores.References()
        GradleStores.kotlin(inBuildFile: "plugins {\n  id(\"org.jetbrains.kotlin.android\") version \"2.3.21\" apply false\n  id 'org.jetbrains.kotlin.multiplatform' version '2.1.0'\n  kotlin(\"jvm\") version \"1.9.25\"\n}\nclasspath(\"org.jetbrains.kotlin:kotlin-gradle-plugin:2.0.21\")\n", into: &refs)
        XCTAssertEqual(refs.kotlinVersions, ["2.3.21", "2.1.0", "1.9.25", "2.0.21"])
        XCTAssertFalse(refs.unresolvedKotlin)
        GradleStores.kotlin(inBuildFile: "plugins { kotlin(\"multiplatform\") version libs.versions.kotlin.get() }", into: &refs)
        XCTAssertFalse(refs.unresolvedKotlin, "a catalog reference resolves through the catalog")
        GradleStores.kotlin(inBuildFile: "plugins { id(\"org.jetbrains.kotlin.jvm\") version kotlinVersion }", into: &refs)
        XCTAssertTrue(refs.unresolvedKotlin)
        var catalog = GradleStores.References()
        GradleStores.kotlin(inCatalog: "[versions]\nkotlin = \"2.4.10\"\nkotlin-serialization = \"2.4.10\"\nkotlinx-datetime = \"0.7.0\"\nagp = \"9.0.0\"\n[plugins]\nkmp = { id = \"org.jetbrains.kotlin.multiplatform\", version = \"2.3.0\" }\nandroid = { id = \"com.android.application\", version.ref = \"agp\" }\n[libraries]\nkotlin-test = \"org.jetbrains.kotlin:kotlin-test:2.2.21\"\n", into: &catalog)
        XCTAssertEqual(catalog.kotlinVersions, ["2.4.10", "2.3.0", "2.2.21"])
        var properties = GradleStores.References()
        GradleStores.kotlin(inProperties: "kotlin.version=2.2.10\nkotlinVersion = 2.1.21\nkotlin.code.style=official\nkotlin.daemon.jvmargs=-Xmx2g\nkotlin.incremental=true\n", into: &properties)
        XCTAssertEqual(properties.kotlinVersions, ["2.2.10", "2.1.21"])
    }

    // MARK: Gradle

    func testGradleKeepsNamedVersionsAndTheNewestAndOffersTheRestPerStore() throws {
        try fixture()
        let (all, _) = try findings()
        let gradleItems = all.filter { [.gradleCache, .gradleDistribution, .gradleDaemon, .gradleTemporary].contains($0.kind) }
        XCTAssertEqual(Set(gradleItems.map { relative($0.url, to: gradle) }),
                       ["caches/8.14.3", "caches/9.0.0-rc-1", "caches/9.5.1", "wrapper/dists/gradle-8.14.3-bin",
                        "daemon/5.4.1", "daemon/8.14.3", "daemon/9.0.0", ".tmp"])
        for item in gradleItems { XCTAssertEqual(item.root.path, gradle.path) }
        let cache = gradleItems.first { $0.url.lastPathComponent == "8.14.3" && $0.kind == .gradleCache }
        XCTAssertEqual(cache?.title, "Gradle 8.14.3 version cache")
        XCTAssertTrue(cache?.reason.contains("9.7.1") == true, "says which version is kept: \(cache?.reason ?? "")")
        XCTAssertTrue(cache?.reason.contains("could not be read") == true, "says a wrapper URL was not resolved")
        XCTAssertTrue(cache?.consequence.contains("modules-2") == true, "says downloaded dependencies are untouched")
        XCTAssertTrue(cache?.consequence.contains("download") == true || cache?.consequence.contains("rebuild") == true)
        let distribution = gradleItems.first { $0.kind == .gradleDistribution }
        XCTAssertEqual(distribution?.title, "Gradle 8.14.3 distribution (bin)")
        XCTAssertTrue(distribution?.consequence.contains("downloads") == true, "a build re-downloads a removed distribution")
        XCTAssertEqual(gradleItems.first { $0.kind == .gradleDaemon && $0.url.lastPathComponent == "5.4.1" }?.title, "Gradle 5.4.1 daemon logs")
        XCTAssertEqual(gradleItems.first { $0.kind == .gradleTemporary }?.title, "Gradle temporary files")
    }

    func testGradleReferencesAreExactVersionsNotPrefixes() throws {
        try fixture()
        var refs = GradleStores.References()
        refs.gradleVersions = ["8.14"]
        let caches = try findings(refs).findings.filter { $0.kind == .gradleCache }.map { $0.url.lastPathComponent }
        XCTAssertTrue(caches.contains("8.14.3"), "8.14 names neither 8.14.3 nor 9.x")
        XCTAssertFalse(caches.contains("8.14"))
        refs.gradleVersions = ["8.14.3"]
        let again = try findings(refs).findings.filter { $0.kind == .gradleCache }.map { $0.url.lastPathComponent }
        XCTAssertTrue(again.contains("8.14"), "8.14.3 does not name 8.14")
        XCTAssertFalse(again.contains("8.14.3"))
        refs.gradleVersions = ["5.4.1", "8.14", "8.14.3", "9.0.0", "9.0.0-rc-1", "9.2.1", "9.5.1", "9.7.1"]
        let everything = try findings(refs).findings
        XCTAssertTrue(everything.filter { $0.kind != .gradleTemporary && $0.root.path == gradle.path }.isEmpty, "every version named: only .tmp is left")
        XCTAssertEqual(everything.filter { $0.kind == .gradleTemporary }.count, 1)
    }

    func testGradleNeverOffersSharedCachesConfigurationJDKsOrTheHomeItself() throws {
        try fixture()
        let (all, _) = try findings()
        for item in all {
            XCTAssertFalse(FileSafety.isSame(item.url, gradle), "never ~/.gradle itself")
            XCTAssertFalse(FileSafety.isSame(item.url, konan), "never ~/.konan itself")
            XCTAssertTrue(FileSafety.isInside(item.url, root: item.root), item.url.path)
            for never in ["modules-2", "build-cache-1", "jars-9", "journal-1", "CACHEDIR.TAG", "gradle.properties", "init.d", "jdks",
                          "kotlin-profile", "native", "notifications", "cache", ".extracted"] {
                XCTAssertFalse(item.url.pathComponents.contains(never), "\(item.url.path) must never be offered")
            }
        }
        XCTAssertTrue(GradleStores.neverOffered.isSuperset(of: ["modules-2", "build-cache-1", "gradle.properties", "init.d", "jdks", "kotlin-profile"]))
    }

    // MARK: Kotlin/Native

    func testKotlinNativeKeepsNamedVersionsAndTheNewestPerArchitectureAndOffersTheRest() throws {
        try fixture()
        let (all, issues) = try findings()
        let prebuilt = all.filter { $0.kind == .konanPrebuilt }
        XCTAssertEqual(Set(prebuilt.map { $0.url.lastPathComponent }),
                       ["kotlin-native-prebuilt-macos-aarch64-2.2.0", "kotlin-native-prebuilt-macos-aarch64-2.2.20"],
                       "2.2.10, 2.3.0, 2.3.20, 2.4.0 are named; 2.4.10 and the lone Intel build are newest for their architecture")
        for item in prebuilt { XCTAssertEqual(item.root.path, konan.path) }
        let oldest = prebuilt.first { $0.url.lastPathComponent.hasSuffix("2.2.0") }
        XCTAssertEqual(oldest?.title, "Kotlin/Native 2.2.0 (aarch64)")
        XCTAssertTrue(oldest?.reason.contains("2.4.10") == true, "says which version is kept: \(oldest?.reason ?? "")")
        XCTAssertTrue(oldest?.reason.contains("variable") == true, "says a Kotlin version was not resolved")
        XCTAssertTrue(oldest?.consequence.contains("download") == true)
        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    func testSharedDependenciesAreOfferedOnlyWhenNoRemainingVersionNamesThem() throws {
        try fixture()
        let (all, _) = try findings()
        let dependencies = all.filter { $0.kind == .konanDependency }
        XCTAssertEqual(Set(dependencies.map { $0.url.lastPathComponent }),
                       ["llvm-19-aarch64-macos-essentials-74", "target-sysroot-xcode_15.0_15A240d-macosx"],
                       "74 is named only by the offered 2.2.0; the old sysroot by nobody; 79, 81, 97, libffi and lldb by kept versions")
        XCTAssertEqual(dependencies.first { $0.url.lastPathComponent.hasSuffix("74") }?.title, "Kotlin/Native dependency llvm-19-aarch64-macos-essentials-74")
        XCTAssertTrue(dependencies.first?.consequence.contains("downloads") == true)
        for item in dependencies { XCTAssertEqual(item.root.path, konan.path) }
        // A dependency named by a token that merely contains the entry's name is not a match either way:
        // "llvm-19-aarch64-macos-essentials-7" is not an installed entry and must not keep "…-74".
        XCTAssertTrue(GradleStores.names(text: "llvmHome = $llvm.user\nllvm.user=llvm-19-aarch64-macos-essentials-74\n", entry: "llvm-19-aarch64-macos-essentials-74"))
        XCTAssertFalse(GradleStores.names(text: "llvm.user=llvm-19-aarch64-macos-essentials-74\n", entry: "llvm-19-aarch64-macos-essentials-7"))
        XCTAssertFalse(GradleStores.names(text: "llvm.user=llvm-19-aarch64-macos-essentials-74\n", entry: "essentials-74"))
    }

    func testSharedDependenciesAreAllKeptWhenAKeptVersionHasNoReadableManifest() throws {
        try fixture()
        try FileManager.default.removeItem(at: konan.appendingPathComponent("kotlin-native-prebuilt-macos-aarch64-2.4.10/konan/konan.properties"))
        let (all, issues) = try findings()
        XCTAssertTrue(all.filter { $0.kind == .konanDependency }.isEmpty, "without every manifest, nothing shared is offered")
        XCTAssertEqual(all.filter { $0.kind == .konanPrebuilt }.count, 2, "the compilers themselves are still decided by name")
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].message.contains("2.4.10") && issues[0].message.contains("konan.properties"), issues[0].message)
    }

    func testEveryKotlinVersionNamedKeepsEverythingAndAPrefixReferenceKeepsAPatchRelease() throws {
        try fixture()
        var refs = GradleStores.References()
        refs.kotlinVersions = ["1.9.24", "2.2.0", "2.2.10", "2.2.20", "2.3.0", "2.3.20", "2.4.0", "2.4.10"]
        let everything = try findings(refs).findings.filter { $0.root.path == konan.path }
        XCTAssertEqual(Set(everything.map { $0.url.lastPathComponent }), ["target-sysroot-xcode_15.0_15A240d-macosx"], "only the orphan sysroot remains")
        refs.kotlinVersions = ["2.2"]
        let prefixed = try findings(refs).findings.filter { $0.kind == .konanPrebuilt }.map { $0.url.lastPathComponent }
        XCTAssertFalse(prefixed.contains { $0.hasSuffix("-2.2.0") || $0.hasSuffix("-2.2.10") || $0.hasSuffix("-2.2.20") }, "a 2.2 reference keeps every 2.2.x")
        XCTAssertTrue(prefixed.contains { $0.hasSuffix("-2.3.0") })
    }

    // MARK: Scanner

    func testScannerListsGradleAndKotlinItemsAsTrashCandidatesOwnedByStudioAndRespectsExclusions() throws {
        try fixture()
        let report = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [projects]))
        XCTAssertEqual(Set(report.projects.map(\.lastPathComponent)), ["appA", "appB", "appC", "appD"], "the outside project is not a root")
        let items = report.candidates.filter { $0.category == .gradle }
        XCTAssertEqual(Set(items.map(\.title)), [
            "Gradle 8.14.3 version cache", "Gradle 9.0.0-rc-1 version cache", "Gradle 9.5.1 version cache",
            "Gradle 8.14.3 distribution (bin)", "Gradle 5.4.1 daemon logs", "Gradle 8.14.3 daemon logs", "Gradle temporary files",
            "Kotlin/Native 2.2.0 (aarch64)", "Kotlin/Native 2.2.20 (aarch64)",
            "Kotlin/Native dependency llvm-19-aarch64-macos-essentials-74", "Kotlin/Native dependency target-sysroot-xcode_15.0_15A240d-macosx"
        ], "the empty 9.0.0 daemon folder measures nothing and is dropped")
        for item in items {
            XCTAssertTrue(item.canTrash); XCTAssertNil(item.removal); XCTAssertNil(item.blocker)
            XCTAssertEqual(item.ownerBundleID, GradleStores.owner)
            XCTAssertGreaterThan(item.bytes, 0)
            XCTAssertTrue(item.allowedRoot.path == gradle.path || item.allowedRoot.path == konan.path, item.allowedRoot.path)
        }
        XCTAssertEqual(items.first { $0.title.hasPrefix("Gradle") }?.allowedRoot.path, gradle.path)
        XCTAssertEqual(items.first { $0.title.hasPrefix("Kotlin") }?.allowedRoot.path, konan.path)
        let buildCache = report.candidates.first { $0.title == "Gradle build cache" }
        XCTAssertEqual(buildCache?.category, .developer, "the existing rule is untouched")
        XCTAssertEqual(buildCache?.url.path, gradle.appendingPathComponent("caches/build-cache-1").path)
        for never in ["modules-2", "jars-9", "journal-1", "gradle.properties", "init.d", "jdks", "kotlin-profile", "native", ".extracted"] {
            XCTAssertFalse(report.candidates.contains { $0.url.pathComponents.contains(never) }, never)
        }
        XCTAssertFalse(report.candidates.contains { FileSafety.isSame($0.url, gradle) || FileSafety.isSame($0.url, konan) })
        XCTAssertFalse(report.candidates.contains { $0.url.path.contains("dependencies/cache") })

        let excludedStore = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [projects],
                                                                         exclusions: [gradle.appendingPathComponent("caches")]))
        XCTAssertFalse(excludedStore.candidates.contains { $0.title.hasSuffix("version cache") })
        XCTAssertTrue(excludedStore.candidates.contains { $0.title == "Gradle 8.14.3 distribution (bin)" })
        let excludedDescendant = try DiskScanner().scan(configuration: .init(home: home, projectRoots: [projects],
                                                                              exclusions: [gradle.appendingPathComponent("caches/8.14.3/transforms")]))
        XCTAssertFalse(excludedDescendant.candidates.contains { $0.title == "Gradle 8.14.3 version cache" }, "an excluded descendant keeps its parent")
        XCTAssertTrue(excludedDescendant.issues.contains { $0.path.hasSuffix("caches/8.14.3") && $0.message.contains("excluded") })
        XCTAssertTrue(excludedDescendant.candidates.contains { $0.title == "Gradle 9.5.1 version cache" })
    }

    func testNothingIsOfferedWithoutTheToolHomesOrWithEmptyOnes() throws {
        var issues: [ScanIssue] = []
        XCTAssertTrue(GradleStores.findings(home: home, references: .init(), issues: &issues).isEmpty)
        try directory(".gradle/caches"); try directory(".gradle/wrapper/dists"); try directory(".konan/dependencies")
        XCTAssertTrue(GradleStores.findings(home: home, references: .init(), issues: &issues).isEmpty)
        XCTAssertTrue(issues.isEmpty)
        XCTAssertTrue(try DiskScanner().scan(configuration: .init(home: home)).candidates.filter { $0.category == .gradle }.isEmpty)
    }

    func testASingleInstalledVersionIsAlwaysKept() throws {
        try file(".gradle/caches/9.7.1/fileHashes/fileHashes.bin", big)
        try file(".gradle/wrapper/dists/gradle-9.7.1-bin/abc/gradle-9.7.1/lib/gradle-core.jar", big)
        try file(".konan/kotlin-native-prebuilt-macos-aarch64-2.4.10/konan/konan.properties", konanProperties(llvm: "llvm-21-aarch64-macos-essentials-97"))
        try file(".konan/dependencies/llvm-21-aarch64-macos-essentials-97/bin/clang", big)
        let (all, issues) = try findings(.init())
        XCTAssertTrue(all.isEmpty, "\(all.map { $0.url.path })")
        XCTAssertTrue(issues.isEmpty)
    }
}
