#!/bin/bash
# Builds build/ClaudeBar.app (release; signed "ClaudeBar Local" if scripts/make-signing-cert.sh made it, else ad hoc). Copy it to /Applications to install.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudeBar"
APP=build/ClaudeBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The cat sounds (made by scripts/make-sounds.py).
mkdir -p "$APP/Contents/Resources"
cp Resources/Sounds/*.wav "$APP/Contents/Resources/"
# The help guide (the ? panel's "Full guide").
cp -R Resources/Help "$APP/Contents/Resources/Help"
# Onboarding: the patch, its older versions (for upgrades, no git needed in the app), and the scripts.
SETUP="$APP/Contents/Resources/Setup"
mkdir -p "$SETUP/patch-history"
cp patches/cat-office.patch scripts/patch-cat-office.sh scripts/stop-cat-office.sh scripts/statusline-command.sh "$SETUP/"
i=0
for rev in $(git log --reverse --format=%h -- patches/cat-office.patch 2>/dev/null); do
  i=$((i+1)); git show "$rev:patches/cat-office.patch" > "$SETUP/patch-history/$(printf '%02d' $i).patch"
done
# Signed with "ClaudeBar Local" from ClaudeBar's own keychain when scripts/make-signing-cert.sh made one (macOS then
# keeps the microphone permission across updates); otherwise, or if that fails, ad hoc. Never asks for a password.
KEYCHAIN="${CLAUDEBAR_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/claudebar-signing.keychain-db}"
PASSFILE="${CLAUDEBAR_SIGNING_PASSFILE:-$HOME/Library/Application Support/ClaudeBar/signing-keychain.pass}"
signed=""
if [ -f "$KEYCHAIN" ] && [ -f "$PASSFILE" ] && security unlock-keychain -p "$(cat "$PASSFILE")" "$KEYCHAIN" 2>/dev/null; then
  ID="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | awk '/"ClaudeBar Local"/ { print $2; exit }')"
  # codesign only finds keys in keychains on the search list: add ClaudeBar's for this one step, then put the list
  # back exactly as it was (also if the build stops here).
  SEARCH=()
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line#\"}"; line="${line%\"}"
    [ -n "$line" ] && SEARCH+=("$line")
  done < <(security list-keychains -d user)
  trap 'security list-keychains -d user -s ${SEARCH[@]+"${SEARCH[@]}"}' EXIT
  security list-keychains -d user -s ${SEARCH[@]+"${SEARCH[@]}"} "$KEYCHAIN"
  if [ -n "$ID" ] && codesign --force --sign "$ID" --keychain "$KEYCHAIN" "$APP" 2>/dev/null; then
    signed="ClaudeBar Local"
  else
    echo "Couldn't sign with ClaudeBar Local; signing ad hoc instead."
  fi
  security list-keychains -d user -s ${SEARCH[@]+"${SEARCH[@]}"}
  trap - EXIT
fi
[ -n "$signed" ] || codesign --force --sign - "$APP"
echo "Built $APP"
