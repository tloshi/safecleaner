# What the open-source Mac cleaners do well — and what SafeCleaner should take

*30 October 2026. Fourteen GitHub repositories read through the GitHub API only (nothing cloned
or run), by three parallel research agents, then cross-checked against
[STRATEGY-2026-09-18.md](STRATEGY-2026-09-18.md) and the disk measured on the author's Mac the
same day (371 GiB used of 460; see `docs/VALIDATION.md` 0.5.x). Licences matter: GPL projects
are read for ideas only, never code; SafeCleaner is proprietary and native Swift, so every
mechanism below is a reimplementation.*

## The field

| Repository | Stars | Licence | Kind | Removal | Root |
|---|---|---|---|---|---|
| tw93/Mole | 73k | GPL-3 | shell CLI, paid native app | `clean`/`purge` permanent; `uninstall` to Trash | asks admin when needed |
| alienator88/Pearcleaner | 15k | source-available | uninstaller GUI (on hold) | Trash + undo | privileged XPC helper |
| voidcosmos/npkill | 9.5k | MIT | CLI | `rm -rf` | no |
| momenbasel/PureMac | 7.5k | MIT | GUI, notarized | mixed; uninstall/orphans/duplicates to Trash | AppleScript admin |
| Tencent/lemon-cleaner | 6.4k | GPL | GUI | mixed, root daemon | yes |
| mac-cleanup/mac-cleanup-py | 2.4k | Apache | CLI | `rm -rf` | sudo for some |
| iliyami/MacSai | 2.0k | BSD-3 | GUI, notarized, cask | Trash-first, dry-run | root XPC helper |
| guhcostan/mac-cleaner-cli | 2.0k | MIT | CLI + Electron | `fs.rm`, optional backup | sudo maintenance |
| vashpan/xcode-dev-cleaner | 1.6k | GPL-3 | GUI (Mac App Store) | `removeItem` | no |
| bysiber/cleardisk | 746 | MIT | menu bar | Trash, verified after the move | no |
| 137137137/OpenDisk | 343 | MIT | disk analyzer | Trash or permanent | no |
| lumen-xx/spare | 39 | MIT | GUI, signed not notarized | Trash + tool commands | tiny helper |
| leoAnimesh/OpenClean | 39 | GPL-3 | GUI, notarized | own quarantine, or delete | admin where needed |
| eslamfaisal/mac-cleaner | 29 | MIT | local web dashboard | Trash or `rm` | no |

Nobody in this list combines Trash-only, no root, review-everything and version-aware
retention. That is still the open lane the September strategy identified. What the field is
good at is three things SafeCleaner lacks: breadth of catalogue, a few safety mechanisms, and
the UX around permissions and the weekly chore.

## Tier 1 — coverage with version-aware retention (the biggest GB on this Mac)

Ordered by measured size here × safety fit. All are Trash moves unless stated.

1. **Gradle per version** (30.6 GB here; 6 version caches, 13 wrapper versions pinned by
   projects). *[Implemented in 0.5.4 as `GradleStores`; `jdks` is kept, `daemon/<version>` and `.tmp` are offered.]* Candidates: `~/.gradle/caches/<version>` not pinned by any
   `gradle-wrapper.properties` `distributionUrl` under the project roots; `~/.gradle/wrapper/dists/<dist>` likewise; `~/.gradle/jdks`, `~/.gradle/daemon`, `~/.gradle/.tmp`.
   Guard: no Gradle daemon running (`GradleDaemon` process). Consequence: the next build
   re-downloads and rebuilds; `modules-2` can be large. From eslamfaisal/mac-cleaner,
   cleardisk, mac-cleaner-cli (mac-cleanup-py takes the whole directory: do not copy).
2. **Kotlin/Native per version** (11.1 GB here; 7 versions, catalogs reference 5). *[Implemented in 0.5.4; `~/.kotlin` is not touched.]*
   `~/.konan/kotlin-native-prebuilt-*-<version>` and `~/.konan/dependencies/*` not referenced
   by a `kotlin` version in any `libs.versions.toml` or Gradle file; `~/.kotlin` when the
   Kotlin daemon is stopped. From eslamfaisal/mac-cleaner.
