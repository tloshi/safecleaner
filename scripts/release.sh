#!/usr/bin/env bash
# Cut a release: bump the version, verify, notarize, staple and tag.
#
#   ./scripts/release.sh 0.3.0            full release
#   ./scripts/release.sh 0.3.0 --dry-run  bump and verify, but do not notarize or tag
#
# The marketing version is the argument. The build number is derived by counting
# existing tags, so it always increases and is never reused.
set -euo pipefail

SAFECLEANER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SAFECLEANER_ROOT"

SAFECLEANER_VERSION="${1:-}"
SAFECLEANER_DRY=0
[ "${2:-}" = "--dry-run" ] && SAFECLEANER_DRY=1

if ! printf '%s' "$SAFECLEANER_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf 'Usage: %s <major.minor.patch> [--dry-run]\n' "$0" >&2
    exit 1
fi
if git rev-parse "v$SAFECLEANER_VERSION" >/dev/null 2>&1; then
    printf 'Tag v%s already exists.\n' "$SAFECLEANER_VERSION" >&2
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
    printf 'Working tree is dirty. Commit or stash first:\n' >&2
    git status --short >&2
    exit 1
fi

# Build number: strictly increasing, never reused, independent of the marketing version.
SAFECLEANER_BUILD=$(( $(git tag --list 'v*' | wc -l | tr -d ' ') + 4 ))

printf '==> Releasing %s (build %s)\n' "$SAFECLEANER_VERSION" "$SAFECLEANER_BUILD"

# ------------------------------------------------------------------ bump
python3 - "$SAFECLEANER_VERSION" "$SAFECLEANER_BUILD" <<'PY'
import re, sys, pathlib
version, build = sys.argv[1], sys.argv[2]
p = pathlib.Path("scripts/generate-project.py")
s = p.read_text()
new = re.sub(r'CFBundleShortVersionString="[^"]*", CFBundleVersion="[^"]*"',
             f'CFBundleShortVersionString="{version}", CFBundleVersion="{build}"', s, count=1)
if new == s:
    raise SystemExit("could not find the version line in scripts/generate-project.py")
p.write_text(new)
print(f"    version -> {version}, build -> {build}")
PY
python3 scripts/generate-project.py >/dev/null
printf '    Info.plist regenerated\n'

# ---------------------------------------------------------------- verify
printf '==> Verifying\n'
swift test >/dev/null
printf '    tests passed\n'
python3 scripts/check-boundaries.py >/dev/null
printf '    architecture boundaries passed\n'

if [ "$SAFECLEANER_DRY" -eq 1 ]; then
    printf '==> Dry run: stopping before notarization. Version bump is uncommitted.\n'
    exit 0
fi

# ------------------------------------------------- remind, then package
if ! grep -q "^## $SAFECLEANER_VERSION" docs/VALIDATION.md; then
    printf 'docs/VALIDATION.md has no "## %s" section.\n' "$SAFECLEANER_VERSION" >&2
    printf 'Record what was and was not tested before releasing.\n' >&2
    exit 1
fi

printf '==> Building and notarizing (this waits on Apple; 2-15 minutes)\n'
./scripts/build-app.sh --notarize

# ------------------------------------------------------------ commit+tag
git add -A
git commit -q -m "chore: release $SAFECLEANER_VERSION"
git tag -a "v$SAFECLEANER_VERSION" -m "SafeCleaner $SAFECLEANER_VERSION"
printf '==> Tagged v%s\n' "$SAFECLEANER_VERSION"
printf '    Ship build/SafeCleaner.dmg\n'
