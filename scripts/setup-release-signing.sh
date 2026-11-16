#!/usr/bin/env bash
# One-time setup for GitHub releases: creates a self-signed code-signing certificate,
# "WheelSmith Release Signing", and stores it as GitHub Actions secrets so every release is signed
# with the same identity. That's what lets macOS keep a user's Accessibility grant across updates.
#
# It isn't an Apple Developer ID: releases still aren't notarized, and macOS still asks people to
# confirm the app once. Nothing is added to your keychain.
#
#   ./scripts/setup-release-signing.sh [backup-dir]
#
# Writes a backup (the .p12 and its password) to backup-dir, by default
# ~/Documents/WheelSmith Release Signing. Keep it: if it's lost, a new certificate means every user
# re-grants Accessibility once after the next update.
#
# Needs the GitHub CLI, logged in with access to this repo (`gh auth status`).
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="WheelSmith Release Signing"
BACKUP="${1:-$HOME/Documents/WheelSmith Release Signing}"

if gh secret list --json name -q '.[].name' | grep -qx SIGNING_P12_BASE64; then
    echo "✗ The repo already has SIGNING_P12_BASE64. Replacing it changes the signing identity," >&2
    echo "  so users would re-grant Accessibility. Delete it first if that's really what you want:" >&2
    echo "  gh secret delete SIGNING_P12_BASE64" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# macOS's own LibreSSL writes a PKCS#12 that `security import` understands.
OPENSSL=/usr/bin/openssl
P12_PASS="$("$OPENSSL" rand -hex 24)"
echo "→ Generating \"$NAME\" (valid 20 years)"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/identity.p12" -passout "pass:$P12_PASS"

echo "→ Saving a backup to $BACKUP"
mkdir -p "$BACKUP"
chmod 700 "$BACKUP"
cp "$WORK/identity.p12" "$BACKUP/wheelsmith-release-signing.p12"
printf '%s\n' "$P12_PASS" > "$BACKUP/password.txt"
chmod 600 "$BACKUP"/*

echo "→ Storing GitHub Actions secrets SIGNING_P12_BASE64 and SIGNING_P12_PASSWORD"
base64 -i "$WORK/identity.p12" | gh secret set SIGNING_P12_BASE64
printf '%s' "$P12_PASS" | gh secret set SIGNING_P12_PASSWORD

echo "✓ Releases will be signed with \"$NAME\"."
