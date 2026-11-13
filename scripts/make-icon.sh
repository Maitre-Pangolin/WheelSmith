#!/usr/bin/env bash
# Regenerates Support/AppIcon.icns from the shape in Sources/WheelSmith/LogoMark.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swiftc -O -parse-as-library scripts/make-icon.swift Sources/WheelSmith/LogoMark.swift -o "$WORK/make-icon"
"$WORK/make-icon" "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o Support/AppIcon.icns
echo "✓ Wrote Support/AppIcon.icns"
