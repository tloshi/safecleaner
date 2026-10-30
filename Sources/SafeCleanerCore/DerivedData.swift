import Foundation

/// Xcode's DerivedData, one item per project instead of one folder for all of them. On the
/// author's Mac the whole folder was 31 GB across nine projects, all but two live, so
/// all-or-nothing meant never. Each project folder is `<Name>-<28-letter hash>` with an
/// `info.plist` naming the workspace it was built for; the shared caches beside them are
/// offered by name, and anything else at that level is not ours to nominate.
public enum DerivedData {
    public static let owner = "com.apple.dt.Xcode"
    static let hashLength = 28
    static let maxPlistBytes = 1_000_000
    static let secondsPerDay = 86_400.0

    public struct Finding: Sendable, Equatable {
        public enum Kind: Sendable { case project, shared }
        public let kind: Kind
        public let url: URL
        public let root: URL
        public let title: String
        public let reason: String
        public let consequence: String
    }

    /// Shared caches at the top level, with what each costs to lose.
    static let sharedCaches: [String: (title: String, reason: String, consequence: String)] = [
        "ModuleCache.noindex": ("Xcode module cache", "Compiled module interfaces shared by every project.",
            "Every project's next build recompiles the modules it needs, which takes a few minutes. Quit Xcode first."),
        "SDKExplicitPrecompiledModules": ("Xcode precompiled SDK modules", "SDK modules Xcode precompiled, shared by every project.",
            "Every project's next build precompiles them again, which takes a few minutes. Quit Xcode first."),
        "SymbolCache.noindex": ("Xcode symbol cache", "Symbols Xcode caches while debugging.",
            "Rebuilt during the next debug session. Quit Xcode first."),
        "SDKStatCaches.noindex": ("Xcode SDK stat cache", "File-system metadata Xcode caches for the installed SDKs.",
            "Rebuilt on the next build. Quit Xcode first."),
        "CompilationCache.noindex": ("Xcode compilation cache", "Cached compilation results shared by every project.",
            "Every project's next build starts without them and takes longer. Quit Xcode first.")
    ]

    public static func root(home: URL) -> URL { home.appendingPathComponent("Library/Developer/Xcode/DerivedData") }

    public static func findings(home: URL, now: Date = Date(), fm: FileManager = .default) -> [Finding] {
        let root = root(home: home)
        var result: [Finding] = []
        for folder in directories(root, fm: fm) {
            let name = folder.lastPathComponent
            if isProjectFolder(name) {
                result.append(project(folder, root: root, home: home, now: now, fm: fm))
            } else if let shared = sharedCaches[name] {
                result.append(Finding(kind: .shared, url: folder, root: root, title: shared.title,
                                      reason: shared.reason, consequence: shared.consequence))
            }
        }
        return result
    }

    /// "iosApp-azaccffsrlnhjihdatilcgpznoub": a name, a dash, then Xcode's 28 lowercase letters.
    static func isProjectFolder(_ name: String) -> Bool {
        guard let dash = name.lastIndex(of: "-"), dash > name.startIndex else { return false }
        let hash = name[name.index(after: dash)...]
        return hash.count == hashLength && hash.allSatisfy { $0.isASCII && $0.isLetter && $0.isLowercase }
    }

    static func projectName(_ folder: String) -> String {
        guard isProjectFolder(folder), let dash = folder.lastIndex(of: "-") else { return folder }
        return String(folder[..<dash])
    }

    static func project(_ folder: URL, root: URL, home: URL, now: Date, fm: FileManager) -> Finding {
        let workspace = workspacePath(of: folder, fm: fm)
        let name = workspace.map { URL(fileURLWithPath: $0).lastPathComponent } ?? projectName(folder.lastPathComponent)
        let age = lastBuilt(in: folder, now: now, fm: fm).map(BuildOutput.idleLabel) ?? "No build products or logs inside."
        let reason: String
        if let workspace {
            let shown = abbreviate(workspace, home: home)
            reason = fm.fileExists(atPath: workspace)
                ? "Build products, indexes and logs for \(shown). \(age)"
                : "Built for \(shown), which no longer exists. \(age)"
        } else {
            reason = "No info.plist names its project; the folder is called \(projectName(folder.lastPathComponent)). \(age)"
        }
        return Finding(kind: .project, url: folder, root: root, title: "\(name) build data", reason: reason,
            consequence: "The next build of \(name) starts from scratch and takes longer; the project itself is untouched. Quit Xcode first.")
    }

    /// `WorkspacePath` from the folder's own `info.plist`; nil when absent or unreadable.
    static func workspacePath(of folder: URL, fm: FileManager) -> String? {
        let plist = folder.appendingPathComponent("info.plist")
        guard let size = (try? fm.attributesOfItem(atPath: plist.path))?[.size] as? NSNumber, size.intValue <= maxPlistBytes,
              let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let path = object["WorkspacePath"] as? String, !path.isEmpty else { return nil }
        return path
    }

    /// Whole days since Xcode last built here: the newest activity log directly under
    /// `Logs/Build` (one per build) or the newest file under `Build`. The index is left out
    /// because it changes on every edit, not on builds.
    static func lastBuilt(in folder: URL, now: Date, fm: FileManager) -> Int? {
        let logs = folder.appendingPathComponent("Logs/Build")
        let newestLog = ((try? fm.contentsOfDirectory(at: logs, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])) ?? [])
            .compactMap { url -> Date? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                return values?.isDirectory == true ? nil : values?.contentModificationDate
            }.max()
        let newestProduct = XcodeStores.newestModification(in: folder.appendingPathComponent("Build"), fm: fm)
        guard let newest = [newestLog, newestProduct].compactMap({ $0 }).max() else { return nil }
        return max(0, Int(now.timeIntervalSince(newest) / secondsPerDay))
    }

    static func abbreviate(_ path: String, home: URL) -> String {
        let prefix = home.path.hasSuffix("/") ? home.path : home.path + "/"
        return path.hasPrefix(prefix) ? "~/" + path.dropFirst(prefix.count) : path
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
