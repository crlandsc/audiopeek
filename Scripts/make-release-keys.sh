#!/bin/bash
# Creates the two keys an AudioPeek release is signed with. Run it once, by hand.
#
#   1. "AudioPeek Release Signing": a self-signed code-signing certificate (RSA 2048,
#      valid 25 years) in the login keychain. Every release is signed with it, so macOS
#      sees each new version as the same app and keeps its Finder permission.
#   2. The update key: an EdDSA key Sparkle keeps in the login keychain (account
#      "audiopeek"). Every update is signed with it, and the app checks that signature.
#
# Running it again creates nothing new: it finds both keys and prints them again.
# The private keys stay in the keychain. Back them up as the script explains, and never
# put them in the repo.
#
#   Scripts/make-release-keys.sh
#   Scripts/make-release-keys.sh --keychain <path> --certificate-only   (testing only)

set -Eeuo pipefail

CERT_NAME="AudioPeek Release Signing"
SPARKLE_ACCOUNT="audiopeek"
VALID_DAYS=9132 # 25 years

die() {
    echo "make-release-keys: $*" >&2
    exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
CERTIFICATE_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --keychain) KEYCHAIN="${2:?--keychain needs a path}"; shift 2 ;;
        --certificate-only) CERTIFICATE_ONLY=1; shift ;;
        *) die "Unknown option '$1'." ;;
    esac
done
[ -f "$KEYCHAIN" ] || die "No keychain at $KEYCHAIN."

# SHA-1 hashes of every certificate with this exact name in the keychain, one per line.
certificate_hashes() {
    security find-certificate -a -c "$CERT_NAME" -Z "$KEYCHAIN" 2>/dev/null |
        awk '/^SHA-1 hash:/ { hash = $3 } /"alis"<blob>="/ { if (index($0, "=\"'"$CERT_NAME"'\"")) print hash }'
}

echo "== Certificate: $CERT_NAME"
hashes="$(certificate_hashes)"
if [ -n "$hashes" ]; then
    echo "Already in the keychain; nothing created."
else
    umask 077
    TEMP="$(mktemp -d)"
    trap 'rm -rf "$TEMP"' EXIT
    cat > "$TEMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CERT_NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF
    # macOS's own LibreSSL, so the result doesn't depend on which openssl is first in PATH.
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days "$VALID_DAYS" \
        -config "$TEMP/cert.cnf" -keyout "$TEMP/key.pem" -out "$TEMP/cert.pem" 2>/dev/null ||
        die "openssl couldn't create the certificate."
    PASSWORD="$(uuidgen)"
    /usr/bin/openssl pkcs12 -export -inkey "$TEMP/key.pem" -in "$TEMP/cert.pem" \
        -name "$CERT_NAME" -out "$TEMP/identity.p12" -passout "pass:$PASSWORD" ||
        die "openssl couldn't package the certificate."
    security import "$TEMP/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign > /dev/null ||
        die "Couldn't add the certificate to $KEYCHAIN."
    rm -rf "$TEMP"
    echo "Created and added to the keychain."
    hashes="$(certificate_hashes)"
fi
[ "$(printf '%s\n' "$hashes" | grep -c .)" = "1" ] ||
    die "Expected one '$CERT_NAME' certificate in the keychain, found: $(printf '%s ' $hashes). Remove the extra copies in Keychain Access."
CERT_HASH="$hashes"
security find-certificate -c "$CERT_NAME" -p "$KEYCHAIN" | /usr/bin/openssl x509 -noout -enddate | sed 's/^notAfter=/Valid until: /'

if [ "$CERTIFICATE_ONLY" = "1" ]; then
    echo ""
    echo "Certificate SHA-1: $CERT_HASH"
    exit 0
fi

echo ""
echo "== Update key (Sparkle, account '$SPARKLE_ACCOUNT')"
SPARKLE="$("$ROOT/Scripts/fetch-sparkle.sh")" || die "Couldn't get Sparkle's tools."
GENERATE_KEYS="$SPARKLE/bin/generate_keys"
echo "macOS may ask to let generate_keys use the keychain. Allow it."
if PUBLIC_KEY="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null)" && [ -n "$PUBLIC_KEY" ]; then
    echo "Already in the keychain; nothing created."
else
    "$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" > /dev/null || die "generate_keys couldn't create the update key."
    PUBLIC_KEY="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p)" || die "generate_keys couldn't read the new key back."
    echo "Created and added to the keychain."
fi
[ "$(printf '%s' "$PUBLIC_KEY" | base64 -D 2>/dev/null | wc -c | tr -d ' ')" = "32" ] ||
    die "The update public key '$PUBLIC_KEY' isn't a 32-byte EdDSA key."

cat <<EOF

== Back up both private keys now (once)
Losing either key is recoverable; losing both means everyone downloads AudioPeek by hand again.

1. Certificate: open Keychain Access, choose the login keychain and My Certificates,
   right-click "$CERT_NAME", choose Export, save as a .p12 with a strong password.
   Store the .p12 and its password in your password manager, then delete the file.
2. Update key: run these three lines (a private folder, never the Desktop, which iCloud may sync):
     folder="\$(mktemp -d)" && "$GENERATE_KEYS" --account $SPARKLE_ACCOUNT -x "\$folder/update-key.txt"
     cat "\$folder/update-key.txt"
     rm -rf "\$folder"
   Store what cat prints in your password manager.

== Give the agent these two public values (nothing else)
Certificate SHA-1: $CERT_HASH
Update public key: $PUBLIC_KEY
EOF
