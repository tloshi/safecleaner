import AppKit
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

@MainActor final class MacDesktopService: DesktopInteracting {
    func chooseProjectFolders() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true; panel.prompt = "Add folder"
        panel.message = "Choose local project folders inside your home directory. Cloud folders are excluded."
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.urls : []) }
        }
    }
    func runningApplicationIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
    func applicationName(for bundleID: String) -> String? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.localizedName
    }
    /// `terminate()` is the same request as choosing Quit in the app's menu, so the app can
    /// ask to save unsaved work. `forceTerminate()` is never used: it would lose that work.
    /// The outcome is observed rather than assumed, because the app may refuse, wait on the
    /// user, or macOS may not deliver the request at all.
    func quitApplication(_ bundleID: String) async -> AppQuitOutcome {
        guard bundleID != Bundle.main.bundleIdentifier else { return .stillRunning }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !apps.isEmpty else { return .notRunning }
        apps.forEach { _ = $0.terminate() }
        for _ in 0..<Self.quitPolls {
            if apps.allSatisfy(\.isTerminated) { return .quit }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return apps.allSatisfy(\.isTerminated) ? .quit : .stillRunning
    }
    /// About ten seconds: long enough for a normal quit, short enough not to feel stuck.
    private static let quitPolls = 40
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    /// Opens Settings ▸ Privacy & Security ▸ Full Disk Access. There is no API to request
    /// that permission, so the user grants it there and relaunches the app themselves.
    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
