export const meta = {
  name: 'viggoclean-product-audit',
  description: 'Audit ViggoClean for safety, code quality, efficacy and App Store viability',
  phases: [
    { title: 'Assess', detail: '7 parallel lenses: data-loss safety, Swift correctness, scale+tests, UX/a11y, real-world efficacy, macOS distribution, release readiness' },
    { title: 'Verify', detail: 'adversarial 2-lens verification of the highest-severity findings' },
    { title: 'Market', detail: '3 independent commercial verdicts from different angles' },
    { title: 'Critique', detail: 'completeness critic hunts for what the audit missed' },
    { title: 'Synthesize', detail: 'final scorecard, verdict and concrete ship path' },
  ],
}

const REPO = '/Users/tloshi/AndroidStudioProjects/loshis/viggoclean'

const CONTEXT = `You are auditing a real macOS application. Repository: ${REPO}

PROJECT: ViggoClean 0.2.0 — a native macOS 14+ disk cleaner. SwiftUI + Swift Package Manager, 2,523 lines total across Swift/Python/shell, zero third-party dependencies. Modules: ViggoCleanCore (domain + file safety + scanner + repository), ViggoCleanPresentation (ViewModel/Presenter/ViewState), ViggoClean (SwiftUI views, services, composition root).

THE AUTHOR'S SITUATION AND QUESTION: They built this for themselves and a few friends. They are developers on Macs with 512 GB SSDs that fill up fast during development work. They now ask two things: (a) how good is this app, really? (b) could it also go in an app store? Your findings feed a direct, honest answer to both.

FACTS ALREADY VERIFIED — treat as established, do not spend effort re-checking:
- \`swift test\` passes: 32 tests total (15 SafetyTests, 7 RepositoryTests, 10 WorkspaceViewModelTests) in ~30 ms. The count claimed in docs/VALIDATION.md is accurate.
- There is NO .entitlements file anywhere in the repo, and no App Sandbox / hardened-runtime build settings in ViggoClean.xcodeproj/project.pbxproj.
- scripts/build-app.sh signs ad-hoc (\`codesign --force --sign - --options runtime\`). There is no Developer ID signing and no notarization step.
- Info.plist: bundle id com.loshi.viggoclean, LSMinimumSystemVersion 14.0, CFBundleShortVersionString 0.2.0. No usage-description keys of any kind.
- Git history is a single commit ("Initial Commit"). There is no LICENSE file, no CI configuration, and no update mechanism.

READ FIRST (they are short and dense): README.md, AGENTS.md, docs/ARCHITECTURE.md, docs/VALIDATION.md, and docs/ROADMAP.md (written in Albanian — read it anyway, it contains the real product plan and the author's stated principles).

GROUND RULES:
- The app's scan is read-only, but DO NOT run ViggoClean's cleanup, and do not move anything to Trash. Reading code, \`swift build\`, \`swift test\` and \`python3 scripts/check-boundaries.py\` are all fine.
- Ground every finding in a specific file and line. A finding with no file:line and no quoted code is worthless.
- BE BRUTALLY HONEST AND CALIBRATED. The author wants a real assessment, not encouragement. Do not inflate severity to seem rigorous, and do not soften real problems to seem kind. If something is genuinely better than typical hobby code, say so and say why; if something is weak, missing or wrong, say that plainly.
- IMPORTANT CALIBRATION RULE: this project documents its own limitations unusually thoroughly in README.md "Current limits", docs/ARCHITECTURE.md "Limits / threat model" and docs/ROADMAP.md. Before you file a finding, check whether the author already discloses it. A known, documented, deliberately-accepted limitation is NOT the same as a bug — file it at lower severity and say explicitly that it is disclosed. Reserve CRITICAL/HIGH for things that are genuinely undisclosed, or disclosed but still unacceptable for the shipping decision being considered.
- Use the STRENGTH severity for things this project does notably better than comparable software. A credible audit reports both.`

