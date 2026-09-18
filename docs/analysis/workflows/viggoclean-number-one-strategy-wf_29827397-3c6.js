export const meta = {
  name: 'viggoclean-number-one-strategy',
  description: 'Research what it takes for ViggoClean to beat every Mac cleaner: competitor coverage matrix, full reclaimable-space catalogue, Apple permission rules, strategy',
  phases: [
    { title: 'Competitors', detail: '9 parallel deep-dives, one per competitor cluster, cataloguing every cleanable target they ship' },
    { title: 'Catalogue', detail: '7 parallel domain experts mapping everything reclaimable on a developer Mac, with paths, safety and regeneration cost' },
    { title: 'Apple rules', detail: '4 parallel researchers on TCC/FDA, privileged helpers, distribution/review, and real freed-space measurement' },
    { title: 'Verify', detail: 'adversarial 2-lens verification of the load-bearing Apple-rules claims' },
    { title: 'Strategy', detail: '3 independent strategists: product whitespace, principal engineer, trust/safety' },
    { title: 'Critique', detail: 'completeness critic' },
    { title: 'Synthesize', detail: 'final strategy document' },
  ],
}

const REPO = '/Users/tloshi/AndroidStudioProjects/loshis/viggoclean'

const CONTEXT = `You are part of a research team answering one question for the author of ViggoClean: **what would it take to make this the best Mac cleaner in the world — not merely competitive, but clearly ahead of every competitor — while staying inside Apple's rules?** The author is willing to do whatever it takes, including asking users for any permission macOS legitimately offers, but will NOT break Apple's rules (no SIP disabling, no unsanctioned root, no App Review deception).

PROJECT: ViggoClean 0.2.0 at ${REPO}. Native macOS 14+ SwiftUI, Swift Package Manager, 2,523 lines, zero dependencies. Modules: ViggoCleanCore (FileSafety, Scanner, LocalCleaningRepository, Models), ViggoCleanPresentation, ViggoClean (views/services). Read README.md, docs/ARCHITECTURE.md and docs/ROADMAP.md (Albanian — read it anyway) if your task touches the product.

FACTS ALREADY ESTABLISHED THIS SESSION — do not re-derive:
- Safety posture is unusually strong: exactly one destructive call in the codebase (FileManager.trashItem at FileSafety.swift:94), no removeItem, no shell, no root helper, no Select All, mandatory acknowledgement listing every full path, refuses to call Trash moves "freed space". Tests assert files SURVIVE failed deletes. This posture is the asset to protect.
- Coverage is the weakness. Seven hardcoded developer rules (Scanner.swift:60-68) as tuples inside a 145-line function: DerivedData, SwiftPM cache, npm _cacache, gradle build-cache-1, CocoaPods, Homebrew downloads, pip. Plus third-party ~/Library/Caches children, browser caches within cache paths, and .log files >30 days. Project folders are scan-only.
- FileSafety.snapshot refuses an ENTIRE candidate tree if any entry is a symlink, package, hard link or special file. Measured on the author's Mac: this refuses DerivedData (8.2 GB, 181 symlinks, 494 .framework/.bundle/.app dirs), ~/Library/Caches/Google (6.7 GB), JetBrains (1.6 GB), Spotify (1.4 GB), and the SwiftPM cache (929 MB — its root has a .swiftpm extension so isPackage==true on the root itself). Net: the app frees 1.4 GB today; a per-entry-skip fix raises the ceiling to ~19.5 GB.
- Scanner is confined to $HOME (Scanner.swift:7). The app never empties Trash by design.
- The author's Mac (460 GiB, 351 GiB used, 84%) measured with du: 39 GB /Library/Developer/CoreSimulator, 34 GB ~/.android, 26 GB Docker VM (~/Library/Containers/com.docker.docker), 26 GB /opt/homebrew, 22 GB ~/Library/Android, 12 GB node_modules across repos, 9.9 GB ~/.gradle (build-cache-1 is only 509 MB of it), 8.2 GB DerivedData, 6.4 GB ~/Library/Developer/CoreSimulator, 5.6 GB iOS DeviceSupport. Roughly 200 GB is plausibly reclaimable.
- Distribution: today ad-hoc signed and Gatekeeper-rejected. Author already holds an active paid Apple Developer membership (Apple Distribution cert present, team F3X3EF7L5N) but no Developer ID Application cert yet. ENABLE_APP_SANDBOX = NO. Previous audit concluded Developer ID + notarized DMG is the channel and the Mac App Store sandbox would make the scanner see only its own container.
- Three commercial judges previously concluded the only real differentiator today is CHECKABLE safety (open source), and that free/open-source is the right price at 0.2. The author now wants to go beyond that and win on capability too.

GROUND RULES:
- Read-only on this machine. You may run \`ls\`, \`du -sh\` (skip any single du that takes over ~60 s), \`stat\`, \`defaults read\`, \`brew --cache\`, \`xcrun simctl list\`, \`docker system df\` (if Docker is running; do not start it), \`ls -la\` for ownership checks, and read any file. NEVER delete, move, trash, prune, or modify anything. Never run any cleanup tool. Never change system settings.
- USE WebSearch/WebFetch for anything about competitors, Apple documentation, or tool cache layouts. Do not rely on memory for prices, features or Apple policy — they change. Cite URLs.
- Precision over volume. An exact path with a source beats a vague category. When you give a size, say whether it is measured on this machine or typical from a source.
- Be honest about uncertainty. Mark confidence.`

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
          vendor: { type: 'string' },
          price: { type: 'string', description: 'current price and model (one-time / subscription / free), with source' },
          channel: { type: 'string', description: 'Mac App Store / Developer ID direct / Setapp / Homebrew / CLI / built-in macOS — list all' },
          sandboxed: { type: 'string', enum: ['yes', 'no', 'partial', 'unknown'] },
          openSource: { type: 'boolean' },
          targets: {
            type: 'array',
            description: 'EVERY distinct cleanable target this product ships. Be exhaustive — this feeds a coverage matrix.',
            items: {
              type: 'object',
              properties: {
                category: { type: 'string', description: 'one of: xcode, android-jvm, js-web, systems-langs, python-ml, containers-vms, browsers, mail-messages, photos-media, ios-backups, system-caches, logs-crash, app-leftovers, uninstaller, large-old-files, duplicates, downloads-installers, localizations, homebrew, trash, purgeable-snapshots, memory-ram, startup-items, malware, privacy, other' },
                target: { type: 'string', description: 'the specific thing, e.g. "iOS DeviceSupport" or "Docker build cache"' },
                mechanism: { type: 'string', description: 'how it cleans it: path deletion, tool API/CLI, privileged helper, etc. if known' },
              },
              required: ['category', 'target'],
            },
          },
          capabilities: { type: 'array', items: { type: 'string' }, description: 'non-rule capabilities: scheduling, menu bar, real freed-space measurement, undo, uninstaller, smart scan, disk map, CLI, etc.' },
          permissionsRequested: { type: 'array', items: { type: 'string' }, description: 'Full Disk Access, privileged helper, Automation, App Management, etc. — what the product asks for on onboarding' },
          trustSignals: { type: 'array', items: { type: 'string' }, description: 'trash vs permanent delete, preview before delete, path listing, undo, open source, notarized' },
          weaknesses: { type: 'array', items: { type: 'string' }, description: 'documented user complaints, review rejections, known-bad behaviours, things it cannot do' },
          sources: { type: 'array', items: { type: 'string' } },
        },
        required: ['name', 'vendor', 'price', 'channel', 'sandboxed', 'openSource', 'targets', 'capabilities', 'permissionsRequested', 'trustSignals', 'weaknesses', 'sources'],
      },
    },
    clusterInsight: { type: 'string', description: 'what this cluster teaches about winning: what users love, what they hate, where the whitespace is' },
  },
  required: ['cluster', 'products', 'clusterInsight'],
}

