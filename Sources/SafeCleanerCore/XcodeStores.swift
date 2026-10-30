import Foundation

/// Xcode's per-version stores under `~/Library/Developer/Xcode`. Xcode adds an entry per OS
/// version, per documentation build, per device and per archive, and retires none of them.
///
/// Everything here is a plain directory that moves to Trash through the scanner's usual
/// path, so exclusions, the snapshot digest, the running-owner check (Xcode) and the change
/// re-check apply unchanged. What is kept is decided per store: the newest OS version per
/// platform, logs touched in the last `logIdleDays`, archives younger than `archiveKeepDays`.
public enum XcodeStores {
    public static let owner = "com.apple.dt.Xcode"
    /// Device logs are offered once nothing new was copied from the device for this long.
    public static let logIdleDays = 30
    /// An archive is the only copy of a signed build and its symbols; it is listed, never
    /// preselected, and only once it is this old.
    public static let archiveKeepDays = 180
    static let deviceSupportSuffix = " DeviceSupport"
    static let logFolders = ["DeviceLogs", "iOS Device Logs"]
    static let secondsPerDay = 86_400.0
    static let maxLogEntries = 20_000
    static let maxPlistBytes = 1_000_000

    public struct Finding: Sendable, Equatable {
        public enum Kind: Sendable { case deviceSupport, documentation, deviceLogs, archive }
        public let kind: Kind
        public let url: URL
        public let root: URL
        public let title: String
        public let reason: String
        public let consequence: String
    }

    public static func root(home: URL) -> URL { home.appendingPathComponent("Library/Developer/Xcode") }

    public static func findings(home: URL, now: Date = Date(), fm: FileManager = .default) -> [Finding] {
        let root = root(home: home)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { return [] }
        return deviceSupportFindings(root: root, fm: fm)
            + documentationFindings(root: root, fm: fm)
            + deviceLogFindings(root: root, now: now, fm: fm)
            + archiveFindings(root: root, now: now, fm: fm)
    }

    // MARK: Device symbols

    static func deviceSupportFindings(root: URL, fm: FileManager) -> [Finding] {
        var result: [Finding] = []
        for platform in directories(root, fm: fm) where platform.lastPathComponent.hasSuffix(deviceSupportSuffix) {
            let os = String(platform.lastPathComponent.dropLast(deviceSupportSuffix.count))
            let entries = directories(platform, fm: fm).compactMap { url in version(in: url.lastPathComponent).map { (url: url, version: $0) } }
            guard let newest = entries.map(\.version).max(by: { $0.lexicographicallyPrecedes($1) }) else { continue }
            for entry in entries where entry.version != newest {
                let label = versionLabel(entry.version)
                let build = build(in: entry.url.lastPathComponent).map { " (\($0))" } ?? ""
                result.append(Finding(kind: .deviceSupport, url: entry.url, root: root, title: "\(os) \(label) device symbols",
                    reason: "Debug symbols Xcode copied from a device on \(os) \(label)\(build). The newest version here, \(os) \(versionLabel(newest)), is kept.",
                    consequence: "Debugging a device still on \(os) \(label) waits a few minutes while Xcode copies the symbols from it again. Quit Xcode first."))
            }
        }
        return result
    }

    /// The first dotted number in a folder name: "iPhone15,3 26.5.2 (23F84)" → [26, 5, 2].
    /// A single number is not a version, so a model identifier never qualifies.
    static func version(in name: String) -> [Int]? {
        for token in name.split(separator: " ") {
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { continue }
            return parts.map { Int($0) ?? 0 }
        }
        return nil
    }

    /// The build in parentheses: "17.2 (21C62) arm64e" → "21C62".
    static func build(in name: String) -> String? {
        guard let open = name.firstIndex(of: "("), let close = name[open...].firstIndex(of: ")") else { return nil }
        let inner = name[name.index(after: open)..<close]
        guard !inner.isEmpty, inner.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return String(inner)
    }

    static func versionLabel(_ version: [Int]) -> String { version.map(String.init).joined(separator: ".") }

    // MARK: Documentation indexes

    static func documentationFindings(root: URL, fm: FileManager) -> [Finding] {
        var result: [Finding] = []
        for entry in directories(root.appendingPathComponent("DocumentationCache"), fm: fm) {
            let name = entry.lastPathComponent
            // The cache is versioned by schema ("v3") and then by Xcode build; an entry that is
            // not a schema folder is itself an index.
            let isSchema = name.count > 1 && name.hasPrefix("v") && name.dropFirst().allSatisfy(\.isNumber)
            for index in isSchema ? directories(entry, fm: fm) : [entry] {
                result.append(Finding(kind: .documentation, url: index, root: root, title: "Xcode documentation cache \(index.lastPathComponent)",
                    reason: "An index Xcode built for its Developer Documentation window.",
                    consequence: "The next time the documentation window opens, Xcode rebuilds the index, which takes a minute. Quit Xcode first."))
            }
        }
        return result
    }