const FINDING_SCHEMA = {
  type: 'object',
  properties: {
    summary: { type: 'string', description: '3-6 sentence verdict for this lens specifically' },
    score: { type: 'number', description: '0-10 score for this dimension. 5 = typical competent hobby project, 7 = solid indie product, 9 = professional commercial quality' },
    scoreRationale: { type: 'string', description: 'why that exact number, with the comparison class named' },
    findings: {
      type: 'array',
      description: 'concrete findings, most important first, max 12',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string', description: 'one specific sentence' },
          severity: { type: 'string', enum: ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'STRENGTH'] },
          location: { type: 'string', description: 'file:line, or the doc/config it concerns' },
          evidence: { type: 'string', description: 'quoted code or text proving it' },
          impact: { type: 'string', description: 'what actually goes wrong, for whom, in what situation' },
          alreadyDisclosed: { type: 'boolean', description: 'true if README/ARCHITECTURE/ROADMAP already states this limitation' },
          recommendation: { type: 'string' },
          effortToFix: { type: 'string', enum: ['minutes', 'hours', 'days', 'weeks', 'months'] },
          blocksShipping: { type: 'boolean', description: 'true if this must be fixed before distributing to people who are not the author' },
        },
        required: ['title', 'severity', 'location', 'evidence', 'impact', 'alreadyDisclosed', 'recommendation', 'effortToFix', 'blocksShipping'],
      },
    },
  },
  required: ['summary', 'score', 'scoreRationale', 'findings'],
}

