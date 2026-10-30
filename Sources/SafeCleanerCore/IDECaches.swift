import Foundation

/// IDE caches by version, and editor caches beside their settings.
///
/// JetBrains IDEs and Android Studio keep one cache folder per version under a vendor folder
/// in `~/Library/Caches` and retire none, so the vendor folder grows by one IDE per upgrade.
/// The newest version of each product is always kept; older ones are offered one by one.
/// Siblings in the same vendor folder that are not versioned (Chrome's cache lives beside
/// Android Studio's) keep their own rows, so splitting the folder hides nothing. VS Code and
/// Cursor keep caches next to settings in Application Support; only the cache folders are
/// offered, never settings, extensions or workspace state.
public enum IDECaches {
    /// Vendor folders under `~/Library/Caches` whose children are per-version caches.
    public static let vendors = ["Google", "JetBrains"]

    public struct Product: Sendable, Equatable {
        public let prefix: String
        public let name: String
        public let owner: String
    }
    /// Longest prefix wins, so "PyCharmCE" is checked before "PyCharm".
    static let products: [Product] = [
        .init(prefix: "AndroidStudioPreview", name: "Android Studio Preview", owner: "com.google.android.studio-EAP"),
        .init(prefix: "AndroidStudio", name: "Android Studio", owner: "com.google.android.studio"),
        .init(prefix: "IntelliJIdea", name: "IntelliJ IDEA", owner: "com.jetbrains.intellij"),
        .init(prefix: "IdeaIC", name: "IntelliJ IDEA CE", owner: "com.jetbrains.intellij.ce"),
        .init(prefix: "WebStorm", name: "WebStorm", owner: "com.jetbrains.WebStorm"),
        .init(prefix: "PhpStorm", name: "PhpStorm", owner: "com.jetbrains.PhpStorm"),
        .init(prefix: "PyCharmCE", name: "PyCharm CE", owner: "com.jetbrains.pycharm.ce"),
        .init(prefix: "PyCharm", name: "PyCharm", owner: "com.jetbrains.pycharm"),
        .init(prefix: "GoLand", name: "GoLand", owner: "com.jetbrains.goland"),
        .init(prefix: "RustRover", name: "RustRover", owner: "com.jetbrains.rustrover"),
        .init(prefix: "RubyMine", name: "RubyMine", owner: "com.jetbrains.rubymine"),
        .init(prefix: "DataGrip", name: "DataGrip", owner: "com.jetbrains.datagrip"),
        .init(prefix: "CLion", name: "CLion", owner: "com.jetbrains.CLion"),
        .init(prefix: "Rider", name: "Rider", owner: "com.jetbrains.rider"),
        .init(prefix: "Fleet", name: "Fleet", owner: "com.jetbrains.fleet")
    ].sorted { $0.prefix.count > $1.prefix.count }

    public struct Editor: Sendable, Equatable {
        public let folder: String
        public let name: String
        public let owner: String
    }
    static let editors: [Editor] = [
        .init(folder: "Code", name: "VS Code", owner: "com.microsoft.VSCode"),
        .init(folder: "Code - Insiders", name: "VS Code Insiders", owner: "com.microsoft.VSCodeInsiders"),
        .init(folder: "VSCodium", name: "VSCodium", owner: "com.vscodium"),
        .init(folder: "Cursor", name: "Cursor", owner: "com.todesktop.230313mzl4w4u92")
    ]
    /// Everything else beside them (User, extensions, workspaceStorage, globalStorage,
    /// History, Backups, logs) is settings or state and is never listed.
    static let editorCacheFolders = ["Cache", "CachedData", "CachedExtensionVSIXs", "CachedProfilesData", "Code Cache",
                                     "GPUCache", "DawnCache", "DawnWebGPUCache", "DawnGraphiteCache",
                                     "Service Worker/CacheStorage", "Service Worker/ScriptCache"]