    // MARK: Device logs

    static func deviceLogFindings(root: URL, now: Date, fm: FileManager) -> [Finding] {
        var result: [Finding] = []
        for folder in logFolders {
            for device in directories(root.appendingPathComponent(folder), fm: fm) {
                guard let newest = newestModification(in: device, fm: fm) else { continue }
                let idle = Int(now.timeIntervalSince(newest) / secondsPerDay)
                guard idle >= logIdleDays else { continue }
                result.append(Finding(kind: .deviceLogs, url: device, root: root, title: "\(deviceName(device.lastPathComponent)) device logs",
                    reason: "Crash and diagnostic reports Xcode copied from this device. The newest is \(idle) days old.",
                    consequence: "These reports leave Xcode's Devices window; the device keeps its own copies until it rotates them. Quit Xcode first."))
            }
        }
        return result
    }

    /// "Moza 14Pro Max-00008120-000C10EC3CA0C01E" → "Moza 14Pro Max". A modern UDID is two hex
    /// groups; an older one is a single 40-character group. Anything else is left alone.
    static func deviceName(_ folder: String) -> String {
        let parts = folder.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        func hex(_ s: String, _ length: Int) -> Bool { s.count == length && s.allSatisfy(\.isHexDigit) }
        if parts.count >= 3, hex(parts[parts.count - 2], 8), hex(parts[parts.count - 1], 16) {
            return parts.dropLast(2).joined(separator: "-")
        }
        if parts.count >= 2, hex(parts[parts.count - 1], 40) { return parts.dropLast().joined(separator: "-") }
        return folder
    }

    /// The newest modification date of any file below `directory`, or nil when it holds no
    /// files. Symbolic links are not followed; the walk is capped so a surprise tree cannot
    /// stall a scan.
    static func newestModification(in directory: URL, fm: FileManager) -> Date? {
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                                             options: [], errorHandler: { _, _ in true }) else { return nil }
        var newest: Date?
        var seen = 0
        for case let url as URL in enumerator {
            seen += 1
            if seen > maxLogEntries { break }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isDirectory != true, let date = values.contentModificationDate else { continue }
            if newest.map({ date > $0 }) ?? true { newest = date }
        }
        return newest
    }

    // MARK: Archives

    struct ArchiveInfo {
        var name: String?
        var created: Date?
        var bundleID: String?
        var version: String?
        var build: String?
    }

    static func archiveFindings(root: URL, now: Date, fm: FileManager) -> [Finding] {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        var result: [Finding] = []
        for day in directories(root.appendingPathComponent("Archives"), fm: fm) {
            let dayDate = dayFormatter.date(from: day.lastPathComponent)
            for archive in directories(day, fm: fm) where archive.pathExtension == "xcarchive" {
                let info = archiveInfo(archive, fm: fm)
                let created = info.created ?? dayDate
                    ?? (try? fm.attributesOfItem(atPath: archive.path))?[.creationDate] as? Date
                guard let created else { continue }
                let age = Int(now.timeIntervalSince(created) / secondsPerDay)
                guard age >= archiveKeepDays else { continue }
                let name = archive.deletingPathExtension().lastPathComponent
                var what = info.name ?? name
                if let version = info.version { what += " \(version)" + (info.build.map { " (\($0))" } ?? "") }
                if let bundleID = info.bundleID { what += ", \(bundleID)" }
                result.append(Finding(kind: .archive, url: archive, root: root, title: "Xcode archive \(name)",
                    reason: "\(what), archived \(age) days ago. It holds the signed app and its dSYM symbols, and nothing can rebuild it.",
                    consequence: "Crash reports from this exact build can no longer be symbolicated in Xcode unless its symbols were uploaded with it. Keep it while that version is still in users' hands; restore from Trash if in doubt."))
            }
        }
        return result
    }

    /// Reads the archive's own `Info.plist`; every field is optional so a malformed or missing
    /// file only costs the detail, not the finding.
    static func archiveInfo(_ archive: URL, fm: FileManager) -> ArchiveInfo {
        var info = ArchiveInfo()
        let plist = archive.appendingPathComponent("Info.plist")
        guard let size = (try? fm.attributesOfItem(atPath: plist.path))?[.size] as? NSNumber, size.intValue <= maxPlistBytes,
              let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return info }
        info.name = object["Name"] as? String
        info.created = object["CreationDate"] as? Date
        if let app = object["ApplicationProperties"] as? [String: Any] {
            info.bundleID = app["CFBundleIdentifier"] as? String
            info.version = app["CFBundleShortVersionString"] as? String
            info.build = app["CFBundleVersion"] as? String
        }
        return info
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
