export const meta = {
  name: 'viggoclean-number-one-lean',
  description: 'Lean, rate-limit-resilient research: competitor coverage, reclaimable-space catalogue, Apple rules, and a strategy for ViggoClean to beat every Mac cleaner',
  phases: [
    { title: 'Competitors', detail: '6 clusters, batches of 4, ≤10 web calls each' },
    { title: 'Catalogue', detail: '6 domains, batches of 4, measurements pre-supplied' },
    { title: 'Apple rules', detail: '3 topics, primary sources only' },
    { title: 'Verify', detail: 'top 4 load-bearing claims × 2 lenses' },
    { title: 'Strategy', detail: '3 strategists' },
    { title: 'Synthesize', detail: 'critic + final document' },
  ],
}

const REPO = '/Users/tloshi/AndroidStudioProjects/loshis/viggoclean'

const BUDGET = `HARD BUDGET: at most 10 WebSearch/WebFetch calls and 6 shell/read commands in total. Work fast and decisively. When you reach the budget — or after ~8 minutes — STOP and return what you have, marking anything unverified as low confidence. A partial answer returned is worth 10× a perfect answer never returned. Do not browse exhaustively; go straight to the 2-4 most authoritative pages (official pricing page, App Store listing, GitHub README/source, Apple developer docs).`

const CONTEXT = `You are part of a research team answering one question for the author of ViggoClean: **what would it take to make this the best Mac cleaner in the world — clearly ahead of every competitor — while staying inside Apple's rules?** The author will do whatever it takes, including asking users for any permission macOS legitimately offers, but will NOT break Apple's rules (no SIP disabling, no unsanctioned root, no App Review deception).

PROJECT: ViggoClean 0.2.0 at ${REPO}. Native macOS 14+ SwiftUI, SwiftPM, 2,523 lines, zero dependencies. Core files: Sources/ViggoCleanCore/{FileSafety,Scanner,Models}.swift, Sources/ViggoCleanCore/Repositories/LocalCleaningRepository.swift, Sources/ViggoCleanCore/Contracts/WorkspaceContracts.swift.

ESTABLISHED FACTS — do not re-derive:
- Safety posture is the asset: exactly one destructive call (FileManager.trashItem at FileSafety.swift:94), no removeItem, no shell, no root, no Select All, mandatory acknowledgement listing every path, never calls Trash moves "freed". Tests assert files SURVIVE failed deletes.
- Coverage is the weakness: seven hardcoded rules (Scanner.swift:60-68) — DerivedData, SwiftPM cache, npm _cacache, gradle build-cache-1, CocoaPods, Homebrew downloads, pip — plus third-party ~/Library/Caches children and .log files >30 days. Project folders scan-only. Scanner confined to $HOME (Scanner.swift:7). App never empties Trash.
- FileSafety.snapshot refuses a WHOLE tree if any entry is a symlink/package/hard link/special file. On the author's Mac this refuses DerivedData, Google/JetBrains/Spotify caches and the SwiftPM cache (its root is itself a .swiftpm package). Frees 1.4 GB today; per-entry-skip fix raises the ceiling to ~19.5 GB.
- Distribution: ad-hoc signed, Gatekeeper-rejected today. Author holds a paid Apple Developer membership (Apple Distribution cert, team F3X3EF7L5N), no Developer ID Application cert yet. ENABLE_APP_SANDBOX=NO. Prior audit: Developer ID + notarized DMG is the channel; MAS sandbox would make the scanner see only its own container.

GROUND TRUTH MEASURED ON THE AUTHOR'S MAC (460 GiB, 351 GiB used, 84%) — USE THESE, DO NOT RE-MEASURE:
- /Library/Developer/CoreSimulator: root:wheel owned. Volumes 32 GB (3 runtimes: iOS 26.2, 26.5, 27.0 = 23.2 GB per \`simctl runtime list\`, all lastUsedAt yesterday, \`deletable\` key present), Caches 6.9 GB. → mechanism is \`xcrun simctl runtime delete\`, not Trash.
- ~/Library/Developer/CoreSimulator/Devices: 6.3 GB, 12 devices; simctl JSON exposes \`lastUsedAt\` and \`dataPathSize\`; 2 booted yesterday (3.5 + 2.6 GB), 10 never used (~20 MB each).
- ~/.android/avd: 34 GB, ONE AVD (Pixel_9_Pro.avd), modified yesterday — live, not junk.
- ~/Library/Android/sdk: ndk 10.3 GB (FOUR versions: 25.1, 26.1, 27.0, 28.2), system-images 7.7 GB (3 images), emulator 1.1 GB, platforms 783 MB, build-tools 754 MB, sources 673 MB.
- ~/.gradle 9.9 GB: caches/9.1.0/transforms 4.0 GB, wrapper/dists 1.9 GB (SIX versions 5.4.1→9.7.1), jdks 1.5 GB (3 JDKs + 2 leftover .tar.gz ~550 MB), caches/modules-2 1.1 GB, build-cache-1 538 MB, daemon 379 MB.
- Docker.raw: 27.4 GB allocated / 34.4 GB logical (sparse). Docker not running. User-owned.
- DerivedData 8.2 GB: 6.0 GB is ONE live project (built yesterday, info.plist WorkspacePath resolves), ModuleCache.noindex 1.7 GB, SDKExplicitPrecompiledModules 351 MB. 181 symlinks, 494 .framework/.bundle/.app dirs inside.
- iOS DeviceSupport 5.6 GB. /opt/homebrew 26 GB (user-owned). node_modules across repos ~12 GB.
- ~/Library/Caches: Google 6.7 GB, JetBrains 1.5 GB (App Support/JetBrains 1.9 GB — precious), com.spotify.client 1.4 GB, ms-playwright 554 MB, bruno-updater 319 MB, Codex 265 MB, claude-cli-nodejs 163 MB, org.swift.swiftpm 929 MB.
- ~/.cache 1.8 GB: codex-runtimes 1.6 GB, firebase 198 MB. No HuggingFace/Ollama/torch caches. No Time Machine local snapshots. ~/.m2 48 KB.
- Root-owned and NOT reachable without a helper or a tool CLI: /Library/Developer/CoreSimulator/*, /Library/Logs, /private/var/log. /Library/Caches is root:admin sticky-world-writable.

GROUND RULES: Read-only on this machine — NEVER delete, trash, prune or modify anything; never run a cleanup tool; never change settings. Prefer WebSearch/WebFetch for competitors and Apple policy (cite URLs); do not trust memory for prices or rules. Precision over volume. Mark confidence.

${BUDGET}`

