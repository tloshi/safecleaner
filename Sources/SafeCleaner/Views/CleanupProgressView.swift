import SwiftUI
#if SWIFT_PACKAGE
import SafeCleanerPresentation
#endif

/// The middle step of the cleanup sheet. Shows how far along it is and what it is doing now,
/// so a long re-check of a large folder never looks like a hang.
struct CleanupProgressView: View {
    let progress: CleanupProgressState
    let send: (WorkspaceAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "trash").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.mint)
                .frame(width: 62, height: 62).background(Palette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            Text("Moving to Trash").font(.system(size: 25, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress.fraction).tint(Palette.mint)
                    .animation(reduceMotion ? nil : Motion.measurement, value: progress.fraction)
                    .accessibilityLabel("Cleanup progress")
                    .accessibilityValue("\(progress.countLabel), \(progress.bytesLabel)")
                HStack {
                    Text(progress.countLabel)
                    Spacer()
                    Text(progress.bytesLabel)
                }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                    .monospacedDigit()
            }
            HStack(alignment: .top, spacing: 12) {
                ProgressView().controlSize(.small).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.current).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(progress.currentDetail).font(.system(size: 11))
                        .foregroundStyle(progress.isStopping ? .orange : Palette.muted)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
            Text("Large folders take longest: each item is measured again right before it moves, so nothing that changed since the scan is moved by mistake. Stopping waits for the current item, never cutting one off half-moved.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(progress.isStopping ? "Stopping…" : "Stop after this item") { send(.stopCleanup) }
                    .disabled(!progress.canStop)
            }
        }.padding(30).frame(width: 580).background(Palette.sidebar)
    }
}

/// One sheet for the whole cleanup, so confirm → progress → result never swaps sheets.
struct CleanupFlowView: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        Group {
            if let result = state.cleanupResult {
                CleanupResultView(result: result, send: send)
            } else if let progress = state.cleanupProgress {
                CleanupProgressView(progress: progress, send: send)
            } else {
                ConfirmationView(state: state, send: send)
            }
        }.interactiveDismissDisabled(state.isCleaning)
    }
}
