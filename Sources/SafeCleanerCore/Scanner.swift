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
            protected.contains { FileSafety.isSame(url, $0) || FileSafety.isInside(url, root: $0) }
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
            // A floor under every rule, including a project root pointed at a credential folder.
            if let label = FileSafety.sensitiveLabel(for: url, home: c.home) {
                report.issues.append(.init(path: url.path, message: "Inside \(label), which SafeCleaner never offers."))
                return
            }
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
                // An item this user cannot write is still measured and listed, but never
                // selectable: the cleanup-time ownership error would only repeat this, and
                // SafeCleaner does not ask for administrator rights. A file needs a writable
                // parent to move; a folder must be writable itself as well.
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                let writable = fm.isWritableFile(atPath: url.deletingLastPathComponent().path)
                    && (!isDirectory || fm.isWritableFile(atPath: url.path))
                let blocker = writable ? nil
                    : "Owned by another user or read-only, so it cannot move to Trash from here; SafeCleaner does not ask for administrator rights."
                report.candidates.append(Candidate(url: url, title: title, category: category,
                    reason: reason, consequence: consequence, stamp: stamp, allowedRoot: root,
                    canTrash: canTrash && writable, ownerBundleID: owner, blocker: blocker))
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
                // One line per root, not per folder. A single unnominated build tree can
                // otherwise bury every real finding: before build output was cleanable,
                // one Xcode project produced 2,359 identical depth-limit issues.
                var deepestSkipped = 0
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
                    let manifests = Set(BuildOutput.rules.flatMap(\.manifests))
                        .union(["pyproject.toml", "requirements.txt", "setup.py", "go.mod", "Gemfile"])
                    if names.contains(".git") || !names.isDisjoint(with: manifests)
                        || names.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
                        if !report.projects.contains(where: { FileSafety.isSame($0, directory) || FileSafety.isInside(directory, root: $0) }) {
                            report.projects.removeAll { FileSafety.isInside($0, root: directory) }
                            report.projects.append(directory)
                        }
                    }
                    for child in children {
                        guard !excluded(child) else { continue }
                        let values: URLResourceValues
                        do { values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]) }
                        catch { report.issues.append(.init(path: child.path, message: error.localizedDescription)); continue }
                        guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                        let name = child.lastPathComponent
                        // Build output is cleanable. It is regenerable by definition, so the
                        // worst case is a slower next build rather than lost work, and it
                        // still moves to Trash like everything else. The staleness line is
                        // per candidate because it is the thing worth deciding on.
                        if let rule = BuildOutput.rule(for: name, siblings: names) {
                            let idle = BuildOutput.idleDays(child)
                            try add(child, title: "\(directory.lastPathComponent) / \(name)", category: .projects, root: root,
                                    reason: "\(rule.label.prefix(1).uppercased() + rule.label.dropFirst()) beside \(name == "__pycache__" ? "Python sources" : "its project manifest"). \(BuildOutput.idleLabel(idle))",
                                    consequence: rule.consequence + " Close the editor and stop any running build first.")
                            continue
                        }
                        guard values.isPackage != true else { continue }
                        guard !name.hasPrefix("."), !["node_modules", "vendor", "Pods", "Library", "Pictures", "Photos Library.photoslibrary"].contains(name) else { continue }
                        if depth < 8 { queue.append((child, depth + 1)) }
                        else { deepestSkipped += 1 }
                    }
                }
                if deepestSkipped > 0 {
                    report.issues.append(.init(path: root.path, message:
                        "Depth limit reached: \(deepestSkipped) folder\(deepestSkipped == 1 ? " was" : "s were") "
                        + "not scanned past 8 levels. Add a deeper folder as its own project root to include them."))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { report.issues.append(.init(path: root.path, message: error.localizedDescription)) }
        }
        // Android SDK stores nothing names any more, and emulator snapshots. Version-aware:
        // what a project or a virtual device still names is kept. Trash, like everything else.
        let androidReferences = AndroidSDK.references(projects: report.projects, avdRoot: AndroidSDK.avdRoot(home: c.home), fm: fm)
        for finding in AndroidSDK.findings(home: c.home, references: androidReferences, fm: fm, issues: &report.issues) {
            try add(finding.url, title: finding.title, category: .android, root: finding.root,
                    reason: finding.reason, consequence: finding.consequence, owner: AndroidSDK.owner)
        }
        // Xcode's per-version stores: device symbols older than the newest per OS, documentation
        // indexes, device logs idle 30 days and archives older than 180 days. Trash, Xcode as owner.
        for finding in XcodeStores.findings(home: c.home, fm: fm) {
            try add(finding.url, title: finding.title, category: .xcode, root: finding.root,
                    reason: finding.reason, consequence: finding.consequence, owner: XcodeStores.owner)
        }
        // Gradle and Kotlin/Native stores per version under ~/.gradle and ~/.konan: every version a
        // project under the chosen folders names is kept, so is the newest installed; shared
        // dependency caches, configuration and JDKs are never offered. Trash, Android Studio as owner.
        let gradleReferences = GradleStores.references(projects: report.projects, fm: fm)
        for finding in GradleStores.findings(home: c.home, references: gradleReferences, fm: fm, issues: &report.issues) {
            try add(finding.url, title: finding.title, category: .gradle, root: finding.root,
                    reason: finding.reason, consequence: finding.consequence, owner: GradleStores.owner)
        }
        report.candidates.sort { $0.bytes > $1.bytes }
        report.projects.sort { $0.path < $1.path }
        report.finishedAt = Date()
        return report
    }
}
