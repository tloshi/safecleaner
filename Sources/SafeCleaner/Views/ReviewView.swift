import SwiftUI
#if SWIFT_PACKAGE
import SafeCleanerCore
import SafeCleanerPresentation
#endif

struct ReviewView: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        VStack(spacing: 0) {
            if let group = state.aiGroupFilterTitle {
                HStack {
                    Text("Claude review: \(group) · Nothing selected automatically")
                    Spacer()
                    Button("Show all items") { send(.clearAIGroupFilter) }
                }.font(.system(size: 12)).padding(16).background(Palette.mint.opacity(0.07))
            }
            VStack(alignment: .leading, spacing: 23) {
                HStack(alignment: .center) {
                    PageHeading(eyebrow: "THE FINAL SAY IS YOURS", title: "You’re in control.", subtitle: "Review each item. Keep what matters.")
                    Spacer()
                    Label("Manual selection", systemImage: "checkmark.shield")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.mint)
                        .padding(10).background(Palette.mint.opacity(0.07), in: Capsule())
                }
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                        TextField("Find an item or path", text: Binding(get: { state.query }, set: { send(.queryChanged($0)) }))
                            .textFieldStyle(.plain).accessibilityLabel("Find an item or path")
                    }.padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
                    Picker("Category", selection: Binding(get: { state.categoryFilter }, set: { send(.categoryChanged($0)) })) {
                        Text("All categories").tag(CleanCategory?.none)
                        ForEach(state.categories) { category in Text(category.title).tag(Optional(category.category)) }
                    }.labelsHidden().frame(width: 170)
                    Button("Clear selection") { send(.clearSelection) }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.muted).disabled(state.isBusy)
                }
            }.padding(32)

            if state.isScanning {
                VStack {
                    ScanActivity(detail: state.progress) { send(.cancelScan) }.padding(.horizontal, 32)
                    Spacer()
                }
            } else if state.candidates.isEmpty {
                VStack {
                    EmptyState(symbol: "sparkle.magnifyingglass", title: state.hasScanned ? "Nothing to review here" : "Start with a scan",
                        detail: state.hasScanned ? "Try another category or search. Check Overview for skipped locations." : "Find candidates in supported locations. Scanning only reads files.")
                    if !state.hasScanned {
                        Button("Scan my Mac") { send(.scan) }.buttonStyle(PrimaryButton()).disabled(!state.canScan)
                    }
                    Spacer()
                }
            } else {
                SelectAllRow(state: state, send: send).padding(.horizontal, 32).padding(.bottom, 10)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(state.candidates) { item in CandidateRow(state: item, send: send) }
                    }.padding(.horizontal, 32).padding(.bottom, 24)
                }
            }

            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        AnimatedNumber(text: state.selectedSize, value: state.selectedValue)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("selected").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Text(state.selectionCaption).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if state.isCleaning { ProgressView().controlSize(.small) }
                Button { send(.openConfirmation) } label: { Label("Review selection", systemImage: "arrow.right") }
                    .buttonStyle(PrimaryButton()).disabled(!state.canReviewSelection)
            }.padding(.horizontal, 32).padding(.vertical, 20).background(Palette.sidebar)
                .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }
    }
}

private struct SelectAllRow: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var symbol: String {
        switch state.selectAll {
        case .all: return "checkmark.square.fill"
        case .some: return "minus.square.fill"
        case .none: return "square"
        }
    }
    var body: some View {
        HStack(spacing: 14) {
            Button { send(.toggleSelectAll) } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 21))
                        .foregroundStyle(state.selectAll == .none ? Palette.muted.opacity(0.45) : Palette.mint)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    Text(state.selectAllLabel).font(.system(size: 12, weight: .medium))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!state.canSelectAll)
                .accessibilityLabel(state.selectAll == .all ? "Deselect all shown items" : "Select all shown items")
                .accessibilityValue(state.selectAllAccessibilityValue)
            Spacer()
            Text("Scan-only items are never selected").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(.horizontal, 18)
    }
}

private struct CandidateRow: View {
    let state: CandidateRowState
    let send: (WorkspaceAction) -> Void
    // Only ephemeral presentation state is local to a view.
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button { send(.toggleCandidate(state.id)) } label: {
                    Image(systemName: state.isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 21)).foregroundStyle(state.isSelected ? Palette.mint : Palette.muted.opacity(0.45))
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                }.buttonStyle(.plain).disabled(!state.canSelect)
                    .accessibilityLabel("\(state.isSelected ? "Deselect" : "Select") \(state.title)")
                CategoryIcon(category: state.category)
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(state.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(state.size).font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(state.badge).font(.system(size: 9, weight: .medium)).foregroundStyle(.orange.opacity(0.85))
                }
                Button { send(.revealCandidate(state.id)) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).help("Show in Finder").accessibilityLabel("Show \(state.title) in Finder").disabled(!state.canReveal)
                Button { send(.excludeCandidate(state.id)) } label: { Image(systemName: "shield") }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).help("Exclude from future scans").accessibilityLabel("Exclude \(state.title)").disabled(!state.canExclude)
                Button { expanded.toggle() } label: {
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                }.buttonStyle(.plain).foregroundStyle(Palette.muted).accessibilityLabel("Details for \(state.title)")
            }.padding(18)
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle().fill(Palette.line).frame(height: 1).padding(.bottom, 3)
                    Text(state.reason).font(.system(size: 12))
                    Text(state.consequence).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Text(state.metadata).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                    Text(state.fullPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                }.padding(.horizontal, 20).padding(.bottom, 20)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }.background(Palette.card, in: RoundedRectangle(cornerRadius: 15))
            .modifier(HoverSurface(radius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(state.isSelected ? Palette.mint.opacity(0.45) : Palette.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .animation(reduceMotion ? nil : Motion.detail, value: expanded)
            .animation(reduceMotion ? nil : Motion.feedback, value: state.isSelected)
    }
}

struct ConfirmationView: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "trash").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.mint)
                .frame(width: 62, height: 62).background(Palette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            Text(state.confirmationTitle).font(.system(size: 25, weight: .semibold))
            Text(state.confirmationDetail).font(.system(size: 13)).foregroundStyle(Palette.muted)
            if let note = state.confirmationToolNote {
                Label { Text(note).font(.system(size: 12)) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(state.confirmationItems) { item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.system(size: 12, weight: .medium))
                                Text(item.fullPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                            }
                            Spacer()
                            Text(item.size).font(.system(size: 12, weight: .medium))
                        }
                    }
                }.padding(16)
            }.frame(maxHeight: 230).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
            Toggle("I’ve reviewed these items, closed related apps and stopped builds or installs.",
                isOn: Binding(get: { state.confirmationAcknowledged }, set: { send(.acknowledge($0)) }))
                .toggleStyle(.checkbox).font(.system(size: 12))
            Text("Items that changed since the scan, and items SafeCleaner can tie to an app that is still open, are left in place and listed afterwards. Other items move even if a related app is open, so close it first. Moving to Trash does not immediately free disk space. No permanent deletion is performed.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
            HStack {
                Button("Cancel") { send(.dismissConfirmation) }.keyboardShortcut(.cancelAction)
                Spacer()
                if let hint = state.confirmationHint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(.orange)
                }
                Button(state.confirmButtonTitle) { send(.confirmCleanup) }.buttonStyle(PrimaryButton()).disabled(!state.canConfirmCleanup)
            }
        }.padding(30).frame(width: 560).background(Palette.sidebar)
    }
}