const COMPETITORS = [
  { id: 'cleanmymac', label: 'competitor:CleanMyMac', prompt: 'CLUSTER: CleanMyMac (MacPaw) — the market leader. Catalogue every module and every cleanable target it ships in its current version (System Junk subcategories, Mail Attachments, Trash Bins, Large & Old Files, Uninstaller, Updater, Malware, Privacy, Optimization, Space Lens, Shredder, Menu app, Cleanup Assistant, any "Developer" or Xcode-related items). Establish exact current pricing (one-time vs subscription, Setapp), distribution channels (why it is NOT on the Mac App Store, and what the older MAS "CleanMyMac X" version dropped), what it asks for on onboarding (Full Disk Access, privileged helper, etc.), and the most common substantive complaints (e.g. inflated numbers, deleting things users wanted, subscription pressure, "freed" reporting). Also check MacPaw\'s own documentation of how its privileged helper works.' },
  { id: 'daisydisk-sensei', label: 'competitor:DaisyDisk+Sensei', prompt: 'CLUSTER: DaisyDisk (Software Ambience) and Sensei (Cindori). For each: every cleanable target and capability, current price, MAS vs direct differences (what the Mac App Store build cannot do — scan as administrator, purgeable space, etc.), permissions requested, sandbox status, and their treatment of purgeable/APFS-snapshot space. DaisyDisk is the benchmark for disk visualization; capture what makes its map good. Sensei is the benchmark for a polished paid dev-adjacent utility with a Developer/Xcode cleaner; capture its exact developer targets.' },
  { id: 'devcleaner', label: 'competitor:DevCleaner+Xcode-tools', prompt: 'CLUSTER: developer-focused cleaners. DevCleaner for Xcode (free, MAS, open source on GitHub — read its source to list EXACTLY which Xcode locations it cleans and which it had to drop because of sandbox), xcodes/Xcodes.app cleanup features, "Xcode Cleaner" apps, and any 2025-2026 developer-cache cleaners (search GitHub for recent Swift/Mac "developer cache cleaner", "DerivedData cleaner", "dev cleaner mac"). For DevCleaner specifically, get its actual store listing text, its permissions approach under sandbox, its GitHub issues about things it cannot reach, and its download/rating numbers as a market-size signal.' },
  { id: 'uninstallers', label: 'competitor:Pearcleaner+AppCleaner', prompt: 'CLUSTER: uninstallers and leftover-finders. Pearcleaner (open source — read the repo: what it finds, how it finds app leftovers by bundle ID, its "orphaned files" and "development environments" features, its licence saga, its permissions), AppCleaner (FreeMacSoft), TrashMe, and AppCleaner-like features. Capture exactly how they map an app to its leftover files (bundle ID matching, Spotlight kMDItemCFBundleIdentifier, known paths), what permissions they request, and their known false-positive complaints. Pearcleaner reportedly has a developer-environment cleaner — catalogue exactly what it covers.' },
  { id: 'analyzers', label: 'competitor:disk-analyzers', prompt: 'CLUSTER: disk analyzers and free utilities. OmniDiskSweeper, GrandPerspective, Disk Inventory X, ncdu/dust/gdu (CLI), and Apple\'s built-in Storage Management (System Settings > General > Storage, and the "Optimize Storage"/"Reduce Clutter" recommendations, plus what Finder and macOS do with purgeable space and iOS backups). For each: what it can find and delete, what permissions it needs, how it handles APFS (clones, snapshots, purgeable), and its limits. Apple\'s built-in tool is the free incumbent every user already has — be precise about what it covers, because a #1 app must clearly beat it.' },
  { id: 'cli-devtools', label: 'competitor:developer-CLI-tools', prompt: 'CLUSTER: the tools developers ACTUALLY use — this is the real competition for a developer cleaner. Catalogue precisely, with current docs: `xcrun simctl delete unavailable` / `simctl erase`, `xcrun simctl runtime delete`, Xcode > Settings > Platforms runtime deletion, `brew cleanup` / `brew autoremove` (what it removes, --prune), `docker system prune` / `docker builder prune` / `docker system df` and the Docker Desktop disk-image shrink behaviour, `npm cache clean`, `yarn cache clean`, `pnpm store prune`, `bun pm cache rm`, `npkill`, `cargo clean` / `cargo-sweep` / `cargo cache`, `go clean -modcache` / `-cache`, `pip cache purge`, `uv cache clean`, `conda clean --all`, `gradle --stop` and Gradle cache cleanup settings, `flutter clean` / `dart pub cache clean`, `mac-cleanup-py` (open source — read its module list, it is the closest thing to a developer rule catalogue), `tmutil thinlocalsnapshots`, and `sudo periodic`. For each, capture what it deletes, what it deliberately preserves, whether it has an official "safe" semantics, and how a GUI app could invoke it or replicate it via a documented API rather than a shell command.' },
  { id: 'mass-market', label: 'competitor:mass-market-cleaners', prompt: 'CLUSTER: mass-market and controversial cleaners. CCleaner for Mac, MacKeeper, MegaCleaner, Mac Cleaner Pro, CleanMaster/BuhoCleaner, Nektony MacCleaner Pro, OnyX (Titanium), and Malwarebytes-style "cleaners". Capture their target lists, pricing, permission demands, and — importantly — the trust failures: scareware tactics, false positives, deleted user data, App Review rejections, community warnings (e.g. Reddit r/mac, MacRumors forums, Apple Support Communities). This cluster defines what a #1 app must NOT do. Also capture which of them are on the Mac App Store and how they got there.' },
  { id: 'setapp-market', label: 'competitor:market-and-channels', prompt: 'CLUSTER: market structure. Research the Mac cleaner/utility market itself: the current Setapp catalogue of cleaners and disk tools (names, and Setapp\'s revenue-share model), Homebrew cask presence of cleaners, Product Hunt / Hacker News / Reddit launches of Mac cleaners in 2025-2026 (what got traction, what got torn apart), the size signals (DevCleaner ratings count, CleanMyMac claimed user numbers, MacPaw revenue if public), and the most upvoted complaints about the category as a whole. Also: is there any evidence of developer-specific demand — GitHub stars on dev-cache cleaners, HN threads about "my 512GB Mac is full", Apple forum threads on DerivedData/simulator bloat. Quantify demand where possible.' },
  { id: 'ai-era', label: 'competitor:AI-era-cleaners', prompt: 'CLUSTER: the new generation. Search for Mac cleaning tools launched or substantially updated in 2025-2026, especially: ones that clean AI/LLM tooling caches (Ollama models, Hugging Face hub, LM Studio, Cursor/VS Code/Copilot/Claude Code/Codex caches, MLX), ones with "explain before delete" or safety-first positioning, open-source Swift cleaners on GitHub with recent commits, and ones that do rebuild-cost or regeneration-cost estimation. Also search for cleaners that measure ACTUAL freed space after action (before/after free bytes) rather than summing candidate sizes. Identify whether anyone occupies the "safety-first, developer-first, open-source" position ViggoClean is aiming at. If nobody does, say so with evidence of what you searched.' },
]

