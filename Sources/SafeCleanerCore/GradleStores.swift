import Foundation

/// Gradle's user home (`~/.gradle`) and Kotlin/Native's (`~/.konan`) keep one store per
/// version and retire none of them: a version cache, a wrapper distribution and daemon logs
/// per Gradle version; a prebuilt compiler per Kotlin version plus the LLVM toolchains,
/// sysroots and libraries those compilers share.
///
/// The rules are version-aware and need no process: every version a project under the
/// chosen folders names is kept (`distributionUrl` in a wrapper, the Kotlin version in a
/// catalog, build file or `gradle.properties`), the newest installed version is kept because
/// Gradle and the IDE resolve to a recent one, and what is shared across versions is never
/// offered: `modules-2` (downloaded dependencies), `build-cache-1` (its own rule),
/// `jars-*`, configuration, provisioned JDKs, and the tool homes themselves. Each finding is
/// a plain directory that moves to Trash through the scanner's usual path, so exclusions,
/// the snapshot digest, the running-owner check, the open-file check and the change re-check
/// apply unchanged. A build whose version was removed downloads it again.
public enum GradleStores {
    public static let owner = "com.google.android.studio"
    /// Wrapper, catalog and build files sit near a project root; deeper trees are build
    /// output or sources.
    public static let maxReferenceDepth = 4
    /// Entries under `~/.gradle` that hold shared data, configuration or installed tools and
    /// are never offered, whatever a name looks like. `jars-*` is matched by prefix.
    public static let neverOffered: Set<String> = [
        "modules-2", "build-cache-1", "journal-1", "gradle.properties", "init.d", "jdks", "kotlin-profile",
        "native", "notifications", "workers", "undefined-build", "android", "build-scan-data", "completion", "CACHEDIR.TAG"
    ]
    static let prebuiltPrefix = "kotlin-native-prebuilt-macos-"
    static let distributionTypes = ["bin", "all"]
    static let maxTextBytes = 1_000_000

    public struct Finding: Sendable, Equatable {
        public enum Kind: Sendable { case gradleCache, gradleDistribution, gradleDaemon, gradleTemporary, konanPrebuilt, konanDependency }
        public let kind: Kind
        public let url: URL
        public let root: URL
        public let title: String
        public let reason: String
        public let consequence: String
    }

    /// What projects under the chosen folders still name.
    public struct References: Sendable, Equatable {
        /// "8.14.3", from `distributionUrl` in each `gradle-wrapper.properties`.
        public var gradleVersions: Set<String> = []
        /// A wrapper points at a distribution whose file name carries no Gradle version.
        public var unresolvedGradle = false
        /// "2.3.0", from a version catalog, a build file or `gradle.properties`.
        public var kotlinVersions: Set<String> = []
        /// A build file takes its Kotlin version from a variable that was not resolved.
        public var unresolvedKotlin = false
        public init() {}
    }

    public static func gradleHome(home: URL) -> URL { home.appendingPathComponent(".gradle") }
    public static func konanHome(home: URL) -> URL { home.appendingPathComponent(".konan") }

    // MARK: References

