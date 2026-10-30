# Validation

## Unreleased — project protection, select all, explicit cleanup failures, 3 October 2026

- **Most likely cause of "delete does nothing".** No `history.json` existed on the author's Mac, so
  no cleanup had reached the move step. Xcode, Android Studio and Chrome were open, and any selection
  containing one of their caches made `clean` refuse the whole batch, reported only in a banner.
  Other candidates that also end in "nothing happens" are addressed too: the disabled Move to Trash
  button now says why, and refusals open a dialog. Not confirmed by a real cleanup.
- An open app's items are skipped per item and recorded with the app's name (policy change;
  `testRunningOwnerBlocksBatch` became `testRunningOwnerSkipsOnlyItsOwnItems`). Items with no
  known owner (project build output, `Caches/Google`) are not covered by this check — the sheet
  now says so and asks the user to close related apps.
- Failures carry a `CleanupFailure` kind. The innermost POSIX code decides: EPERM → `permission`
  (offers Full Disk Access, says locked/system files stay blocked), EACCES → `ownership` (no Full
  Disk Access offer), ENOENT → `changed`. Unknown kinds from a newer build decode as `other`, so
  the history stays readable. The field is optional; older histories decode unchanged.
- **Settings were locked for the whole length of a scan** (the reported "cannot add a key"). The
  API key now saves during a scan without replacing it, and a status line on every screen names
  what the app is busy with, with Stop for a scan.
- Select all (tri-state, filtered rows only, never scan-only, accessibility value) and per-project
  "Don't touch". Protected paths compare by path components, so a trailing slash or a renamed
  folder cannot strand a protection. Unprotecting keeps the row; same-named projects show their parent.
- **Cleanup result screen.** The first real cleanup on the author's Mac moved 189 items and kept 12
  because their apps were open, shown as one paragraph of repeated sentences. A sheet now lists each
  open app once with its item count and size, and a **Quit** button that sends a normal quit
  (`NSRunningApplication.terminate()`, never `forceTerminate`), observes for ~10 s whether the app
  closed, and shows Closed / Still open. "Select N remaining in Review" puts only the closed apps'
  items back into the selection; review and confirmation still apply. Other causes get one row each.
- **Cleanup progress.** Confirm, progress and result are one sheet (swapping sheets in one update is
  unreliable on macOS). The progress step shows a bar weighted by bytes (re-measuring follows size),
  "N of M items · X of Y", the item being re-checked now and its size, and "Stop after this item",
  which cancels between items only. The result now also appears when everything moved, so the end
  of a long run is unmistakable.
- Classification tightened after a second review: Carbon OSStatus codes from `trashItem` are mapped
  (-5000/-54/-61 → ownership, -43/-120 → changed); a bare Cocoa "no permission" is `other`, so Full
  Disk Access is only suggested on EPERM. A file vanishing inside an item no longer reads as the
  item being gone.
- Two adversarial reviews (5 + 3 reviewers, 49 verifiers) confirmed 28 findings; all were fixed except
  owner coverage for owner-less items, which is recorded above as a limitation.
- **135 XCTest tests passed:** 85 core, 48 presentation, 2 service. `check-boundaries.py` passed;
  native arm64 Debug `xcodebuild` succeeded.

### Not performed

- No cleanup was run on this Mac and the new controls were not clicked by the developer.
- Real macOS EPERM/EACCES refusals were not reproduced; those paths use injected errors.
- **Not verified that a hardened-runtime build may quit other apps without the
  `com.apple.security.automation.apple-events` entitlement**, or whether macOS asks for Automation
  consent. A probe was prepared and not run. The button reports "Still open" if the request is not
  delivered; if that happens for every app, add the entitlement and an `NSAppleEventsUsageDescription`.

## 0.5.4 — Gradle and Kotlin/Native per-version stores, 30 October 2026