const CATALOGUE_SCHEMA = {
  type: 'object',
  properties: {
    domain: { type: 'string' },
    rules: {
      type: 'array',
      description: 'every reclaimable location in this domain, most valuable first. Be exhaustive. 15-40 entries expected.',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'stable kebab-case id, e.g. xcode-ios-device-support' },
          title: { type: 'string' },
          paths: { type: 'array', items: { type: 'string' }, description: 'exact paths with ~ for home; include custom-location config keys/env vars if the tool supports relocating it' },
          insideHome: { type: 'boolean' },
          whatItIs: { type: 'string', description: 'one or two sentences on what lives here and why it grows' },
          safeToTrash: { type: 'string', enum: ['yes-regenerates', 'conditional', 'partial-subpaths-only', 'inventory-only-use-tool-api', 'never'] },
          conditions: { type: 'string', description: 'when it is safe / unsafe; sub-paths to preserve; what must be closed or stopped' },
          preferredMechanism: { type: 'string', description: 'move-to-Trash of paths, OR an official tool API/CLI (e.g. simctl, docker API, brew cleanup) if deleting the folder directly is wrong. Name the exact command/API.' },
          regeneration: { type: 'string', description: 'what happens after: rebuild time, re-download size, internet needed, sign-in needed' },
          typicalSize: { type: 'string', description: 'typical range on a developer Mac, with source; and the measured value on THIS Mac if you measured it' },
          measuredHereGB: { type: 'number', description: 'measured on this machine with du if you did; 0 if not measured or absent' },
          activeProcessCheck: { type: 'string', description: 'how to detect the owner is running (bundle ID, process name, lock file, socket, daemon)' },
          permissionNeeded: { type: 'string', enum: ['none', 'files-and-folders-prompt', 'full-disk-access', 'app-management', 'admin-privileged-helper', 'automation-apple-events', 'tool-api-only'] },
          officialSource: { type: 'string', description: 'URL of official documentation describing this location or its cleanup' },
          competitorsCovering: { type: 'array', items: { type: 'string' }, description: 'which known tools already clean this (CleanMyMac, DevCleaner, Sensei, Pearcleaner, mac-cleanup-py, brew, simctl...) — empty array if none you know of' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
        required: ['id', 'title', 'paths', 'insideHome', 'whatItIs', 'safeToTrash', 'conditions', 'preferredMechanism', 'regeneration', 'typicalSize', 'measuredHereGB', 'activeProcessCheck', 'permissionNeeded', 'officialSource', 'competitorsCovering', 'confidence'],
      },
    },
    domainSummary: { type: 'string', description: 'total realistic GB on a heavy dev Mac, the 3 biggest wins, and the traps (things that look like cache but are not)' },
  },
  required: ['domain', 'rules', 'domainSummary'],
}

