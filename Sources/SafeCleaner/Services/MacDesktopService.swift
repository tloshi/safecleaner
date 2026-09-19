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
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    /// Opens Settings ▸ Privacy & Security ▸ Full Disk Access. There is no API to request
    /// that permission, so the user grants it there and relaunches the app themselves.
    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
