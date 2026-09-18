#!/usr/bin/env bash
# Build, sign and optionally notarize SafeCleaner.app.
#
#   ./scripts/build-app.sh              build a universal, signed .app
#   ./scripts/build-app.sh --notarize   also build a DMG, notarize it and staple the ticket
#
# Environment overrides:
#   SAFECLEANER_SIGN_ID         signing identity (default: the first "Developer ID Application")
#   SAFECLEANER_NOTARY_PROFILE  notarytool keychain profile (default: safecleaner-notary)
#   SAFECLEANER_ARCHS           architectures to build (default: "arm64 x86_64")
#
# Ad-hoc signing is the fallback when no Developer ID identity exists. Ad-hoc builds
# are rejected by Gatekeeper on other Macs and their identity changes on every rebuild,
# which silently drops any Full Disk Access grant.
set -euo pipefail

SAFECLEANER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAFECLEANER_APP="$SAFECLEANER_ROOT/build/SafeCleaner.app"
SAFECLEANER_DMG="$SAFECLEANER_ROOT/build/SafeCleaner.dmg"
SAFECLEANER_NOTARY_PROFILE="${SAFECLEANER_NOTARY_PROFILE:-safecleaner-notary}"
read -r -a SAFECLEANER_ARCH_LIST <<< "${SAFECLEANER_ARCHS:-arm64 x86_64}"
SAFECLEANER_NOTARIZE=0
[ "${1:-}" = "--notarize" ] && SAFECLEANER_NOTARIZE=1

SAFECLEANER_ARCH_FLAGS=()
for arch in "${SAFECLEANER_ARCH_LIST[@]}"; do SAFECLEANER_ARCH_FLAGS+=(--arch "$arch"); done

# ---------------------------------------------------------------- build
swift build --package-path "$SAFECLEANER_ROOT" --scratch-path "$SAFECLEANER_ROOT/.build" \
    -c release "${SAFECLEANER_ARCH_FLAGS[@]}"
SAFECLEANER_BIN="$(swift build --package-path "$SAFECLEANER_ROOT" --scratch-path "$SAFECLEANER_ROOT/.build" \
    -c release "${SAFECLEANER_ARCH_FLAGS[@]}" --show-bin-path)"

# ------------------------------------------------------------- assemble
rm -rf "$SAFECLEANER_APP"
mkdir -p "$SAFECLEANER_APP/Contents/MacOS" "$SAFECLEANER_APP/Contents/Resources"
cp "$SAFECLEANER_BIN/SafeCleaner" "$SAFECLEANER_APP/Contents/MacOS/SafeCleaner"
cp "$SAFECLEANER_ROOT/Info.plist" "$SAFECLEANER_APP/Contents/Info.plist"
cp "$SAFECLEANER_ROOT/PrivacyInfo.xcprivacy" "$SAFECLEANER_APP/Contents/Resources/PrivacyInfo.xcprivacy"

# Compile the asset catalog: App Store Connect rejects a bundle whose icon is only a
# loose .icns, and CFBundleIconName has no meaning without a compiled Assets.car.
xcrun actool "$SAFECLEANER_ROOT/Assets.xcassets" \
    --compile "$SAFECLEANER_APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$SAFECLEANER_ROOT/.build/actool-partial.plist" \
    --output-format human-readable-text >/dev/null

# ----------------------------------------------------------------- sign
if [ -n "${SAFECLEANER_SIGN_ID:-}" ]; then
    SAFECLEANER_IDENTITY="$SAFECLEANER_SIGN_ID"
else
    SAFECLEANER_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi

if [ -n "$SAFECLEANER_IDENTITY" ]; then
    codesign --force --sign "$SAFECLEANER_IDENTITY" --options runtime --timestamp \
        "$SAFECLEANER_APP"
    printf 'Signed with %s\n' "$SAFECLEANER_IDENTITY"
else
    codesign --force --sign - --options runtime "$SAFECLEANER_APP"
    printf 'WARNING: no Developer ID Application identity found; signed ad-hoc.\n' >&2
    printf '         This build will not open on another Mac.\n' >&2
    printf '         Create one at https://developer.apple.com/account/resources/certificates\n' >&2
fi

codesign --verify --strict --deep "$SAFECLEANER_APP"
printf 'Built %s (%s)\n' "$SAFECLEANER_APP" "$(lipo -archs "$SAFECLEANER_APP/Contents/MacOS/SafeCleaner")"

# ------------------------------------------------------------ notarize
if [ "$SAFECLEANER_NOTARIZE" -eq 1 ]; then
    if [ -z "$SAFECLEANER_IDENTITY" ]; then
        printf 'Cannot notarize an ad-hoc build. Create a Developer ID Application certificate first.\n' >&2
        exit 1
    fi
    rm -f "$SAFECLEANER_DMG"
    hdiutil create -volname SafeCleaner -srcfolder "$SAFECLEANER_APP" \
        -ov -format UDZO -quiet "$SAFECLEANER_DMG"
    # Sign the image itself as well as the app: an unsigned disk image is stapled
    # but still reports "no usable signature" to Gatekeeper's own assessment.
    codesign --force --sign "$SAFECLEANER_IDENTITY" --timestamp "$SAFECLEANER_DMG"
    # Notarize and staple the DMG: that is what the user actually downloads.
    if ! xcrun notarytool submit "$SAFECLEANER_DMG" \
            --keychain-profile "$SAFECLEANER_NOTARY_PROFILE" --wait; then
        printf '\nnotarytool failed. If the profile does not exist yet, create it once with:\n' >&2
        printf '  xcrun notarytool store-credentials %s \\\n' "$SAFECLEANER_NOTARY_PROFILE" >&2
        printf '      --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>\n' >&2
        exit 1
    fi
    xcrun stapler staple "$SAFECLEANER_DMG"
    xcrun stapler validate "$SAFECLEANER_DMG"
    printf 'Notarized and stapled %s\n' "$SAFECLEANER_DMG"
fi

# --------------------------------------------------------- gatekeeper
printf 'Gatekeeper: '
spctl --assess --verbose=2 --type exec "$SAFECLEANER_APP" 2>&1 | tail -2 || true