const DOMAINS = [
  { id: 'apple-toolchain', label: 'catalogue:Apple-toolchain', prompt: 'DOMAIN: Apple developer toolchain. Xcode DerivedData (per-project structure, ModuleCache.noindex, Index.noindex, SymbolCache), Archives, iOS/watchOS/tvOS/visionOS DeviceSupport, ~/Library/Developer/CoreSimulator (Devices, Caches/dyld, Temp) vs /Library/Developer/CoreSimulator (runtime cryptex images — check ownership with ls -la on this machine, and whether they must go through `xcrun simctl runtime delete`), Xcode Previews (~/Library/Developer/Xcode/UserData/Previews), Xcode caches in ~/Library/Caches/com.apple.dt.Xcode, Instruments traces, Playground caches, CoreML compiled models, Swift toolchains in /Library/Developer/Toolchains, xcodes/Xcodes.app downloads, Xcode .xip leftovers, ~/Library/Developer/Xcode/iOS Device Logs, Products, DocumentationCache, XCPGDevices, and the Xcode "Products" in old Archives. Note which of these Apple itself deletes via Xcode > Settings > Platforms/Components, and which DevCleaner covers. Use Apple docs and the DevCleaner source as sources.' },
  { id: 'android-jvm', label: 'catalogue:Android-JVM-Flutter', prompt: 'DOMAIN: Android, JVM and Flutter. ~/.android (avd/*.avd images, build-cache, cache, breakpad, adb keys — which are precious), ~/Library/Android/sdk (system-images per API, platforms, build-tools multiple versions, emulator, ndk versions, sources, skins — and the official sdkmanager --uninstall path), ~/.gradle (caches/modules-2, caches/transforms-*, caches/build-cache-1, caches/jars-*, wrapper/dists, daemon/*/ logs, native, kotlin dsl, .tmp — and Gradle\'s own cleanup policy & org.gradle.caching settings), ~/.m2/repository, ~/.kotlin, Kotlin daemon logs, ~/.konan, JetBrains caches (~/Library/Caches/JetBrains/<product>/ — index, caches, tmp — vs ~/Library/Application Support/JetBrains which holds settings/plugins and is precious), Android Studio system dirs, Flutter (~/.pub-cache, flutter/bin/cache including engine artifacts, .dart_tool, build/ in projects, ~/.flutter), Dart analysis server cache, Bazel output base, sbt/ivy caches, Maven wrapper dists. The author\'s Mac has 34 GB in ~/.android and 22 GB in ~/Library/Android — inspect (read-only) what is actually in them.' },
  { id: 'js-web', label: 'catalogue:JS-web', prompt: 'DOMAIN: JavaScript/web. node_modules discovery across project roots (the npkill approach; how to detect staleness by project mtime/last git activity), npm _cacache and _logs, yarn v1 cache vs Berry .yarn/cache, pnpm content-addressable store (`pnpm store path`) and prune semantics, bun install cache, corepack cache, nvm/fnm/volta node versions, Playwright browsers (~/Library/Caches/ms-playwright), Puppeteer/Chromium downloads, Cypress cache (~/Library/Caches/Cypress), Electron and electron-builder caches, framework outputs (.next, .nuxt, .svelte-kit, .turbo, .parcel-cache, .cache, dist/build with caveats, .angular/cache, .vite, .expo, .eas), Vercel/Netlify CLI caches, Deno cache, TypeScript incremental build info, Storybook caches, Sass/webpack persistent caches. Include the exact config keys/env vars that relocate each cache (npm_config_cache, YARN_CACHE_FOLDER, PNPM_HOME, etc.) so the app can discover custom locations instead of assuming defaults. The author\'s Mac has ~12 GB node_modules.' },
  { id: 'systems-langs', label: 'catalogue:Rust-Go-Python-Ruby-etc', prompt: 'DOMAIN: systems and scripting languages. Rust (~/.cargo/registry/{cache,src,index}, ~/.cargo/git, per-project target/ dirs and how cargo-sweep detects stale artifacts, ~/.rustup toolchains and docs), Go (GOMODCACHE, GOCACHE at ~/Library/Caches/go-build, GOPATH/pkg), Python (pip cache, uv cache, poetry cache, pipx venvs, pyenv versions, conda/mamba pkgs and envs, __pycache__/.pytest_cache/.mypy_cache/.ruff_cache in projects, project venvs .venv/venv/env detection and staleness, Jupyter runtime), Ruby (gems, bundler cache, rbenv versions), PHP Composer cache, .NET NuGet packages (~/.nuget/packages) and obj/bin, Haskell (~/.stack, ~/.cabal), Elixir/Erlang (_build, deps, ~/.hex, ~/.mix), Zig cache, Swift Package Manager (~/Library/Caches/org.swift.swiftpm, .build in projects), CMake/ccache/sccache caches, Nix store (inventory only), Bazel. For each: exact path, relocating env var, official cleanup command, and what must be preserved (credentials files, config).' },
  { id: 'containers-ml', label: 'catalogue:containers-VMs-AI-ML', prompt: 'DOMAIN: containers, VMs and AI/ML. Docker Desktop (the Docker.raw / VM disk at ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw — explain why deleting the file is wrong and how the Docker Engine API /system/df, /images/prune, /build/prune, /volumes/prune over the unix socket is the correct mechanism, plus Docker Desktop\'s "disk image size" and how the raw file shrinks), OrbStack, Colima/Lima, Podman machine, Rancher Desktop, minikube/kind, Vagrant boxes (~/.vagrant.d/boxes), VirtualBox/UTM/Parallels VM images (inventory only), Multipass. AI/ML: Ollama models (~/.ollama/models, and its API for listing/removing), Hugging Face hub cache (~/.cache/huggingface/hub — and the huggingface-cli delete-cache tooling), LM Studio models, MLX/mlx-community caches, PyTorch hub (~/.cache/torch), TensorFlow datasets, Keras, Whisper models, Stable Diffusion/ComfyUI models, CoreML compiled model caches, Xcode/Apple Intelligence model caches if any exist on disk, Claude Code / Codex / Cursor / Windsurf / Copilot / VS Code caches (~/Library/Caches/claude-cli-nodejs, ~/Library/Caches/Codex exist on this machine — inspect what is in them and what is precious like conversation history vs disposable). Check `docker system df` only if Docker is already running.' },
  { id: 'macos-general', label: 'catalogue:macOS-general-junk', prompt: 'DOMAIN: general macOS space consumers — the CleanMyMac territory a #1 app must also cover. ~/Library/Caches (which children are safe, which are Apple-owned and must be left), /Library/Caches, ~/Library/Logs and /Library/Logs and /private/var/log, DiagnosticReports/crash reports, Mail (~/Library/Mail attachments and the Mail Downloads folder — precious vs cache), Messages attachments (~/Library/Messages/Attachments — precious), Photos (caches vs originals), iOS device backups (~/Library/Application Support/MobileSync/Backup — precious, inventory only), iOS/iPadOS software update .ipsw files (~/Library/iTunes/iPhone Software Updates), ~/Library/Application Support of removed apps (leftover detection by bundle-ID / Spotlight), Downloads installers (.dmg/.pkg/.zip older than N days), Trash size (~/.Trash and per-volume .Trashes), Time Machine local snapshots and `tmutil listlocalsnapshots` / thinlocalsnapshots, APFS purgeable space and how System Settings reports it, Spotlight index size, language localizations (why removing .lproj is a bad idea in 2026 — signed bundles), Safari/Chrome/Firefox/Arc/Brave/Edge caches vs profiles/cookies/history, Slack/Discord/Teams/Zoom caches, Spotify offline cache (~/Library/Caches/com.spotify.client vs Application Support), Adobe caches, font caches, QuickLook thumbnails, ~/Library/Saved Application State, Homebrew (Cellar old versions via brew cleanup, ~/Library/Caches/Homebrew, /opt/homebrew size — the author has 26 GB there; what is reclaimable vs installed software), and /private/var/folders (the confstr DARWIN_USER_CACHE_DIR — what is safe and what is not). For each: needs Full Disk Access? (Mail, Messages, Safari, Time Machine, MobileSync are TCC-protected).' },
  { id: 'measurement', label: 'catalogue:measurement-and-staleness', prompt: 'DOMAIN: not locations but MEASUREMENT AND INTELLIGENCE — the things that would make a cleaner smarter than any competitor. Research and specify: (1) how to compute real reclaimable bytes on APFS — allocated vs logical size, clone detection (FS_IOC / fcntl F_LOG2PHYS? or `du -A`? research which APIs expose cloning), snapshots holding blocks, purgeable space via `URLResourceValues.volumeAvailableCapacityForImportantUsage` / `.volumeAvailableCapacityForOpportunisticUsage`, and how to measure ACTUAL freed space before/after (statfs free blocks) rather than summing candidate sizes; (2) staleness signals: last access (atime is unreliable — research what works: kMDItemLastUsedDate, project git activity, mtime of parent, Xcode "last opened" plist), whether a DerivedData folder maps to a project that still exists on disk (info.plist WorkspacePath inside each DerivedData folder — verify), whether a node_modules parent has a package.json and recent git commits, whether a simulator device has been booted recently (simctl list -j has lastBootedAt?); (3) regeneration-cost estimation: rebuild time proxies (DerivedData size vs last build log), re-download size (cache size ≈ download), internet required; (4) active-process detection beyond bundle IDs: lock files (.gradle lock, DerivedData/.lock?), unix sockets, `lsof`-free approaches using proc_listpids/proc_pidpath in libproc (allowed for a non-sandboxed app?), NSRunningApplication, launchd services; (5) safe-verification of tool-managed stores: which caches have integrity files (npm _cacache index, pnpm store) so partial deletion is dangerous vs whole-dir deletion is safe. Cite Apple docs and tool docs for each.' },
]

