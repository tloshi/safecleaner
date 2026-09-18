# SafeCleaner

A personal, native macOS cleaner. Understand disk usage, review every candidate, and move selected caches to Trash.

**macOS 14+ · Swift / SwiftUI · No third-party packages · No network service**

## Start

Open `SafeCleaner.xcodeproj` in Xcode, select **SafeCleaner → My Mac**, then Run (⌘R). The Xcode project uses ad-hoc local signing; no paid developer account is required for this local development build.

Or build a standalone application:

```sh
./scripts/build-app.sh          # universal (arm64 + x86_64), signed
open build/SafeCleaner.app
```

`build-app.sh` signs with the first `Developer ID Application` identity in your keychain. With
none present it falls back to ad-hoc signing and says so: an ad-hoc build is rejected by
Gatekeeper on any other Mac, and its identity changes on every rebuild, which silently drops
any Full Disk Access grant. Create the certificate at
[developer.apple.com](https://developer.apple.com/account/resources/certificates) — it is free
with an existing membership.

To produce a distributable disk image:

```sh
xcrun notarytool store-credentials safecleaner-notary \
    --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>   # once
./scripts/build-app.sh --notarize
```

That builds, signs, packages `build/SafeCleaner.dmg`, submits it to Apple, waits for the result
and staples the ticket to the image. Override the identity with `SAFECLEANER_SIGN_ID`, the keychain
profile with `SAFECLEANER_NOTARY_PROFILE`, and the architectures with `SAFECLEANER_ARCHS`.

Build and run core tests:

```sh
swift build
swift test
python3 scripts/check-boundaries.py
```

The Swift package is also openable in Xcode. The `.xcodeproj` produces the native app bundle; the package exposes the independently testable core.

## Releasing a new version

Every release is built, notarized and stapled from a clean tree. The keychain profile created by
`notarytool store-credentials` is permanent, so only the first release needs that step.

1. **Bump the version.** It currently lives in two places and they drift silently:
   - `scripts/generate-project.py` — `CFBundleShortVersionString` and `CFBundleVersion`,
     then run `python3 scripts/generate-project.py` to rewrite `Info.plist`.
   - `Sources/SafeCleaner/Views/WorkspaceScreens.swift` — the About line.

   Do not hand-edit `Info.plist`; the generator owns it and will overwrite the change.

2. **Verify.**

   ```sh
   swift test && python3 scripts/check-boundaries.py
   ```

3. **Record what was and was not tested** in `docs/VALIDATION.md`, per version. Keep the
   "not performed" list honest; it is the part of that file worth reading.

4. **Build, notarize and staple.**

   ```sh
   ./scripts/build-app.sh --notarize
   ```

   Expect two to fifteen minutes at the `--wait` step; that is Apple's queue, not a hang.
   Success reports `status: Accepted` followed by `The staple and validate action worked!`.
   The ticket is stapled to `build/SafeCleaner.dmg`, which is what people download, so the
   image validates offline. The script's closing Gatekeeper line re-checks the `.app`, which
   was signed before the submission and carries no ticket of its own — judge the run by the
   stapler result, not that line.

5. **Tag and ship.**

   ```sh
   git tag -a v0.3.0 -m "SafeCleaner 0.3.0"
   ```

### Version numbers

`CFBundleShortVersionString` is the version people see. `CFBundleVersion` is a build counter that
must strictly increase and must never be reused, because Apple rejects a repeated build number and
update mechanisms compare it. Notarization is per build, not per app: every disk image handed to
anyone needs its own submission.

### What survives an update

The signed app's designated requirement is anchored to the bundle identifier and the Team ID
rather than to a per-build code hash:

```text
identifier "com.loshi.safecleaner" and anchor apple generic
  and certificate leaf[subject.OU] = F3X3EF7L5N
```

So a rebuild keeps the same identity to macOS, and any Full Disk Access the user granted survives
the update. Ad-hoc builds do not have this property: their requirement is a bare code hash, and a
one-character version bump is enough to make macOS treat the app as a different program and drop
the grant.

### Known gap: there is no update channel

The app does not check for, announce or install updates, and nothing here publishes an appcast.
Anyone given a disk image stays on that build until they are handed another one by hand. For a tool
whose worst failure is moving a file someone needed, that means a safety fix currently has no
delivery path. Closing it means either a version check that reports a newer release, or Sparkle for
real in-app updates — and either one adds an outbound network request, so the "no network requests
or telemetry" claim in this README and in the app's own About text has to change with it.

## What works in 0.2

- Real disk capacity and free-space display. No pre-populated fake scan results.
- Read-only scanning with progress and cancellation.
- Targeted developer-cache rules: Xcode DerivedData, SwiftPM, npm `_cacache`, Gradle `build-cache-1`, CocoaPods, Homebrew downloads and pip.
- Third-party immediate children of `~/Library/Caches`, individually reviewed; Apple caches are excluded.
- Browser cache classification in user cache locations. Browser profiles are not targeted.
- `.log` files under user logs that have not changed for over 30 days.
- Explicitly selected local project roots. Detection of `.next`, `.dart_tool` and selected `build` directories is **scan-only**.
- Search, category filters, per-item details, Show in Finder, exclusions and manual selection.
- A confirmation sheet showing exact paths; acknowledgement to close apps and stop builds/installations.
- Revalidation of the tree before Trash; no permanent-delete fallback.
- Persistent local cleanup history with Finder links. Restore uses Finder’s Trash; no automated restore yet.
- Clearly reported skipped locations, partial project scans and failures.

## Architecture and motion

Services → Repository → ViewModel → ViewState → passive Views, assembled through constructor injection. SwiftUI views render snapshots and emit actions; they do not call the filesystem, AppKit services, settings or persistence. Navigation, number changes, storage/category rings, row expansion and button feedback animate while respecting macOS Reduce Motion. See `docs/ARCHITECTURE.md`.

## First use

1. Open the app and choose **Scan Mac**.
2. Review results and skipped locations in Overview.
3. Optionally add folders in **Projects**, then scan again.
4. In **Review & clean**, expand each candidate before selecting it.
5. Close related applications and stop build/install processes. Known running owner apps block cleanup; unknown command-line processes cannot yet be detected reliably.
6. Confirm the exact selection to move items to Trash. The app never empties Trash.

## Current limits

This is a conservative development release, not a claim to clean the entire system. Broad app-cache detection is based on location and still requires human review. Project marker detection is provisional and cannot trigger cleanup. Tool paths are initial defaults; custom cache locations are not yet discovered.

Snapshot validation checks identity, size and modification metadata, not content hashes. It catches ordinary concurrent changes but does not eliminate the race between validation and a filesystem move. Do not run cleanup while other processes are writing to the selected locations. No root helper or privileged service is installed.

Any selected tree containing symbolic links, hard-linked files, packages, special files, unreadable entries or another device is rejected rather than partially cleaned. This may skip useful candidates. Project scanning is capped at 8 levels / 20,000 directories per root and reports the cap.

Allocated bytes are an estimate. APFS sharing, snapshots, compression and Trash mean candidate size is not guaranteed physical space recovered. The app does not call moved bytes “freed”.

## Privacy and storage

- Settings: app-scoped UserDefaults (`com.loshi.safecleaner` in the app bundle).
- Activity: `~/Library/Application Support/SafeCleaner/history.json`.
- No analytics, telemetry, remote classification or automatic file uploads.
- No automatic scan, automatic cleanup or launch agent.
- macOS permissions and SIP are respected. Missing access is visible in results; Full Disk Access is not automatically granted or required blindly.

## Design preview

For visual development only:

```sh
open build/SafeCleaner.app --args --preview-data
```

Close any running instance first. The preview is explicitly labelled, uses synthetic candidate data and disables scanning/cleaning. Normal launch always uses real data.

## Project layout

```text
Sources/SafeCleaner/                 Passive Views, DesignSystem, Services and Composition
Sources/SafeCleanerCore/             Domain, service contracts, repository and file safety
Sources/SafeCleanerPresentation/     ViewModel, immutable ViewState and pure Presenter
Tests/SafeCleanerCoreTests/          Filesystem safety and repository tests
Tests/SafeCleanerPresentationTests/  ViewModel tests with a fake repository
docs/ROADMAP.md              Product, UI and engineering roadmap (Shqip)
docs/ARCHITECTURE.md         Invariants, limitations and extension guidance
scripts/build-app.sh        Build and ad-hoc sign the local .app
scripts/generate-project.py Regenerate the checked-in Xcode project
```

## Documentation used

- [SwiftUI WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)
- [Foundation directory enumeration](https://developer.apple.com/documentation/foundation/filemanager/enumerator(at:includingpropertiesforkeys:options:errorhandler:))
- [Foundation Trash API](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))
- [Swift Package Manager](https://github.com/swiftlang/swift-package-manager)

No real user files are removed by the tests. Tests inject a synthetic Trash destination.
