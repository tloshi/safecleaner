import SwiftUI
#if SWIFT_PACKAGE
import ViggoCleanPresentation
#endif

/// Passive shell. Receives a snapshot and emits intents; no services or ViewModel.
struct ContentView: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigation

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                if state.isPreview {
                    Label("DESIGN PREVIEW · Sample data · Cleaning disabled", systemImage: "eye")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity).padding(8).background(.orange.opacity(0.08))
                }
                if let message = state.message {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle").foregroundStyle(Palette.mint)
                        Text(message).font(.system(size: 12)).textSelection(.enabled)
                        Spacer()
                        Button { send(.dismissMessage) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                    }.padding(14).background(Palette.mint.opacity(0.07))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                ZStack {
                    Group {
                        switch state.destination {
                        case .overview: OverviewView(state: state, send: send)
                        case .review: ReviewView(state: state, send: send)
                        case .projects: ProjectsView(state: state, send: send)
                        case .history: ActivityView(state: state, send: send)
                        case .settings: SettingsView(state: state, send: send)
                        }
                    }.id(state.destination)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .background(Palette.background).tint(Palette.mint)
        .animation(reduceMotion ? nil : Motion.navigation, value: state.destination)
        .animation(reduceMotion ? nil : Motion.feedback, value: state.message)
        .sheet(isPresented: Binding(get: { state.showConfirmation }, set: { if !$0 { send(.dismissConfirmation) } })) {
            ConfirmationView(state: state, send: send)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "sparkle").font(.system(size: 24, weight: .medium)).foregroundStyle(Palette.background)
                    .frame(width: 39, height: 39)
                    .background(LinearGradient(colors: [Palette.mint, Palette.mint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Palette.mint.opacity(0.12), radius: 12)
                (Text("viggo").font(.system(size: 25, weight: .bold, design: .rounded))
                    + Text("clean").font(.system(size: 25, weight: .regular, design: .rounded)).foregroundColor(Palette.muted))
            }.padding(.top, 43).padding(.bottom, 42)
            Text("WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted)
                .padding(.leading, 12).padding(.bottom, 14)
            ForEach(Destination.allCases) { destination in
                Button { send(.navigate(destination)) } label: {
                    HStack(spacing: 11) {
                        Image(systemName: destination.symbol).font(.system(size: 16)).frame(width: 20)
                        Text(destination.rawValue).font(.system(size: 13, weight: state.destination == destination ? .semibold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.9)
                        Spacer(minLength: 0)
                        if destination == .review && state.hasScanned {
                            Text(state.candidateCount).font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 7).padding(.vertical, 3).background(Color.white.opacity(0.06), in: Capsule())
                        }
                    }.foregroundStyle(state.destination == destination ? Palette.mint : Palette.muted)
                        .padding(.horizontal, 13).padding(.vertical, 14)
                        .background {
                            if state.destination == destination {
                                RoundedRectangle(cornerRadius: 11).fill(Palette.mint.opacity(0.09))
                                    .overlay(alignment: .leading) { Capsule().fill(Palette.mint).frame(width: 3, height: 18).padding(.leading, 1) }
                                    .matchedGeometryEffect(id: "sidebar-selection", in: navigation)
                            }
                        }
                        .contentShape(Rectangle()).modifier(HoverSurface())
                }.buttonStyle(.plain).padding(.bottom, 5)
                    .accessibilityAddTraits(state.destination == destination ? [.isSelected] : [])
            }
            Spacer()
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: "shield.lefthalf.filled").foregroundStyle(Palette.mint).font(.system(size: 19, weight: .light))
                Text("A lighter Mac.\nA little more peace of mind.").font(.system(size: 12, weight: .medium)).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Local scans. No account.\nNothing leaves your Mac.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Palette.mint.opacity(0.045), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
            HStack {
                Circle().fill(Palette.mint).frame(width: 5, height: 5)
                Text("PERSONAL EDITION").tracking(1.2)
                Spacer()
                Text("0.2")
            }.font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted).padding(.top, 20).padding(.bottom, 22)
        }.padding(.horizontal, 18).frame(width: 231).background(Palette.sidebar)
    }

    private var topbar: some View {
        HStack {
            Text("My Mac").foregroundStyle(Palette.muted)
            Text("/").foregroundStyle(Palette.muted.opacity(0.5)).padding(.horizontal, 7)
            Text(state.destination.rawValue).id(state.destination).transition(.opacity)
            Spacer()
            Label("On-device", systemImage: "lock.shield").foregroundStyle(Palette.muted)
            Circle().fill(Palette.mint).frame(width: 6, height: 6).padding(.leading, 14)
        }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 32).frame(height: 67)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}