- Version-aware Trash candidates under `~/.gradle` and `~/.konan`, no process: per Gradle version
  no project under the chosen folders names in its wrapper, the version cache, the wrapper
  distribution and the daemon logs, plus Gradle's `.tmp`; Kotlin/Native compilers no catalog,
  build file or `gradle.properties` names; shared `dependencies/` entries no remaining compiler's
  `konan.properties` names. Measured read-only on the author's Mac with `~/AndroidStudioProjects`
  as the project root (`/usr/bin/du -sk`, `/usr/bin/find`): `~/.gradle` is 32.8 GB and `~/.konan`
  12.0 GB. Projects name 14 wrapper versions (7.6.2 to 9.6.0), which covers all six version caches
  (8.14, 8.14.3, 9.1.0, 9.2.1, 9.4.1, 9.5.1; 19.4 GB together) and seven of the eight
  distributions; the eighth, 9.7.1, is the newest and is kept. So from Gradle only the `.tmp`
  folder (123 MB, 1,698 files) and the 5.4.1 daemon logs (8 KB) would be offered; the empty 9.0.0
  daemon folder measures nothing and is dropped. Catalogs and build files name Kotlin 2.2.10,
  2.3.0, 2.3.20, 2.4.0 and 2.4.10 (and 1.9.25, 2.2.21 and 2.3.21, which are not installed), so of
  the seven compilers 2.2.0 (1.02 GB, 27,171 files) and 2.2.20 (1.23 GB) would be offered; 2.4.10
  is also the newest. Of the five shared dependencies, LLVM 19 build 74 (482 MB) is named only by
  2.2.0 and would be offered; builds 79 and 81, LLVM 21 build 97 and libffi are named by kept
  compilers and stay. About 2.9 GB in all. `modules-2` (4.98 GB), `build-cache-1` (4.32 GB, its
  own rule) and `jdks` (1.58 GB) are never offered. No hard links or special files were found in
  the offered trees; five interior symlinks inside the compilers are counted, not followed. Every
  real wrapper file sits two levels below its detected project root, within the four-level
  reference walk.
- **206 XCTest tests passed:** 144 core, 55 presentation, 7 service. New tests cover name parsing
  (a shared cache never looks like a version, pre-release suffixes, distribution types, a wrapper
  URL on any host, Intel and Apple-silicon compilers, another OS ignored, a release ordered after
  its own pre-release), reference parsing (wrapper, catalog, Kotlin and Groovy DSL, `.version()`,
  `kotlin-gradle-plugin:` coordinates, `gradle.properties`, comments and `kotlinx` libraries
  ignored, `build/`-nested wrappers ignored, a project outside the roots not consulted, unresolved
  variables flagged), the Gradle rule (named kept, newest kept, exact not prefix references, every
  store, `.tmp`, everything named leaves only `.tmp`), the never-offer list (shared caches,
  configuration, JDKs, the homes themselves), the Kotlin/Native rule (named kept, newest per
  architecture kept, a `major.minor` reference keeps its patch releases, shared dependencies only
  when no remaining compiler names them, token rather than substring matching, all kept with an
  issue when a manifest is unreadable), scanner integration (category, owner, roots, exclusion of
  a store and of a descendant inside a candidate, the `build-cache-1` rule untouched, nothing
  never-offered listed, an empty folder dropped), absent and empty homes, and a single installed
  version.
- `check-boundaries.py` passed. Native arm64 Debug `xcodebuild` succeeded. Project regenerated
  for `GradleStores.swift`. Version 0.5.4 (11).

### Not performed

- Nothing was moved on the author's Mac. That Gradle rebuilds a removed version cache and that
  Kotlin/Native re-downloads a removed compiler or dependency was taken from their documented
  behaviour (the dependency check in `DependencyProcessor.kt` reads the folder, not only the
  `.extracted` marker), not exercised here. `GRADLE_USER_HOME` and `KONAN_DATA_DIR` are not read.
  Notarization still waits for the author to re-store the notary keychain profile.

## 0.5.3 — safety pack: open-file check, verified moves, never-offer list, Full Disk Access follow-up, structural tests, 30 October 2026

