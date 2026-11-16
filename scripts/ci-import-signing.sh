#!/usr/bin/env bash
# CI only: imports the release certificate from $SIGNING_P12_BASE64 / $SIGNING_P12_PASSWORD into a
# throwaway keychain, trusts it for code signing, and exports SIGN_IDENTITY + SIGNING_KEYCHAIN for
# build.sh via $GITHUB_ENV. Without those secrets it does nothing and the build is signed ad-hoc.
set -euo pipefail

if [[ -z "${SIGNING_P12_BASE64:-}" ]]; then
    echo "::warning::No SIGNING_P12_BASE64 secret: signing ad-hoc. Users will lose the Accessibility grant on every update. Run ./scripts/setup-release-signing.sh once."
    exit 0
fi

WORK="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$WORK/release-signing.keychain-db"
KEYCHAIN_PASS="$(openssl rand -hex 16)"

echo "$SIGNING_P12_BASE64" | base64 --decode > "$WORK/identity.p12"
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$SIGNING_P12_PASSWORD" -T /usr/bin/codesign
# Let codesign use the key without a UI prompt.
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
# Add it to the search list so codesign finds the certificate.
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
rm -f "$WORK/identity.p12"

# codesign refuses an untrusted self-signed certificate. The runner has passwordless sudo.
security find-certificate -c "WheelSmith Release Signing" -p "$KEYCHAIN" > "$WORK/release.pem"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$WORK/release.pem"

HASH="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/"WheelSmith Release Signing"/ {print $2; exit}')"
if [[ -z "$HASH" ]]; then
    echo "::error::Imported the certificate but it isn't valid for code signing." >&2
    exit 1
fi
echo "SIGN_IDENTITY=$HASH" >> "$GITHUB_ENV"
echo "SIGNING_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
echo "✓ Signing with WheelSmith Release Signing ($HASH)"
