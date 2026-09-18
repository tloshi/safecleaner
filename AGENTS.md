# ViggoClean development

Native macOS 14+ SwiftUI application with a Foundation/CryptoKit core. Read `docs/ROADMAP.md` and `docs/ARCHITECTURE.md` before extending cleanup capabilities.

- Use Context7 to resolve and query current official framework/tool documentation when implementing API-specific behavior or cleanup adapters.
- User cache directories are never test fixtures. Use synthetic directories and inject the Trash operation in tests.
- Scans are read-only. Never execute a cleanup on the developer's machine merely to verify the app.
- No permanent-delete fallback, broad shell cleanup commands, root helper or disabling SIP.
- Preserve explicit exclusions, including an excluded descendant inside a candidate parent.
- Keep project discovery scan-only until each adapter has lifecycle, source-file and active-process checks.
- Every new cleanable rule needs positive/negative fixtures and explicit consequences in the UI.
- Run `swift test` for core changes. Build the native app with `xcodebuild -project ViggoClean.xcodeproj -scheme ViggoClean -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build` when changing the app.
- `scripts/generate-project.py` owns the Xcode project structure. Regenerate it after adding or removing Swift files.
- Update the roadmap's implemented/planned distinction with actual behavior; do not mark a phase complete because the UI exists.
- Synthetic design previews must remain visibly labelled and incapable of cleanup.

## Architecture (0.2)

- Keep Views passive: receive display state and emit typed actions. Do not inject repositories/ViewModels into leaf views or call FileManager, NSWorkspace, NSOpenPanel, UserDefaults or persistence from Views/DesignSystem.
- Presentation imports Foundation/Combine only and depends on the CleaningRepository protocol. Formatting and eligibility belong in the presenter/ViewModel.
- Concrete OS/storage implementations belong in Services; assemble them only in Composition/AppContainer.
- Run `python3 scripts/check-boundaries.py` after changing architectural boundaries.
- Respect `accessibilityReduceMotion` for all custom animations; local view state may contain only ephemeral presentation state.