- **Open-file check.** `LibprocOpenFileService` reads, through libproc, every file descriptor,
  working directory and executable of this user's processes (1,324 processes in 0.2–0.6 s on
  the author's Mac) into an `OpenFileIndex`; the repository reads it once per batch, refreshed
  after ten seconds, and leaves an item in place with `failure: .inUse` naming the process and
  pid when anything in it sits inside the item. Found while writing it: `proc_listallpids`
  returns a pid count, not a byte length (an earlier reading dropped three quarters of the
  table), and `withUnsafeBytes(of:)` on a Swift array reads the array header, not its
  elements. Both are pinned by the service test, which opens a file in a synthetic folder and
  must find and then lose itself.
- **Verified moves.** `CleanupEngine` now fails a move whose source still exists after the
  Trash operation returned; the scanner lists items this user cannot write as *Not movable*
  (`Candidate.blocker`, `canTrash = false`) instead of failing them at cleanup.
- **Never-offer list.** `FileSafety.sensitiveLocations` (credentials, keychains, Mail,
  Messages, Safari, cookies, accounts, preferences, iPhone backups, Photos, iCloud and cloud
  mirrors) is refused in the scanner (an issue) and again in the engine before the item is read.
- **Full Disk Access.** The grant applies only after a relaunch, so `awaitingFullDiskAccess`
  is persisted when the pane is opened and the next launch reports the outcome once.
- **Structural tests** read `Sources` and pin: one `trashItem` call, no delete API anywhere,
  `Process()` only in `ToolRunner`, `URLSession` only in `ClaudeService`, libproc only in
  `OpenFileService`, and no filesystem, desktop or storage access in Views, DesignSystem or
  Presentation.
- **193 XCTest tests passed:** 131 core, 55 presentation, 7 service. `check-boundaries.py`
  passed. Native arm64 Debug `xcodebuild` succeeded. Project regenerated for
  `OpenFileService.swift`. Version 0.5.3 (10).

### Not performed

- Nothing was moved on the author's Mac. The open-file check was not exercised against a real
  Gradle daemon or emulator, only against the test process's own descriptor. Memory-mapped
  files (loaded dylibs) are not descriptors and are not detected.
- **Notarization of 0.5.2 and 0.5.3 did not happen.** The `safecleaner-notary` keychain profile,
  which worked for 0.5.1 at 01:07 the same day, was no longer in the login keychain by 07:40
  (`notarytool`: "No Keychain password item found for profile"). `scripts/build-app.sh
  --notarize` signed the 0.5.2 app and then stopped before building a DMG; `build/SafeCleaner.dmg`
  on disk is still the notarized 0.5.1. Only the author can re-store the profile (it needs the
  Apple ID app-specific password).

## 0.5.2 — Xcode device symbols, documentation indexes, device logs and archives, 30 October 2026

- Version-aware Trash candidates under `~/Library/Developer/Xcode`, no process: device
  symbols below the newest OS version per platform, every documentation index, per-device
  logs whose newest file is 30 days old, archives 180 days old by their `Info.plist` creation
  date. Measured read-only on the author's Mac: the one `iOS DeviceSupport` entry
  (iPhone15,3 26.5.2, 5.6 GB) is the newest and is kept; the four archives (514 MB) are 3 to
  68 days old and are kept; there is no documentation cache; one device-log folder whose
  reports were last copied on 17 September (1 MB) would be offered. No hard links or special
  files were found in those trees.
- **172 XCTest tests passed:** 115 core, 52 presentation, 5 service. New tests cover version
  and build parsing of DeviceSupport names (a model identifier is never a version), the
  newest-per-platform rule (both devices on the newest version kept, a lone watchOS version
  kept, unversioned folders skipped), documentation indexes (schema folder descended, loose
  files ignored), device logs (per device, 30-day idle by newest file, UDID stripped from the
  title, the legacy `iOS Device Logs` folder), archives (keep period, app/version/build/bundle
  ID from `Info.plist`, folder-name date fallback, empty date folders and loose files never
  findings, a date folder never a finding), scanner integration (category, owner, root,
  exclusions, DerivedData rule untouched, provisioning profiles never listed) and an absent or
  empty Xcode folder.
