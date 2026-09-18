# Ground truth — measured on the author's Mac, 2026-09-18

> ## ⚠️ CORRECTIONS (added after the strategy research caught them)
>
> This document's first version had three errors. They matter because the strategy roadmap was
> calibrated on these numbers, so its per-phase GB figures are understated by ~30 GB.
>
> 1. **`~/Library/Application Support/Claude` = 17 GB was never measured.** `vm_bundles` 12 GB,
>    `simulator-builds` 1.7 GB, `Cache` 1.0 GB, `local-agent-mode-sessions` 699 MB. I never looked
>    inside `~/Library/Application Support` at all — which also hid **`Google` = 10 GB**, separate
>    from the 6.7 GB in `~/Library/Caches/Google`.
> 2. **`~/.konan` = 11 GB was never measured** — 8+ Kotlin/Native versions (2.4.10 = 2.0 GB,
>    2.4.0 = 1.6, 2.3.20 = 1.4, 2.3.0 = 1.3, 2.2.20 = 1.1, 2.2.0 = 972 MB, 2.2.10 = 940 MB) plus
>    `dependencies` 1.8 GB. The catalogue recorded `authorsMacGB: 0` as a result. This is a *better*
>    version-aware-retention demo than the Android NDK case.
> 3. **`~/.Trash` is NOT empty — it is unreadable.** `du -sh ~/.Trash` returns
>    `Operation not permitted` (TCC-protected). The original probe suppressed stderr with
>    `2>/dev/null`, so silence was misread as zero. **Measuring the Trash requires Full Disk Access** —
>    itself a product-relevant finding.
>
> Lesson for the probes: never suppress stderr when measuring, and treat `EPERM` as a distinct
> outcome from "absent". ~19 GB sat uncatalogued in plain sight.


Every number here was measured directly, not estimated. Volume: 460 GiB, **351 GiB used, 84% full**,
71 GiB available. Re-run `probe-guards.swift` and `probe-ceiling.swift` (same directory) to refresh.

## 1. What ViggoClean 0.2 actually frees today

`probe-guards.swift` replicates `FileSafety.record()`'s guards exactly and runs them against the real
paths from `Scanner.swift:60-68`.

| Rule | On disk | Result |
|---|---|---|
| Xcode DerivedData | 8.2 GB | ❌ REFUSED — symlink at `ModuleCache.noindex/.../Accessibility-*.pcm.lock` |
| SwiftPM cache | 929 MB | ❌ REFUSED — root itself is a package (`.swiftpm` extension → `isPackage == true`) |
| `.gradle/caches/build-cache-1` | 509 MB | ✅ 533 MB |
| `.npm/_cacache` | 33 MB | ✅ 34.7 MB |
| CocoaPods / Homebrew downloads / pip | — | absent on this Mac |

**Total: 568 MB.** Old `.log` files > 30 days under `~/Library/Logs`: **0 files**.

### Why DerivedData is refused
`FileSafety.swift:45-47` (link/special), `:51-53` (package) and `:58-60` (hard link) abort the *entire*
candidate on the first offending entry. DerivedData contains **181 symlinks** (clang `.pcm.lock` files
are symlinks) and **494** `.framework`/`.bundle`/`.app` directories. Zero sockets/fifos.

### Ceiling if the guard is fixed
`probe-ceiling.swift` re-runs with per-entry *skip* instead of whole-tree *refuse*:

```
CANDIDATE                            TODAY     IF FIXED   SKIPPED
Library/Developer/Xcode/DerivedData  REFUSED     8.19 GB      567
Library/Caches/Google                REFUSED     6.67 GB       17
Library/Caches/JetBrains             REFUSED     1.59 GB        7
Library/Caches/com.spotify.client    REFUSED      1.4 GB        4
.gradle/caches/build-cache-1        564.3 MB    564.3 MB        0
Library/Caches/bruno-updater        318.7 MB    318.7 MB        0
Library/Caches/Codex                264.7 MB    264.7 MB        0
Library/Caches/ms-playwright         REFUSED    208.2 MB        1
Library/Caches/claude-cli-nodejs    163.1 MB    163.1 MB        0
Library/Caches/GeoServices           REFUSED     80.7 MB       42
Library/Caches/node-gyp              55.6 MB     55.6 MB        0
.npm/_cacache                        34.7 MB     34.7 MB        0
Library/Caches/org.swift.swiftpm     REFUSED     Zero KB        1
                             TOTAL     1.4 GB    19.54 GB
```

