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
- Targeted developer-cache rules: Xcode DerivedData per project (0.5.5), SwiftPM, npm `_cacache`, Gradle `build-cache-1`, CocoaPods, Homebrew downloads and pip.
- Simulator runtimes and devices idle for 30 days, removed through `xcrun simctl` after review (0.5).
- Android NDK versions and system images nothing names, and stopped emulators' snapshots (0.5.1).
- Xcode device symbols below the newest OS version, documentation indexes, device logs idle for 30 days and archives older than 180 days (0.5.2).
- Build output with hard-linked files (pnpm-style installs) is offered instead of refused, with only its unique bytes counted and the link count on the row; hard links elsewhere still mean manual review (0.5.10).
- Duplicates: byte-identical files of 1 MB or more in folders you choose and in your project folders, every copy but one offered, the original kept (0.5.9).
- Stale projects: each project's last edit, commit and build read locally, a Stale badge after 60 idle days, a one-step selection of stale projects' build output, and anonymized project rows for the Claude review (0.5.8).
- Docker images no container uses, stopped containers and build cache idle for 30 days, each removed by the docker command by ID, never volumes, never a bare prune (0.5.7).
- IDE caches by version: older Android Studio and JetBrains caches offered one by one, the newest kept; VS Code and Cursor cache folders, never settings or workspace state (0.5.6).
- Before any move: items a running process holds open are left in place and the process named; items you cannot write are listed as not movable; nothing inside credential, mail or backup stores is ever offered; a move counts only once the source is gone (0.5.3).
- Gradle version caches, wrapper distributions and daemon logs no project names (the newest installed stays) plus Gradle's temporary folder, and Kotlin/Native compilers and shared LLVM toolchains nothing names; `modules-2`, `build-cache-1`, configuration and JDKs are never offered (0.5.4).
- Third-party immediate children of `~/Library/Caches`, individually reviewed; Apple caches are excluded.
- Browser cache classification in user cache locations. Browser profiles are not targeted.
- `.log` files under user logs that have not changed for over 30 days.
- Explicitly selected local project roots. Detection of `.next`, `.dart_tool` and selected `build` directories is **scan-only**.
- Search, category filters, per-item details, Show in Finder, exclusions and manual selection.
- A confirmation sheet showing exact paths; acknowledgement to close apps and stop builds/installations.
- Revalidation of the tree before Trash; no permanent-delete fallback.
- Persistent local cleanup history with Finder links. Restore uses Finder’s Trash; no automated restore yet.
- Clearly reported skipped locations, partial project scans and failures.

## Simulators (0.5)

Scanning now lists Xcode simulator runtimes and devices that nothing has used for 30 days.
These are removed by Xcode's own `xcrun simctl`, not moved to Trash, and the app says so on
the row, in the selection summary, in the confirmation sheet and in Activity. The newest
runtime for each platform is always kept, a runtime with any booted or recently used device
is kept, and every item is re-checked immediately before removal. Quit Simulator before
cleaning; while it is open these items are left in place.

## Android SDK (0.5.1)

Scanning also lists NDK versions no project under your folders names (the newest installed
stays), system images no virtual device uses, and the quick-boot snapshots of stopped
emulators. These move to Trash like other items, which is what SDK Manager's uninstall does
minus the way back. Device user data and configuration are never listed.

## Xcode stores (0.5.2)

Scanning also lists Xcode's per-version stores under `~/Library/Developer/Xcode`: device
symbols (`iOS DeviceSupport` and the other platforms) for every OS version except the newest
per platform, which Xcode copies from a device again when it is next connected; documentation
indexes, rebuilt the next time the documentation window opens; per-device crash logs that
received nothing new for 30 days; and archives older than 180 days. An archive is the only
copy of a signed build and its symbols, so its row names the app, version and bundle
identifier and says what symbolication is lost; nothing is ever preselected. All of these move
to Trash. Quit Xcode before cleaning; while it is open these items are left in place.

## DerivedData per project (0.5.5)

Xcode's DerivedData is listed one row per project instead of one folder for all of them, so
live projects stay and stale ones go. Each row names the workspace it was built for (from the
folder's own `info.plist`), says when Xcode last built it (the newest build log or product,
never the index, which changes on every edit) and says plainly when that workspace no longer
exists. A folder without an `info.plist` is still listed under its folder name. The shared
caches beside them (module cache, precompiled SDK modules, symbol cache, SDK stat cache,
compilation cache) are their own rows with their own cost; anything else at that level is
left alone. Quit Xcode before cleaning. The optional Claude review keeps the single fixed
label "Xcode DerivedData" for all of them, so no project name leaves your Mac.

## IDE caches by version (0.5.6)

Android Studio and the JetBrains IDEs keep one cache folder per version under
`~/Library/Caches/Google` and `~/Library/Caches/JetBrains` and retire none, so those folders
grow by one IDE per upgrade. Scanning now lists older versions one by one and always keeps the
newest version of each product; the vendor folder is no longer one all-or-nothing row, and
siblings that are not versioned, such as Chrome's cache inside the Google folder, keep rows
of their own so nothing drops out of the picture. VS Code and Cursor keep caches beside their
settings in Application Support; only the cache folders are offered, never settings,
extensions or workspace state. Quit the IDE before cleaning.

## Docker (0.5.7)

