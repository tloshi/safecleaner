# ViggoClean

A personal, native macOS cleaner. Understand disk usage, review every candidate, and move selected caches to Trash.

**macOS 14+ · Swift / SwiftUI · No third-party packages · No network service**

## Start

Open `ViggoClean.xcodeproj` in Xcode, select **ViggoClean → My Mac**, then Run (⌘R). The Xcode project uses ad-hoc local signing; no paid developer account is required for this local development build.

Or build a standalone application:

```sh
./scripts/build-app.sh          # universal (arm64 + x86_64), signed
open build/ViggoClean.app
```

`build-app.sh` signs with the first `Developer ID Application` identity in your keychain. With
none present it falls back to ad-hoc signing and says so: an ad-hoc build is rejected by
Gatekeeper on any other Mac, and its identity changes on every rebuild, which silently drops
any Full Disk Access grant. Create the certificate at
[developer.apple.com](https://developer.apple.com/account/resources/certificates) — it is free
with an existing membership.

To produce a distributable disk image:

```sh
xcrun notarytool store-credentials viggoclean-notary \
    --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>   # once
./scripts/build-app.sh --notarize
```

That builds, signs, packages `build/ViggoClean.dmg`, submits it to Apple, waits for the result
and staples the ticket to the image. Override the identity with `VIGGO_SIGN_ID`, the keychain
profile with `VIGGO_NOTARY_PROFILE`, and the architectures with `VIGGO_ARCHS`.

Build and run core tests:

```sh
swift build
swift test
python3 scripts/check-boundaries.py
```

The Swift package is also openable in Xcode. The `.xcodeproj` produces the native app bundle; the package exposes the independently testable core.

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

- Settings: app-scoped UserDefaults (`com.loshi.viggoclean` in the app bundle).
- Activity: `~/Library/Application Support/ViggoClean/history.json`.
- No analytics, telemetry, remote classification or automatic file uploads.
- No automatic scan, automatic cleanup or launch agent.
- macOS permissions and SIP are respected. Missing access is visible in results; Full Disk Access is not automatically granted or required blindly.

## Design preview

For visual development only:

```sh
open build/ViggoClean.app --args --preview-data
```

Close any running instance first. The preview is explicitly labelled, uses synthetic candidate data and disables scanning/cleaning. Normal launch always uses real data.

## Project layout

```text
Sources/ViggoClean/                 Passive Views, DesignSystem, Services and Composition
Sources/ViggoCleanCore/             Domain, service contracts, repository and file safety
Sources/ViggoCleanPresentation/     ViewModel, immutable ViewState and pure Presenter
Tests/ViggoCleanCoreTests/          Filesystem safety and repository tests
Tests/ViggoCleanPresentationTests/  ViewModel tests with a fake repository
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
