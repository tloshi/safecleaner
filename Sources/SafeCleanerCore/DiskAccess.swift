import Foundation

/// One area the scanner wants to read and currently cannot.
public struct BlockedArea: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public let path: String
    public let label: String
    /// True when macOS will show its own prompt the first time the app touches this folder.
    /// The rest need Full Disk Access, which has no prompt an app is allowed to raise.
    public let isPromptable: Bool
}

public struct DiskAccessReport: Sendable, Equatable {
    public let blocked: [BlockedArea]
    public var hasFullDiskAccess: Bool { blocked.allSatisfy(\.isPromptable) }
    public var needsSystemSettings: Bool { blocked.contains { !$0.isPromptable } }
    public init(blocked: [BlockedArea]) { self.blocked = blocked }
}

/// Reports which protected locations the app cannot read.
///
/// macOS has no API to request Full Disk Access — unlike camera or microphone, an app
/// cannot raise that prompt. The only honest thing it can do is notice it is blocked, say
/// what that costs, and send the user to the right Settings pane. Desktop, Documents and
/// Downloads are different: touching those does raise a real prompt, provided the
/// usage-description keys are in Info.plist.
///
/// Probing is a directory read, never a write, and the result is only ever used to explain
/// the gap. Silence would be worse: without this, a blocked scan reports fewer bytes with no
/// error, which reads as "your Mac is clean".
public enum DiskAccess {
    /// Only what the scanner actually reads.
    ///
    /// The first version of this probed Trash, Desktop, Documents and Downloads, chosen
    /// because they returned permission errors when the author's disk was measured. That was
    /// wrong: the app never reads any of them. Trash in particular is on the scanner's
    /// permanently protected list — it is never cleaned, by design — so demanding access to
    /// it was a request no grant could satisfy, and the warning returned after every launch
    /// no matter what the user did.
    ///
    /// A permission warning is only honest if granting it would change the result.
    static func probes(home: URL, projectRoots: [URL] = []) -> [(URL, String, Bool)] {
        [(home.appendingPathComponent("Library/Caches"), "your app caches", false),
         (home.appendingPathComponent("Library/Logs"), "your logs", false)]
        + projectRoots.map { ($0, $0.lastPathComponent, true) }
    }

    public static func report(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                              projectRoots: [URL] = []) -> DiskAccessReport {
        DiskAccessReport(blocked: probes(home: home, projectRoots: projectRoots)
            .compactMap { url, label, promptable in
                guard isDenied(url) else { return nil }
                return BlockedArea(path: url.path, label: label, isPromptable: promptable)
            })
    }

    /// Distinguishes "refused" from "absent". A missing folder is not a permission problem,
    /// and treating the two alike is how a TCC denial gets recorded as an empty directory.
    static func isDenied(_ url: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return false
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain,
               error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError {
                return false
            }
            return true
        }
    }
}