const COMPETITOR_SCHEMA = {
  type: 'object',
  properties: {
    cluster: { type: 'string' },
    products: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          price: { type: 'string', description: 'current price/model with source URL' },
          channel: { type: 'string', description: 'MAS / Developer ID direct / Setapp / Homebrew / CLI / built-in' },
          sandboxed: { type: 'string', enum: ['yes', 'no', 'partial', 'unknown'] },
          openSource: { type: 'boolean' },
          targets: { type: 'array', items: { type: 'string' }, description: 'each distinct cleanable target as "category: target" e.g. "xcode: iOS DeviceSupport", "containers: Docker build cache". Aim for the complete list as documented; 10-40 entries.' },
          capabilities: { type: 'array', items: { type: 'string' }, description: 'non-rule capabilities: scheduling, menu bar, real freed-space measurement, undo, uninstaller, disk map, CLI' },
          permissionsRequested: { type: 'array', items: { type: 'string' } },
          trustSignals: { type: 'array', items: { type: 'string' } },
          weaknesses: { type: 'array', items: { type: 'string' }, description: 'documented complaints and things it cannot do' },
          sources: { type: 'array', items: { type: 'string' } },
        },
        required: ['name', 'price', 'channel', 'sandboxed', 'openSource', 'targets', 'capabilities', 'weaknesses', 'sources'],
      },
    },
    clusterInsight: { type: 'string', description: 'what this cluster teaches about winning; where the whitespace is' },
  },
  required: ['cluster', 'products', 'clusterInsight'],
}

