import SwiftUI
#if SWIFT_PACKAGE
import SafeCleanerPresentation
#endif

struct ProjectsView: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "BUILT FOR BUILDERS", title: "Space between builds.", subtitle: "Choose the folders where you keep your projects.")
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label("Project folders", systemImage: "folder").font(.headline)
                            Spacer()
                            Button { send(.addProjectFolder) } label: { Label("Add folder", systemImage: "plus") }
                                .buttonStyle(PrimaryButton()).disabled(!state.canEditSettings)
                        }
                        if state.projectRoots.isEmpty {
                            EmptyState(symbol: "folder.badge.plus", title: "Give your projects some space", detail: "Add a local folder, then scan to discover generated build folders.")
                        }
                        ForEach(state.projectRoots) { root in
                            HStack(spacing: 14) {
                                Image(systemName: "folder.fill").foregroundStyle(Palette.mint)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(root.title).font(.system(size: 13, weight: .medium))
                                    Text(root.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                }
                                Spacer()
                                Button { send(.removeProjectFolder(root.id)) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).disabled(!state.canEditSettings).accessibilityLabel("Remove \(root.title) from scanning")
                            }.padding(.vertical, 10)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label("Duplicate folders", systemImage: "doc.on.doc").font(.headline)
                            Spacer()
                            Button { send(.addDuplicateFolder) } label: { Label("Add folder", systemImage: "plus") }
                                .buttonStyle(PrimaryButton()).disabled(!state.canEditSettings)
                        }
                        Text("Byte-identical files of 1 MB or more are found in these folders and in your project folders. The original stays; every other copy is listed under Duplicates, nothing preselected.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        ForEach(state.duplicateRoots) { root in
                            HStack(spacing: 14) {
                                Image(systemName: "folder.fill").foregroundStyle(Palette.mint)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(root.title).font(.system(size: 13, weight: .medium))
                                    Text(root.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                }
                                Spacer()
                                Button { send(.removeDuplicateFolder(root.id)) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).disabled(!state.canEditSettings).accessibilityLabel("Stop searching \(root.title) for duplicates")
                            }.padding(.vertical, 10)
                        }
                    }
                }
                ProjectProtectionCard(state: state, send: send)
                Card(accent: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Discovery first", systemImage: "eye").foregroundStyle(Palette.mint).font(.headline)
                        Text("Generated folders are identified beside supported project manifests. Project results stay scan-only until their cleanup rules are verified.")
                            .foregroundStyle(Palette.muted).font(.system(size: 13)).lineSpacing(5)
                        Text("Cloud folders, links and dependency folders are excluded. Scans are limited to 8 levels and 20,000 folders per root.")
                            .foregroundStyle(Palette.muted).font(.system(size: 12)).lineSpacing(4)
                        Button("View project candidates →") { send(.review(.projects)) }.buttonStyle(.plain).foregroundStyle(Palette.mint).padding(.top, 6)
                    }
                }
            }.padding(32)
        }
    }
}

/// "I'm working on this one today — don't touch it." A protected project is skipped by
/// the scanner and refused by cleanup, until the switch is turned off again.
private struct ProjectProtectionCard: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Your projects", systemImage: "lock.shield").font(.headline)
                Text("Turn on “Don’t touch” for a project you are working on. SafeCleaner will not scan or clean anything inside it; every other project is still included.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                if let empty = state.projectsEmptyMessage {
                    Text(empty).font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.vertical, 6)
                }
                if let stale = state.staleSummary {
                    HStack(spacing: 12) {
                        Label(stale, systemImage: "clock.badge.exclamationmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.amber)
                        Spacer()
                        Button("Select stale build output") { send(.selectStaleBuildOutput) }
                            .disabled(!state.canSelectStaleBuildOutput)
                            .help("Selects the build folders of projects with no edit, commit or build in 60 days. Nothing moves until you review and confirm.")
                    }
                }
                if !state.canEditSettings, let status = state.busyStatus {
                    Label(status, systemImage: "hourglass").font(.system(size: 11)).foregroundStyle(.orange)
                }
                ForEach(state.projects) { project in
                    HStack(spacing: 14) {
                        Image(systemName: project.isProtected ? "lock.fill" : "folder")
                            .foregroundStyle(project.isProtected ? .orange : Palette.mint).frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(project.title).font(.system(size: 13, weight: .medium))
                                Text(project.badge).font(.system(size: 9, weight: .semibold)).tracking(1)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background((project.isStale ? Palette.amber : Palette.muted).opacity(0.18), in: Capsule())
                                    .foregroundStyle(project.isStale ? Palette.amber : Palette.muted)
                            }
                            Text(project.detail).font(.system(size: 11)).foregroundStyle(project.isProtected ? .orange : Palette.muted)
                            Text(project.activity).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Toggle("Don’t touch", isOn: Binding(get: { project.isProtected },
                                                           set: { send(.setProjectProtection(project.id, $0)) }))
                            .toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
                            .disabled(!state.canEditSettings)
                            .accessibilityLabel("Don’t touch \(project.title)")
                    }.padding(.vertical, 6).help(project.path)
                }
            }
        }
    }
}

