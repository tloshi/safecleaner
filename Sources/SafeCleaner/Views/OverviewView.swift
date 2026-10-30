import SwiftUI
#if SWIFT_PACKAGE
import SafeCleanerPresentation
#endif

struct OverviewView: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    PageHeading(eyebrow: "LESS CLUTTER. MORE POSSIBILITY.", title: "A little room to breathe.", subtitle: "Know what takes space. Choose what goes.")
                    Spacer()
                    Button { send(state.isScanning ? .cancelScan : .scan) } label: {
                        Label(state.isScanning ? "Cancel scan" : "Scan Mac", systemImage: state.isScanning ? "stop" : "arrow.clockwise")
                    }.buttonStyle(PrimaryButton()).disabled(!state.canScan && !state.isScanning)
                }.padding(.top, 4)

                // A scan that cannot read a folder otherwise just reports fewer bytes, with
                // no error. That reads as "your Mac is clean", which is the worst thing a
                // cleaner can say. Say what is hidden instead.
                if !state.blockedAreas.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Some locations are hidden from SafeCleaner", systemImage: "lock")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                            Text("macOS is blocking \(state.blockedAreas.joined(separator: ", ")). Anything in there is missing from your results — not counted, not shown.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            if state.needsFullDiskAccess {
                                Text("macOS does not let an app ask for this. Turn on Full Disk Access for SafeCleaner in Settings, then quit and reopen the app.")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                Button("Open Full Disk Access settings") { send(.openFullDiskAccessSettings) }
                            }
                        }
                    }
                }

                if let stale = state.staleSummary {
                    Card {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(stale, systemImage: "clock.badge.exclamationmark").font(.system(size: 13, weight: .medium))
                                Text("Projects with no edit, commit or build in 60 days. Their output rebuilds on the next build; the projects themselves are untouched.")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button("Select stale build output") { send(.selectStaleBuildOutput) }.disabled(!state.canSelectStaleBuildOutput)
                        }
                    }
                }

                // The largest category on a developer's Mac is build output inside project
                // folders, and it stays invisible until a root is added. Saying nothing here
                // means the first scan under-reports by tens of GB for no visible reason.
                if state.noProjectRootsYet {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("No project folders added yet", systemImage: "folder.badge.plus")
                                .font(.system(size: 13, weight: .medium))
                            Text("Build output — node_modules, build, .gradle, Pods — is usually the biggest thing on a developer's Mac, and SafeCleaner only looks inside folders you add.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            Button("Add a projects folder") { send(.addProjectFolder) }
                                .disabled(!state.canEditSettings)
                        }
                    }
                }

                HStack(spacing: 18) {
                    Card {
                        HStack(spacing: 20) {
                            StorageRing(fraction: state.diskFraction, label: state.diskPercent)
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Mac storage", systemImage: "internaldrive").font(.system(size: 14, weight: .semibold))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(state.freeSpace).font(.system(size: 28, weight: .semibold, design: .rounded))
                                        .lineLimit(1).minimumScaleFactor(0.75)
                                    Text("available on your disk").font(.system(size: 12)).foregroundStyle(Palette.muted)
                                }
                                HStack(spacing: 7) {
                                    Circle().fill(Palette.mint).frame(width: 5, height: 5)
                                    Text(state.usedSpace).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                            }
                            Spacer(minLength: 0)
                        }.frame(height: 192)
                    }
                    Card(accent: true) {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Text(state.hasScanned ? "FOUND FOR REVIEW" : "READY WHEN YOU ARE")
                                    .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                                Spacer()
                                Image(systemName: "sparkles")
                            }.foregroundStyle(Palette.mint)
                            AnimatedNumber(text: state.foundSize, value: state.foundValue)
                                .font(.system(size: state.hasScanned ? 39 : 29, weight: .semibold, design: .rounded))
                                .lineLimit(1).minimumScaleFactor(0.75).padding(.top, 4)
                            Text(state.foundCaption).font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 2)
                            Button { send(state.hasScanned ? .review(nil) : .scan) } label: {
                                HStack {
                                    Text(state.hasScanned ? "Review candidates" : "Scan my Mac")
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                }
                            }.buttonStyle(PrimaryButton()).disabled(state.isBusy || (!state.hasScanned && !state.canScan))
                        }.frame(height: 192)
                    }.frame(width: 292)
                }

                if state.isScanning {
                    ScanActivity(detail: state.progress) { send(.cancelScan) }
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                }

                Card {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Where your space goes").font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Text(state.scanDate).font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }.padding(.bottom, 17)
                        ForEach(state.categories) { category in
                            CategorySummaryRow(state: category) { send(.review(category.category)) }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "leaf").foregroundStyle(Palette.mint).font(.system(size: 17, weight: .light))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A considered clean.").font(.system(size: 12, weight: .semibold))
                        Text("Candidates are estimates, not guaranteed savings. Trash keeps items recoverable until you empty it.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.horizontal, 4)
                if !state.issues.isEmpty {
                    DisclosureGroup("\(state.issues.count) locations skipped or partially scanned") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(state.issues) { issue in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(issue.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                    Text(issue.message).font(.caption).foregroundStyle(Palette.muted)
                                }
                            }
                        }.padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: 12)).padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                }
            }.padding(32)
        }.animation(reduceMotion ? nil : Motion.detail, value: state.isScanning)
    }
}

private struct CategorySummaryRow: View {
    let state: CategorySummary
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                CategoryIcon(category: state.category)
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text(state.detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    HStack(spacing: 9) {
                        Text(state.count).font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Text(state.size).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(Color.white.opacity(0.045))
                            .overlay(alignment: .leading) {
                                Capsule().fill(LinearGradient(colors: [Palette.color(state.category).opacity(0.45), Palette.color(state.category)], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geometry.size.width * state.fraction)
                            }
                    }.frame(width: 124, height: 3)
                        .animation(reduceMotion ? nil : Motion.measurement, value: state.fraction)
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.muted).padding(.leading, 8)
            }.padding(.vertical, 14).padding(.horizontal, 7).contentShape(Rectangle()).modifier(HoverSurface())
        }.buttonStyle(.plain)
    }
}
