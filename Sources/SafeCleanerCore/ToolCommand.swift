import Foundation

/// A command the app is permitted to run.
///
/// Reaching the bytes that Trash cannot touch — simulator runtimes, Docker images, Homebrew
/// downloads — means asking the owning tool to release them. Deleting those folders directly
/// corrupts the tool. So the app runs commands, and the safety has to live in how those
/// commands are constructed rather than in a promise never to run any.
///
/// The invariants, in order of importance:
///
/// 1. **`init` is private.** The only instances that exist are the literals in `Catalogue`.
///    Nothing can build a `ToolCommand` from a string, a config file, a scan result or
///    anything a user typed.
/// 2. **Arguments are compile-time literals.** No interpolation, no concatenation, nothing
///    derived from a path, a filename or a preference. Argument injection has no surface.
/// 3. **No shell, ever.** `Process` is given an executable and an argument vector directly.
///    `/bin/sh -c` never appears, so quoting and metacharacters are meaningless here.
/// 4. **Absolute executable paths.** No `PATH` lookup, so a directory earlier in `PATH`
///    cannot substitute a different binary.
/// 5. **Checked before each run** by `validateExecutable`.
public struct ToolCommand: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]

    private init(_ executable: String, _ arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    /// Shells are never runnable, even if one were somehow listed: their whole purpose is to
    /// reinterpret a string as a command, which is the property this type exists to avoid.
    static let forbidden: Set<String> = [
        "/bin/sh", "/bin/bash", "/bin/zsh", "/bin/csh", "/bin/tcsh", "/bin/ksh",
        "/usr/bin/env", "/usr/bin/open", "/usr/bin/osascript", "/usr/bin/sudo"
    ]

    public enum ToolError: LocalizedError, Equatable {
        case notAllowed(String)
        case invalidArgument(String)
        case missing(String)
        case notExecutable(String)
        case writableByOthers(String)
        case toolUnavailable(String)
        case failed(String, Int32, String)

        public var errorDescription: String? {
            switch self {
            case .notAllowed(let p): return "\(p) is not an allowed tool."
            case .invalidArgument(let a): return "\(a) is not a valid simulator identifier, so no command was run."
            case .missing(let p): return "\(p) is not installed."
            case .notExecutable(let p): return "\(p) is not executable."
            case .writableByOthers(let p):
                return "\(p) can be modified by other users on this Mac, so it will not be run."
            case .toolUnavailable(let name):
                return "\(name) is not running or not available right now."
            case .failed(let name, let code, let output):
                return "\(name) exited with code \(code). \(output)"
            }
        }
    }

    /// Checked immediately before every run, not once at startup: a binary can be replaced
    /// between launch and use.
    ///
    /// Ownership is deliberately not required to be `root`. Homebrew on Apple Silicon and the
    /// Android command-line tools are installed into user-owned prefixes by design, so a
    /// root-ownership rule would exclude the tools that matter while proving little: anyone
    /// who can write to the user's own prefix can already run code as that user without
    /// involving this app. What is checked is that *other* users cannot modify the binary.
    public func validateExecutable(_ fm: FileManager = .default) throws {
        try Self.validate(executable: executable,
                          allowed: Set(Self.Catalogue.every.map(\.executable)), fm: fm)
    }

    /// Split out from `validateExecutable` so the rules can be exercised against arbitrary
    /// paths in tests. `ToolCommand.init` is private on purpose, so a test cannot otherwise
    /// build the rejected cases this needs to cover.
    static func validate(executable: String, allowed: Set<String>, fm: FileManager) throws {
        guard executable.hasPrefix("/"), !forbidden.contains(executable) else {
            throw ToolError.notAllowed(executable)
        }
        guard allowed.contains(executable) else { throw ToolError.notAllowed(executable) }
        let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        guard fm.fileExists(atPath: resolved) else { throw ToolError.missing(executable) }
        guard fm.isExecutableFile(atPath: resolved) else { throw ToolError.notExecutable(executable) }
        let attrs = try fm.attributesOfItem(atPath: resolved)
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else {
            throw ToolError.notExecutable(executable)
        }
        let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        // 0o022 = group-writable or world-writable.
        guard mode & 0o022 == 0 else { throw ToolError.writableByOthers(executable) }
    }

    /// The complete set. Adding one is a source change and a code review, never configuration.
    public enum Catalogue {
        static let xcrun = "/usr/bin/xcrun"
        static let dockerPaths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"]
        static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

        // Simulator runtimes: the largest tool-managed item on a developer Mac.
        /// A placeholder so the structural tests see the shape of the parameterized commands.
        static let sampleUUID = "00000000-0000-0000-0000-000000000000"

        public static func simulatorRuntimeList() -> ToolCommand { .init(xcrun, ["simctl", "runtime", "list", "-j"]) }
        public static func simulatorDeviceList() -> ToolCommand { .init(xcrun, ["simctl", "list", "devices", "-j"]) }
        /// Per-item removal. The identifier is the only argument a scan result ever contributes,
        /// and it must be a UUID that simctl itself reported; anything else is refused here.
        public static func simulatorRuntimeDelete(identifier: String) throws -> ToolCommand {
            .init(xcrun, ["simctl", "runtime", "delete", try uuid(identifier)])
        }
        public static func simulatorDeviceDelete(udid: String) throws -> ToolCommand {
            .init(xcrun, ["simctl", "delete", try uuid(udid)])
        }
        static func uuid(_ value: String) throws -> String {
            guard value.count == 36, let parsed = UUID(uuidString: value) else {
                throw ToolError.invalidArgument(String(value.prefix(60)))
            }
            return parsed.uuidString
        }

        static func simulatorRuntimesPreview() -> ToolCommand {
            .init(xcrun, ["simctl", "runtime", "delete", "--notUsedSinceDays", "30", "--dry-run"])
        }
        static func simulatorRuntimesApply() -> ToolCommand {
            .init(xcrun, ["simctl", "runtime", "delete", "--notUsedSinceDays", "30"])
        }
        static func unavailableDevicesPreview() -> ToolCommand {
            .init(xcrun, ["simctl", "list", "devices", "unavailable"])
        }
        static func unavailableDevicesApply() -> ToolCommand {
            .init(xcrun, ["simctl", "delete", "unavailable"])
        }
        static func dockerPreview(_ path: String) -> ToolCommand { .init(path, ["system", "df"]) }
        static func dockerApply(_ path: String) -> ToolCommand { .init(path, ["image", "prune", "-a", "-f"]) }
        static func brewPreview(_ path: String) -> ToolCommand { .init(path, ["cleanup", "--prune=30", "--dry-run"]) }
        static func brewApply(_ path: String) -> ToolCommand { .init(path, ["cleanup", "--prune=30"]) }

        /// Every command that may ever run, for `validateExecutable` to check against.
        static var every: [ToolCommand] {
            var all = [simulatorRuntimesPreview(), simulatorRuntimesApply(),
                       unavailableDevicesPreview(), unavailableDevicesApply(),
                       simulatorRuntimeList(), simulatorDeviceList()]
            if let runtime = try? simulatorRuntimeDelete(identifier: sampleUUID),
               let device = try? simulatorDeviceDelete(udid: sampleUUID) { all += [runtime, device] }
            all += dockerPaths.flatMap { [dockerPreview($0), dockerApply($0)] }
            all += brewPaths.flatMap { [brewPreview($0), brewApply($0)] }
            return all
        }
    }
}