struct ActivityView: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "EVERY STEP, VISIBLE", title: "Every action, accounted for.", subtitle: "A local record of what moved and what stayed.")
                // Cleanup is paused whenever the stored history cannot be read. Without a
                // control here the only way out is deleting a file by hand in Finder.
                if state.historyNeedsReset {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Activity history unreadable", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                            Text("Cleanup stays paused while the record of past actions cannot be read, so nothing moves without being written down first.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            Text("Starting a new history discards the old record. Files already in Trash are not affected.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            Button("Start a new history") { send(.resetHistory) }
                                .disabled(state.isBusy)
                        }
                    }
                }
                if state.history.isEmpty {
                    EmptyState(symbol: "clock.arrow.circlepath", title: "A clean slate", detail: "Your first cleanup will appear here. Scanning never changes files.")
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Restore items in Finder’s Trash before you empty it. Automatic restore is planned for a later release.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                            ForEach(state.history) { record in
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: record.failed ? "exclamationmark.circle" : "checkmark.circle")
                                        .foregroundStyle(record.failed ? .orange : Palette.mint)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(record.title).font(.system(size: 13, weight: .medium))
                                        Text(record.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                                        Text(record.result).font(.system(size: 11)).foregroundStyle(record.failed ? .orange : Palette.muted)
                                        if record.canReveal {
                                            Button("Show in Trash") { send(.revealHistory(record.id)) }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.mint)
                                        }
                                    }
                                    Spacer()
                                    Text(record.date).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }.padding(.vertical, 10)
                            }
                        }
                    }
                }
            }.padding(32)
        }
    }
}

struct SettingsView: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "THOUGHTFUL BY DEFAULT", title: "Make room, on your terms.", subtitle: "Personal, local and deliberately transparent.")
                ClaudeSettingsCard(state: state, send: send)
                Card {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("Cleanup policy", systemImage: "shield.lefthalf.filled").font(.headline)
                        policy("Review every item", "Nothing is selected automatically.")
                        policy("Trash, never permanent delete", "SafeCleaner does not empty your Trash.")
                        policy("Keep personal data", "No cleanup rules for documents, photos, passwords, conversations or model libraries.")
                        policy("Respect macOS", "No root helper. No changes to System Integrity Protection.")
                        policy("Considered motion", "Animations follow your macOS Reduce Motion preference.")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Excluded locations").font(.headline)
                        Text("CloudStorage, iCloud Drive and Trash are excluded by default. Use the shield button on a candidate to add your own exclusions.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        ForEach(state.exclusions) { location in
                            HStack {
                                Text(location.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                Spacer()
                                Button("Remove") { send(.removeExclusion(location.id)) }.disabled(!state.canEditSettings)
                            }
                        }
                    }
                }
                Text("SafeCleaner \(state.version) · Local scans · Optional requests to Anthropic · No telemetry\nAccess failures appear in scan results. Full Disk Access does not override all macOS protections.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(5)
            }.padding(32)
        }
    }
    private func policy(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "checkmark").foregroundStyle(Palette.mint).font(.caption.weight(.bold))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
        }
    }
}