const COMPETITORS = [
  { id: 'cleanmymac', label: 'competitor:CleanMyMac', prompt: 'CLUSTER: CleanMyMac (MacPaw), the market leader. Catalogue every module and cleanable target in the current version (System Junk subcategories, Mail Attachments, Trash Bins, Large & Old Files, Uninstaller, Malware, Privacy, Optimization, Space Lens, any Xcode/developer items). Current pricing (one-time vs subscription, Setapp). Why it is not on the Mac App Store and what the old MAS build dropped. What it asks for on onboarding (Full Disk Access, privileged helper). Top substantive complaints (inflated numbers, deleted wanted files, subscription pressure).' },
  { id: 'daisy-sensei', label: 'competitor:DaisyDisk+Sensei', prompt: 'CLUSTER: DaisyDisk and Sensei (Cindori). For each: cleanable targets and capabilities, price, MAS vs direct differences (what the store build cannot do — scan as admin, purgeable), permissions, purgeable/APFS-snapshot handling. Sensei: its exact Developer/Xcode cleaner targets.' },
  { id: 'devcleaner-ai', label: 'competitor:DevCleaner+dev-and-AI-cleaners', prompt: 'CLUSTER: developer-focused and new-generation cleaners. DevCleaner for Xcode (free, MAS, open source — read its GitHub source for EXACTLY which Xcode locations it cleans, what it dropped due to sandbox, its store listing text, ratings count). Then search GitHub/HN/Product Hunt for 2025-2026 Mac cleaners: developer-cache cleaners, AI/LLM cache cleaners (Ollama, Hugging Face, LM Studio, Cursor/Copilot/Claude Code caches), "explain before delete" / safety-first tools, and anything measuring ACTUAL freed space. Does anyone occupy "safety-first, developer-first, open-source"? Say what you searched.' },
  { id: 'uninstallers', label: 'competitor:Pearcleaner+AppCleaner', prompt: 'CLUSTER: uninstallers/leftover finders: Pearcleaner (open source — read repo: what it finds, bundle-ID leftover matching, its "development environments" cleaner and exactly what it covers, licence saga, permissions), AppCleaner, TrashMe. How they map an app to leftovers (bundle ID, Spotlight kMDItemCFBundleIdentifier, known paths); false-positive complaints.' },
  { id: 'analyzers-cli', label: 'competitor:analyzers+Apple-builtin+dev-CLI', prompt: 'CLUSTER: the free incumbents a #1 app must beat. (a) Apple built-in Storage Management (System Settings > General > Storage recommendations, what it can delete, how it treats purgeable/iOS backups). (b) OmniDiskSweeper, GrandPerspective, ncdu/dust. (c) The developer CLI tools that ARE the real competition: `xcrun simctl delete unavailable` / `simctl runtime delete`, `brew cleanup`/`autoremove`, `docker system prune`/`builder prune`, `npm cache clean`, `pnpm store prune`, `npkill`, `cargo-sweep`, `go clean -modcache`, `pip cache purge`, `uv cache clean`, `conda clean`, `flutter clean`, `tmutil thinlocalsnapshots`, and mac-cleanup-py (open source — read its module list; it is the closest thing to a developer rule catalogue). For each: what it deletes, what it preserves, whether it is officially "safe", and how a GUI app could invoke it or replicate it via a documented API.' },
  { id: 'mass-market', label: 'competitor:mass-market+market-structure', prompt: 'CLUSTER: (a) mass-market/controversial cleaners — CCleaner for Mac, MacKeeper, BuhoCleaner, Nektony MacCleaner Pro, OnyX: target lists, prices, permission demands, and the trust failures (scareware, false positives, deleted user data, community warnings). This defines what a #1 app must NOT do. (b) Market structure: Setapp cleaner catalogue and revenue share, Homebrew cask presence, 2025-2026 launches on HN/Product Hunt/Reddit and what got traction or torn apart, demand signals for developer-specific cleaning (DevCleaner ratings count, GitHub stars on dev-cache cleaners, "my 512GB Mac is full" threads).' },
]

const CATALOGUE_SCHEMA = {
  type: 'object',
  properties: {
    domain: { type: 'string' },
    rules: {
      type: 'array',
      description: 'every reclaimable location in this domain, most valuable first; 12-30 entries',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'kebab-case, e.g. xcode-ios-device-support' },
          title: { type: 'string' },
          paths: { type: 'array', items: { type: 'string' }, description: 'exact paths with ~; plus env var/config key that relocates it' },
          insideHome: { type: 'boolean' },
          whatItIs: { type: 'string' },
          safeToTrash: { type: 'string', enum: ['yes-regenerates', 'conditional', 'partial-subpaths-only', 'inventory-only-use-tool-api', 'never'] },
          conditions: { type: 'string', description: 'sub-paths to preserve; what must be closed/stopped' },
          mechanism: { type: 'string', description: 'Trash move of paths, OR the exact official tool command/API if folder deletion is wrong' },
          regeneration: { type: 'string', description: 'rebuild time / re-download size / internet or sign-in needed' },
          typicalSize: { type: 'string', description: 'typical range on a dev Mac with source; and the ground-truth value on the author\'s Mac if known' },
          authorsMacGB: { type: 'number', description: 'from the GROUND TRUTH list; 0 if absent/unknown' },
          activeProcessCheck: { type: 'string', description: 'bundle ID, process name, lock file, socket, daemon' },
          permission: { type: 'string', enum: ['none', 'files-and-folders-prompt', 'full-disk-access', 'app-management', 'admin-privileged-helper', 'automation-apple-events', 'tool-api-only'] },
          officialSource: { type: 'string' },
          competitorsCovering: { type: 'array', items: { type: 'string' } },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['id', 'title', 'paths', 'insideHome', 'whatItIs', 'safeToTrash', 'conditions', 'mechanism', 'regeneration', 'typicalSize', 'authorsMacGB', 'permission', 'officialSource', 'competitorsCovering', 'confidence'],
      },
    },
    domainSummary: { type: 'string', description: 'realistic GB on a heavy dev Mac, 3 biggest wins, and the traps' },
  },
  required: ['domain', 'rules', 'domainSummary'],
}

