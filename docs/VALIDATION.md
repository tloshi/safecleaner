# Validation

## 0.2 — architecture and motion, 18 September 2026

- Swift package debug build: passed.
- **32 XCTest tests passed:** 15 filesystem safety, 7 repository, 10 ViewModel tests. Test dependencies are synthetic files or in-memory fakes.
- Architecture boundary checker: passed. Passive Views/DesignSystem have no filesystem, storage, desktop-service or ViewModel dependencies. Presentation has no SwiftUI/AppKit imports.
- Native Xcode Debug build and standalone release app build: passed.
- Normal launch and real disk-capacity projection through injected services: checked.
- Native visual inspection: Overview, Projects and Review layouts checked; sidebar text truncation corrected during inspection.
- Preview navigation, expanded candidate details, search filtering and disabled filesystem actions: checked through the native UI.
- Reduce Motion support is implemented in all custom motion components and inspected in code; the user's OS accessibility settings were not changed for testing.
- No real cleanup performed during this refactor. Previous scanner behavior remains covered by the filesystem suite.
- Core tests also cover unreadable history, persistence preflight failure, failure after a move, running owners, changed exclusions and duplicate candidates.
- ViewModel tests cover cancellation/stale progress, selection across filters, confirmation acknowledgement, preview isolation, persistence errors and partial cleanup results.

## 0.1 — initial implementation, 18 September 2026

## Completed

- Swift package debug build: passed.
- XCTest core suite: **15 tests passed, 0 failures**.
- Native Xcode project Debug build: passed (local ad-hoc signing).
- Standalone release `.app` build and signing: passed.
- Native app launch: passed.
- Visual inspection of the real Overview window: passed; dark sidebar, storage ring, category cards and scan actions rendered correctly.
- Read-only real scan: completed with 126 candidates, approximately 1.86 GB of allocated-byte estimates, and 13 reported skipped/partial locations. These values are one observation and will change.
- Review navigation, default empty selection, selecting one candidate, confirmation path list, disabled final action before acknowledgement, Cancel, and clearing selection: checked through the native UI.
- App left on Overview with no candidates selected.

## Tests covered

Component-aware containment; descendant and ancestor symbolic links; hard links; changes after scanning; replaced directories; no delete fallback when Trash fails; recording an injected synthetic move; scan-only enforcement; cache vs configuration paths; exclusions including protected descendants; manifest-gated project detection and overlapping roots; recent vs old logs; scanner cancellation.

Tests first revealed that Foundation's temporary-path handling can retain macOS symlink aliases. Fixtures now use a real `/private/tmp` path, keeping the production policy of rejecting symlink ancestors intact.

## Not performed

- No real user cache was moved to Trash or permanently deleted.
- No permanent deletion, full-disk access grant, root helper or security setting change.
- Native Finder restore and real `trashItem` behavior are not end-to-end certified by the synthetic move tests.
- Runtime testing on macOS 14 or Intel hardware remains outstanding.
- Destructive project cleanup, app uninstall, duplicates, automatic restore and scheduling remain roadmap work.

The first real cleanup should be a user-reviewed small cache with its owning application and related build processes stopped.
