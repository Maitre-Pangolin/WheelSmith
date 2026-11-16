#!/usr/bin/env bash
# Builds a universal WheelSmith.app and zips it for a GitHub release: dist/WheelSmith-<version>.zip
# plus its .sha256 (what a Homebrew cask needs).
#
#   VERSION=1.2.3 ./scripts/package.sh     (default: the version in Support/Info.plist)
#
# Signing follows build.sh (SIGN_IDENTITY / SIGNING_KEYCHAIN). The result is NOT notarized: people who
# download it confirm it once in System Settings → Privacy & Security → Open Anyway.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)}"
export VERSION
UNIVERSAL=1 ./scripts/build.sh

ZIP="dist/WheelSmith-$VERSION.zip"
mkdir -p dist
rm -f "$ZIP" "$ZIP.sha256"
# ditto keeps the bundle's signature, symlinks and extended attributes intact (zip -r doesn't).
ditto -c -k --keepParent build/WheelSmith.app "$ZIP"
(cd dist && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")

codesign --verify --strict build/WheelSmith.app
echo "✓ $ZIP"
cat "$ZIP.sha256"
