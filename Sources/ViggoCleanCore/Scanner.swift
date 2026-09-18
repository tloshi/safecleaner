import Foundation

public struct ScanConfiguration: Sendable {
    public var home: URL
    public var projectRoots: [URL]
    public var exclusions: [URL]
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                projectRoots: [URL] = [], exclusions: [URL] = []) {
        self.home = home; self.projectRoots = projectRoots; self.exclusions = exclusions
    }
}

public struct DiskScanner: Sendable {
    public init() {}

    public func scan(configuration c: ScanConfiguration,
                     progress: @Sendable (String) -> Void = { _ in }) throws -> ScanReport {
        let fm = FileManager.default
        var report = ScanReport()
        let cacheRoot = c.home.appendingPathComponent("Library/Caches")
        let logRoot = c.home.appendingPathComponent("Library/Logs")
        let protected = ["Library/Mobile Documents", "Library/CloudStorage", ".Trash"]
            .map { c.home.appendingPathComponent($0) } + c.exclusions
        func excluded(_ url: URL) -> Bool {
            protected.contains { url.standardized == $0.standardized || FileSafety.isInside(url, root: $0) }
        }
        func exists(_ url: URL) -> Bool {
            // fileExists follows symlinks, so attributes are used to avoid silently
            // treating broken links as missing data.
            do { _ = try fm.attributesOfItem(atPath: url.path); return true }
            catch let error as NSError {
                if error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { return false }
                report.issues.append(.init(path: url.path, message: error.localizedDescription))
                return false
            }
        }
        func add(_ url: URL, title: String, category: CleanCategory, root: URL,
                 reason: String, consequence: String, canTrash: Bool = true, owner: String? = nil) throws {
            try Task.checkCancellation()
            guard !excluded(url), exists(url) else { return }
            guard !protected.contains(where: { FileSafety.isInside($0, root: url) }) else {
                report.issues.append(.init(path: url.path, message: "Contains an excluded location; the entire parent is kept."))
                return
            }
            // If a parent item is selected for measurement, never count its children again.
            guard !report.candidates.contains(where: { $0.url == url || FileSafety.isInside(url, root: $0.url) }) else { return }
            progress(title)
            do {
                let stamp = try FileSafety.snapshot(url, root: root)
                guard stamp.logicalBytes > 0 else { return }
                report.candidates.append(Candidate(url: url, title: title, category: category,
                    reason: reason, consequence: consequence, stamp: stamp, allowedRoot: root,
                    canTrash: canTrash, ownerBundleID: owner))
            } catch is CancellationError { throw CancellationError() }
            catch { report.issues.append(.init(path: url.path, message: error.localizedDescription)) }
        }

        // Deliberately target cache subdirectories, not entire tool homes (.npm,
        // .gradle, etc.) that may also hold configuration or credentials.
        let developerRules: [(String, String, String?)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData", "com.apple.dt.Xcode"),
            ("Library/Caches/org.swift.swiftpm", "Swift package cache", "com.apple.dt.Xcode"),
            (".npm/_cacache", "npm package cache", nil),
            (".gradle/caches/build-cache-1", "Gradle build cache", "com.google.android.studio"),
            ("Library/Caches/CocoaPods", "CocoaPods cache", "com.apple.dt.Xcode"),
            ("Library/Caches/Homebrew/downloads", "Homebrew downloads", nil),
            ("Library/Caches/pip", "Python package cache", nil)
        ]
        for (path, name, owner) in developerRules {
            try add(c.home.appendingPathComponent(path), title: name, category: .developer, root: c.home,
                    reason: "Known developer cache location. Review before moving to Trash.",
                    consequence: "Future builds or installs may take longer and need internet. Stop related builds first.", owner: owner)
        }

        if exists(cacheRoot) {
            do {
                try FileSafety.validate(cacheRoot, root: c.home)
                let children = try fm.contentsOfDirectory(at: cacheRoot, includingPropertiesForKeys: nil)
                let reserved = ["Homebrew", "org.swift.swiftpm", "CocoaPods", "pip"]
                for url in children.sorted(by: { $0.path < $1.path }) {
                    let name = url.lastPathComponent
                    guard !name.hasPrefix("com.apple."), !name.hasPrefix("."), !reserved.contains(name) else { continue }
                    let browser = ["com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox", "Firefox", "BraveSoftware", "com.brave.Browser"].contains(name)
                    try add(url, title: name, category: browser ? .browsers : .applications, root: cacheRoot,
                            reason: "Located in your user Library/Caches. Contents require your review.",
                            consequence: "Close the owning app first. Cached content may need to download again.",
                            owner: name.contains(".") ? name : nil)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { report.issues.append(.init(path: cacheRoot.path, message: error.localizedDescription)) }
        }

        if exists(logRoot) {
            do {
                try FileSafety.validate(logRoot, root: c.home)
                let enumerator = fm.enumerator(at: logRoot, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsPackageDescendants], errorHandler: { url, error in
                        report.issues.append(.init(path: url.path, message: error.localizedDescription)); return true
                    })
                if let enumerator {
                    for case let url as URL in enumerator {
                        try Task.checkCancellation()
                        if excluded(url) { enumerator.skipDescendants(); continue }
                        do {
                            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey])
                            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                            guard values.isDirectory != true, url.pathExtension == "log",
                                  let date = values.contentModificationDate, date < Date().addingTimeInterval(-30 * 86400) else { continue }
                            try add(url, title: url.lastPathComponent, category: .logs, root: logRoot,
                                    reason: "A .log file last modified more than 30 days ago.",
                                    consequence: "Historical diagnostics will be unavailable until restored from Trash.")
                        } catch is CancellationError { throw CancellationError() }
                        catch { report.issues.append(.init(path: url.path, message: error.localizedDescription)) }
                    }
                } else { report.issues.append(.init(path: logRoot.path, message: "Could not enumerate logs.")) }
            } catch is CancellationError { throw CancellationError() }
            catch { report.issues.append(.init(path: logRoot.path, message: error.localizedDescription)) }
        }

