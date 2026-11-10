#!/usr/bin/env bash
# Builds build/TheOneRing.app (release, signed ad-hoc unless SIGN_IDENTITY is set).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/TheOneRing.app"

echo "→ swift build ($CONFIGURATION)"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TheOneRing" "$APP/Contents/MacOS/TheOneRing"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signing ("-") is enough to run locally. If you have a Developer ID / Apple Development
# certificate, set SIGN_IDENTITY so macOS keeps the Accessibility grant across rebuilds.
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP" >/dev/null
echo "✓ Built $APP"