const DOMAINS = [
  { id: 'apple', label: 'catalogue:Apple-toolchain', prompt: 'DOMAIN: Apple toolchain. DerivedData (per-project dirs with info.plist WorkspacePath, ModuleCache.noindex, Index.noindex, SDKExplicitPrecompiledModules), Archives, iOS/watchOS/tvOS/visionOS DeviceSupport, ~/Library/Developer/CoreSimulator (Devices, Caches/dyld) vs root-owned /Library/Developer/CoreSimulator (runtime cryptex volumes — only via `xcrun simctl runtime delete`), Xcode Previews, ~/Library/Caches/com.apple.dt.Xcode, Instruments traces, Playgrounds, CoreML compiled models, /Library/Developer/Toolchains, Xcode .xip leftovers, iOS Device Logs, DocumentationCache. Note which Xcode > Settings > Platforms/Components deletes itself, and which DevCleaner covers. Sources: Apple docs, DevCleaner source.' },
  { id: 'android', label: 'catalogue:Android-JVM-Flutter', prompt: 'DOMAIN: Android/JVM/Flutter. ~/.android (avd images, build-cache, cache; adb keys and debug.keystore are precious), ~/Library/Android/sdk (system-images, ndk multiple versions, platforms, build-tools, emulator, sources — official `sdkmanager --uninstall`), ~/.gradle (caches/modules-2, caches/<version>/transforms, build-cache-1, jars-*, wrapper/dists, daemon logs, jdks incl. leftover .tar.gz; Gradle\'s own cleanup policy), ~/.m2, ~/.kotlin, ~/.konan, JetBrains caches (~/Library/Caches/JetBrains vs Application Support — precious), Android Studio system dirs, Flutter (~/.pub-cache, flutter/bin/cache, .dart_tool, build/), Bazel, sbt/ivy. The ground truth shows 4 NDK versions and 6 Gradle wrapper dists — specify how to decide which are unreferenced (project gradle-wrapper.properties, ndkVersion in build.gradle).' },
  { id: 'js-langs', label: 'catalogue:JS-Rust-Go-Python-etc', prompt: 'DOMAIN: language ecosystems. JS: node_modules discovery across roots (npkill approach; staleness by git activity/mtime), npm _cacache/_logs, yarn v1 vs Berry cache, pnpm store (`pnpm store path`, prune semantics), bun cache, nvm/fnm/volta versions, Playwright browsers, Cypress cache, Electron caches, framework outputs (.next .nuxt .turbo .parcel-cache .angular/cache .vite .expo), Deno. Rust: ~/.cargo registry/git, target/ dirs (cargo-sweep), ~/.rustup. Go: GOMODCACHE, GOCACHE. Python: pip/uv/poetry caches, pipx, pyenv, conda pkgs/envs, project venvs, __pycache__/.pytest_cache/.mypy_cache/.ruff_cache. Ruby gems, Composer, NuGet, Haskell stack, Elixir _build/deps, SwiftPM .build, ccache/sccache. Include the env var/config key that relocates each cache and the official cleanup command.' },
  { id: 'containers-ai', label: 'catalogue:containers-VMs-AI', prompt: 'DOMAIN: containers/VMs/AI. Docker Desktop: why deleting Docker.raw is wrong; the Docker Engine API over the unix socket (/system/df, /images/prune, /build/prune, /volumes/prune, /containers/prune) as the correct mechanism; Docker Desktop disk-image size and raw-file shrink behaviour. OrbStack, Colima/Lima, Podman machine, Rancher, minikube/kind, Vagrant boxes, UTM/Parallels/VirtualBox images (inventory only), Multipass. AI: Ollama models (~/.ollama, API), Hugging Face hub cache (huggingface-cli delete-cache), LM Studio, MLX, PyTorch hub, TensorFlow datasets, Whisper, Stable Diffusion/ComfyUI models, and coding-agent caches (~/Library/Caches/claude-cli-nodejs, ~/Library/Caches/Codex, ~/.cache/codex-runtimes, Cursor, VS Code, Copilot — separate disposable cache from precious conversation history/settings).' },
  { id: 'macos', label: 'catalogue:macOS-general-junk', prompt: 'DOMAIN: general macOS junk (CleanMyMac territory). ~/Library/Caches (safe children vs Apple-owned to leave), /Library/Caches, ~/Library/Logs, /Library/Logs, /private/var/log, DiagnosticReports, Mail attachments/Mail Downloads (precious vs cache), Messages attachments (precious), Photos caches vs originals, iOS backups (MobileSync — inventory only), iOS update .ipsw files, leftover Application Support of removed apps, Downloads installers (.dmg/.pkg/.zip by age), Trash size per volume, Time Machine local snapshots (`tmutil listlocalsnapshots`/thinlocalsnapshots — root needed?), APFS purgeable, language .lproj (why NOT in 2026 — signed bundles), browser caches vs profiles (Safari/Chrome/Firefox/Arc/Brave/Edge), Slack/Discord/Teams/Zoom/Spotify/Adobe caches, font caches, QuickLook thumbnails, Saved Application State, Homebrew (Cellar old versions via brew cleanup, ~/Library/Caches/Homebrew; what of /opt/homebrew 26 GB is reclaimable vs installed software), /private/var/folders. For each: TCC permission needed (Mail, Messages, Safari, TM, MobileSync are FDA-protected).' },
  { id: 'intelligence', label: 'catalogue:measurement-and-staleness', prompt: 'DOMAIN: MEASUREMENT AND INTELLIGENCE — what makes a cleaner smarter than any competitor. Specify with Apple/tool docs: (1) real reclaimable bytes on APFS — allocated vs logical, clones, snapshots pinning blocks, purgeable via URLResourceValues volumeAvailableCapacityForImportantUsage/ForOpportunisticUsage, and measuring ACTUAL freed bytes before/after via statfs; (2) staleness signals that work: simctl lastUsedAt/dataPathSize, DerivedData info.plist WorkspacePath existence + project mtime, node_modules parent package.json + git activity, kMDItemLastUsedDate, Gradle wrapper dists vs gradle-wrapper.properties references, NDK versions vs ndkVersion; (3) regeneration-cost estimation proxies; (4) active-process detection beyond bundle IDs: lock files, unix sockets, libproc proc_listpids (allowed non-sandboxed?), NSRunningApplication, launchd; (5) which tool stores have integrity indexes (npm _cacache, pnpm store) making partial deletion dangerous. Each rule here is a capability, not a path — use the same schema with paths describing the signal source.' },
]