        for root in c.projectRoots {
            try Task.checkCancellation()
            guard !excluded(root) else { continue }
            do {
                // v0.1 scans only locally selected folders below the user's home.
                try FileSafety.validate(root, root: c.home)
                var queue: [(URL, Int)] = [(root, 0)]
                var visited = 0
                while let (directory, depth) = queue.popLast() {
                    try Task.checkCancellation()
                    guard !excluded(directory) else { continue }
                    visited += 1
                    if visited > 20_000 {
                        report.issues.append(.init(path: root.path, message: "Project scan capped at 20,000 folders. Choose a narrower root.")); break
                    }
                    let children: [URL]
                    do { children = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]) }
                    catch { report.issues.append(.init(path: directory.path, message: error.localizedDescription)); continue }
                    let names = Set(children.map(\.lastPathComponent))
                    let nodeProject = names.contains("package.json")
                    let dartProject = names.contains("pubspec.yaml")
                    let gradleProject = names.contains("build.gradle") || names.contains("build.gradle.kts")
                    for child in children {
                        guard !excluded(child) else { continue }
                        let values: URLResourceValues
                        do { values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]) }
                        catch { report.issues.append(.init(path: child.path, message: error.localizedDescription)); continue }
                        guard values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true else { continue }
                        let name = child.lastPathComponent
                        let candidate = (name == ".next" && nodeProject) || (name == ".dart_tool" && dartProject)
                            || (name == "build" && (dartProject || gradleProject))
                        if candidate {
                            try add(child, title: "\(directory.lastPathComponent) / \(name)", category: .projects, root: root,
                                    reason: "Generated-folder candidate beside a project manifest. Detection is provisional.",
                                    consequence: "Scan-only in v0.1. Project-aware cleanup will arrive after tool-specific validation.", canTrash: false)
                            continue
                        }
                        guard !name.hasPrefix("."), !["node_modules", "vendor", "Pods", "Library", "Pictures", "Photos Library.photoslibrary"].contains(name) else { continue }
                        if depth < 8 { queue.append((child, depth + 1)) }
                        else { report.issues.append(.init(path: child.path, message: "Depth limit reached; this folder was not scanned.")) }
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { report.issues.append(.init(path: root.path, message: error.localizedDescription)) }
        }
        report.candidates.sort { $0.bytes > $1.bytes }
        report.finishedAt = Date()
        return report
    }
}