const DIMENSIONS = [
  {
    id: 'safety',
    label: 'lens:data-loss-safety',
    prompt: `LENS: DATA-LOSS SAFETY. This is the single most important lens — the app moves user files to Trash, so a wrong deletion is the existential failure mode.

Adversarially hunt for any path by which ViggoClean could move something to Trash that the user did not intend, or destroy something unrecoverably. Read Sources/ViggoCleanCore/FileSafety.swift, Sources/ViggoCleanCore/Scanner.swift, Sources/ViggoCleanCore/Repositories/LocalCleaningRepository.swift and Sources/ViggoCleanCore/Models.swift line by line.

Specifically probe: containment logic in \`FileSafety.isInside\` (is prefix-of-pathComponents sound? standardized vs resolvingSymlinksInPath?); the ancestor symlink walk in \`validate\`; the TOCTOU window between \`snapshot\` at scan time and re-\`snapshot\` at cleanup time; whether the TreeStamp digest can collide or miss a meaningful change; hard-link and package and special-file rejection; cross-device checks; how exclusions propagate to descendants and ancestors; whether a scan-only candidate can ever reach \`trash\`; what happens when \`trashItem\` fails (is there truly no removeItem fallback?); whether history can be replayed as a delete request; and whether any rule could nominate source code, credentials, or user documents.

Also assess the QUALITY of the safety model as a whole, not just its holes: compared to how disk cleaners are usually written, is this conservative, average, or reckless? Say so explicitly with evidence.`,
  },
  {
    id: 'correctness',
    label: 'lens:swift-correctness',
    prompt: `LENS: SWIFT AND CONCURRENCY CORRECTNESS.

Review every Swift file for language-level and API-level correctness. Probe: Sendable conformance and actor isolation (ViggoCleanApp, AppContainer, the actor-based history store, @MainActor usage); data races on mutable state captured by the scanner's progress closure; structured-concurrency correctness and whether cancellation actually propagates to the detached worker; the \`Task.checkCancellation\` placement; error handling (swallowed errors, errors converted to strings and losing type, \`localizedDescription\` used as control flow); force unwraps and implicitly-unwrapped optionals; integer overflow in byte accumulation; the RECURSIVE \`walk\` function in FileSafety.snapshot and its stack-depth behaviour on deep trees; double \`attributesOfItem\` calls per entry; correct vs incorrect use of FileManager, URLResourceValues, and the Trash API; and whether the code would compile cleanly under Swift 6 strict concurrency.

Run \`swift build -Xswiftc -strict-concurrency=complete\` if useful, and \`python3 scripts/check-boundaries.py\`. Report what the compiler actually says.`,
  },
  {
    id: 'scale',
    label: 'lens:scale-and-tests',
    prompt: `LENS: BEHAVIOUR AT REAL SCALE, PLUS TEST RIGOUR AND ARCHITECTURE.

PART A — scale. This app's whole purpose is cleaning developer machines, where Xcode DerivedData can be 50+ GB across hundreds of thousands of files and node_modules trees are enormous and deep. Analyse what actually happens then. Note that \`Scanner.add\` calls \`FileSafety.snapshot\` for EVERY candidate during the scan, which fully enumerates and stats every file in the tree — and \`CleanupEngine.perform\` does it AGAIN at cleanup. Quantify that cost. Also examine the O(n^2)-looking \`report.candidates.contains(where:)\` check, memory held per directory, whether work blocks the main actor, and how fast cancellation actually takes effect on a huge tree.

PART B — tests. There are 32 passing tests. Judge whether they test what actually matters given the threat model in docs/ARCHITECTURE.md. Read all three test files. What real risk is covered, and what risk is claimed but untested? Note in particular that no test exercises real \`FileManager.trashItem\`, there are no UI tests, no performance tests, and docs/VALIDATION.md admits macOS 14 and Intel runtime testing was never done.

PART C — architecture. docs/ARCHITECTURE.md makes strong layering claims. Verify them against the code. Is scripts/check-boundaries.py (24 lines) a real enforcement mechanism or security theatre? Would this architecture actually support the rule-catalogue expansion that docs/ROADMAP.md Phase 2 requires, or would it need restructuring?`,
  },
  {
    id: 'ux',
    label: 'lens:ux-and-accessibility',
    prompt: `LENS: USER EXPERIENCE, VISUAL DESIGN AND ACCESSIBILITY.

Read Sources/ViggoClean/Views/*.swift and Sources/ViggoClean/DesignSystem/*.swift. Evaluate the five surfaces (Overview, Review & clean, Projects, Activity, Settings) as a product a stranger would use, not as code.

Probe: is the information hierarchy clear enough that a user understands what will be deleted and why, before they confirm? Are consequences communicated honestly and specifically? Are the empty / scanning / cancelled / no-results / partial-results / permission-denied / confirming / cleaning / partial-success / failure states all actually handled in the views, or only listed in the roadmap? Is the confirmation flow genuinely hard to fire accidentally?

Accessibility: VoiceOver labels, keyboard navigation and focus order, colour-independent meaning, Dynamic Type / long text, contrast, window resizing down to the stated 1000x700 minimum, and the \`accessibilityReduceMotion\` handling in the motion system. Does the accessibility claimed in docs match the code?

Also judge the visual design direction itself (dark graphite/blue with mint accent) against current native macOS app expectations — does this look like a credible commercial macOS app in 2026, or like a developer's side project? Be specific about what would need to change.`,
  },
  {
    id: 'efficacy',
    label: 'lens:real-world-efficacy',
    prompt: `LENS: DOES IT ACTUALLY SOLVE THE PROBLEM?

The author's stated problem: developers on 512 GB Macs whose disks fill up. Judge whether ViggoClean 0.2 meaningfully solves that TODAY.

First, establish what actually consumes space on a modern developer Mac. Use WebSearch/WebFetch for current, concrete figures. Consider at minimum: Xcode DerivedData, iOS DeviceSupport, Xcode Archives, simulator runtimes and unavailable simulator devices, Android SDK + AVD system images, Docker.raw / Docker Desktop VM disk, node_modules across many repos, pnpm/yarn stores, ~/.gradle (caches, wrapper distributions, daemon), Rust target/ dirs and ~/.cargo, Go module cache, Python venvs and ~/.cache/pip, CocoaPods, Flutter/Dart pub cache, ~/.m2, conda envs, Homebrew cellar and downloads, Time Machine local snapshots, Mail/Photos caches, and the APFS purgeable-space effect.

Then map that against README.md "What works in 0.2": Xcode DerivedData, SwiftPM, npm _cacache, Gradle build-cache-1, CocoaPods, Homebrew downloads, pip, third-party ~/Library/Caches children, browser caches in cache paths, and .log files older than 30 days — with project folders SCAN-ONLY (cannot be cleaned).

Quantify the coverage gap in GB terms where you can. Critically: Xcode DeviceSupport, Archives, simulator runtimes, Docker.raw, node_modules and Gradle distributions are usually among the very biggest wins on a dev Mac — check carefully which of those ViggoClean can and cannot reclaim today. Note that ~/.gradle/caches/build-cache-1 is only a fraction of ~/.gradle.

Conclude with a direct answer: on a typical full 512 GB dev Mac, roughly how much would ViggoClean 0.2 actually free, versus the tools a developer already has? Is the app currently worth running?`,
  },
  {
    id: 'distribution',
    label: 'lens:macos-distribution',
    prompt: `LENS: MACOS DISTRIBUTION AND APP STORE VIABILITY. This lens directly answers the author's second question, so be concrete and current.

USE WEBSEARCH/WEBFETCH — do not rely on memory for Apple's rules, they change.

Establish and report, with sources:
1. Mac App Store technical requirements: is App Sandbox mandatory for MAS distribution? What exactly can a sandboxed app read and delete under ~/Library/Caches, ~/Library/Developer/Xcode/DerivedData, ~/.gradle, ~/.npm? Cover security-scoped bookmarks and \`com.apple.security.files.user-selected.read-write\`, and the temporary-exception entitlements (are they still granted in 2026?).
2. App Review Guidelines that specifically bite disk cleaners / system utilities. Quote the guideline numbers and text. Include anything about apps that claim to clean, optimise, or scan the system, and rules on accessing other apps' data.
3. Real precedent — check what actually exists today and how it is distributed: DevCleaner for Xcode, DaisyDisk (MAS vs direct, and what the MAS version cannot do), CleanMyMac (why it is NOT on the Mac App Store), OmniDiskSweeper, GrandPerspective, Pearcleaner, AppCleaner, Sensei. This precedent is the strongest available evidence.
4. The Developer ID path: $99/yr Apple Developer Program, Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper. What must change in this repo's scripts/build-app.sh and project.pbxproj?
5. TCC / Full Disk Access: what does this app need, when does macOS prompt, and what can it not reach without it?

Then give a DIRECT recommendation on channel: Mac App Store, Developer ID + notarized DMG outside the store, both, or neither. State what specifically would have to be built or changed for each, and be honest about which parts of the current feature set would have to be dropped for a sandboxed MAS build.`,
  },
  {
    id: 'readiness',
    label: 'lens:release-readiness',
    prompt: `LENS: RELEASE ENGINEERING, LEGAL AND SUPPORT READINESS — the gap between "works on my Mac" and "other people can install and rely on it".

Assess what is missing: there is no LICENSE file (what does that mean legally if friends or strangers use it?); no CI; a single-commit git history; no versioning discipline or changelog; no auto-update mechanism (Sparkle or equivalent) and what that means for shipping a safety fix to users of a file-deleting app; no crash reporting; no error telemetry (note the app deliberately has no telemetry — weigh that trade-off honestly for a tool that deletes files).

Legal and liability: a tool that moves user files to Trash and gets it wrong. What disclaimer, EULA or warranty language is needed? What is the realistic exposure for a paid vs free tool? Does "ViggoClean" carry any trademark risk worth checking?

Documentation and onboarding: README quality, the fact that docs/ROADMAP.md is in Albanian while README is in English, and what a first-time non-author user is missing.

Support burden: realistically, what happens the first week after strangers install a disk cleaner? What support surface does the author not have?

Finally: what is the minimum credible bar to hand this to friends outside the author's own machine, versus to sell it to strangers? Enumerate both lists concretely.`,
  },
]

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean', description: 'true if the finding does not hold up' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    correctedSeverity: { type: 'string', enum: ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'NOT_A_FINDING'] },
    reasoning: { type: 'string', description: 'what you checked and what you concluded, citing file:line' },
    correction: { type: 'string', description: 'if the finding is partly right, the corrected statement of it' },
  },
  required: ['refuted', 'confidence', 'correctedSeverity', 'reasoning'],
}