    public struct Finding: Sendable, Equatable {
        public enum Kind: Sendable { case olderVersion, vendorChild, editorCache }
        public let kind: Kind
        public let url: URL
        public let root: URL
        public let category: CleanCategory
        public let title: String
        public let reason: String
        public let consequence: String
        public let owner: String?
        /// The vendor folder this came from; the scanner then stops offering that folder whole.
        public let vendor: String?
    }

    /// "AndroidStudio2025.3.4" → Android Studio, [2025, 3, 4]. The whole remainder after the
    /// product prefix must be a dotted number, so a backup copy or a stray suffix is not a version.
    public static func productVersion(_ name: String) -> (product: Product, version: [Int])? {
        guard let product = products.first(where: { name.hasPrefix($0.prefix) }) else { return nil }
        let rest = name.dropFirst(product.prefix.count)
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard !rest.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return (product, parts.map { Int($0) ?? 0 })
    }

    public static func findings(home: URL, fm: FileManager = .default) -> [Finding] {
        let cacheRoot = home.appendingPathComponent("Library/Caches")
        var result: [Finding] = []
        for vendor in vendors {
            result += vendorFindings(vendor: vendor, root: cacheRoot, fm: fm)
        }
        let support = home.appendingPathComponent("Library/Application Support")
        for editor in editors {
            let base = support.appendingPathComponent(editor.folder)
            guard isDirectory(base, fm: fm) else { continue }
            for relative in editorCacheFolders {
                let url = base.appendingPathComponent(relative)
                guard isDirectory(url, fm: fm) else { continue }
                result.append(Finding(kind: .editorCache, url: url, root: base, category: .applications,
                    title: "\(editor.name) \(relative)",
                    reason: "A cache folder beside \(editor.name)'s settings. Settings, extensions and workspace state are never listed.",
                    consequence: "\(editor.name) rebuilds it on the next launch, which is slower once. Quit \(editor.name) first.",
                    owner: editor.owner, vendor: nil))
            }
        }
        return result
    }

    static func vendorFindings(vendor: String, root: URL, fm: FileManager) -> [Finding] {
        let folder = root.appendingPathComponent(vendor)
        let children = directories(folder, fm: fm)
        var versioned: [(url: URL, product: Product, version: [Int])] = []
        var others: [URL] = []
        for child in children {
            if let parsed = productVersion(child.lastPathComponent) { versioned.append((child, parsed.product, parsed.version)) }
            else { others.append(child) }
        }
        var result: [Finding] = []
        for product in Set(versioned.map(\.product.prefix)).sorted() {
            let entries = versioned.filter { $0.product.prefix == product }
            guard let newest = entries.map(\.version).max(by: { $0.lexicographicallyPrecedes($1) }) else { continue }
            for entry in entries where entry.version != newest {
                let label = entry.version.map(String.init).joined(separator: "."), name = entry.product.name
                result.append(Finding(kind: .olderVersion, url: entry.url, root: root, category: .applications,
                    title: "\(name) \(label) cache",
                    reason: "\(name) keeps a cache per version and retires none. The newest here, \(newest.map(String.init).joined(separator: ".")), is kept.",
                    consequence: "Opening \(name) \(label) again rebuilds its caches and indexes, which takes a few minutes. Quit \(name) first.",
                    owner: entry.product.owner, vendor: vendor))
            }
        }
        // Only when the folder is being split: with no per-version finding, the vendor folder
        // keeps its ordinary row and these would be duplicates inside it.
        guard !result.isEmpty else { return [] }
        for other in others {
            let name = other.lastPathComponent
            let isChrome = name == "Chrome" || name.hasPrefix("Chrome-")
            result.append(Finding(kind: .vendorChild, url: other, root: root, category: isChrome ? .browsers : .applications,
                title: "\(vendor)/\(name)",
                reason: "Located in your user Library/Caches/\(vendor). Contents require your review.",
                consequence: "Close the owning app first. Cached content may need to download again.",
                owner: isChrome ? "com.google.Chrome" : nil, vendor: vendor))
        }
        return result
    }

    private static func isDirectory(_ url: URL, fm: FileManager) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private static func directories(_ url: URL, fm: FileManager) -> [URL] {
        ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? [])
            .filter { isDirectory($0, fm: fm) && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