- `check-boundaries.py` passed. Native arm64 Debug `xcodebuild` succeeded. Project regenerated
  for `XcodeStores.swift`. Version 0.5.2 (9).

### Not performed

- Nothing was moved on the author's Mac. Whether Xcode re-copies symbols from a device that
  has since updated past a removed version was not exercised; the newest version is kept
  regardless, so a removed entry is always older than one Xcode already has.

## 0.5.1 — Android NDK, system images and emulator snapshots, 30 October 2026

- Version-aware Trash candidates, no process: NDK versions no project names except the newest
  installed; system images no AVD uses; the `snapshots` folder of each stopped AVD (the
  emulator's `hardware-qemu.ini.lock` marks a running one). Measured on the author's Mac this
  offers NDK 25.1, 26.1 and 27.0 (7.5 GB; 28.2 is named and newest), two system images
  (4.7 GB) and the Pixel 9 Pro snapshots (8.5 GB). No hard links or special files were found
  in those trees, so the snapshot digest accepts them; interior symlinks are counted.
- **165 XCTest tests passed:** 108 core, 52 presentation, 5 service. New tests cover reference parsing (Gradle quoting styles,
  comments, `build/`-nested files ignored, Flutter's unresolved version flagged, `sdk.dir`,
  AVD configs), the NDK rule (newest kept, named kept, prefix references), the image rule
  (only directories with a real image, only unreferenced), the snapshot rule (running AVD
  skipped with an issue, user data and the device itself never listed), scanner integration
  (category, owner, exclusions) and an SDK outside home reported rather than scanned.
- `check-boundaries.py` passed. Native arm64 Debug `xcodebuild` succeeded. Project regenerated
  for `AndroidSDK.swift`. Version 0.5.1 (8).

### Not performed

- Nothing was moved on the author's Mac. Which NDK Flutter's `flutter.ndkVersion` resolves to
  was not determined; the reason line says so and a build re-downloads a removed version.

## 0.5.0 — simulator runtimes and devices via simctl, 30 October 2026

- First tool-managed adapter. The scan runs `xcrun simctl runtime list -j` and
  `xcrun simctl list devices -j` through `ToolRunner`, the only place the app launches a
  process (validated executable from the `ToolCommand` catalogue, minimal environment, no
  stdin, 120 s timeout, terminated on cancellation). Offered only: deletable runtimes that are
  not the newest for their platform, unused for 30 days, with no booted or recently used
  device; shut-down, available devices with data, unused for 30 days. Removal is
  `simctl runtime delete <uuid>` / `simctl delete <udid>` one item at a time, after a fresh
  inventory; an item used since the scan is left in place as “changed”. The identifier is the
  only scan-derived argument and is re-validated as a UUID. Simulator.app open keeps all of
  them in place. Row, selection caption, confirmation sheet, result and Activity all state
  that these removals are permanent and never reach Trash.
- **159 XCTest tests passed:** 102 core, 52 presentation, 5 service. New tests cover parsing,
  every guard (newest, recent, non-deletable, single-platform, busy runtime, booted device,
  zero size, unavailable, 29 vs 31 days), the exact command sequence, the re-check refusing a
  changed item, forged identifiers never reaching a command, tool failures, scan quietness
  without Xcode, exclusions, repository dispatch (tool items never reach the Trash path, left
  in place with a reason without a tool service, kept in place while Simulator runs,
  `CleanupEngine` refuses them), history `method` round-trip and legacy decoding, and the
  presentation copy before and after a mixed cleanup. One service test lists devices through
  the real runner read-only and is skipped where simctl is absent.
- `check-boundaries.py` passed. Native arm64 Debug `xcodebuild` succeeded. Project regenerated
  for `Simulators.swift` and `ToolRunner.swift`. Version 0.5.0 (7).

### Not performed

- No simulator runtime or device was removed on the author's Mac; the delete path was
  exercised only through the fake runner. The first real removal is the user's to run, after
  reviewing the row and quitting Simulator.
- The app was built but not opened; the new category tile, badge and confirmation copy were
  verified through presenter and view-model tests, not on screen.

## 0.4.1 — key status, Test key, Claude 5.5 models, 30 October 2026

- Audit of the 0.4.0 Claude integration. Findings fixed: no way to learn whether a saved key
  works short of a paid request; Anthropic's error body (which names the cause) was discarded and
  transport errors were flattened to “could not be reached”; Sonnet 5.5 could never succeed, since
  the decoder required exactly one content block and a 1,200-token cap that the model's own
  reasoning consumes; Haiku 4.5 was a dated snapshot ID at ten times the price of Haiku 5.5; the
  send button was disabled without a reason; key presence was read once at launch only.
- Added **Test key** (one free `GET /v1/models/{model}`), a five-state key indicator in Settings
  and Claude review, sanitized surfacing of Anthropic's error type and message, a reason line under
  a disabled send button, key-presence refresh when opening Settings or Claude review, admin-key
  rejection on save, thinking-aware response decoding, `effort: low` with `max_tokens` 4,000,
  model IDs `claude-haiku-5-5` and `claude-sonnet-5-5`, and `anthropic-version: 2026-10-21`.
- Fixed a pre-existing test, `testIdleDaysReadsTheDirectoryModificationDate`, which failed every
  day whose 40-day look-back crosses a daylight-saving change (it used 40 × 86,400 s, the
  implementation counts calendar days). The fixture now uses calendar arithmetic.
- **145 XCTest tests passed:** 90 core, 51 presentation, 4 service. New tests cover the
  Models-endpoint request shape and timeout, 401 bodies on both requests, thinking-block decoding,
  error-kind mapping and bounding, model-ID matching, the request's effort/version/model fields,
  admin-key refusal, the key-status transitions, the send hint, and Keychain refresh on navigation.
  No real API key or network request was used.
- `check-boundaries.py` passed. Native arm64 Debug `xcodebuild` succeeded. Version 0.4.1 (6).

### Not performed

- Live Anthropic authentication, Test key against a real account, real response generation on
  Haiku 5.5 / Sonnet 5.5 and billing need the user's API key. The 4,000-token cap with low effort
  is taken from Anthropic's migration guidance and has not been measured on a real plan.
- The app was built but not opened; the new status row and hint were verified through the
  presenter and view-model tests, not on screen.

## 0.4.0 — optional Claude review, 3 October 2026

- Added opt-in Messages API review with Haiku 4.5 / Sonnet 5.5, Keychain credentials, a fixed
  endpoint, no redirects, ephemeral networking, bounded grouped input and structured output.
- **92 XCTest tests passed:** 69 core, 21 presentation, 2 service. The new tests cover payload
  privacy and grouping limits, changed-snapshot fingerprints, rejected/truncated/unknown-ID
  responses, scan-only restrictions, credential validation through a fake store, no requests on
  save/start/scan, no auto-selection, cancellation, preview isolation, failure recovery and
  request reuse without another transport call. No real API key or network request was used.
- `check-boundaries.py` passed. Native arm64 Debug `xcodebuild` succeeded. Updated generated
  bundle version and sidebar to 0.4.0 (5); no new distribution/notarization was performed.
- Opened the native app and checked Claude review and Settings: model picker, privacy notice,
  payload disclosure, secure field, disabled send/save controls without a key, and readable layout.
- Updated network/privacy copy and the privacy manifest for optional aggregate data sent under
  the user's API account. No analytics or tracking was added.

### Not performed

- Live Anthropic authentication, real response generation and billing need the user's API key.
- Keychain write/read/delete on the user's real account and behavior across signed upgrades were
  not exercised; the implementation compiles, and repository tests use an injected fake store.
- No cleanup was performed. The advisor uses existing scan coverage; it does not add adapters,
  inspect file contents or establish last-use/activity facts.

## 0.3.0 — audit remediation and project build output, 19 September 2026

Addresses audit items A2, A6 and A9 from `docs/analysis/AUDIT-2026-09-18.md`.

- **Candidate-root package exemption.** `~/Library/Caches/org.swift.swiftpm` carries a `.swiftpm`
  extension, so `isPackage` was true for the candidate root and `FileSafety.snapshot` threw before
  reading a child — the Swift package cache rule was dead on every Mac. The guard now exempts the
  root only. Measured on the author's machine with `probe-guards.swift`: that rule went
  `REFUSED (package)` → `ACCEPTED [973,8 MB, 689 files]`, and the seven developer rules together
  went **674,3 MB → 1,65 GB**. The guard had no test at all before.
  **Superseded later the same day** by the A4 change below, which stopped packages refusing
  anywhere, making the root exemption redundant; its plumbing and its nested-package test were
  removed. The measurement above still stands as the intermediate step.
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
- Intermediate regression after the scanner work: 51 XCTest tests passed, with one deliberate policy
  assertion rewritten as described above.

- **Tool command allowlist (no execution yet).** Simulator runtimes, Docker images and Homebrew
  downloads cannot be reclaimed by moving folders — deleting them corrupts the owning tool — so the
  app will run commands. `ToolCommand.init` is private, so the only instances that exist are the
  literals in the catalogue; arguments are compile-time literals; `Process` receives an executable
  and an argv with no shell; paths are absolute and re-validated before each run. Ownership is
  deliberately **not** required to be root, because Homebrew on Apple Silicon and the Android tools
  install into user-owned prefixes; what is checked is that *other* users cannot modify the binary.
  Flags were verified against the installed tools rather than assumed. 13 tests, including that the
  real `xcrun`, `brew` and `docker` on this machine pass validation. **Nothing executes yet.**
- **Access warnings now cover only what the scanner reads.** The first version demanded Full Disk
  Access to read Trash — a folder the scanner permanently protects and never cleans — so no grant
  could clear the warning and it returned after every launch. Probes are now `~/Library/Caches`,
  `~/Library/Logs` and the user's project roots. Verified against the real home directory: nothing
  blocked, warning absent.
- **Three defects found by using the app, not by the suite.** All three passed a green test run:
  the sidebar still read `viggoclean` (built as `Text("viggo") + Text("clean")`, so no search for
  the product name could match it); the Overview reported 30,11 GB of project builds as "Scan only"
  because the label was keyed off the category rather than the candidates; and the permission loop
  above. The first is now guarded by `check-boundaries.py`, which greps the rendering layers for the
  fragment and fails the build — verified by reintroducing the old string.
- Regression at release: **75 XCTest tests passed** (60 core, 15 presentation), boundary checker
  passed, `xcodebuild` Debug build succeeded.

### Not performed

- **NO CLEANUP HAS EVER BEEN EXECUTED.** This is the significant gap in this release. Every number
  above is measurement through the real scanner; not one file has been moved to Trash by the new
  rules, in testing or in use. The cleanup path is covered by unit tests against synthetic files and
  in-memory fakes only. Trash and restore one small stale candidate before trusting a 30 GB batch.
- The three defects listed above were found by opening the app, while the suite was green. Treat the
  passing count as evidence about the core, not about the product.
- Tool commands do not execute. The allowlist and its validation are complete and tested; no runner
  exists, so simulator runtimes, Docker images and Homebrew downloads are still unreachable.
- 7 build directories still refuse on interior hard links, and 3 on cross-volume or special files.
  Neither was investigated.
- The history reset control has never been exercised in the running app, only through the ViewModel.
- Whether Full Disk Access makes the 39 GB of simulator runtimes reachable is **unverified**; the
  assumption that it does has not been tested.
- The 30-day idle threshold is displayed, not enforced: nothing filters or sorts by it yet, so the
  user still reads the age per row.
- Tests use synthetic files and in-memory fakes throughout.

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
