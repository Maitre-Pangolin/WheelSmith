#!/usr/bin/env bash
# One-time setup: creates a self-signed code-signing certificate "TheOneRing Local Signing" in your
# login keychain and trusts it for code signing. build.sh / install.sh pick it up automatically.
#
# Why: with ad-hoc signing every build looks like a brand-new app to macOS, so the Accessibility
# permission is lost on each reinstall. Signed with one fixed certificate, macOS recognises every
# build as the same app and the permission sticks.
#
# The certificate is only used to sign this app on this Mac and is trusted for code signing only.
# To remove it: Keychain Access → login → My Certificates → delete "TheOneRing Local Signing".
set -euo pipefail

NAME="TheOneRing Local Signing"
KEYCHAIN="${SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

is_valid() {
    security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""
}

if is_valid; then
    echo "✓ \"$NAME\" is already set up, nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
cleanup() { rm -f "$WORK"/*.pem "$WORK"/*.p12 "$WORK"/*.cnf; rmdir "$WORK"; }
trap cleanup EXIT

if ! security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
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

    # macOS's own LibreSSL writes a PKCS#12 that `security import` understands
    # (Homebrew's OpenSSL 3 would need -legacy).
    OPENSSL=/usr/bin/openssl
    P12_PASS="theonering-$$-$RANDOM"
    echo "→ Generating certificate (valid 10 years)"
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
    "$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
        -out "$WORK/identity.p12" -passout "pass:$P12_PASS"

    echo "→ Importing into $(basename "$KEYCHAIN")"
    # -T lets codesign use the key without asking every time.
    security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
fi

# codesign refuses untrusted certificates, so trust this one, for code signing only.
echo "→ Trusting it for code signing. macOS will ask for your password."
security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$WORK/trust.pem"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/trust.pem"

if ! is_valid; then
    echo "✗ The certificate exists but macOS doesn't accept it for code signing yet." >&2
    echo "  Run this script again, or open Keychain Access and set it to Always Trust for Code Signing." >&2
    exit 1
fi

echo "✓ \"$NAME\" is ready."
echo "  The first build may ask to let codesign use this key: click \"Always Allow\"."
echo "  Then run ./scripts/install.sh and grant Accessibility one last time; it sticks from then on."