const RULES_SCHEMA = {
  type: 'object',
  properties: {
    topic: { type: 'string' },
    facts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          source: { type: 'string' },
          implication: { type: 'string', description: 'for ViggoClean specifically' },
          loadBearing: { type: 'boolean', description: 'true if the strategy changes if this is wrong' },
        },
        required: ['claim', 'confidence', 'source', 'implication', 'loadBearing'],
      },
    },
    allowed: { type: 'array', items: { type: 'string' } },
    forbidden: { type: 'array', items: { type: 'string' } },
    recommendedApproach: { type: 'string', description: 'concrete design with API names' },
  },
  required: ['topic', 'facts', 'allowed', 'forbidden', 'recommendedApproach'],
}

const RULE_TOPICS = [
  { id: 'tcc', label: 'apple:TCC-FDA-Automation', prompt: 'TOPIC: permissions a cleaner can legitimately request. From Apple docs: Full Disk Access (what it unlocks — Mail, Messages, Safari, Time Machine, MobileSync; request only via System Settings deep link x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles; how to DETECT the grant by probing a protected path; how signing identity affects grant persistence), Files & Folders prompts (Desktop/Documents/Downloads; NSOpenPanel implicit grants; security-scoped bookmarks — needed for non-sandboxed apps?), App Management (kTCCServiceSystemPolicyAppBundles — needed to modify other apps\' bundles), Automation/Apple Events to Finder to EMPTY THE TRASH (no NSWorkspace API — confirm; `tell application "Finder" to empty trash`; NSAppleEventsUsageDescription), and exact Info.plist usage-description keys. Does a non-sandboxed Developer ID app need FDA to read ~/Library/Caches, ~/Library/Developer, ~/.gradle? (Answer from docs; do not probe TCC-protected paths.)' },
  { id: 'privileged-review', label: 'apple:privileged-helpers+App-Review', prompt: 'TOPIC: privileged work and review rules. SMAppService (macOS 13+) for a privileged launch daemon inside the app bundle: SMAuthorizedClients/SMPrivilegedExecutables pairing, signing requirements, works for Developer ID outside the store? allowed in MAS? Least-privilege XPC helper pattern (allow-listed, path-validated ops). Which dev-Mac targets actually REQUIRE root (ground truth: /Library/Developer/CoreSimulator is root-owned but simctl deletes runtimes without the app escalating) vs merely FDA. Root cannot use the user\'s Trash — what does Apple recommend? Then the CURRENT App Store Review Guidelines: quote the numbered guidelines affecting cleaners/utilities (2.4.5 Mac requirements incl. sandbox and no launching other code, 2.5.x, 5.1.x privacy/FDA justification, anything on "clean/optimize/boost" or misleading freed-space claims). Load-bearing: can a sandboxed MAS app use FDA to read outside its container? Notarization requirements incl. bundled helpers/CLI tools. Is invoking `docker`/`brew`/`xcrun simctl`/Docker socket/Ollama HTTP acceptable for a Developer ID app?' },
  { id: 'freed-space', label: 'apple:real-freed-space-APFS', prompt: 'TOPIC: telling the truth about freed space on APFS — a capability no mainstream competitor has. From Apple docs: reading free space correctly (statfs vs URLResourceValues volumeAvailableCapacity / ForImportantUsage / ForOpportunisticUsage; what "purgeable" means); why a Trash move frees nothing and emptying may free less than expected (clones sharing extents, local TM snapshots pinning blocks); any public API to detect clones/shared extents (be honest if none — propose best proxy); measuring ACTUAL freed bytes: sample free space before, after Trash move, after Trash empty, after snapshot thinning; what the Trash is per volume (~/.Trash vs /Volumes/X/.Trashes/<uid>) and options for emptying it (Finder Apple Events vs removeItem on ~/.Trash contents — the latter breaks ViggoClean\'s one-trashItem principle; weigh both); `tmutil thinlocalsnapshots`/`deletelocalsnapshots` — root needed? You may run `tmutil listlocalsnapshots /` and `df -H` read-only.' },
]

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    reasoning: { type: 'string' },
    correction: { type: 'string' },
  },
  required: ['refuted', 'confidence', 'reasoning'],
}