const LENSES = [
  {
    id: 'technical-truth',
    build: (f) => `Adversarially verify this audit finding about ViggoClean at ${REPO}. Your job is to REFUTE it if you can.

FINDING: ${f.title}
SEVERITY CLAIMED: ${f.severity}
LOCATION: ${f.location}
EVIDENCE OFFERED: ${f.evidence}
CLAIMED IMPACT: ${f.impact}

Go read the actual code at that location and the surrounding context. Is the technical claim literally true? Check whether a guard elsewhere already prevents it, whether the auditor misread the control flow, whether the quoted evidence actually says what they claim, and whether the described failure could really occur. Run code or tests if that settles it.

Default to refuted=true if you cannot positively confirm the mechanism. A finding that "sounds plausible" but that you cannot demonstrate is refuted.`,
  },
  {
    id: 'materiality',
    build: (f) => `Assess whether this audit finding about ViggoClean at ${REPO} actually MATTERS. Assume the technical claim is true; judge its real-world weight.

FINDING: ${f.title}
SEVERITY CLAIMED: ${f.severity}
LOCATION: ${f.location}
CLAIMED IMPACT: ${f.impact}
AUTHOR ALREADY DISCLOSES THIS: ${f.alreadyDisclosed}

Context: this is a 2,523-line personal macOS disk cleaner at version 0.2, currently used by its author and a few friends, being considered for wider distribution. The author documents their own limitations extensively and honestly.

Judge: would a real user actually hit this, and how bad is it when they do? Is the claimed severity calibrated, or is it inflated? If the author already discloses this as a known limitation and consciously accepted it, that should usually reduce severity — a documented, deliberate scope boundary is a roadmap item, not a defect. Conversely, if it is disclosed but would still lose someone's data or get the app rejected from a store, keep it high.

Set refuted=true ONLY if the finding is so immaterial that reporting it would waste the author's attention. Otherwise set the correctedSeverity you believe is right.`,
  },
]

