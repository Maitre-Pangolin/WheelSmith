#!/usr/bin/env bash
# Builds build/WheelSmith.app (release). Signs with a stable identity when one is available.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/WheelSmith.app"

echo "→ swift build ($CONFIGURATION)"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WheelSmith" "$APP/Contents/MacOS/WheelSmith"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Theme fonts (OFL), registered by the app for itself at launch.
mkdir -p "$APP/Contents/Resources/Fonts"
find Support/Fonts -name "*.ttf" -exec cp {} "$APP/Contents/Resources/Fonts/" \;

# Signing identity, in order of preference:
#   1. $SIGN_IDENTITY, if you set it (e.g. an "Apple Development: …" certificate)
#   2. "WheelSmith Local Signing", created once by ./scripts/setup-signing.sh
#   3. ad-hoc ("-"): runs fine, but macOS forgets the Accessibility grant on every rebuild
LOCAL_IDENTITY="WheelSmith Local Signing"
KEYCHAIN_ARGS=()
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN"); fi

SIGN_LABEL=""
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    # Sign by SHA-1 hash: unambiguous even if the name ever appears twice.
    HASH="$(security find-identity -v -p codesigning ${SIGNING_KEYCHAIN:+"$SIGNING_KEYCHAIN"} 2>/dev/null \
        | awk -v name="\"$LOCAL_IDENTITY\"" 'index($0, name) {print $2; exit}')"
    if [[ -n "$HASH" ]]; then
        SIGN_IDENTITY="$HASH"
        SIGN_LABEL="$LOCAL_IDENTITY"
    else
        SIGN_IDENTITY="-"
        if security find-certificate -c "$LOCAL_IDENTITY" ${SIGNING_KEYCHAIN:+"$SIGNING_KEYCHAIN"} >/dev/null 2>&1; then
            echo "  (\"$LOCAL_IDENTITY\" isn't trusted for code signing yet: run ./scripts/setup-signing.sh)"
        else
            echo "  (signing ad-hoc: run ./scripts/setup-signing.sh once so Accessibility survives reinstalls)"
        fi
    fi
fi

codesign --force --sign "$SIGN_IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$APP" >/dev/null
echo "✓ Built $APP (signed: $([[ "$SIGN_IDENTITY" == "-" ]] && echo ad-hoc || echo "${SIGN_LABEL:-$SIGN_IDENTITY}"))"