const STRATEGY_SCHEMA = {
  type: 'object',
  properties: {
    angle: { type: 'string' },
    canBeNumberOne: { type: 'string', enum: ['yes-clearly', 'yes-in-a-defined-niche', 'only-with-a-team', 'no'] },
    whatNumberOneMeans: { type: 'string' },
    thesis: { type: 'string' },
    whitespace: { type: 'array', items: { type: 'string' } },
    mustHave: { type: 'array', items: { type: 'string' } },
    mustNot: { type: 'array', items: { type: 'string' } },
    architectureChanges: { type: 'array', items: { type: 'string' }, description: 'concrete, with file references' },
    phases: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          name: { type: 'string' },
          goal: { type: 'string' },
          deliverables: { type: 'array', items: { type: 'string' } },
          effortPartTime: { type: 'string' },
          gbUnlockedOnAuthorsMac: { type: 'string' },
        },
        required: ['name', 'goal', 'deliverables', 'effortPartTime', 'gbUnlockedOnAuthorsMac'],
      },
    },
    biggestRisk: { type: 'string' },
  },
  required: ['angle', 'canBeNumberOne', 'whatNumberOneMeans', 'thesis', 'whitespace', 'mustHave', 'mustNot', 'architectureChanges', 'phases', 'biggestRisk'],
}

async function batched(items, size, fn) {
  const out = []
  for (let i = 0; i < items.length; i += size) {
    const chunk = items.slice(i, i + size)
    const r = await parallel(chunk.map((it) => () => fn(it)))
    out.push(...r)
    log(`  batch ${Math.floor(i / size) + 1}/${Math.ceil(items.length / size)} done (${r.filter(Boolean).length}/${chunk.length} returned)`)
  }
  return out
}

phase('Competitors')
log(`Competitors: ${COMPETITORS.length} clusters in batches of 4`)
const competitorRaw = await batched(COMPETITORS, 4, (c) =>
  agent(CONTEXT + '\n\n========\n\nYOUR TASK: ' + c.prompt + '\n\nList `targets` as completely as the official docs allow within budget.', { label: c.label, phase: 'Competitors', schema: COMPETITOR_SCHEMA, effort: 'medium' })
)
const competitors = competitorRaw.filter(Boolean)
const missingC = COMPETITORS.filter((_, i) => !competitorRaw[i]).map((c) => c.id)
log(`${competitors.length}/${COMPETITORS.length} clusters, ${competitors.reduce((n, c) => n + c.products.length, 0)} products, ${competitors.reduce((n, c) => n + c.products.reduce((m, p) => m + p.targets.length, 0), 0)} targets` + (missingC.length ? ` — MISSING: ${missingC.join(', ')}` : ''))

phase('Catalogue')
log(`Catalogue: ${DOMAINS.length} domains in batches of 4`)
const catalogueRaw = await batched(DOMAINS, 4, (d) =>
  agent(CONTEXT + '\n\n========\n\nYOUR TASK: ' + d.prompt + '\n\nUse the GROUND TRUTH sizes for authorsMacGB; do not run du. Every rule needs an officialSource.', { label: d.label, phase: 'Catalogue', schema: CATALOGUE_SCHEMA, effort: 'medium' })
)
const catalogue = catalogueRaw.filter(Boolean)
const allRules = catalogue.flatMap((d) => d.rules.map((r) => Object.assign({ domain: d.domain }, r)))
const missingD = DOMAINS.filter((_, i) => !catalogueRaw[i]).map((d) => d.id)
log(`${catalogue.length}/${DOMAINS.length} domains, ${allRules.length} rules` + (missingD.length ? ` — MISSING: ${missingD.join(', ')}` : ''))

phase('Apple rules')
const rulesRaw = await parallel(RULE_TOPICS.map((t) => () =>
  agent(CONTEXT + '\n\n========\n\nYOUR TASK: ' + t.prompt + '\n\nMark loadBearing=true on facts that would change the strategy if wrong.', { label: t.label, phase: 'Apple rules', schema: RULES_SCHEMA, effort: 'medium' })
))
const rules = rulesRaw.filter(Boolean)
const loadBearing = rules.flatMap((r) => r.facts.filter((f) => f.loadBearing).map((f) => Object.assign({ topic: r.topic }, f)))
log(`${rules.length}/${RULE_TOPICS.length} topics, ${loadBearing.length} load-bearing claims`)