phase('Assess')
log('Running 7 analysis lenses over ViggoClean in parallel')

const raw = await parallel(DIMENSIONS.map((d) => () =>
  agent(CONTEXT + '\n\n========\n\n' + d.prompt, { label: d.label, phase: 'Assess', schema: FINDING_SCHEMA })
))

const assessments = raw
  .map((r, i) => (r ? { id: DIMENSIONS[i].id, label: DIMENSIONS[i].label, ...r } : null))
  .filter(Boolean)

log(`${assessments.length}/${DIMENSIONS.length} lenses reported`)
if (assessments.length < DIMENSIONS.length) {
  const missing = DIMENSIONS.filter((d) => !assessments.some((a) => a.id === d.id)).map((d) => d.id)
  log(`WARNING: these lenses produced no result and are NOT covered: ${missing.join(', ')}`)
}

const normalize = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim().split(' ').slice(0, 9).join(' ')
const merged = new Map()
for (const a of assessments) {
  for (const f of a.findings || []) {
    const key = normalize(f.title) + '||' + normalize(f.location)
    if (merged.has(key)) {
      merged.get(key).lenses.push(a.id)
    } else {
      merged.set(key, Object.assign({}, f, { lenses: [a.id] }))
    }
  }
}
const all = Array.from(merged.values())
const strengths = all.filter((f) => f.severity === 'STRENGTH')
const issues = all.filter((f) => f.severity !== 'STRENGTH')
const major = issues.filter((f) => f.severity === 'CRITICAL' || f.severity === 'HIGH')
const minor = issues.filter((f) => f.severity === 'MEDIUM' || f.severity === 'LOW')

log(`${all.length} distinct findings after dedup: ${strengths.length} strengths, ${major.length} CRITICAL/HIGH, ${minor.length} MEDIUM/LOW`)

phase('Verify')
const CAP = 8
const order = { CRITICAL: 0, HIGH: 1 }
const ranked = major.slice().sort((a, b) => (order[a.severity] - order[b.severity]) || (b.lenses.length - a.lenses.length))
const toVerify = ranked.slice(0, CAP)
if (major.length > CAP) {
  log(`Adversarially verifying the top ${CAP} of ${major.length} CRITICAL/HIGH findings; the remaining ${major.length - CAP} are reported UNVERIFIED and flagged as such`)
} else {
  log(`Adversarially verifying all ${toVerify.length} CRITICAL/HIGH findings with 2 independent lenses each`)
}

const verified = await parallel(toVerify.map((f) => () =>
  parallel(LENSES.map((l) => () =>
    agent(l.build(f), { label: `${l.id}: ${String(f.title).slice(0, 48)}`, phase: 'Verify', schema: VERDICT_SCHEMA })
  )).then((votes) => {
    const v = votes.filter(Boolean)
    const refutedCount = v.filter((x) => x.refuted).length
    return {
      finding: f,
      votes: v,
      refuted: refutedCount,
      survives: v.length > 0 && refutedCount === 0,
      contested: refutedCount > 0 && refutedCount < v.length,
    }
  })
))

