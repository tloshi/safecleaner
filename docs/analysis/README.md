# Analysis — 2026-09-18

Independent audit of ViggoClean 0.2.0 plus measured ground truth from the author's machine.

| File | What it is |
|---|---|
| `AUDIT-2026-09-18.md` | Synthesized audit: verdict, strengths, defects, efficacy, App Store reality, ship checklists |
| `AUDIT-RAW-FINDINGS-2026-09-18.md` | All 28 agent outputs unabridged — 82 findings, 16 strengths, 3 commercial verdicts |
| `MEASUREMENTS-2026-09-18.md` | Everything measured directly: what the app frees, the ceiling, disk contents, ownership, build state |
| `probe-guards.swift` | Replicates `FileSafety.record()` guards against real paths — shows which rules fire |
| `probe-ceiling.swift` | Strict vs lenient guard comparison — shows what the per-entry fix would buy |
| `STRATEGY-2026-09-18.md` | Can it be #1? Coverage matrix, 150-rule catalogue, permissions map, architecture, roadmap |
| `STRATEGY-RAW-FINDINGS-2026-09-18.md` | All 28 strategy-agent outputs unabridged |
| `strategist-verdicts.json` | The 3 strategists' verdicts and definitions of "#1" |
| `workflows/` | The agent workflow scripts, re-runnable |

Run the probes (read-only, they delete nothing):

```sh
swift docs/analysis/probe-guards.swift
swift docs/analysis/probe-ceiling.swift
```

## Headline numbers

- ViggoClean 0.2 frees **568 MB** from its developer rules on a 351 GiB-used disk.
- Per-entry guard fix raises the ceiling to **~19.5 GB** (14×), but reports 19.54 GB while moving 21.7 GB.
- **~200 GB** is reclaimable on the machine; most of it needs tool APIs (`simctl`, `sdkmanager`,
  Docker socket), not Trash moves.
- `spctl` **rejects** the current build — friends cannot open it. Fix is a free Developer ID cert.

## Status since the audit (19 September 2026)

The reports below are dated records of what was measured on 18 September and are left unedited.
What has changed since, per `docs/VALIDATION.md`:

| Audit item | State |
|---|---|
| A1 ad-hoc signing, `spctl` rejected | **Fixed** — Developer ID, notarized and stapled |
| A2 SwiftPM rule dead by construction | **Fixed** — root package exemption; rules now total 1,65 GB |
| A6 no LICENSE | **Fixed** — proprietary EULA at the repo root |
| A6 history schema / fail-closed forever | **Fixed** — versioned envelope, 0.2 migration, in-app reset |
| A7 missing store artifacts | **Fixed** — `PrivacyInfo.xcprivacy`, `Assets.car`, category |
| A8 arm64-only binary | **Fixed** — universal, `minos 14.0` on both slices |
| A9 `autoreleasepool` in `walk` | **Applied** — perf delta not independently re-measured |
| A4 whole-tree package/symlink rejection | **Fixed** — measure the subtree rather than refuse it; DerivedData now ACCEPTED 8,95 GB |
| B2 rules that reach real bytes | **Partly** — project build output is cleanable; tool-API rules (simctl, Docker, sdkmanager) still open |
| A5 no diagnosability / `os.Logger` | **Open** |
| B* rule coverage, `Table`, a11y, update channel | **Open** |

Note the headline numbers below are stale. Measured 19 September with the real scanner:
**214 candidates, 46,27 GB** (the reports say 1,83 GB), of which 30,1 GB is project build output.

The reports also mis-frame the biggest item. They treat tool caches as the target; the author's
actual 200 GB DaisyDisk pass was mostly **build files in projects left untouched**, which regrew
32 GB in one month. That is a recurring ~30 GB/month, not a one-off hunt.

## Open items — do not treat the strategy as settled

- **0 of 4 load-bearing Apple claims were confirmed** (3 contested, 1 refuted). The strategists were
  reportedly wrong that the Mac App Store is impossible and that `~/Library/Containers` is a
  zero-permission read. Re-verify before acting on the permissions section.
- **The per-entry "skip" fix is not coherent.** `trashItem` renames the whole subtree, so it cannot
  skip anything inside it. `probe-ceiling.swift`'s "IF FIXED" column measures what a lenient *scanner*
  would count, not what would move — hence the 2.15 GB gap it reports. The report's census-then-policy
  model supersedes it.
- **The roadmap's GB figures are understated** — it was calibrated on ground truth that missed ~30 GB
  (see the corrections banner in MEASUREMENTS-2026-09-18.md).