phase('Verify')
const CAP = 4
const toVerify = loadBearing.slice(0, CAP)
if (loadBearing.length > CAP) log(`Verifying first ${CAP} of ${loadBearing.length} load-bearing claims; rest reported UNVERIFIED`)
const LENSES = [
  { id: 'refute', build: (f) => `Adversarially verify this claim about macOS/Apple rules using CURRENT primary sources (developer.apple.com, support.apple.com, App Store Review Guidelines). REFUTE it if you can.\n\nCLAIM: ${f.claim}\nSOURCE OFFERED: ${f.source}\n\nIs it literally true today? Did it change in macOS 13/14/15/26? Default refuted=true if you cannot confirm from a primary source. ${BUDGET}` },
  { id: 'implication', build: (f) => `Assume this claim is TRUE. Does the stated implication for ViggoClean (non-sandboxed, Developer ID, one-trashItem safety posture, wants to be #1 within Apple's rules) actually follow, and is it the most important one?\n\nCLAIM: ${f.claim}\nIMPLICATION: ${f.implication}\n\nrefuted=true only if the implication is wrong or misleading; otherwise give the sharper implication in correction. ${BUDGET}` },
]
const verified = await batched(toVerify, 4, (f) =>
  parallel(LENSES.map((l) => () =>
    agent(l.build(f), { label: `${l.id}: ${String(f.claim).slice(0, 48)}`, phase: 'Verify', schema: VERDICT_SCHEMA, effort: 'medium' })
  )).then((votes) => ({ claim: f, votes: votes.filter(Boolean) }))
)
const verdicts = verified.filter(Boolean).map((v) => ({
  claim: v.claim.claim, topic: v.claim.topic,
  status: v.votes.length === 0 ? 'unverified' : v.votes.every((x) => !x.refuted) ? 'confirmed' : v.votes.every((x) => x.refuted) ? 'refuted' : 'contested',
  notes: v.votes.map((x) => `[${x.confidence}] ${x.reasoning}${x.correction ? ' CORRECTION: ' + x.correction : ''}`),
}))
log(`Verification: ${verdicts.filter((v) => v.status === 'confirmed').length} confirmed, ${verdicts.filter((v) => v.status === 'contested').length} contested, ${verdicts.filter((v) => v.status === 'refuted').length} refuted`)

const coverageByTool = {}
for (const c of competitors) for (const p of c.products) coverageByTool[p.name] = p.targets
const digest = JSON.stringify({
  competitorClusters: competitors.map((c) => ({ cluster: c.cluster, insight: c.clusterInsight, products: c.products.map((p) => ({ name: p.name, price: p.price, channel: p.channel, sandboxed: p.sandboxed, openSource: p.openSource, targetCount: p.targets.length, capabilities: p.capabilities, permissions: p.permissionsRequested, trust: p.trustSignals, weaknesses: p.weaknesses })) })),
  coverageByTool,
  rulesCatalogue: allRules,
  domainSummaries: catalogue.map((d) => ({ domain: d.domain, summary: d.domainSummary })),
  appleRules: rules,
  verification: verdicts,
  coverageGaps: { missingCompetitorClusters: missingC, missingCatalogueDomains: missingD },
}, null, 1)

phase('Strategy')
const STRATEGISTS = [
  { id: 'product', prompt: 'ANGLE: product strategist. From the coverage matrix and catalogue, find the WHITESPACE: what no competitor does or does well; where incumbents\' business models (subscriptions, scareware, MAS sandbox) structurally prevent them from following. Define what "#1" can credibly mean for a solo developer within 12 months and argue the sharpest positioning. Rank rules by GB × prevalence × how badly competitors cover them. Say plainly if "best in the world" must be narrowed to be true.' },
  { id: 'engineer', prompt: 'ANGLE: principal engineer. Read FileSafety.swift, Scanner.swift, LocalCleaningRepository.swift, WorkspaceContracts.swift, Models.swift in the repo. Design the architecture to hold 100+ catalogue rules with multiple mechanisms (Trash move; tool APIs — Docker socket, Ollama HTTP, simctl, sdkmanager, brew; optionally a least-privilege root helper), custom-location discovery via env/config, staleness scoring, active-process detection, real freed-space measurement, and a rule catalogue with provenance and per-rule fixtures per AGENTS.md. Preserve invariants: one destructive filesystem primitive, no Select All, scan-only-until-validated. Concrete: file layout, protocols, rule DSL, how a helper stays inside the one-primitive principle, and the fix for the whole-tree-refusal problem (measured unit vs moved unit). Effort per phase.' },
  { id: 'trust', prompt: 'ANGLE: trust and safety architect. The category is defined by tools that lie and tools that delete the wrong thing; ViggoClean\'s only current moat is checkable safety. As coverage expands 10× and permissions expand (FDA, maybe a helper, Automation to empty Trash), how does it KEEP that moat and make it the reason it wins? Specify: permission-onboarding UX that asks for the most while feeling safest; categories that may never auto-select; how "real freed space" is reported; undo/journal guarantees; making safety claims publicly verifiable (open source, reproducible fixtures, published threat model); what it must refuse even when asked. List every point where "more coverage" and "provable safety" conflict, and resolve each.' },
]
const strategies = (await parallel(STRATEGISTS.map((s) => () =>
  agent(`${CONTEXT}\n\n========\n\n${s.prompt}\n\nYou have the full research digest below; you need at most 3 web calls.\n\n========\n\nRESEARCH DIGEST:\n${digest}`, { label: `strategy:${s.id}`, phase: 'Strategy', schema: STRATEGY_SCHEMA })
))).filter(Boolean)
log(`${strategies.length}/${STRATEGISTS.length} strategies: ${strategies.map((s) => s.canBeNumberOne).join(', ')}`)