3. **Xcode per-version stores.** `iOS/watchOS/tvOS/visionOS DeviceSupport/<version>` all but
   the newest per OS (5.6 GB here; symbols re-copy on next device connect);
   `DocumentationCache/*/<version>` for versions other than the installed Xcode;
   `iOS Device Logs` all but newest; `XCTestDevices`, `XCPGDevices`, `DVTDownloads`,
   `UserData/Previews` when Xcode and Simulator are not running. **Archives** only as an
   inventory with app, version, build, date and upload status, never in a safe bucket: dSYMs
   of shipped builds cannot be regenerated. From DevCleaner, cleardisk, eslamfaisal.
4. **IDE caches by version.** `~/Library/Caches/Google/AndroidStudio*` older than the newest
   and idle 90 days (13.7 GB of Google caches here), `~/Library/Caches/JetBrains`,
   `~/Library/Logs/JetBrains`, VS Code and Cursor `Cache`, `CachedData`, `Code Cache`,
   `GPUCache`, `CachedExtensionVSIXs`. Never `workspaceStorage` or the settings side under
   `Application Support`. Guard: IDE not running.
5. **Heap dumps and agent worktrees.** `~/*.hprof` and `java_pid*.hprof` (2.1 GB here, may
   hold secrets, not regenerable, so "your call"); `~/.claude/worktrees`, `~/.cursor/worktrees`,
   `~/.codex/worktrees` only when the tree is clean, pushed and idle 7+ days. From
   mac-cleanup-py and mac-cleaner-cli.
