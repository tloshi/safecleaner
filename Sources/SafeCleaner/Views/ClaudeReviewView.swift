import SwiftUI
#if SWIFT_PACKAGE
import SafeCleanerCore
import SafeCleanerPresentation
#endif

struct ClaudeReviewView: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "SMALL SUMMARY. CONSIDERED ADVICE.", title: "A second look, with Claude.",
                            subtitle: "Prioritize what to review. You stay in control of every cleanup.")
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Private by minimization", systemImage: "lock.shield").font(.headline)
                        Text(state.aiConsent).font(.system(size: 13)).foregroundStyle(Palette.muted)
                        Picker("Claude model", selection: Binding(get: { state.claudeModel }, set: { send(.claudeModelChanged($0)) })) {
                            ForEach(ClaudeModel.allCases, id: \.self) { model in Text(model.title).tag(model) }
                        }.disabled(!state.canEditSettings)
                        Text("One request · Up to 16 groups · Short response · No automatic retries\nUnchanged analyses are reused in memory. No chat history is sent.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        if !state.hasClaudeKey {
                            Button("Add API key in Settings") { send(.navigate(.settings)) }
                        }
                        if !state.hasScanned {
                            Button("Scan supported locations first") { send(.scan) }.disabled(!state.canScan)
                        }
                        HStack {
                            Button { send(.analyzeWithClaude) } label: {
                                Label("Send summary to Claude", systemImage: "sparkles")
                            }.buttonStyle(PrimaryButton()).disabled(!state.canAnalyze)
                            if state.isAnalyzing {
                                ProgressView().controlSize(.small).accessibilityLabel("Waiting for Claude")
                                Button("Cancel") { send(.cancelClaude) }
                            }
                        }
                        Text(state.aiScope).font(.caption).foregroundStyle(Palette.muted)
                        DisclosureGroup("Preview the scan data sent to Anthropic") {
                            Text(state.aiPayload).font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }.font(.system(size: 12))
                    }
                }
                if let summary = state.aiSummary {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Claude's review plan", systemImage: "sparkles").font(.headline)
                            Text(verbatim: summary).textSelection(.enabled)
                            if let usage = state.aiUsage { Text(usage).font(.caption).foregroundStyle(Palette.muted) }
                            Text("AI advice can be wrong. It does not verify file contents or recent use, and does not expand scan coverage. Review the local details before selecting anything.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                    }
                    ForEach(state.aiAdvice) { advice in
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(advice.title).font(.headline)
                                    Spacer()
                                    Text(advice.disposition).font(.caption).foregroundStyle(Palette.mint)
                                }
                                Text(advice.detail).font(.caption).foregroundStyle(Palette.muted)
                                Text(verbatim: advice.reason).font(.system(size: 13))
                                Text(verbatim: advice.caution).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                Button("Review these items") { send(.reviewAIGroup(advice.id)) }.disabled(state.isBusy || state.isPreview)
                            }
                        }
                    }
                }
            }.padding(32)
        }
    }
}

struct ClaudeSettingsCard: View {
    let state: WorkspaceViewState
    let send: (WorkspaceAction) -> Void
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 15) {
                Label("Claude · Optional", systemImage: "sparkles").font(.headline)
                Text("Use your Anthropic API credits for a compact review plan. Scanning and manual cleanup work without it.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                Text(state.hasClaudeKey ? "API key saved in macOS Keychain" : "No API key saved").font(.system(size: 12))
                SecureField("Anthropic API key (sk-ant-…)", text: Binding(
                    get: { state.claudeKeyDraft }, set: { send(.claudeKeyChanged($0)) }))
                    .textFieldStyle(.roundedBorder).disabled(!state.canEditClaudeKey)
                HStack {
                    Button("Save to Keychain") { send(.saveClaudeKey) }.disabled(!state.canSaveClaudeKey)
                    if state.hasClaudeKey {
                        Button("Remove saved key") { send(.removeClaudeKey) }.disabled(!state.canEditClaudeKey)
                    }
                    Spacer()
                    Button("Open Claude review") { send(.navigate(.assistant)) }
                }
                Text("Saving the key does not send a request. Only “Send summary to Claude” contacts Anthropic. Your key is not stored in settings, logs or the scan report.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
    }
}