**Two findings that change the design:**

1. **Measured ≠ moved.** Lenient mode reports 19.54 GB but `trashItem` would actually move **21.7 GB** —
   a **2.15 GB under-report**, because the skipped packages/symlinks still travel with the directory.
   The unit of *measurement* and the unit of *movement* must be separated before loosening the guard.
2. **The SwiftPM fix is separate.** It yields `Zero KB` even in lenient mode, because the refusal is on
   the *root*. It needs an explicit root-level package exemption, plus removal of `"org.swift.swiftpm"`
   from the `reserved` list at `Scanner.swift:79` — otherwise 929 MB stays invisible by two mechanisms.

## 2. What is actually on the disk, and the mechanism each needs

The key insight: **most big items are tool-managed stores, not Trash moves.**

| Item | Size | Correct mechanism | Trash? |
|---|---|---|---|
| `/Library/Developer/CoreSimulator/Volumes` | **32 GB** (3 runtimes = 23.2 GB) | `xcrun simctl runtime delete` — root:wheel owned | ❌ |
| `~/.android/avd/Pixel_9_Pro.avd` | **34 GB** — ONE AVD, modified yesterday (live) | `avdmanager delete` / wipe-data | ❌ |
| `Docker.raw` | 27.4 GB allocated / 34.4 GB logical (**sparse**) | Docker Engine API `/images/prune`, `/build/prune` over the socket. Deleting the file destroys all images+volumes | ❌ |
| `/opt/homebrew` | 26 GB — user-owned (`tloshi:admin`) | `brew cleanup` / `autoremove`; most is installed software | partial |
| `~/Library/Android/sdk/ndk` | **10.3 GB — 4 versions** (25.1, 26.1, 27.0, 28.2) | `sdkmanager --uninstall`; keep versions pinned by `ndkVersion` | ❌ |
| `~/.gradle` | 9.9 GB | mixed — see breakdown below | partial |
| Xcode DerivedData | 8.2 GB — 6.0 GB is ONE live project | Trash move (after per-entry fix) | ✅ |
| `~/Library/Android/sdk/system-images` | 7.7 GB (3 images) | `sdkmanager --uninstall` | ❌ |
| `/Library/Developer/CoreSimulator/Caches` | 6.9 GB | root-owned; simctl / Xcode | ❌ |
| `~/Library/Caches/Google` | 6.7 GB | Trash move | ✅ |
| `~/Library/Developer/CoreSimulator/Devices` | 6.3 GB / 12 devices | `simctl delete` by `lastUsedAt` | ❌ |
| iOS DeviceSupport | 5.6 GB | Trash move | ✅ |
| node_modules across repos | ~12 GB | Trash move + staleness check | ✅ |
| `~/Library/Caches/JetBrains` | 1.5 GB (App Support 1.9 GB is **precious**) | Trash move | ✅ |
| `~/.cache/codex-runtimes` | 1.6 GB | Trash move | ✅ |

### Breakdowns
```
~/.gradle 9.9 GB    caches/9.1.0/transforms 4.0G · wrapper/dists 1.9G (6 versions 5.4.1→9.7.1)
                    jdks 1.5G (3 JDKs + 2 leftover .tar.gz ≈550M) · caches/modules-2 1.1G
                    build-cache-1 538M · daemon 379M · caches/jars-9 210M
~/.android 34 GB    avd 34G · cache 9.1M · debug.keystore + adb keys (PRECIOUS, tiny)
Android SDK 22 GB   ndk 10G · system-images 7.7G · emulator 1.1G · platforms 783M
                    build-tools 754M · sources 673M · cmdline-tools 147M
DerivedData 8.2 GB  iosApp (live project, built yesterday) 6.0G · ModuleCache.noindex 1.7G
                    SDKExplicitPrecompiledModules 351M · ViggoClean 150M · SymbolCache 53M
~/.cache 1.8 GB     codex-runtimes 1.6G · firebase 198M · prisma 39M
```

