#!/usr/bin/env bash
# Builds build/WheelSmith.app (release). Signs with a stable identity when one is available.
#
#   UNIVERSAL=1   build for Apple Silicon and Intel, merged with lipo (default: this Mac's arch only)
#   VERSION=1.2.3 stamp CFBundleShortVersionString (default: the one in Support/Info.plist)
#   BUILD_NUMBER  stamp CFBundleVersion (default: the number of commits, when VERSION is set)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/WheelSmith.app"
MIN_MACOS="14.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    SLICES=()
    for ARCH in arm64 x86_64; do
        TRIPLE="$ARCH-apple-macosx$MIN_MACOS"
        echo "→ swift build ($CONFIGURATION, $ARCH)"
        swift build -c "$CONFIGURATION" --triple "$TRIPLE"
        SLICES+=("$(swift build -c "$CONFIGURATION" --triple "$TRIPLE" --show-bin-path)/WheelSmith")
    done
    lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/WheelSmith"
else
    echo "→ swift build ($CONFIGURATION)"
    swift build -c "$CONFIGURATION"
    cp "$(swift build -c "$CONFIGURATION" --show-bin-path)/WheelSmith" "$APP/Contents/MacOS/WheelSmith"
fi

cp Support/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
        -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
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
echo "✓ Built $APP $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist") [$(lipo -archs "$APP/Contents/MacOS/WheelSmith")] (signed: $([[ "$SIGN_IDENTITY" == "-" ]] && echo ad-hoc || echo "${SIGN_LABEL:-$SIGN_IDENTITY}"))"