6. **Docker through the Engine API, per resource type** (21 GB image here): `/system/df`
   inventory, then build cache, dangling images and stopped containers as three separate
   consents; never volumes; say plainly that the host file shrinks only after Docker Desktop
   restarts. From mac-cleaner-cli (mac-cleanup-py's `system prune -af` is the thing to avoid).
7. **Package-manager caches**, each its own rule with fixtures: pnpm, yarn, bun, uv, poetry,
   conda, cargo registry, composer, nuget, `~/.pub-cache`, `~/.dartServer` (2.4 GB here),
   Playwright, Cypress, puppeteer, electron. Go's module cache is read-only on disk, so Trash
   fails; offer `go clean -modcache` as a tool command or only `go/pkg/mod/cache`. From
   cleardisk's catalogue of ~90 entries and Mole's `dev.sh`.
8. **Homebrew old versions** via `brew cleanup -n` then `brew cleanup --prune=all` as a tool
   command. Low value here (99 MB) but common elsewhere. From mac-cleaner-cli.

## Tier 2 — safety mechanisms worth adding (cheap, and they widen the moat)

1. **Open-file check with libproc** (Spare): before moving a tree, ask which processes hold
   files inside it open and refuse with the process name. Today only the owning app's bundle
   ID is checked; a standalone emulator or a Gradle daemon slips through.
2. **Writability guard, then verified move** (cleardisk): refuse to offer a tree that is not
   writable, and after `trashItem` confirm the source is gone before counting bytes as moved.
3. **Sensitive-location denylist for project artifacts** (npkill): a `node_modules` under
   `~/Library/Application Support`, `Containers`, `~/.config`, `~/.local/share` or inside an
   `.app` belongs to an installed app, never to a project.
4. **Structural tests for the single destructive path** (OpenClean, and strategy item 7): one
   test proves only `CleanupEngine` calls `trashItem` and only `ToolRunner` launches a
   process. `ToolCommandTests` already does this for commands; extend it to the filesystem.
5. **Network-surface audit in CI** (MacSai): a script that runs `nm -u` and `strings` on the
   built binary and fails if any network symbol is used outside `ClaudeService`, plus the same
   snippet in the README for users to run.
6. **Fail-closed inventories** (Mole): when a tool inventory times out or is partial, offer
   nothing from it. `SimulatorScan` already does this; keep it as a stated rule.
7. **Decision on hard links.** SafeCleaner refuses hard-linked trees; pnpm, bun and cargo
   stores are built from hard links, so they can never be offered. cleardisk sizes them by
   dividing by link count. Either keep the refusal and say why, or size by link count and move
   the whole store as one unit.

## Tier 3 — UX for the weekly chore

1. **Full Disk Access flow.** Show guarded folders as "locked" without triggering per-folder
   prompts (Spare); after a permission failure open Settings, reveal the app bundle, poll once
   a second and retry the failed batch once granted (PureMac); a permissions page with status
   per protected area and no launch-time prompts (MyMacCleaner).
2. **Reminder, never a scan.** A local notification on a chosen cadence, gated by "the last
   scan found more than N GB", with nothing running in the background and no LaunchAgent
   (OpenClean and PureMac offer schedules; theirs clean, which SafeCleaner must not).
3. **"What grew since last scan."** The activity history exists; add the per-store delta so the
   weekly review starts from what changed. Nobody surveyed does this.
4. **A "typical" badge, not a preselection** (Lemon's `recommend`, Spare's "Your Call"): keep
   everything unselected, but mark regenerable caches as typical and non-regenerable items
   (archives, heap dumps, worktrees) as your call, so review is faster without losing control.
5. **Menu-bar free-space indicator**, read-only, opens the app (Lemon, MacSai, PureMac).
6. **Scan cache and incremental rescan** (OpenDisk): `getattrlistbulk` with about eight
   readers, a cached tree and FSEvents replay make rescans 20× faster. Relevant once the disk
   explorer (roadmap phase 4) exists.
7. **Receipts** (strategy item 2): "moved · freed now · gained after emptying Trash", exportable.

## Tier 4 — larger features, mapped to the roadmap

- **Phase 3, app leftovers and uninstaller.** Evidence tiers before anything is listed:
  container metadata bundle ID and package receipts (certain), exact bundle-ID directory or
  Team ID prefix (strong), substring (weak, shown but never preselected). Guards from the
  field: 30-day age (Mole), same-vendor-still-installed (Lemon), minimum 5-character match and
  UUID-name skip (Pearcleaner), fail closed when the installed-app inventory is incomplete
  (Mole). A Trash watcher that offers a leftover review when an `.app` is trashed
  (Pearcleaner's sentinel) is user-space and optional.
- **Phase 4, duplicates and large files.** One protected keeper, a byte-compare immediately
  before moving the extras (PureMac), and "consolidate" through an atomic APFS clone instead of
  deletion (MacSai, Sift): clone to a temp name, copy attributes, rename over the original,
  never across volumes or on open files. Large and old files are listed, never selected.
- **Phase 4, disk explorer.** OpenDisk's reader pool, mount-point and snapshot boundaries,
  partial rendering during the scan, and a collector tray (Trash only).

## Do not copy

Root helpers and daemons (Pearcleaner, MacSai, Lemon); permanent deletion as a default (Mole
`clean`/`purge`, npkill, mac-cleanup-py, DevCleaner); whole-folder items for `~/Library/Caches`,
Downloads or the Trash; memory "optimizers" and DNS flushes sold as cleanup; Apple's private
cleanup service (Spare); browser password or cookie deletion (MyMacCleaner, mac-cleanup-py's
Arc module); editing `/etc/pam.d` (Sift); an app-managed quarantine instead of the system
Trash (OpenClean); unnotarized distribution (Spare, MyMacCleaner); unattended scheduled
deletion (PureMac). cleardisk's issue #27 is the cautionary tale: a user lost every Claude
CoWork session because `~/.claude` was labelled "caution"; names lie, and agent profile
directories stay excluded.

## Sources

Repositories: tw93/Mole, alienator88/Pearcleaner, Tencent/lemon-cleaner, vashpan/xcode-dev-cleaner,
voidcosmos/npkill, mac-cleanup/mac-cleanup-py, guhcostan/mac-cleaner-cli, bysiber/cleardisk,
eslamfaisal/mac-cleaner, iliyami/MacSai, Kevin-De-Koninck/Clean-Me (archived), momenbasel/PureMac,
lumen-xx/spare, leoAnimesh/OpenClean, Prot10/MyMacCleaner, 137137137/OpenDisk, SadeepaNHerath/Sift.
Web: openalternative.co/alternatives/cleanmymac, thesweetbits.com/free-mac-cleaning-software,
bysiber.github.io/cleardisk/blog/free-disk-space-mac-developer.
