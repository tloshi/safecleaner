import Foundation

/// Android SDK stores that nothing names any more, and emulator quick-boot snapshots.
///
/// `sdkmanager --uninstall` deletes the package directory and nothing else, so moving that
/// directory to Trash is the same uninstall with a way back, and needs no Java or process.
/// The rules are version-aware: what a project or a virtual device still names is kept, and
/// the newest NDK is always kept because builds that name no version resolve to a recent one.
public enum AndroidSDK {
    public static let owner = "com.google.android.studio"
    /// Gradle files sit near a project root; deeper trees are build output or sources.
    public static let maxReferenceDepth = 4

    public struct Finding: Sendable, Equatable {
        public enum Kind: Sendable { case ndk, systemImage, snapshots }
        public let kind: Kind
        public let url: URL
        public let root: URL
        public let title: String
        public let reason: String
        public let consequence: String
    }

    /// What projects and virtual devices still name.
    public struct References: Sendable, Equatable {
        public var ndkVersions: Set<String> = []
        /// A project takes its NDK from Flutter or a variable; the version is unknown.
        public var unresolvedNDK = false
        /// "android-37.0/google_apis_playstore_ps16k/arm64-v8a", from each AVD's config.ini.
        public var imageDirectories: Set<String> = []
        public var sdkRoots: [URL] = []
        public init() {}
    }

    public static func defaultSDK(home: URL) -> URL { home.appendingPathComponent("Library/Android/sdk") }
    public static func avdRoot(home: URL) -> URL { home.appendingPathComponent(".android/avd") }

