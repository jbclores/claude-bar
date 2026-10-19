#!/bin/bash
# Makes a self-signed code-signing certificate called "ClaudeBar Local" in your login keychain, once.
# With it, scripts/build.sh signs ClaudeBar the same way every time, so macOS keeps the microphone and
# speech-recognition permissions across updates. You run this yourself; nothing else does.
set -euo pipefail

NAME="ClaudeBar Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "\"$NAME\" already exists in your keychain, so nothing was changed."
  echo "To start over, delete it in Keychain Access first."
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="claudebar-$$-$RANDOM"

# Stops with openssl's own reason when a step fails.
fail() {
  echo "Couldn't make the certificate: $(tr '\n' ' ' < "$TMP/err")" >&2
  exit 1
}

echo "Making a certificate valid for 10 years..."
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature" 2>"$TMP/err" || fail

LEGACY=()
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then LEGACY=(-legacy); fi
openssl pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/cert.p12" -passout "pass:$PASS" 2>"$TMP/err" || fail

echo "Adding it to your login keychain (only codesign may use it)..."
security import "$TMP/cert.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -P "$PASS"

echo
echo "Done: \"$NAME\" is now in your login keychain. The temporary files are gone."
echo "Next: Run scripts/run.sh --install; macOS will ask for the microphone once more, then remember it."
echo "When ClaudeBar is signed, macOS may ask once for your login password so codesign can use the certificate:"
echo "type it and choose \"Always Allow\"."
