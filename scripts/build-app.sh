#!/usr/bin/env bash
# Build, sign and optionally notarize ViggoClean.app.
#
#   ./scripts/build-app.sh              build a universal, signed .app
#   ./scripts/build-app.sh --notarize   also build a DMG, notarize it and staple the ticket
#
# Environment overrides:
#   VIGGO_SIGN_ID         signing identity (default: the first "Developer ID Application")
#   VIGGO_NOTARY_PROFILE  notarytool keychain profile (default: viggoclean-notary)
#   VIGGO_ARCHS           architectures to build (default: "arm64 x86_64")
#
# Ad-hoc signing is the fallback when no Developer ID identity exists. Ad-hoc builds
# are rejected by Gatekeeper on other Macs and their identity changes on every rebuild,
# which silently drops any Full Disk Access grant.
set -euo pipefail

VIGGO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIGGO_APP="$VIGGO_ROOT/build/ViggoClean.app"
VIGGO_DMG="$VIGGO_ROOT/build/ViggoClean.dmg"
VIGGO_NOTARY_PROFILE="${VIGGO_NOTARY_PROFILE:-viggoclean-notary}"
read -r -a VIGGO_ARCH_LIST <<< "${VIGGO_ARCHS:-arm64 x86_64}"
VIGGO_NOTARIZE=0
[ "${1:-}" = "--notarize" ] && VIGGO_NOTARIZE=1

VIGGO_ARCH_FLAGS=()
for arch in "${VIGGO_ARCH_LIST[@]}"; do VIGGO_ARCH_FLAGS+=(--arch "$arch"); done

# ---------------------------------------------------------------- build
swift build --package-path "$VIGGO_ROOT" --scratch-path "$VIGGO_ROOT/.build" \
    -c release "${VIGGO_ARCH_FLAGS[@]}"
VIGGO_BIN="$(swift build --package-path "$VIGGO_ROOT" --scratch-path "$VIGGO_ROOT/.build" \
    -c release "${VIGGO_ARCH_FLAGS[@]}" --show-bin-path)"

# ------------------------------------------------------------- assemble
rm -rf "$VIGGO_APP"
mkdir -p "$VIGGO_APP/Contents/MacOS" "$VIGGO_APP/Contents/Resources"
cp "$VIGGO_BIN/ViggoClean" "$VIGGO_APP/Contents/MacOS/ViggoClean"
cp "$VIGGO_ROOT/Info.plist" "$VIGGO_APP/Contents/Info.plist"
cp "$VIGGO_ROOT/PrivacyInfo.xcprivacy" "$VIGGO_APP/Contents/Resources/PrivacyInfo.xcprivacy"

# Compile the asset catalog: App Store Connect rejects a bundle whose icon is only a
# loose .icns, and CFBundleIconName has no meaning without a compiled Assets.car.
xcrun actool "$VIGGO_ROOT/Assets.xcassets" \
    --compile "$VIGGO_APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$VIGGO_ROOT/.build/actool-partial.plist" \
    --output-format human-readable-text >/dev/null

# ----------------------------------------------------------------- sign
if [ -n "${VIGGO_SIGN_ID:-}" ]; then
    VIGGO_IDENTITY="$VIGGO_SIGN_ID"
else
    VIGGO_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi

if [ -n "$VIGGO_IDENTITY" ]; then
    codesign --force --sign "$VIGGO_IDENTITY" --options runtime --timestamp \
        "$VIGGO_APP"
    printf 'Signed with %s\n' "$VIGGO_IDENTITY"
else
    codesign --force --sign - --options runtime "$VIGGO_APP"
    printf 'WARNING: no Developer ID Application identity found; signed ad-hoc.\n' >&2
    printf '         This build will not open on another Mac.\n' >&2
    printf '         Create one at https://developer.apple.com/account/resources/certificates\n' >&2
fi

codesign --verify --strict --deep "$VIGGO_APP"
printf 'Built %s (%s)\n' "$VIGGO_APP" "$(lipo -archs "$VIGGO_APP/Contents/MacOS/ViggoClean")"

# ------------------------------------------------------------ notarize
if [ "$VIGGO_NOTARIZE" -eq 1 ]; then
    if [ -z "$VIGGO_IDENTITY" ]; then
        printf 'Cannot notarize an ad-hoc build. Create a Developer ID Application certificate first.\n' >&2
        exit 1
    fi
    rm -f "$VIGGO_DMG"
    hdiutil create -volname ViggoClean -srcfolder "$VIGGO_APP" \
        -ov -format UDZO -quiet "$VIGGO_DMG"
    # Notarize and staple the DMG: that is what the user actually downloads.
    if ! xcrun notarytool submit "$VIGGO_DMG" \
            --keychain-profile "$VIGGO_NOTARY_PROFILE" --wait; then
        printf '\nnotarytool failed. If the profile does not exist yet, create it once with:\n' >&2
        printf '  xcrun notarytool store-credentials %s \\\n' "$VIGGO_NOTARY_PROFILE" >&2
        printf '      --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>\n' >&2
        exit 1
    fi
    xcrun stapler staple "$VIGGO_DMG"
    xcrun stapler validate "$VIGGO_DMG"
    printf 'Notarized and stapled %s\n' "$VIGGO_DMG"
fi

# --------------------------------------------------------- gatekeeper
printf 'Gatekeeper: '
spctl --assess --verbose=2 --type exec "$VIGGO_APP" 2>&1 | tail -2 || true