### Absent on this machine
No Time Machine local snapshots (`tmutil listlocalsnapshots /` → empty). No Ollama, Hugging Face,
PyTorch or LM Studio caches. `~/.m2` is 48 KB. Docker was not running.

**NOT absent — unmeasurable:** `~/.Trash` returns `Operation not permitted`. Size unknown without
Full Disk Access. Do not record it as zero.

### Missed in the first pass (added 2026-09-18)
| Item | Size | Note |
|---|---|---|
| `~/Library/Application Support/Claude` | **17 GB** | `vm_bundles` 12 GB; a `.bundle` package `FileSafety` refuses today |
| `~/.konan` | **11 GB** | 8+ Kotlin/Native versions + `dependencies` 1.8 GB |
| `~/Library/Application Support/Google` | **10 GB** | separate from `~/Library/Caches/Google` 6.7 GB |
| `~/.local/pipx` | 2.1 GB | |
| `~/Library/Developer/Xcode/Archives` | 380 MB | |

## 3. Staleness signals that actually work

Verified available on this machine:

- **`xcrun simctl list -j devices`** exposes `lastUsedAt` and `dataPathSize` per device (no `du` needed).
  Measured: 2 devices booted yesterday (3.55 + 2.57 GB), **10 never used** (~20 MB each).
- **`xcrun simctl runtime list -j`** exposes `lastUsedAt`, `sizeBytes` and a `deletable` flag per runtime.
  All 3 runtimes last used 2026-09-17.
- **DerivedData `info.plist` → `WorkspacePath`** resolves to the source project. Both folders on this
  machine point at projects that still exist — so age, not orphanhood, is the signal here.
- Gradle wrapper dists can be cross-checked against each project's `gradle-wrapper.properties`;
  NDK versions against `ndkVersion` in `build.gradle`.

## 4. Ownership — what would need a privileged helper

```
root:wheel   /Library/Developer/CoreSimulator  (+ Volumes, Images, Caches)
root:wheel   /Library/Logs, /private/var/log
root:admin   /Library/Caches                    (sticky, world-writable)
tloshi:admin /opt/homebrew, /opt/homebrew/Cellar
tloshi:staff ~/Library/Containers/com.docker.docker/..., ~/Library/Developer/CoreSimulator/*
```

**A root helper is not the unlock it appears to be** — every root-owned item here is a simulator
artifact, and Apple's own `simctl` deletes those without the app escalating privileges.

## 5. Build and distribution state

- `swift test` → **32 tests pass** in ~30 ms (15 SafetyTests, 7 RepositoryTests, 10 WorkspaceViewModelTests).
  The count claimed in `docs/VALIDATION.md` is accurate.
- `spctl -a -vvv -t exec build/ViggoClean.app` → **rejected**.
  `flags=0x10002(adhoc,runtime)`, `Signature=adhoc`, `TeamIdentifier=not set`.
- `lipo -info` → **arm64 only**. An Intel Mac cannot launch it.
- Bundle is 4 files, **no `Assets.car`** (SwiftPM path copies only binary + Info.plist + .icns).
- `project.pbxproj`: `ENABLE_APP_SANDBOX = "NO"`, `ENABLE_HARDENED_RUNTIME = "YES"`,
  `SWIFT_VERSION = "5.0"`, `CODE_SIGN_IDENTITY = "-"`.
- No `LICENSE`, no `PrivacyInfo.xcprivacy`, **0** logging call sites (`os.Logger|OSLog|NSLog|os_log`).
- `security find-identity -v` → **`Apple Distribution: Taulant Loshi (F3X3EF7L5N)`** exists, so the paid
  membership is active. **Zero `Developer ID Application` certs** — that is a free request from the
  existing account, not a new $99 enrollment.
