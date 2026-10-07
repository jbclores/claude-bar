#!/bin/bash
# Builds build/ClaudeBar.app (release, ad-hoc signed). Copy it to /Applications to install.
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
codesign --force --sign - "$APP"
echo "Built $APP"