/// One thing the user can reclaim, as a read-only preview paired with the command that does it.
///
/// The preview is what makes this safe to automate: the app never reports a number it did not
/// get from the tool itself, and the user sees the tool's own account of what will go before
/// anything goes.
public struct ToolAction: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let consequence: String
    public let preview: ToolCommand
    public let apply: ToolCommand

    public static func all(fm: FileManager = .default) -> [ToolAction] {
        var actions: [ToolAction] = [
            .init(id: "simulator-runtimes", title: "Unused simulator runtimes",
                  detail: "iOS runtimes not used for 30 days. Usually the largest single item on a developer Mac.",
                  consequence: "Xcode re-downloads a runtime the next time you need that iOS version.",
                  preview: ToolCommand.Catalogue.simulatorRuntimesPreview(),
                  apply: ToolCommand.Catalogue.simulatorRuntimesApply()),
            .init(id: "simulator-devices", title: "Unavailable simulator devices",
                  detail: "Simulators whose runtime is no longer installed. They cannot boot.",
                  consequence: "Nothing: these devices are already unusable.",
                  preview: ToolCommand.Catalogue.unavailableDevicesPreview(),
                  apply: ToolCommand.Catalogue.unavailableDevicesApply())
        ]
        if let docker = ToolCommand.Catalogue.dockerPaths.first(where: { fm.isExecutableFile(atPath: $0) }) {
            actions.append(.init(id: "docker-images", title: "Unused Docker images",
                detail: "Images no container is using. Docker's disk file never shrinks on its own.",
                consequence: "The next build or run pulls them again and needs internet.",
                preview: ToolCommand.Catalogue.dockerPreview(docker),
                apply: ToolCommand.Catalogue.dockerApply(docker)))
        }
        if let brew = ToolCommand.Catalogue.brewPaths.first(where: { fm.isExecutableFile(atPath: $0) }) {
            actions.append(.init(id: "brew-cache", title: "Homebrew downloads",
                detail: "Cached downloads and superseded versions older than 30 days.",
                consequence: "Reinstalling an old version downloads it again.",
                preview: ToolCommand.Catalogue.brewPreview(brew),
                apply: ToolCommand.Catalogue.brewApply(brew)))
        }
        return actions
    }
}
