#!/usr/bin/env bash
# Build, sign and optionally notarize SafeCleaner.app.
#
#   ./scripts/build-app.sh              build a universal, signed .app
#   ./scripts/build-app.sh --notarize   notarize the .app, then build, notarize and staple a DMG
#
# --notarize submits twice on purpose. The app is notarized and stapled FIRST, so the
# copy a user drags to /Applications carries its own ticket and launches offline; then
# the DMG is built from that stapled app and notarized in turn. Stapling rewrites the
# bundle, so it has to happen before hdiutil captures it.
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
SAFECLEANER_ZIP="$SAFECLEANER_ROOT/build/SafeCleaner.zip"
SAFECLEANER_STAGE="$SAFECLEANER_ROOT/build/dmg-stage"
SAFECLEANER_NOTARY_PROFILE="${SAFECLEANER_NOTARY_PROFILE:-safecleaner-notary}"
read -r -a SAFECLEANER_ARCH_LIST <<< "${SAFECLEANER_ARCHS:-arm64 x86_64}"
SAFECLEANER_NOTARIZE=0
[ "${1:-}" = "--notarize" ] && SAFECLEANER_NOTARIZE=1

SAFECLEANER_ARCH_FLAGS=()
for arch in "${SAFECLEANER_ARCH_LIST[@]}"; do SAFECLEANER_ARCH_FLAGS+=(--arch "$arch"); done

# Submit one artifact and wait for Apple's verdict. Called once for the app and once
# for the DMG, so the store-credentials hint lives in a single place.
safecleaner_notarize() {
    if xcrun notarytool submit "$1" \
            --keychain-profile "$SAFECLEANER_NOTARY_PROFILE" --wait; then
        return 0
    fi
    printf '\nnotarytool failed. If the profile does not exist yet, create it once with:\n' >&2
    printf '  xcrun notarytool store-credentials %s \\\n' "$SAFECLEANER_NOTARY_PROFILE" >&2
    printf '      --apple-id <your-apple-id> --team-id <TEAMID> --password <app-specific-password>\n' >&2
    exit 1
}

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
    # Pass 1: notarize the app itself and staple the ticket into the bundle. Without
    # this the app copied out of the DMG has no local ticket, so its first launch
    # needs a round trip to Apple and shows a warning to anyone who is offline.
    rm -f "$SAFECLEANER_ZIP"
    # ditto, not zip: it preserves the symlinks and extended attributes in a bundle.
    ditto -c -k --keepParent "$SAFECLEANER_APP" "$SAFECLEANER_ZIP"
    safecleaner_notarize "$SAFECLEANER_ZIP"
    rm -f "$SAFECLEANER_ZIP"
    xcrun stapler staple "$SAFECLEANER_APP"
    xcrun stapler validate "$SAFECLEANER_APP"
    printf 'Notarized and stapled %s\n' "$SAFECLEANER_APP"

    # Pass 2: build the DMG from the now-stapled app. Staging a folder rather than
    # pointing -srcfolder at the bundle is what gives the image the /Applications
    # alias, so the mounted window offers the expected drag-to-install.
    rm -rf "$SAFECLEANER_STAGE"
    mkdir -p "$SAFECLEANER_STAGE"
    cp -R "$SAFECLEANER_APP" "$SAFECLEANER_STAGE/"
    ln -s /Applications "$SAFECLEANER_STAGE/Applications"
    rm -f "$SAFECLEANER_DMG"
    hdiutil create -volname SafeCleaner -srcfolder "$SAFECLEANER_STAGE" \
        -ov -format UDZO -quiet "$SAFECLEANER_DMG"
    rm -rf "$SAFECLEANER_STAGE"
    # Sign the image itself as well as the app: an unsigned disk image is stapled
    # but still reports "no usable signature" to Gatekeeper's own assessment.
    codesign --force --sign "$SAFECLEANER_IDENTITY" --timestamp "$SAFECLEANER_DMG"
    # Notarize and staple the DMG too: that is what the user actually downloads.
    safecleaner_notarize "$SAFECLEANER_DMG"
    xcrun stapler staple "$SAFECLEANER_DMG"
    xcrun stapler validate "$SAFECLEANER_DMG"
    printf 'Notarized and stapled %s\n' "$SAFECLEANER_DMG"
fi

# --------------------------------------------------------- gatekeeper
printf 'Gatekeeper: '
spctl --assess --verbose=2 --type exec "$SAFECLEANER_APP" 2>&1 | tail -2 || true
