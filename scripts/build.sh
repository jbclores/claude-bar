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
if security find-identity -p codesigning 2>/dev/null | grep -q '"ClaudeBar Local"'; then
  codesign --force --sign "ClaudeBar Local" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