const RULES_SCHEMA = {
  type: 'object',
  properties: {
    topic: { type: 'string' },
    facts: {
      type: 'array',
      description: 'concrete, sourced facts; 8-20 expected',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string', description: 'one precise sentence' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          source: { type: 'string', description: 'URL or the exact command/probe you ran on this machine' },
          implication: { type: 'string', description: 'what this means for ViggoClean specifically' },
          loadBearing: { type: 'boolean', description: 'true if the whole strategy would change if this fact were wrong' },
        },
        required: ['claim', 'confidence', 'source', 'implication', 'loadBearing'],
      },
    },
    allowed: { type: 'array', items: { type: 'string' }, description: 'what a Developer ID app may legitimately do/request in this area' },
    forbidden: { type: 'array', items: { type: 'string' }, description: 'what Apple forbids or App Review rejects' },
    recommendedApproach: { type: 'string', description: 'the concrete design ViggoClean should adopt, with API names' },
  },
  required: ['topic', 'facts', 'allowed', 'forbidden', 'recommendedApproach'],
}

const RULE_TOPICS = [
  { id: 'tcc', label: 'apple:TCC-and-Full-Disk-Access', prompt: 'TOPIC: TCC permissions a cleaner can legitimately ask for. Research from Apple docs and current WWDC/Platform Security guide: Full Disk Access (kTCCServiceSystemPolicyAllFiles) — what it unlocks (Mail, Messages, Safari, Time Machine, MobileSync, other users\' homes?), whether it can be requested programmatically or only via System Settings deep link (x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles), how to DETECT whether it has been granted (probe a protected path), and how app identity (signing) affects grant persistence. Files and Folders prompts (Desktop/Documents/Downloads/Removable/Network volumes) — when they fire, NSOpenPanel implicit grants, security-scoped bookmarks for non-sandboxed apps (needed or not?). App Management (kTCCServiceSystemPolicyAppBundles) — required to modify other apps\' bundles (relevant to uninstaller features). Automation/Apple Events to Finder — is this how to empty the Trash? (NSWorkspace has no empty-trash API; research the AppleScript `tell application "Finder" to empty trash` route, its NSAppleEventsUsageDescription requirement, and any alternative.) Also: does a NON-sandboxed Developer ID app need FDA to read ~/Library/Caches, ~/Library/Developer, ~/.gradle, /Library/Developer/CoreSimulator? Verify on this machine by attempting reads (read-only) and noting which fail with EPERM. Which exact Info.plist usage-description keys must exist?' },
  { id: 'privileged', label: 'apple:privileged-helpers-and-root', prompt: 'TOPIC: doing privileged work within Apple\'s rules. Research SMAppService (macOS 13+) for registering a privileged launch daemon from an app bundle (Contents/Library/LaunchDaemons), the required SMAuthorizedClients / SMPrivilegedExecutables Info.plist pairing, code-signing requirements, whether it works for Developer ID apps outside the store, and whether Mac App Store apps can use it (sandbox implications). Compare with the deprecated SMJobBless. What does CleanMyMac\'s helper actually do? Which cleanup targets on a dev Mac actually REQUIRE root (check ownership on this machine with ls -la: /Library/Developer/CoreSimulator/*, /Library/Caches, /private/var/log, /Library/Logs, /opt/homebrew, Docker\'s VM) versus merely FDA? Also research: XPC design for a root helper that only performs an allow-listed, path-validated operation (the least-privilege pattern), how to keep the "one trashItem call" safety posture when a helper exists (root cannot use the user\'s Trash — what does Apple recommend?), Endpoint Security / System Extensions (not needed for a cleaner — confirm), and what App Review / notarization forbid (no SIP changes, no disabling Gatekeeper, no undocumented private APIs).' },
  { id: 'review', label: 'apple:App-Review-and-distribution', prompt: 'TOPIC: App Store Review and distribution rules that apply to cleaners in 2026. Pull the CURRENT App Store Review Guidelines and quote the numbered guidelines that affect cleaners/utilities: 2.4.5 (Mac app requirements: sandbox, no unsupported APIs, no installing/launching other code, no privilege escalation), 2.5.x on system integrity, 4.x on design, 5.1.x privacy (data collection, FDA justification), and any rule about apps that "clean", "optimize", "boost" or "scan" systems, or misleading claims about freed space. Determine precisely: can a sandboxed MAS app use Full Disk Access? (Research: FDA is a TCC grant, sandbox is a separate mandatory container — a sandboxed app with FDA still cannot read outside its container without security-scoped access. Verify this from Apple docs or a reliable source; it is load-bearing.) What did DevCleaner and DaisyDisk change for MAS? Setapp requirements. Notarization: hardened runtime, timestamps, stapling, and whether a privileged helper or a CLI tool inside the bundle affects notarization. Also: does Apple allow an app to invoke `docker`, `brew`, `xcrun simctl` binaries on the user\'s machine (launching other code is a MAS restriction — outside MAS it is fine but confirm), and is calling the Docker Engine socket or Ollama HTTP API acceptable everywhere?' },
  { id: 'freed-space', label: 'apple:real-freed-space-and-APFS', prompt: 'TOPIC: telling the truth about freed space on APFS — a capability no mainstream competitor has, and a natural fit for ViggoClean\'s honesty posture. Research and specify with Apple docs: (1) how to read volume free space correctly — statfs vs URLResourceValues volumeAvailableCapacity, volumeAvailableCapacityForImportantUsage, volumeAvailableCapacityForOpportunisticUsage, and what "purgeable" means; (2) why moving to Trash frees nothing and emptying Trash may still free less than expected (APFS clones sharing extents, local Time Machine snapshots pinning blocks — `tmutil listlocalsnapshots /`, and how System Settings > Storage handles this); (3) APIs to detect clones/shared extents per file if any are public (research FSCTL/fcntl F_GETPATH? attrlist ATTR_CMN_DATA_PROTECT? — be honest if there is no public API and propose the best proxy); (4) how to measure ACTUAL freed bytes: sample free space before, after Trash move (expect ~0), after Trash empty, and after snapshot thinning; (5) what the Trash actually is per volume (~/.Trash vs /Volumes/X/.Trashes/<uid>), and the correct API for emptying it (research: no public NSWorkspace API; options are Finder Apple Events with NSAppleEventsUsageDescription, or deleting ~/.Trash contents directly with removeItem — the latter would violate ViggoClean\'s one-trashItem principle, so weigh both); (6) `tmutil thinlocalsnapshots` and `tmutil deletelocalsnapshots` — do they need root? Test read-only commands on this machine: `tmutil listlocalsnapshots /`, `df`, `diskutil apfs list` summaries.' },
]

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    reasoning: { type: 'string', description: 'what you checked (URLs, commands) and what you concluded' },
    correction: { type: 'string', description: 'the corrected statement if partly right' },
  },
  required: ['refuted', 'confidence', 'reasoning'],
}