    public static func references(projects: [URL], fm: FileManager = .default) -> References {
        var refs = References()
        let skip: Set<String> = ["build", "node_modules", ".gradle", ".git"]
        let buildFiles: Set<String> = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
        for project in projects {
            var queue: [(URL, Int)] = [(project, 0)]
            while let (directory, depth) = queue.popLast() {
                guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
                for child in children {
                    let name = child.lastPathComponent
                    guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]), values.isSymbolicLink != true else { continue }
                    if values.isDirectory == true {
                        if depth < maxReferenceDepth, !skip.contains(name), !name.hasPrefix(".") { queue.append((child, depth + 1)) }
                        continue
                    }
                    let isWrapper = name == "gradle-wrapper.properties"
                    let isCatalog = name.hasSuffix(".versions.toml")
                    let isProperties = name == "gradle.properties"
                    guard isWrapper || isCatalog || isProperties || buildFiles.contains(name) else { continue }
                    guard (values.fileSize ?? 0) <= maxTextBytes, let text = try? String(contentsOf: child, encoding: .utf8) else { continue }
                    if isWrapper { gradle(inWrapper: text, into: &refs) }
                    else if isCatalog { kotlin(inCatalog: text, into: &refs) }
                    else if isProperties { kotlin(inProperties: text, into: &refs) }
                    else { kotlin(inBuildFile: text, into: &refs) }
                }
            }
        }
        return refs
    }

    /// `distributionUrl=https\://services.gradle.org/distributions/gradle-8.14.3-bin.zip`.
    static func gradle(inWrapper text: String, into refs: inout References) {
        for line in lines(text) where line.hasPrefix("distributionUrl") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let version = distributionVersion(inURL: value) { refs.gradleVersions.insert(version) }
            else if !value.isEmpty { refs.unresolvedGradle = true }
        }
    }

    /// `kotlin("multiplatform") version "2.3.0"`, `id("org.jetbrains.kotlin.jvm") version "2.3.0"`,
    /// `id 'org.jetbrains.kotlin.android' version '2.3.0'`, `.version("2.3.0")`,
    /// `classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.3.0")`, `ext.kotlin_version = '1.9.25'`.
    /// A version that is a variable other than a catalog accessor is reported as unresolved.
    static func kotlin(inBuildFile text: String, into refs: inout References) {
        for line in lines(text) where !line.hasPrefix("//") && !line.hasPrefix("*") {
            if let range = line.range(of: "kotlin-gradle-plugin:") {
                let version = line[range.upperBound...].prefix { $0 != "\"" && $0 != "'" && $0 != ")" }
                if self.version(in: String(version)) != nil { refs.kotlinVersions.insert(String(version)) }
                continue
            }
            if line.contains("kotlin_version") || line.contains("kotlinVersion"), line.contains("="),
               let quoted = firstQuoted(in: line[line.index(after: line.firstIndex(of: "=")!)...]), version(in: quoted) != nil {
                refs.kotlinVersions.insert(quoted)
                continue
            }
            guard line.contains("org.jetbrains.kotlin") || line.contains("kotlin(") else { continue }
            var search = line.startIndex
            while let range = line.range(of: "version", range: search..<line.endIndex) {
                search = range.upperBound
                // Not the tail of an identifier such as `pluginVersion`, and not `version.ref`.
                if range.lowerBound > line.startIndex, line[line.index(before: range.lowerBound)].isLetter { continue }
                let rest = line[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " \t(="))
                guard let first = rest.first else { continue }
                if first == "\"" || first == "'" {
                    let value = rest.dropFirst().prefix { $0 != first }
                    if version(in: String(value)) != nil { refs.kotlinVersions.insert(String(value)) }
                } else if first.isLetter, !rest.hasPrefix("libs.") {
                    refs.unresolvedKotlin = true
                }
                break
            }
        }
    }

    /// `kotlin = "2.3.0"` under `[versions]` (any `kotlin…` key except `kotlinx…` libraries),
    /// an inline `version = "2.3.0"` on a Kotlin plugin, or `"org.jetbrains.kotlin:kotlin-test:2.3.0"`.
    static func kotlin(inCatalog text: String, into refs: inout References) {
        var section = ""
        for line in lines(text) where !line.hasPrefix("#") {
            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                section = String(line[line.index(after: line.startIndex)..<close]).trimmingCharacters(in: .whitespaces)
                continue
            }
            if section == "versions", let equals = line.firstIndex(of: "=") {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                guard key.hasPrefix("kotlin"), !key.hasPrefix("kotlinx"),
                      let value = firstQuoted(in: line[line.index(after: equals)...]), version(in: value) != nil else { continue }
                refs.kotlinVersions.insert(value)
                continue
            }
            guard line.contains("org.jetbrains.kotlin") else { continue }
            if let range = line.range(of: "version"), !line[range.upperBound...].hasPrefix(".ref"),
               let value = firstQuoted(in: line[range.upperBound...]), version(in: value) != nil {
                refs.kotlinVersions.insert(value)
            }
            for quoted in allQuoted(in: line[...]) where quoted.contains("org.jetbrains.kotlin") {
                let parts = quoted.split(separator: ":")
                if parts.count == 3, let version = version(in: String(parts[2])) { refs.kotlinVersions.insert(version) }
            }
        }
    }

    /// `kotlin.version=2.3.0` or `kotlinVersion=2.3.0`; any other `kotlin.*` setting has no version value.
    static func kotlin(inProperties text: String, into refs: inout References) {
        for line in lines(text) where line.hasPrefix("kotlin") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if version(in: value) != nil { refs.kotlinVersions.insert(value) }
        }
    }

    private static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func firstQuoted(in text: Substring) -> String? { allQuoted(in: text).first }

    private static func allQuoted(in text: Substring) -> [String] {
        var result: [String] = []
        var rest = text
        while let open = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
            let quote = rest[open]
            let after = rest.index(after: open)
            guard let close = rest[after...].firstIndex(of: quote) else { break }
            result.append(String(rest[after..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return result
    }

    // MARK: Names

    /// "8.14.3" or "9.0.0-rc-1": a dotted number of at least two parts, optionally followed by a
    /// `-` suffix. A single number, a shared cache ("modules-2", "jars-9") or a hidden folder is not one.
    static func version(in name: String) -> String? {
        guard let first = name.first, first.isNumber else { return nil }
        let numeric = name.prefix { $0 != "-" }
        let parts = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let suffix = name[numeric.endIndex...]
        guard suffix.isEmpty || suffix.count > 1 else { return nil }
        return name
    }

    /// "gradle-8.14.3-bin" → ("8.14.3", "bin").
    static func distribution(in name: String) -> (version: String, type: String)? {
        guard name.hasPrefix("gradle-") else { return nil }
        let rest = name.dropFirst("gradle-".count)
        for type in distributionTypes where rest.hasSuffix("-" + type) {
            let version = String(rest.dropLast(type.count + 1))
            if self.version(in: version) != nil { return (version, type) }
        }
        return nil
    }

    /// The version in a wrapper URL's file name: `…/gradle-8.14.3-all.zip` → "8.14.3", whatever the host.
    static func distributionVersion(inURL url: String) -> String? {
        guard let file = url.split(separator: "/").last, file.hasSuffix(".zip") else { return nil }
        return distribution(in: String(file.dropLast(".zip".count)))?.version
    }

    /// "kotlin-native-prebuilt-macos-aarch64-2.4.10" → ("aarch64", "2.4.10"). Another OS's compiler
    /// never sits in a Mac's `~/.konan` by that name, so it is left alone.
    static func prebuilt(in name: String) -> (architecture: String, version: String)? {
        guard name.hasPrefix(prebuiltPrefix) else { return nil }
        let rest = name.dropFirst(prebuiltPrefix.count)
        guard let dash = rest.firstIndex(of: "-") else { return nil }
        let architecture = String(rest[..<dash])
        let version = String(rest[rest.index(after: dash)...])
        guard !architecture.isEmpty, self.version(in: version) != nil else { return nil }
        return (architecture, version)
    }

    /// Numeric parts padded to four, then 1 for a release and 0 for a pre-release, so
    /// "9.0.0-rc-1" precedes "9.0.0" and "8.14" equals "8.14.0".
    static func versionParts(_ version: String) -> [Int] {
        let numeric = version.prefix { $0 != "-" }
        var parts = numeric.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 4 { parts.append(0) }
        parts.append(numeric.count == version.count ? 1 : 0)
        return parts
    }

    static func newest(_ versions: [String]) -> String? {
        versions.max { versionParts($0).lexicographicallyPrecedes(versionParts($1)) }
    }

    /// Whether `text` names `entry` as a whole token: "llvm-19-…-74" is not named by a manifest
    /// that only mentions "llvm-19-…-7" or "essentials-74".
    static func names(text: String, entry: String) -> Bool {
        let separators = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).inverted
        return text.components(separatedBy: separators).contains(entry)
    }

    // MARK: Findings

    /// Decides which directories may be offered and why. Sizes and change detection come from
    /// the scanner's snapshot of each one, like every other candidate.
    public static func findings(home: URL, references: References, fm: FileManager = .default, issues: inout [ScanIssue]) -> [Finding] {
        let result = gradleFindings(gradle: gradleHome(home: home), references: references, fm: fm)
            + konanFindings(konan: konanHome(home: home), references: references, fm: fm, issues: &issues)
        // Belt and braces under the name rules above: nothing shared, configured or installed
        // leaves by this route even if a future rule is written carelessly.
        return result.filter { finding in
            !FileSafety.isSame(finding.url, finding.root) && FileSafety.isInside(finding.url, root: finding.root)
                && !finding.url.pathComponents.contains { neverOffered.contains($0) || $0.hasPrefix("jars-") }
        }
    }

    static func gradleFindings(gradle: URL, references: References, fm: FileManager) -> [Finding] {
        guard isDirectory(gradle, fm: fm) else { return [] }
        let caches = directories(gradle.appendingPathComponent("caches"), fm: fm).compactMap { url in version(in: url.lastPathComponent).map { (url: url, version: $0) } }
        let distributions = directories(gradle.appendingPathComponent("wrapper/dists"), fm: fm).compactMap { url in distribution(in: url.lastPathComponent).map { (url: url, version: $0.version, type: $0.type) } }
        let daemons = directories(gradle.appendingPathComponent("daemon"), fm: fm).compactMap { url in version(in: url.lastPathComponent).map { (url: url, version: $0) } }
        var result: [Finding] = []
        if let newest = newest(caches.map(\.version) + distributions.map(\.version) + daemons.map(\.version)) {
            func kept(_ version: String) -> Bool { version == newest || references.gradleVersions.contains(version) }
            func reason(_ version: String) -> String {
                var text = "No project under your folders names Gradle \(version) in its wrapper. The newest installed version (\(newest)) is kept."
                if references.unresolvedGradle { text += " One project's wrapper points at a distribution whose version could not be read from its name." }
                return text
            }
            for cache in caches where !kept(cache.version) {
                result.append(Finding(kind: .gradleCache, url: cache.url, root: gradle, title: "Gradle \(cache.version) version cache", reason: reason(cache.version),
                    consequence: "A build with Gradle \(cache.version) rebuilds this version's own caches (compiled scripts, file hashes, transforms), which takes a few minutes; downloaded dependencies live in modules-2 and are not touched. Stop Gradle daemons (./gradlew --stop) and quit Android Studio first."))
            }
            for distribution in distributions where !kept(distribution.version) {
                result.append(Finding(kind: .gradleDistribution, url: distribution.url, root: gradle, title: "Gradle \(distribution.version) distribution (\(distribution.type))", reason: reason(distribution.version),
                    consequence: "A build whose wrapper names Gradle \(distribution.version) downloads the distribution again. Stop Gradle daemons and quit Android Studio first."))
            }
            for daemon in daemons where !kept(daemon.version) {
                result.append(Finding(kind: .gradleDaemon, url: daemon.url, root: gradle, title: "Gradle \(daemon.version) daemon logs", reason: reason(daemon.version),
                    consequence: "Only the logs and registry of Gradle \(daemon.version) daemons move. A daemon of this version that is still running holds them open and is left in place."))
            }
        }
        let temporary = gradle.appendingPathComponent(".tmp")
        if isDirectory(temporary, fm: fm) {
            result.append(Finding(kind: .gradleTemporary, url: temporary, root: gradle, title: "Gradle temporary files",
                reason: "Temporary files Gradle writes while it works (configuration cache reports, extracted jars, JDK downloads) and does not always remove.",
                consequence: "Gradle recreates the folder when it needs it. A running build holds its files open and is left in place."))
        }
        return result
    }

    static func konanFindings(konan: URL, references: References, fm: FileManager, issues: inout [ScanIssue]) -> [Finding] {
        guard isDirectory(konan, fm: fm) else { return [] }
        let prebuilts = directories(konan, fm: fm).compactMap { url in prebuilt(in: url.lastPathComponent).map { (url: url, architecture: $0.architecture, version: $0.version) } }
        var newestPerArchitecture: [String: String] = [:]
        for architecture in Set(prebuilts.map(\.architecture)) {
            newestPerArchitecture[architecture] = newest(prebuilts.filter { $0.architecture == architecture }.map(\.version))
        }
        func kept(_ version: String, _ architecture: String) -> Bool {
            version == newestPerArchitecture[architecture] || references.kotlinVersions.contains { version == $0 || version.hasPrefix($0 + ".") }
        }
        var result: [Finding] = []
        var manifests: [String] = []
        var unreadable: [String] = []
        for prebuilt in prebuilts {
            if kept(prebuilt.version, prebuilt.architecture) {
                let manifest = prebuilt.url.appendingPathComponent("konan/konan.properties")
                if let size = (try? fm.attributesOfItem(atPath: manifest.path))?[.size] as? NSNumber, size.intValue <= maxTextBytes,
                   let text = try? String(contentsOf: manifest, encoding: .utf8) { manifests.append(text) }
                else { unreadable.append(prebuilt.version) }
                continue
            }
            var reason = "No project under your folders names Kotlin \(prebuilt.version). The newest installed version for \(prebuilt.architecture) (\(newestPerArchitecture[prebuilt.architecture] ?? prebuilt.version)) is kept."
            if references.unresolvedKotlin { reason += " One project takes its Kotlin version from a variable, which was not resolved." }
            result.append(Finding(kind: .konanPrebuilt, url: prebuilt.url, root: konan, title: "Kotlin/Native \(prebuilt.version) (\(prebuilt.architecture))", reason: reason,
                consequence: "The next Kotlin/Native build on Kotlin \(prebuilt.version) downloads this compiler again, about a gigabyte. Stop Gradle daemons and quit Android Studio or IntelliJ first."))
        }
        let dependencies = directories(konan.appendingPathComponent("dependencies"), fm: fm).filter { $0.lastPathComponent != "cache" }
        guard !dependencies.isEmpty else { return result }
        guard unreadable.isEmpty else {
            for version in unreadable {
                issues.append(.init(path: konan.appendingPathComponent("dependencies").path,
                    message: "Kotlin/Native \(version) has no readable konan/konan.properties, so the shared dependencies under ~/.konan/dependencies were all kept."))
            }
            return result
        }
        for dependency in dependencies where !manifests.contains(where: { names(text: $0, entry: dependency.lastPathComponent) }) {
            result.append(Finding(kind: .konanDependency, url: dependency, root: konan, title: "Kotlin/Native dependency \(dependency.lastPathComponent)",
                reason: "A shared LLVM toolchain, sysroot or library that no remaining Kotlin/Native version names in its konan.properties.",
                consequence: "The next Kotlin/Native build that needs it downloads and extracts it again; Kotlin/Native checks that the folder exists, not only its .extracted marker. Stop Gradle daemons and quit Android Studio or IntelliJ first."))
        }
        return result
    }

    private static func isDirectory(_ url: URL, fm: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func directories(_ url: URL, fm: FileManager) -> [URL] {
        ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? [])
            .filter {
                let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true && !$0.lastPathComponent.hasPrefix(".")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