When Docker Desktop is installed and running, scanning lists images no container uses,
stopped containers and build-cache entries, each idle for 30 days, by reading `docker image
ls`, `docker container ls` and `docker buildx du`. Like simulators, these are removed by the
tool, one item at a time, by an ID docker itself reported and re-checked immediately before
removal: `docker image rm`, `docker container rm` without `-v`, and `docker buildx prune` with
an `id=` filter. Volumes are never listed or touched and no bare prune exists. An image a
stopped container still references is kept, exactly as docker would refuse it. Every row says
the removal is permanent and that `Docker.raw`, Docker's disk file, shrinks only after Docker
Desktop compacts it or restarts. With the daemon stopped or Docker not installed, nothing is
listed and nothing is warned about.

## Stale projects (0.5.8)

The Projects screen now says how alive each project is, from local facts only: the last
commit from the git reflog (no git process), the last source edit from file dates with build
output, dependencies and `.git` left out, and the last build from the output's own date. A
project with no edit, commit or build in 60 days is badged Stale; "Select stale build output"
on the Overview and Projects screens selects the build folders and DerivedData of stale,
unprotected projects in one step and opens Review, where nothing moves until you confirm.
The Claude review receives the same facts anonymized as "project 1", "project 2" and so on
(days since edit, days since build, output size, committed or not) and its answer is shown
with the real name added locally; no name or path leaves your Mac.

## Duplicates (0.5.9)

Add folders under Settings ▸ Duplicate folders; your project folders are searched too.
Files of 1 MB or more are grouped by size, then by a partial hash, then by a full SHA-256, so
a match is exact. One copy is kept, chosen deterministically (the shallowest path, then the
oldest file), and every other copy is listed under Duplicates as an ordinary Trash row whose
reason names the kept file; nothing is preselected. Hard links are one file, not two;
symbolic links, packages such as photo libraries, hidden entries, dependencies, build output
and the never-offer list are left out. The walk and the bytes hashed are capped, and reaching
a cap is reported, never hidden.

## Hard-linked build output (0.5.10)

pnpm and similar installers hard-link files into a shared store, and until now any folder
holding a hard link was refused for manual review. Build output nominated beside a project
manifest is now measured with hard links allowed: such files stay in the digest and the
logical size but add nothing to the allocated estimate, because moving one name frees
nothing while another remains, and the row says how many files that affects. The link count
is part of the digest, so a name added or removed elsewhere reads as a change before the
move. Everywhere else a hard link still means a tool- or system-managed store, and the
folder is still refused.

## Safety pack (0.5.3)

Four guards taken from the open-source cleaner survey, each with fixtures:

- **Open-file check.** Immediately before a Trash move, the app reads what your own processes
  hold open through libproc (file descriptors, working directories, executables) and leaves an
  item in place when any of them sits inside it, naming the process and its pid. A Gradle
  daemon or a stand-alone emulator blocks only its own folder. Other users' processes are not
  visible without root, so this is a guard, not a proof.
- **Verified moves.** A move counts only once the source is gone; a Trash operation that
  reports success while the item is still there is recorded as a failure with nothing freed.
  Items you cannot write are measured and listed as *Not movable* instead of failing later;
  SafeCleaner never asks for administrator rights.
- **Never-offer list.** Nothing inside `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`,
  keychains, Mail, Messages, Safari, cookies, accounts, preferences, iPhone backups, Photos or
  cloud mirrors is offered or moved, whichever rule matched it, even inside a project folder
  you pointed at one of them.
- **Full Disk Access.** macOS applies the grant only after a relaunch, so the app remembers
  that it sent you to the settings pane and, on the next launch, says whether access is on and
  that a new scan will include what was hidden.
- **Structural tests.** `swift test` proves from the source tree that exactly one place moves
  files to Trash, nothing deletes, one place launches a process, one place talks to the network
  and one place reads process tables, and that views and presentation never touch the
  filesystem.

## Gradle & Kotlin/Native (0.5.4)

Scanning also lists, under `~/.gradle`, the per-version stores no project under your folders
names in its `gradle-wrapper.properties`: the version cache (`caches/<version>`), the wrapper
distribution (`wrapper/dists/gradle-<version>-bin|all`) and the daemon logs
(`daemon/<version>`), plus the `.tmp` folder Gradle does not always empty. The newest installed
version is always kept, and references are exact: a project on 8.14 does not keep 8.14.3. Under
`~/.konan` it lists the Kotlin/Native compilers (`kotlin-native-prebuilt-macos-<arch>-<version>`)
no version catalog, build file or `gradle.properties` names, keeping the newest per architecture,
and the shared LLVM toolchains, sysroots and libraries under `dependencies/` that no remaining
compiler names in its `konan.properties`. Never offered: `~/.gradle` and `~/.konan` themselves,
`caches/modules-2` (downloaded dependencies), `caches/build-cache-1` (its own rule),
`caches/jars-*`, `gradle.properties`, `init.d`, `jdks`, `kotlin-profile` and `dependencies/cache`.
All of these move to Trash; a build whose version was removed downloads it again. A wrapper or
build file whose version could not be read is stated on the row. Stop Gradle daemons
(`./gradlew --stop`) and quit Android Studio before cleaning; a running daemon holds its files
open and is left in place.

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