phase('Synthesize')
const critique = await agent(`${CONTEXT}\n\n========\n\nYou are the completeness critic. Find what is MISSING or WRONG in the research below before it becomes the author's strategy. Check: (1) reclaimable locations on a dev Mac no domain listed — look (read-only, ≤6 commands) at ~/Library/Application Support, ~/Library/Containers, ~/.config sizes for big things the catalogue missed; (2) competitors or tools nobody researched; (3) any Apple-rules claim that looks wrong or outdated — verify the two most consequential with ≤6 web calls; (4) whether the three strategies contradict each other and who is right; (5) whether the strategies actually beat Apple's built-in Storage Management + the CLI tools a developer already has — the real bar; (6) the single most important thing nobody has said. Plain prose under those six headings, citing paths/URLs.\n\nDIGEST:\n${digest}\n\nSTRATEGIES:\n${JSON.stringify(strategies, null, 1)}`, { label: 'completeness-critic', phase: 'Synthesize' })

const report = await agent(`${CONTEXT}\n\n========\n\nWrite the final strategy document for the author, who asked: "can we add more than competitors, can we be number one? I want the best app in the world, passing competitors way way further. Do whatever it takes, ask for any permissions, within Apple's rules."\n\nDIGEST:\n${digest}\n\nSTRATEGIES:\n${JSON.stringify(strategies, null, 1)}\n\nCRITIC:\n${critique}\n\nMarkdown with exactly these sections:\n\n## Straight answer\nCan it be #1? Under what definition? Three sentences, no hedging. If strategists disagreed, say who said what and take a position.\n\n## The coverage matrix\nTable: rows = ~20 most valuable target categories ordered by GB × prevalence; columns = ViggoClean today, CleanMyMac, Sensei, DevCleaner, Pearcleaner, mac-cleanup-py, Apple built-in, dev CLI tools. Cells ✅ / partial / ❌ / n/a. Two sentences on what it shows.\n\n## Everything reclaimable on a developer Mac\nFull catalogue as a table ranked by value: id, path(s), typical GB, author's Mac GB, safe class, mechanism, permission, who covers it today. Include every rule from the research; mark low-confidence rows. This is what the author will build from.\n\n## What no one does — the whitespace\nRanked, with evidence from the competitor research.\n\n## Permissions: what to ask for and what it unlocks\nTable: permission → what it unlocks (GB on author's Mac) → how to request (API/deep link, Info.plist keys) → Apple constraint. Cover FDA, Files & Folders, App Management, Automation (empty Trash), SMAppService helper, tool APIs (Docker socket, Ollama, simctl, sdkmanager, brew). State which Apple rules must never be crossed. Flag any load-bearing claim verification contested or refuted.\n\n## The definition of #1 that is winnable\nOne paragraph positioning, and the five capabilities that make it true.\n\n## Architecture required\nConcrete codebase changes with file references, preserving invariants. Include the rule DSL shape and how a helper (if any) stays inside the safety model.\n\n## Roadmap\nPhases in dependency order: goal, deliverables, part-time effort, GB unlocked on the author's Mac, cumulative GB. Realistic for a solo developer.\n\n## What would kill it\nRanked risks with mitigations.\n\n## Monday morning\nFirst three concrete tasks, each under a day.\n\nRULES: every path, size and Apple claim must come from the research above; never invent. If a research domain or cluster is listed under coverageGaps as missing, say so in the relevant section rather than filling the hole. Tables over prose where tabular. The author is a capable developer. Be direct.`, { label: 'final-strategy', phase: 'Synthesize' })

return {
  counts: {
    competitorClusters: `${competitors.length}/${COMPETITORS.length}`,
    catalogueDomains: `${catalogue.length}/${DOMAINS.length}`,
    rulesCatalogued: allRules.length,
    verification: { confirmed: verdicts.filter((v) => v.status === 'confirmed').length, contested: verdicts.filter((v) => v.status === 'contested').length, refuted: verdicts.filter((v) => v.status === 'refuted').length },
    missing: { competitors: missingC, domains: missingD },
  },
  strategistVerdicts: strategies.map((s) => ({ angle: s.angle, canBeNumberOne: s.canBeNumberOne, definition: s.whatNumberOneMeans })),
  report,
}