const confirmed = verified.filter(Boolean).filter((v) => v.survives).map((v) => v.finding)
const contested = verified.filter(Boolean).filter((v) => v.contested)
const killed = verified.filter(Boolean).filter((v) => !v.survives && !v.contested)
const unverified = ranked.slice(CAP)
log(`Verification: ${confirmed.length} confirmed, ${contested.length} contested, ${killed.length} refuted, ${unverified.length} unverified`)

const findingsDigest = JSON.stringify({
  perLensScores: assessments.map((a) => ({ lens: a.id, score: a.score, rationale: a.scoreRationale, summary: a.summary })),
  confirmedMajor: confirmed.map((f) => ({ title: f.title, severity: f.severity, location: f.location, impact: f.impact, alreadyDisclosed: f.alreadyDisclosed, effortToFix: f.effortToFix, blocksShipping: f.blocksShipping })),
  contestedMajor: contested.map((c) => ({ title: c.finding.title, severity: c.finding.severity, whyContested: c.votes.map((v) => v.reasoning).join(' | ') })),
  refutedMajor: killed.map((c) => ({ title: c.finding.title, whyRefuted: c.votes.map((v) => v.reasoning).join(' | ') })),
  unverifiedMajor: unverified.map((f) => ({ title: f.title, severity: f.severity, location: f.location })),
  minorFindings: minor.map((f) => ({ title: f.title, severity: f.severity, location: f.location, effortToFix: f.effortToFix, alreadyDisclosed: f.alreadyDisclosed })),
  strengths: strengths.map((f) => ({ title: f.title, location: f.location, impact: f.impact })),
}, null, 1)

phase('Market')
const MARKET_SCHEMA = {
  type: 'object',
  properties: {
    angle: { type: 'string' },
    verdict: { type: 'string', enum: ['mac-app-store-viable', 'direct-distribution-only', 'both-channels', 'open-source-free-only', 'keep-personal-for-now'] },
    reasoning: { type: 'string', description: 'the argument, in detail, engaging with the audit findings' },
    topBlockers: { type: 'array', items: { type: 'string' }, description: 'the 3-5 things that must change first, most important first' },
    differentiator: { type: 'string', description: 'the honest answer to why anyone would pick this over what already exists, or "none" if there is not one' },
    pricing: { type: 'string' },
    timeToShip: { type: 'string', description: 'realistic calendar estimate for a solo developer working part-time' },
    biggestRisk: { type: 'string' },
  },
  required: ['angle', 'verdict', 'reasoning', 'topBlockers', 'differentiator', 'pricing', 'timeToShip', 'biggestRisk'],
}

const JUDGES = [
  {
    id: 'apple-reviewer',
    prompt: `You are a pragmatic macOS release engineer who has shipped utilities through both the Mac App Store and Developer ID notarization, and who has had apps rejected. Judge ViggoClean purely on: would this actually get approved and shipped, through which channel, and what would break along the way? Weigh the sandbox constraint against what the app's features require. Be concrete about what a sandboxed Mac App Store build of this app would and would not be able to clean, and whether that crippled version is still worth shipping. Use WebSearch to confirm current Apple rules if you need to.`,
  },
  {
    id: 'indie-business',
    prompt: `You are an indie Mac developer who has monetized small utilities. Judge ViggoClean commercially: is there a real market for a developer-focused disk cleaner, given free alternatives (OmniDiskSweeper, GrandPerspective, Pearcleaner, DevCleaner, plain \`rm -rf\` and \`xcrun simctl delete unavailable\`) and paid incumbents (CleanMyMac, DaisyDisk, Sensei)? What is the honest differentiator, if any? What would it cost to support, and what price could it command? Use WebSearch for current competitor pricing and positioning. If your honest answer is that this should stay free or open source, say that plainly.`,
  },
  {
    id: 'skeptical-user',
    prompt: `You are a senior developer with a full 512 GB MacBook — exactly the target user, and a skeptical one. You already know how to run \`rm -rf ~/Library/Developer/Xcode/DerivedData\`. Judge ViggoClean from pure self-interest: would you install it? Would you TRUST it to move your files to Trash? Would you pay for it? What would it have to do that your shell aliases and Finder do not? Engage specifically with the efficacy findings about coverage gaps — if the app cannot currently clean the biggest space consumers on your machine, say what that means for adoption. Be blunt.`,
  },
]

