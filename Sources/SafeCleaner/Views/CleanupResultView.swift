import SwiftUI
#if SWIFT_PACKAGE
import SafeCleanerPresentation
#endif

/// What a cleanup left behind, one row per open app and per cause, each with its remedy.
struct CleanupResultView: View {
    let result: CleanupResultState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: result.movedAnything ? "checkmark" : "exclamationmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(result.movedAnything ? Palette.mint : .orange)
                    .frame(width: 52, height: 52)
                    .background((result.movedAnything ? Palette.mint : Color.orange).opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title).font(.system(size: 22, weight: .semibold))
                    Text(result.subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !result.apps.isEmpty { apps }
                    if !result.issues.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(result.issues) { IssueRow(issue: $0) }
                        }
                    }
                }
            }.frame(maxHeight: 380)
            if result.offersFullDiskAccess {
                Button { send(.openFullDiskAccessSettings) } label: { Label("Open Full Disk Access", systemImage: "lock.open") }
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack {
                    Button("Done") { send(.dismissResult) }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if !result.apps.isEmpty {
                        Button { send(.selectRemaining) } label: { Label(result.selectRemainingLabel, systemImage: "arrow.uturn.backward") }
                            .buttonStyle(PrimaryButton()).disabled(!result.canSelectRemaining)
                    }
                }
                if let hint = result.selectRemainingHint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
        }.padding(30).frame(width: 580).background(Palette.sidebar)
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("KEPT IN PLACE BECAUSE THESE APPS ARE OPEN")
                .font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.mint)
            VStack(spacing: 0) {
                ForEach(Array(result.apps.enumerated()), id: \.element.id) { index, app in
                    if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                    BlockingAppRow(app: app, send: send)
                }
            }.background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            Text("Quit asks the app to close the normal way, so it can ask you to save first. SafeCleaner never force-quits.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
}

private struct BlockingAppRow: View {
    let app: BlockingAppState
    let send: (WorkspaceAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 12) {
            Text(app.initial).font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(app.status == .closed ? Palette.mint : Palette.muted)
                .frame(width: 32, height: 32).background(Palette.card, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.system(size: 13, weight: .medium))
                Text(app.note ?? app.detail).font(.system(size: 11))
                    .foregroundStyle(app.note == nil ? Palette.muted : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            switch app.status {
            case .open, .stillOpen:
                Button(app.status == .open ? "Quit" : "Try again") { send(.quitApp(app.id)) }
                    .controlSize(.small).disabled(!app.canQuit)
                    .accessibilityLabel("Quit \(app.name)")
            case .quitting:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Quitting…").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            case .closed:
                Label("Closed", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.mint)
            }
        }.padding(.horizontal, 14).padding(.vertical, 11)
            .animation(reduceMotion ? nil : Motion.feedback, value: app.status)
    }
}

private struct IssueRow: View {
    let issue: CleanupIssueState
    private var symbol: String {
        switch issue.kind {
        case .permission: return "lock.shield"
        case .ownership: return "person.crop.circle.badge.exclamationmark"
        case .changed: return "arrow.triangle.2.circlepath"
        case .stopped: return "pause.circle"
        case .inUse: return "cpu"
        case .other: return "exclamationmark.circle"
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.orange).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title).font(.system(size: 13, weight: .medium))
                Text(issue.detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }
}
