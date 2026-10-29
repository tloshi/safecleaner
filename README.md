# SafeCleaner

A personal, native macOS cleaner. Understand disk usage, review every candidate, and move selected caches to Trash.

**macOS 14+ · Swift / SwiftUI · No third-party packages · Optional Claude API review**

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

1. **Bump the version.** It lives in exactly one place: `scripts/generate-project.py`
   (`CFBundleShortVersionString` and `CFBundleVersion`). Run `python3 scripts/generate-project.py`
   to rewrite `Info.plist`.

   Do not hand-edit `Info.plist`; the generator owns it and will overwrite the change. The About
   line reads the version through `ViewState`, so it cannot drift from the bundle — that is what
   `testVersionReachesViewState` protects.

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

   This submits **twice** and waits both times, so expect roughly double the queue — two to
   fifteen minutes per pass. That is Apple's queue, not a hang. Each pass reports
   `status: Accepted` followed by `The staple and validate action worked!`.

   Both the `.app` and the `.dmg` end up with a stapled ticket. See
   [How the disk image is built](#how-the-disk-image-is-built) for why it takes two passes.

5. **Tag and ship.**

   ```sh
   git tag -a v0.3.0 -m "SafeCleaner 0.3.0"
   ```

### How the disk image is built

Creating the image itself is one command — everything else is signing and notarization around it:

```sh
hdiutil create -volname SafeCleaner -srcfolder <folder> -ov -format UDZO build/SafeCleaner.dmg
```

`-format UDZO` is compressed and read-only, `-ov` overwrites. `build-app.sh` runs this against a
staging folder rather than against the bundle directly, because the staging folder is what lets the
image carry an `/Applications` alias:

```text
Applications -> /Applications
SafeCleaner.app
```

That is the drag-to-install window people expect. Pointing `-srcfolder` at `SafeCleaner.app` yields
an image containing only the app, with nothing to drag it onto.

The order of the remaining steps is load-bearing:

1. **Sign the app** — the image captures whatever state the bundle is in, so signing has to come
   first.
2. **Notarize and staple the app.** Stapling rewrites the bundle, so it must happen before
   `hdiutil` captures it. Skipping this pass leaves the copy dragged to `/Applications` without a
   local ticket: its first launch then needs a round trip to Apple, and warns anyone who is offline.
   The app is submitted as a `ditto -c -k --keepParent` zip, which preserves the symlinks and
   extended attributes inside a bundle in a way `zip` does not.
3. **Create the image** from the stapled app.
4. **Sign the image.** An unsigned image still staples and still validates, but reports
   `code object is not signed at all` to `codesign` and "no usable signature" to Gatekeeper's own
   assessment.
5. **Notarize and staple the image** — that is the file people actually download.

Styling the mounted window further (size, icon positions, a background image) means creating the
image as `-format UDRW`, mounting it, setting the layout through Finder AppleScript, unmounting and
`hdiutil convert`-ing to `UDZO`. Tools like `create-dmg` wrap that, at the cost of the first
third-party dependency in a project that currently has none.

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
real in-app updates. Update checks would be a separate network feature from the optional Claude review.

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

## Claude review (0.4)

1. In **Settings → Claude**, paste your Anthropic API key and choose **Save to Keychain**, then **Test key**. The test is one free request that confirms Anthropic accepts the key; it sends no scan data.
2. Run a normal scan, then open **Claude review**. The key status is shown there too, and a line under the send button says why it is disabled, if it is.
3. Use Haiku 5.5 for economy, or choose Sonnet 5.5. Preview the exact scan-data payload, then click **Send summary to Claude**.
4. Review the advice and actual token usage. **Review these items** filters the local list; it does not select, delete or authorize anything.

There is one bounded request, at most 16 aggregate groups, a 12 KB application request-body cap,
and a 4,000-token output cap that includes the model's own reasoning. There are no tool calls,
chat history, automatic retries or model fallbacks. Failures show Anthropic's own reason. The most recent unchanged analysis is reused in memory; quitting clears that cache.
The byte cap is not an exact input-token or dollar limit: Anthropic adds structured-output overhead.
The API account controls spending limits. No paid request is made just by saving a key or scanning.
See [Claude integration](docs/CLAUDE.md) for the privacy boundary, sources and limitations.

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
- No analytics, telemetry or automatic uploads. Optional Claude review sends grouped scan statistics directly to Anthropic only after an explicit action. API keys live in macOS Keychain; paths and file contents stay local.
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
scripts/build-app.sh        Build, sign (Developer ID) and optionally notarize the .app
scripts/generate-project.py Regenerate the checked-in Xcode project
```

## Documentation used

- [SwiftUI WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)
- [Foundation directory enumeration](https://developer.apple.com/documentation/foundation/filemanager/enumerator(at:includingpropertiesforkeys:options:errorhandler:))
- [Foundation Trash API](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:))
- [Swift Package Manager](https://github.com/swiftlang/swift-package-manager)

No real user files are removed by the tests. Tests inject a synthetic Trash destination.

## License

Proprietary. See [LICENSE](LICENSE).

SafeCleaner is not open source. The source is published for inspection — reading it grants no right
to use, copy, modify or redistribute it. Planned model: a 14-day evaluation, then a paid license.

Nothing enforces the evaluation period yet. Until a licensing mechanism exists, the LICENSE
describes the intended terms rather than terms the app applies on its own.