const STRATEGY_SCHEMA = {
  type: 'object',
  properties: {
    angle: { type: 'string' },
    canBeNumberOne: { type: 'string', enum: ['yes-clearly', 'yes-in-a-defined-niche', 'only-with-a-team', 'no'] },
    whatNumberOneMeans: { type: 'string', description: 'the precise definition of #1 this angle argues for, and why that definition is the winnable one' },
    thesis: { type: 'string', description: 'the core argument in detail, engaging with the research digest' },
    whitespace: { type: 'array', items: { type: 'string' }, description: 'specific things no competitor does or does well, ranked' },
    mustHave: { type: 'array', items: { type: 'string' }, description: 'capabilities without which the claim is not credible' },
    mustNot: { type: 'array', items: { type: 'string' }, description: 'things that would destroy the position' },
    architectureChanges: { type: 'array', items: { type: 'string' }, description: 'concrete changes to the current codebase, with file references' },
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

phase('Competitors')
log(`Deep-diving ${COMPETITORS.length} competitor clusters`)
const competitorRaw = await parallel(COMPETITORS.map((c) => () =>
  agent(CONTEXT + '\n\n========\n\nYOUR TASK: ' + c.prompt + '\n\nBe exhaustive on `targets` — every distinct cleanable thing, one entry each. This feeds a coverage matrix and gaps are what we are hunting for.', { label: c.label, phase: 'Competitors', schema: COMPETITOR_SCHEMA })
))
const competitors = competitorRaw.filter(Boolean)
log(`${competitors.length}/${COMPETITORS.length} competitor clusters reported, ${competitors.reduce((n, c) => n + c.products.length, 0)} products, ${competitors.reduce((n, c) => n + c.products.reduce((m, p) => m + p.targets.length, 0), 0)} cleanable targets catalogued`)
if (competitors.length < COMPETITORS.length) log('WARNING: missing clusters: ' + COMPETITORS.filter((_, i) => !competitorRaw[i]).map((c) => c.id).join(', '))

phase('Catalogue')
log(`Mapping ${DOMAINS.length} reclaimable-space domains`)
const catalogueRaw = await parallel(DOMAINS.map((d) => () =>
  agent(CONTEXT + '\n\n========\n\nYOUR TASK: ' + d.prompt + '\n\nYou may measure paths on this machine with `du -sh` (read-only; skip anything over ~60 s) and record the value in measuredHereGB. Be exhaustive and exact. Every rule needs an officialSource URL.', { label: d.label, phase: 'Catalogue', schema: CATALOGUE_SCHEMA })
))
const catalogue = catalogueRaw.filter(Boolean)
const allRules = catalogue.flatMap((d) => d.rules.map((r) => Object.assign({ domain: d.domain }, r)))
log(`${catalogue.length}/${DOMAINS.length} domains reported, ${allRules.length} rules catalogued`)
if (catalogue.length < DOMAINS.length) log('WARNING: missing domains: ' + DOMAINS.filter((_, i) => !catalogueRaw[i]).map((d) => d.id).join(', '))

phase('Apple rules')
const rulesRaw = await parallel(RULE_TOPICS.map((t) => () =>
  agent(CONTEXT + '\n\n========\n\nYOUR TASK: ' + t.prompt + '\n\nMark loadBearing=true on any fact that, if wrong, would change the whole strategy. Those get adversarially verified.', { label: t.label, phase: 'Apple rules', schema: RULES_SCHEMA })
))
const rules = rulesRaw.filter(Boolean)
const loadBearing = rules.flatMap((r) => r.facts.filter((f) => f.loadBearing).map((f) => Object.assign({ topic: r.topic }, f)))
log(`${rules.length}/${RULE_TOPICS.length} rule topics reported, ${loadBearing.length} load-bearing claims`)

phase('Verify')
const CAP = 8
const toVerify = loadBearing.slice(0, CAP)
if (loadBearing.length > CAP) log(`Verifying the first ${CAP} of ${loadBearing.length} load-bearing claims; the rest are reported UNVERIFIED`)
const VERIFY_LENSES = [
  { id: 'refute', build: (f) => `Adversarially verify this claim about macOS/Apple rules. Your job is to REFUTE it if you can, using CURRENT Apple documentation (developer.apple.com, support.apple.com, App Store Review Guidelines) and, where possible, read-only probes on this machine.\n\nCLAIM: ${f.claim}\nOFFERED SOURCE: ${f.source}\nCLAIMED IMPLICATION: ${f.implication}\n\nCheck: is it literally true today? Was it true once but changed (macOS 13/14/15/26 changes)? Does the source actually say this? Default to refuted=true if you cannot positively confirm it from a primary source.` },
  { id: 'implication', build: (f) => `Assume this claim about macOS/Apple rules is TRUE. Judge whether the stated IMPLICATION for ViggoClean actually follows, and whether it is the most important implication.\n\nCLAIM: ${f.claim}\nCLAIMED IMPLICATION: ${f.implication}\n\nContext: ViggoClean is a non-sandboxed, Developer ID-signed (to be) macOS cleaner whose safety posture is one trashItem call, no root, no shell. The author wants to be the best cleaner in the world within Apple's rules. Set refuted=true only if the implication is wrong or misleading. Provide the corrected implication otherwise.` },
]
const verified = await parallel(toVerify.map((f) => () =>
  parallel(VERIFY_LENSES.map((l) => () =>
    agent(CONTEXT + '\n\n========\n\n' + l.build(f), { label: `${l.id}: ${String(f.claim).slice(0, 50)}`, phase: 'Verify', schema: VERDICT_SCHEMA })
  )).then((votes) => ({ claim: f, votes: votes.filter(Boolean) }))
))
const verdicts = verified.filter(Boolean).map((v) => ({
  claim: v.claim.claim,
  topic: v.claim.topic,
  status: v.votes.length === 0 ? 'unverified' : v.votes.every((x) => !x.refuted) ? 'confirmed' : v.votes.every((x) => x.refuted) ? 'refuted' : 'contested',
  notes: v.votes.map((x) => `[${x.confidence}] ${x.reasoning}${x.correction ? ' CORRECTION: ' + x.correction : ''}`),
}))
log(`Verification: ${verdicts.filter((v) => v.status === 'confirmed').length} confirmed, ${verdicts.filter((v) => v.status === 'contested').length} contested, ${verdicts.filter((v) => v.status === 'refuted').length} refuted`)

const coverageByTool = {}
for (const c of competitors) for (const p of c.products) coverageByTool[p.name] = p.targets.map((t) => `${t.category}: ${t.target}`)
const digest = JSON.stringify({
  competitorClusters: competitors.map((c) => ({ cluster: c.cluster, insight: c.clusterInsight, products: c.products.map((p) => ({ name: p.name, price: p.price, channel: p.channel, sandboxed: p.sandboxed, openSource: p.openSource, targetCount: p.targets.length, capabilities: p.capabilities, permissions: p.permissionsRequested, trust: p.trustSignals, weaknesses: p.weaknesses })) })),
  coverageByTool,
  rulesCatalogue: allRules.map((r) => ({ id: r.id, domain: r.domain, title: r.title, paths: r.paths, insideHome: r.insideHome, safeToTrash: r.safeToTrash, mechanism: r.preferredMechanism, typicalSize: r.typicalSize, measuredHereGB: r.measuredHereGB, permission: r.permissionNeeded, competitorsCovering: r.competitorsCovering, confidence: r.confidence, conditions: r.conditions, regeneration: r.regeneration })),
  domainSummaries: catalogue.map((d) => ({ domain: d.domain, summary: d.domainSummary })),
  appleRules: rules.map((r) => ({ topic: r.topic, allowed: r.allowed, forbidden: r.forbidden, recommendedApproach: r.recommendedApproach, facts: r.facts.map((f) => ({ claim: f.claim, confidence: f.confidence, implication: f.implication, loadBearing: f.loadBearing })) })),
  verification: verdicts,
}, null, 1)

phase('Strategy')
const STRATEGISTS = [
  { id: 'product', prompt: 'ANGLE: product strategist. Using the coverage matrix and catalogue, find the WHITESPACE: what does no competitor do, or do well? Where do the incumbents\' business models (subscriptions, scareware, MAS sandbox) structurally prevent them from following? Define what "#1" can credibly mean for a solo developer within 12 months, and argue for the sharpest possible positioning. Rank rules by GB × how many dev Macs have them × how badly competitors cover them. Say plainly if "best in the world" needs to be narrowed to be true.' },
  { id: 'engineer', prompt: 'ANGLE: principal engineer. Read the actual code at the repo (FileSafety.swift, Scanner.swift, LocalCleaningRepository.swift, WorkspaceContracts.swift, Models.swift). Design what the architecture must become to hold 100+ rules from the catalogue, multiple mechanisms (Trash move, tool APIs like Docker socket/Ollama HTTP/simctl, and possibly a least-privilege root helper for root-owned paths), custom-location discovery via env/config, staleness scoring, active-process detection, real freed-space measurement, and a rule catalogue with provenance and fixtures per AGENTS.md. Preserve the invariants: one destructive filesystem primitive, no Select All, scan-only-until-validated, per-rule positive/negative fixtures. Be concrete: file layout, protocols, the rule DSL, how a helper stays inside the one-primitive principle, what to do about the whole-tree-refusal problem. Give effort per phase.' },
  { id: 'trust', prompt: 'ANGLE: trust and safety architect. The category is defined by tools that lie and tools that delete the wrong thing. ViggoClean\'s only current moat is checkable safety. As coverage expands 10x and permissions expand (Full Disk Access, maybe a privileged helper, Automation to empty Trash), how does it KEEP that moat — and turn it into the reason it wins? Specify: the permission-onboarding UX that asks for the most while feeling the safest, the rules for which categories may never auto-select, how "real freed space" should be reported, what an undo/journal must guarantee, how to make safety claims verifiable in public (open source, reproducible fixtures, a published threat model, third-party audit), and what the app must refuse to do even when users ask. Identify every point where "more coverage" and "provable safety" conflict, and resolve each.' },
]
const strategies = (await parallel(STRATEGISTS.map((s) => () =>
  agent(`${CONTEXT}\n\n========\n\n${s.prompt}\n\n========\n\nRESEARCH DIGEST (competitors, catalogue, Apple rules, verification):\n${digest}`, { label: `strategy:${s.id}`, phase: 'Strategy', schema: STRATEGY_SCHEMA })
))).filter(Boolean)
log(`${strategies.length}/${STRATEGISTS.length} strategies: ${strategies.map((s) => s.canBeNumberOne).join(', ')}`)

phase('Critique')
const critique = await agent(`${CONTEXT}\n\n========\n\nYou are the completeness critic. The research below will become the author's strategy for making ViggoClean the best Mac cleaner in the world within Apple's rules. Find what is MISSING or WRONG.\n\nCheck specifically: (1) reclaimable locations on a developer Mac that no catalogue domain listed — go look at this machine's ~/Library, ~/.cache, ~/.config, ~/Library/Application Support and ~/Library/Containers (read-only) for big things the catalogue missed; (2) competitors or tools nobody researched; (3) any Apple-rules claim that looks wrong or outdated — verify the two most consequential yourself; (4) whether the three strategies contradict each other and who is right; (5) whether the strategies would actually beat Apple's built-in Storage Management + the CLI tools a developer already has, which is the real bar; (6) the single most important thing the author should do next that nobody has said. Cite files, paths and URLs. Plain prose under those six headings.\n\nRESEARCH DIGEST:\n${digest}\n\nSTRATEGIES:\n${JSON.stringify(strategies, null, 1)}`, { label: 'completeness-critic', phase: 'Critique' })

phase('Synthesize')
const report = await agent(`${CONTEXT}\n\n========\n\nWrite the final strategy document for the author. They asked: "can we add more than competitors, can we be number one? I want the best app in the world, passing competitors way way further. Do whatever it takes, ask for any permissions, within Apple's rules."\n\nRESEARCH DIGEST:\n${digest}\n\nTHREE STRATEGIES:\n${JSON.stringify(strategies, null, 1)}\n\nCOMPLETENESS CRITIC:\n${critique}\n\nWrite Markdown with exactly these sections:\n\n## Straight answer\nCan it be #1? Under what definition? Say it in three sentences, no hedging. If the three strategists disagreed, say who said what and take a position.\n\n## The coverage matrix\nA Markdown table: rows = the ~20 most valuable target categories (from the catalogue, ordered by GB × prevalence); columns = ViggoClean today, CleanMyMac, Sensei, DevCleaner, Pearcleaner, mac-cleanup-py, Apple built-in, developer CLI tools. Cells: ✅ / partial / ❌ / n/a. Then two sentences on what the matrix shows.\n\n## Everything reclaimable on a developer Mac\nThe full rule catalogue as a table, ranked by value: id, path(s), typical GB, measured on the author's Mac, safe-to-trash class, mechanism (Trash / tool API / helper), permission needed, who covers it today. Include every rule from the research; this is the thing the author will build from. Mark low-confidence rows.\n\n## What no one does — the whitespace\nRanked list with evidence from the competitor research.\n\n## Permissions: what to ask for and what it unlocks\nA table: permission → what it unlocks (GB on the author's Mac) → how to request it (API/deep link, Info.plist keys) → Apple constraint. Include Full Disk Access, Files & Folders, App Management, Automation (empty Trash), privileged helper via SMAppService, tool APIs (Docker socket, Ollama, simctl). State clearly which Apple rules must never be crossed. Flag any load-bearing claim that verification contested or refuted.\n\n## The definition of #1 that is winnable\nThe positioning, in one paragraph, and the five capabilities that make it true.\n\n## Architecture required\nConcrete changes to the codebase with file references, preserving the invariants (one destructive primitive, no Select All, fixtures per rule). Include the rule DSL shape and how a helper (if any) stays inside the safety model.\n\n## Roadmap\nPhases in dependency order. For each: goal, deliverables, part-time effort, GB unlocked on the author's Mac. Cumulative GB at the end of each phase. Be realistic about a solo developer.\n\n## What would kill it\nThe risks, ranked, each with the mitigation.\n\n## Monday morning\nThe first three concrete tasks, in order, each under a day.\n\nRULES: every path, size and Apple claim must come from the research above; do not invent. Prefer tables over prose where the data is tabular. The author is a capable developer — no basics. Be direct.`, { label: 'final-strategy', phase: 'Synthesize' })

return {
  counts: {
    competitorProducts: competitors.reduce((n, c) => n + c.products.length, 0),
    competitorTargets: competitors.reduce((n, c) => n + c.products.reduce((m, p) => m + p.targets.length, 0), 0),
    rulesCatalogued: allRules.length,
    loadBearingClaims: loadBearing.length,
    verification: { confirmed: verdicts.filter((v) => v.status === 'confirmed').length, contested: verdicts.filter((v) => v.status === 'contested').length, refuted: verdicts.filter((v) => v.status === 'refuted').length },
  },
  strategistVerdicts: strategies.map((s) => ({ angle: s.angle, canBeNumberOne: s.canBeNumberOne, definition: s.whatNumberOneMeans })),
  report,
}
