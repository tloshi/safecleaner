import Foundation

/// Regenerable output produced by a build system inside a project folder.
///
/// Every rule requires a manifest to sit beside the directory, so a folder called `build`
/// is only nominated where a build system would actually have produced one. A directory
/// named `build` in a photo library stays invisible.
///
/// Deliberately excluded: `dist` and `out`. Both are regenerable in most projects and
/// committed source in others, and there is no local signal that separates the two. On the
/// author's machine they held 0,01 GB between them, so the ambiguity buys nothing.
public struct BuildOutputRule: Sendable {
    public let directory: String
    /// Exact filenames. Any one of these beside the directory qualifies it.
    public let manifests: [String]
    /// Path extensions that qualify it, for build systems whose manifest is named after the
    /// project rather than the tool — `iosApp.xcodeproj`, not a fixed `Xcodefile`.
    public let manifestExtensions: [String]
    public let label: String
    public let consequence: String

    public init(directory: String, manifests: [String] = [], manifestExtensions: [String] = [],
                label: String, consequence: String) {
        self.directory = directory; self.manifests = manifests
        self.manifestExtensions = manifestExtensions
        self.label = label; self.consequence = consequence
    }

    /// True when nothing is required, so the directory is regenerable wherever it appears.
    var isUnconditional: Bool { manifests.isEmpty && manifestExtensions.isEmpty }
}

public enum BuildOutput {
    public static let rules: [BuildOutputRule] = [
        .init(directory: "node_modules", manifests: ["package.json"], label: "npm packages",
              consequence: "The next install downloads them again and needs internet."),
        .init(directory: ".next", manifests: ["package.json"], label: "Next.js build output",
              consequence: "The next build regenerates it and takes longer."),
        .init(directory: "build", manifests: ["build.gradle", "build.gradle.kts", "pubspec.yaml",
                                              "package.json", "CMakeLists.txt", "Podfile"],
              manifestExtensions: ["xcodeproj", "xcworkspace"],
              label: "build output",
              consequence: "The next build regenerates it and takes longer."),
        .init(directory: ".gradle", manifests: ["build.gradle", "build.gradle.kts",
                                                "settings.gradle", "settings.gradle.kts"],
              label: "Gradle project cache",
              consequence: "Gradle re-resolves and re-indexes on the next build."),
        .init(directory: ".dart_tool", manifests: ["pubspec.yaml"], label: "Dart tool cache",
              consequence: "pub regenerates it on the next command."),
        .init(directory: "Pods", manifests: ["Podfile"], manifestExtensions: ["xcodeproj", "xcworkspace"],
              label: "CocoaPods packages",
              consequence: "pod install restores them and needs internet."),
        .init(directory: ".build", manifests: ["Package.swift"], label: "Swift build output",
              consequence: "The next build regenerates it and takes longer."),
        .init(directory: "target", manifests: ["Cargo.toml", "pom.xml"], label: "build output",
              consequence: "The next build regenerates it and takes longer."),
        .init(directory: "__pycache__", manifests: [], label: "Python bytecode cache",
              consequence: "Python regenerates it automatically on the next run.")
    ]

    /// The rule for `directory`, when one of its manifests is among `siblings`.
    public static func rule(for directory: String, siblings: Set<String>) -> BuildOutputRule? {
        rules.first { rule in
            guard rule.directory == directory else { return false }
            if rule.isUnconditional { return true }
            if rule.manifests.contains(where: { siblings.contains($0) }) { return true }
            return rule.manifestExtensions.contains { ext in
                siblings.contains { $0.hasSuffix("." + ext) }
            }
        }
    }

    /// Whole days since the directory was last written.
    ///
    /// This is the signal that matters, and it is not the same as project activity: a repo
    /// with a commit today can hold a module that has not been built in two months, and
    /// that output is dead weight regardless of how active the project is. One `stat`, and
    /// no subprocess — the app shells out nowhere.
    public static func idleDays(_ url: URL, now: Date = Date()) -> Int? {
        guard let modified = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date else { return nil }
        return Calendar.current.dateComponents([.day], from: modified, to: now).day
    }

    /// Human-readable staleness for the candidate's reason line.
    public static func idleLabel(_ days: Int?) -> String {
        guard let days else { return "Last built at an unknown time." }
        switch days {
        case ..<1: return "Last built today."
        case 1: return "Last built yesterday."
        case ..<30: return "Last built \(days) days ago."
        default: return "Last built \(days) days ago — unused for over a month."
        }
    }
}