const verdicts = (await parallel(JUDGES.map((j) => () =>
  agent(`${CONTEXT}

========

${j.prompt}

========

Here is the digest of the completed technical audit. Engage with it directly — agree or disagree, but do not ignore it:

${findingsDigest}`, { label: `judge:${j.id}`, phase: 'Market', schema: MARKET_SCHEMA })
))).filter(Boolean)

log(`${verdicts.length}/${JUDGES.length} commercial verdicts returned: ${verdicts.map((v) => v.verdict).join(', ')}`)

phase('Critique')
const critique = await agent(`${CONTEXT}

========

You are the completeness critic for an audit of ViggoClean that has just finished. Your job is to find what the audit MISSED, and to catch any place where it is wrong.

Here is everything the audit produced:

${findingsDigest}

COMMERCIAL VERDICTS: ${JSON.stringify(verdicts.map((v) => ({ angle: v.angle, verdict: v.verdict, blockers: v.topBlockers, differentiator: v.differentiator })), null, 1)}

Go back to the repository and check specifically:
1. Is there a significant file, module or behaviour that no lens examined? List what was never read.
2. Is there a claim in the findings that is actually wrong? Verify the two or three most consequential ones yourself against the code.
3. Is the overall severity calibration right, or did the audit inflate or deflate? Compare against what you would expect from a 2,523-line personal project at v0.2.
4. Is there an important QUESTION THE AUTHOR ASKED that the audit does not yet answer well? They asked two things: how good is this app, and could it go in a store.
5. What is the single most important thing the author should do next, that the audit has not clearly surfaced?

Return plain prose, organized under those five headings. Be specific and cite files. If the audit is solid and you find little to add, say that honestly rather than inventing gaps.`, { label: 'completeness-critic', phase: 'Critique' })

phase('Synthesize')
const report = await agent(`${CONTEXT}

========

You are writing the final assessment of ViggoClean for its author. Everything below is the completed audit. Synthesize it into one clear, honest report.

PER-LENS SCORES AND ALL FINDINGS:
${findingsDigest}

COMMERCIAL VERDICTS FROM THREE INDEPENDENT ANGLES:
${JSON.stringify(verdicts, null, 1)}

COMPLETENESS CRITIC:
${critique}

Write a report in Markdown with exactly these sections:

## Verdict
Two or three sentences answering "how good is this app?" directly and honestly, with an overall score out of 10 and the comparison class named explicitly (i.e. good *for what*). Then one sentence answering "can it go in a store?"

## What this project does unusually well
The genuine strengths, with file references. Only real ones — do not pad.

## What is actually wrong
The confirmed problems, ordered by how much they matter, each with file:line, impact, and effort to fix. Mark clearly which are already disclosed by the author as known limitations versus which are undisclosed. Note any finding that was contested or could not be verified, and say so rather than presenting it as settled.

## The efficacy problem
Direct answer to whether this app currently solves the author's own stated problem — a full 512 GB dev Mac — and how much space it would really free today versus what it misses.

## App Store reality
The concrete answer on distribution channel, with the sandbox constraint explained plainly, the precedent apps named, and what a Mac App Store build would have to give up. State a single recommended channel.

## If you want to ship this
Two separate, concrete checklists: (A) the minimum to give it to friends safely, (B) the additional work to sell it to strangers. Each item with a rough effort estimate. Order by dependency.

## What I would do next
A short, opinionated recommendation — the three highest-leverage things, in order.

RULES FOR THE REPORT:
- Be direct and specific. No hedging, no filler, no praise the evidence does not support.
- Every technical claim gets a file reference.
- Where the three commercial judges disagreed, say so and explain the disagreement rather than averaging it away.
- The author is a capable developer. Do not over-explain basics.
- Do not invent facts not present in the audit above.`, { label: 'final-report', phase: 'Synthesize' })

return {
  scores: assessments.map((a) => ({ lens: a.id, score: a.score })),
  counts: {
    distinctFindings: all.length,
    strengths: strengths.length,
    majorFound: major.length,
    majorConfirmed: confirmed.length,
    majorContested: contested.length,
    majorRefuted: killed.length,
    majorUnverified: unverified.length,
    minor: minor.length,
  },
  verdicts: verdicts.map((v) => ({ angle: v.angle, verdict: v.verdict, timeToShip: v.timeToShip })),
  report,
}
