import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import ViggoCleanPresentation
#endif

@main struct ViggoCleanApp: App {
    @StateObject private var model = AppContainer.makeViewModel(preview: ProcessInfo.processInfo.arguments.contains("--preview-data"))
    var body: some Scene {
        Window("ViggoClean", id: "main") {
            ContentView(state: model.state, send: { model.send($0) })
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 700)
                .task { await model.start() }
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1220, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan supported locations") { model.send(.scan) }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(!model.state.canScan)
            }
        }
    }
}
