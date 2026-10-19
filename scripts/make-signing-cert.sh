#!/bin/bash
# Makes a self-signed code-signing certificate called "ClaudeBar Local", once, in a keychain of its own
# (~/Library/Keychains/claudebar-signing.keychain-db), never in your login keychain. Its password is made up here and
# kept beside it, so scripts/build.sh can unlock it without asking you anything. With it, build.sh signs ClaudeBar the
# same way every time, so macOS keeps the microphone and speech-recognition permissions across updates.
# You run this yourself; nothing else does.
set -euo pipefail

NAME="ClaudeBar Local"
KEYCHAIN="${CLAUDEBAR_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/claudebar-signing.keychain-db}"
PASSFILE="${CLAUDEBAR_SIGNING_PASSFILE:-$HOME/Library/Application Support/ClaudeBar/signing-keychain.pass}"

if [ -e "$KEYCHAIN" ]; then
  echo "ClaudeBar's signing keychain already exists ($KEYCHAIN), so nothing was changed."
  echo "To start over: security delete-keychain \"$KEYCHAIN\"; rm \"$PASSFILE\""
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P12PASS="$(openssl rand -hex 16)"
KEYCHAINPASS="$(openssl rand -hex 24)"

# Stops with the tool's own reason when a step fails.
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
  -name "$NAME" -out "$TMP/cert.p12" -passout "pass:$P12PASS" 2>"$TMP/err" || fail

echo "Making ClaudeBar's own keychain..."
mkdir -p "$(dirname "$PASSFILE")"
(umask 077; printf '%s' "$KEYCHAINPASS" > "$PASSFILE")
# create-keychain adds the new keychain to your keychain search list; put the list back exactly as it was.
SEARCH=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"; line="${line#\"}"; line="${line%\"}"
  [ -n "$line" ] && SEARCH+=("$line")
done < <(security list-keychains -d user)
security create-keychain -p "$KEYCHAINPASS" "$KEYCHAIN" 2>"$TMP/err" || fail
security list-keychains -d user -s ${SEARCH[@]+"${SEARCH[@]}"}
security set-keychain-settings "$KEYCHAIN"            # no auto-lock
security unlock-keychain -p "$KEYCHAINPASS" "$KEYCHAIN"

echo "Adding the certificate (only codesign may use it)..."
security import "$TMP/cert.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -P "$P12PASS" >/dev/null 2>"$TMP/err" || fail
# Lets codesign use the key without a password dialog.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAINPASS" "$KEYCHAIN" >/dev/null 2>"$TMP/err" || fail

echo
echo "Done: \"$NAME\" is in ClaudeBar's own keychain; your login keychain wasn't touched. The temporary files are gone."
echo "Next: run scripts/run.sh --install. macOS will ask for the microphone once more, then remember it."