    public static func references(projects: [URL], avdRoot: URL, fm: FileManager = .default) -> References {
        var refs = References()
        let skip: Set<String> = ["build", "node_modules", ".gradle", ".git", ".idea", "Pods", "vendor"]
        for project in projects {
            var queue: [(URL, Int)] = [(project, 0)]
            while let (directory, depth) = queue.popLast() {
                guard let children = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
                for child in children {
                    let name = child.lastPathComponent
                    guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { continue }
                    if values.isDirectory == true {
                        if depth < maxReferenceDepth, !skip.contains(name), !name.hasPrefix(".") { queue.append((child, depth + 1)) }
                        continue
                    }
                    guard let text = try? String(contentsOf: child, encoding: .utf8) else { continue }
                    if name == "build.gradle" || name == "build.gradle.kts" { ndk(in: text, into: &refs) }
                    else if name == "local.properties" { sdkDir(in: text, into: &refs) }
                }
            }
        }
        for avd in (try? fm.contentsOfDirectory(at: avdRoot, includingPropertiesForKeys: nil)) ?? [] where avd.pathExtension == "avd" {
            guard let text = try? String(contentsOf: avd.appendingPathComponent("config.ini"), encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("image.sysdir.1") {
                guard let equals = line.firstIndex(of: "=") else { continue }
                var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("system-images/") { value.removeFirst("system-images/".count) }
                let relative = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !relative.isEmpty { refs.imageDirectories.insert(relative) }
            }
        }
        return refs
    }

    /// `ndkVersion = "27.0.12077973"`, `ndkVersion "27.0.12077973"` or `ndkVersion = flutter.ndkVersion`.
    static func ndk(in text: String, into refs: inout References) {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("//"), let range = line.range(of: "ndkVersion") else { continue }
            let rest = line[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " =("))
            if let quote = rest.first, quote == "\"" || quote == "'" {
                let version = rest.dropFirst().prefix { $0 != quote }
                if !version.isEmpty { refs.ndkVersions.insert(String(version)) }
            } else if !rest.isEmpty {
                refs.unresolvedNDK = true
            }
        }
    }

    static func sdkDir(in text: String, into refs: inout References) {
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("sdk.dir") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\:", with: ":")
            if value.hasPrefix("/") { refs.sdkRoots.append(URL(fileURLWithPath: value)) }
        }
    }

    /// Decides which directories may be offered and why. Sizes and change detection come from
    /// the scanner's snapshot of each one, like every other candidate.
    public static func findings(home: URL, references: References, fm: FileManager = .default, issues: inout [ScanIssue]) -> [Finding] {
        var roots = [defaultSDK(home: home)]
        for root in references.sdkRoots where !roots.contains(where: { FileSafety.isSame($0, root) }) { roots.append(root) }
        var result: [Finding] = []
        for sdk in roots where fm.fileExists(atPath: sdk.path) {
            guard FileSafety.isInside(sdk, root: home) else {
                issues.append(.init(path: sdk.path, message: "An Android SDK outside your home folder is not scanned."))
                continue
            }
            result += ndkFindings(sdk: sdk, references: references, fm: fm)
            result += imageFindings(sdk: sdk, references: references, fm: fm)
        }
        result += snapshotFindings(avdRoot: avdRoot(home: home), fm: fm, issues: &issues)
        return result
    }

    private static func directories(_ url: URL, fm: FileManager) -> [URL] {
        ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? [])
            .filter {
                let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true && !$0.lastPathComponent.hasPrefix(".")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func ndkFindings(sdk: URL, references: References, fm: FileManager) -> [Finding] {
        let versions = directories(sdk.appendingPathComponent("ndk"), fm: fm).filter { $0.lastPathComponent.first?.isNumber == true }
        guard let newest = versions.max(by: { parts($0.lastPathComponent).lexicographicallyPrecedes(parts($1.lastPathComponent)) }) else { return [] }
        return versions.filter { !FileSafety.isSame($0, newest) }.compactMap { directory in
            let version = directory.lastPathComponent
            guard !references.ndkVersions.contains(where: { version == $0 || version.hasPrefix($0 + ".") }) else { return nil }
            var reason = "No project under your folders names NDK \(version). The newest installed NDK (\(newest.lastPathComponent)) is kept."
            if references.unresolvedNDK { reason += " One project takes its NDK version from Flutter or a variable, which was not resolved." }
            return Finding(kind: .ndk, url: directory, root: sdk, title: "Android NDK \(version)", reason: reason,
                consequence: "The same as uninstalling it in SDK Manager, but recoverable from Trash. A build that names this exact version downloads it again. Quit Android Studio and stop builds first.")
        }
    }

    static func imageFindings(sdk: URL, references: References, fm: FileManager) -> [Finding] {
        var result: [Finding] = []
        for api in directories(sdk.appendingPathComponent("system-images"), fm: fm) {
            for tag in directories(api, fm: fm) {
                for abi in directories(tag, fm: fm) {
                    let relative = "\(api.lastPathComponent)/\(tag.lastPathComponent)/\(abi.lastPathComponent)"
                    guard !references.imageDirectories.contains(relative),
                          fm.fileExists(atPath: abi.appendingPathComponent("system.img").path)
                            || fm.fileExists(atPath: abi.appendingPathComponent("package.xml").path) else { continue }
                    result.append(Finding(kind: .systemImage, url: abi, root: sdk,
                        title: "Android system image \(api.lastPathComponent) · \(tag.lastPathComponent) · \(abi.lastPathComponent)",
                        reason: "No virtual device uses this image.",
                        consequence: "The same as uninstalling it in SDK Manager, but recoverable from Trash. Creating a device with this image downloads it again; existing devices are unaffected. Quit Android Studio first."))
                }
            }
        }
        return result
    }

    static func snapshotFindings(avdRoot: URL, fm: FileManager, issues: inout [ScanIssue]) -> [Finding] {
        var result: [Finding] = []
        for avd in directories(avdRoot, fm: fm) where avd.pathExtension == "avd" {
            let snapshots = avd.appendingPathComponent("snapshots")
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: snapshots.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let name = avd.deletingPathExtension().lastPathComponent
            // The emulator holds this lock while an AVD runs and removes it on shutdown.
            if fm.fileExists(atPath: avd.appendingPathComponent("hardware-qemu.ini.lock").path) {
                issues.append(.init(path: snapshots.path, message: "\(name) appears to be running in the emulator, so its snapshots were skipped. Quit it and scan again."))
                continue
            }
            result.append(Finding(kind: .snapshots, url: snapshots, root: avd, title: "\(name) emulator snapshots",
                reason: "Quick-boot snapshots the emulator writes on every shutdown.",
                consequence: "The next start of \(name) is a cold boot and takes longer. Installed apps and data are kept; only the snapshots folder moves. Quit the emulator first."))
        }
        return result
    }

    static func parts(_ version: String) -> [Int] { version.split(separator: ".").map { Int($0) ?? 0 } }
}
