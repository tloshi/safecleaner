# Validation

## Unreleased — audit remediation, 19 September 2026

Addresses audit items A2, A6 and A9 from `docs/analysis/AUDIT-2026-09-18.md`.

- **Candidate-root package exemption.** `~/Library/Caches/org.swift.swiftpm` carries a `.swiftpm`
  extension, so `isPackage` was true for the candidate root and `FileSafety.snapshot` threw before
  reading a child — the Swift package cache rule was dead on every Mac. The guard now exempts the
  root only. Measured on the author's machine with `probe-guards.swift`: that rule went
  `REFUSED (package)` → `ACCEPTED [973,8 MB, 689 files]`, and the seven developer rules together
  went **674,3 MB → 1,65 GB**. Two new tests cover the root exemption and that a *nested* package is
  still refused; the guard had no test at all before.
- **Activity history is now a versioned envelope.** Cleanup is gated on the history being readable,
  so a record-shape change in 0.3 would have paused cleanup for every 0.2 install with no recovery.
  Decoding falls back to the bare array 0.2 wrote, so existing files migrate on next save. A file
  from a newer schema is refused rather than partially read, so a downgrade cannot overwrite it with
  a truncated history. 5 new tests.
- **Recovery path for an unreadable history.** The Activity screen offers "Start a new history" when,
  and only when, the stored file cannot be read. A failed reset is not treated as a recovery — the
  in-memory history is cleared only after the empty file is written. 4 new tests across the
  repository and ViewModel.
- **Per-child `autoreleasepool` in `FileSafety.walk`.** Applied as the audit recommended. Correctness
  is covered by the existing suite; the peak-memory improvement is the audit's measurement, **not
  independently re-measured here.**
- Regression: **44 XCTest tests passed** (17 filesystem safety, 9 repository, 5 history format,
  13 ViewModel), boundary checker passed, `xcodebuild` Debug build succeeded.

- **Measure the whole subtree instead of refusing it (audit A4).** Interior symlinks and packages
  are counted rather than refused. `trashItem` renames the subtree, so the unit that moves is the
  whole tree and the unit measured now matches it. The audit proposed *skipping* those entries and
  then objected — correctly — that skipping makes `TreeStamp` stop describing what moves; including
  them resolves that. The ancestor symlink check in `validate` is unchanged and remains the
  load-bearing guard. One existing test was rewritten: it asserted a symlink target survived a
  snapshot that had already refused, which proved nothing about the move; it now executes the
  cleanup and asserts the target survives and the link moves intact. Measured:
  DerivedData `REFUSED` → **`ACCEPTED 8,95 GB`**; developer rules 1,65 GB → **10,6 GB**.
- **Project build output is cleanable.** `canTrash: false` was hardcoded on every project candidate.
  Detection was also skipping `node_modules`/`Pods`/`vendor` and all dotfolders, and matched only
  fixed manifest filenames — so `iosApp/build` (4,14 GB, the largest single item) was invisible and
  the scanner descended into it, emitting 2,359 depth-limit issues. Rules now require a manifest
  beside the directory, including by extension for `.xcodeproj`/`.xcworkspace`. `dist` and `out` are
  deliberately excluded as ambiguous. Staleness is the build directory's own mtime, which is not the
  same signal as repo activity.
- **End-to-end against the author's real `~/AndroidStudioProjects`, driving the actual `DiskScanner`:**
  81 project candidates, **30,1 GB**, all cleanable, 20,2 GB idle 30+ days. All categories:
  **214 candidates, 46,27 GB** — against the 1,83 GB the audit measured. Scan issues 2,372 → 14.
- Regression after these changes: **51 XCTest tests passed** (18 filesystem safety, 9 repository,
  7 build output, 5 history format, 13 ViewModel — with one deliberate policy assertion rewritten as
  described above), boundary checker passed, `xcodebuild` Debug build succeeded.

### Not performed

- No release build, signing or notarization run since these changes. `build/` still holds the 0.2.1
  artifacts, whose bundled copyright string is stale.
- **No cleanup has actually been executed against the real candidates.** Everything above is
  measurement through the real scanner; no file on the author's machine has been moved to Trash by
  the new rules. Do that on one small candidate before trusting a 30 GB batch.
- 7 build directories still refuse on interior hard links, and 3 on cross-volume or special files.
  Neither was investigated.
- The reset control and the build-output list were verified through the ViewModel and scanner, not
  by driving the real UI.
- The 30-day idle threshold is displayed, not enforced: nothing filters or sorts by it yet, so the
  user still reads the age per row.
- No real cleanup was performed. Tests use synthetic files and in-memory fakes throughout.

## 0.2.1 — distribution packaging, 18 September 2026

- Universal build: `swift build -c release --arch arm64 --arch x86_64` passed. `lipo -archs` reports
  `x86_64 arm64`; `vtool -show-build` reports `minos 14.0` for **both** slices, matching
  `LSMinimumSystemVersion`. The previous release binary was arm64-only and could not launch on Intel.
- Asset catalog is now compiled with `actool` into `Contents/Resources/Assets.car`, and `Info.plist`
  carries `CFBundleIconName`. The bundle previously shipped a loose `.icns` only, which App Store
  Connect rejects.
- `PrivacyInfo.xcprivacy` added and bundled, declaring three required-reason APIs actually used:
  file timestamps `C617.1` (`FileSafety.swift`), disk space `85F4.1` (`FileSystemServices.swift`),
  user defaults `CA92.1` (`PersistenceServices.swift`). No tracking, no collected data types.
- `scripts/build-app.sh` now signs with a `Developer ID Application` identity when one exists,
  with `--timestamp`, and falls back to ad-hoc with an explicit warning. `--notarize` builds a DMG,
  submits it via `notarytool --wait` and staples the ticket.
- `codesign --verify --deep --strict`: passed. `LSApplicationCategoryType` set to
  `public.app-category.developer-tools`.
- **Still ad-hoc on this machine:** `security find-identity -v -p codesigning` returns no
  `Developer ID Application` certificate, so `spctl --assess --type exec` still reports `rejected`.
  The paid membership exists (`Apple Distribution: Taulant Loshi (F3X3EF7L5N)`); the Developer ID
  certificate has not been created yet. Notarization is therefore untested end to end.
- Regression after regenerating the Xcode project: 32 XCTest tests passed, boundary checker passed,
  `xcodebuild` Debug build succeeded.

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
