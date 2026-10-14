#!/bin/bash
# One command for teammates: checks the tools, builds ClaudeBar, and opens it. No admin password needed.
#   scripts/run.sh             run it from this folder (build/ClaudeBar.app)
#   scripts/run.sh --install   copy it to ~/Applications (your own folder) and run it from there
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  "") INSTALL=0 ;;
  --install) INSTALL=1 ;;
  *) echo "Usage: scripts/run.sh [--install]" >&2; exit 64 ;;
esac

if ! xcode-select -p >/dev/null 2>&1; then
  echo "ClaudeBar needs Apple's Command Line Tools. Run:  xcode-select --install" >&2
  echo "(If that asks for an admin password, ask IT to install the Command Line Tools.) Then run this again." >&2
  exit 1
fi
SWIFT_MAJOR=$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+).*/\1/p' | head -1)
if [ -z "$SWIFT_MAJOR" ] || [ "$SWIFT_MAJOR" -lt 6 ]; then
  echo "ClaudeBar needs Swift 6 or newer (found: ${SWIFT_MAJOR:-none})." >&2
  echo "Update the Command Line Tools in System Settings → General → Software Update, then run this again." >&2
  exit 1
fi

echo "Building ClaudeBar (the first build takes a minute)…"
bash scripts/build.sh

# Quit a running ClaudeBar (from here or ~/Applications) so the new build takes its place: asked politely by its
# app id (how macOS quits apps), then by name. If it's still running, stop here: opening would only bring the old
# one forward.
BUNDLE_ID=com.jbclores.claudebar
running() {
  [ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null)" = true ] \
    || pgrep -f "ClaudeBar.app/Contents/MacOS/ClaudeBar" >/dev/null 2>&1
}
wait_quit() {
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    running || return 0
    sleep 0.5
  done
  return 1
}
if running; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  if ! wait_quit; then
    pkill -f "ClaudeBar.app/Contents/MacOS/ClaudeBar" 2>/dev/null || true
    if ! wait_quit; then
      echo "ClaudeBar is still running, so the new build can't take its place." >&2
      echo "Quit it (click the menu bar cat, then Quit) and run this again." >&2
      exit 1
    fi
  fi
fi

APP=build/ClaudeBar.app
if [ "$INSTALL" = 1 ]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/ClaudeBar.app
  cp -R build/ClaudeBar.app ~/Applications/
  APP=~/Applications/ClaudeBar.app
fi
open "$APP"
# Check the new one is the one running.
for _ in 1 2 3 4 5 6 7 8 9 10; do running && break; sleep 0.5; done
if ! running; then
  echo "ClaudeBar didn't start. Open $APP from Finder to see why." >&2
  exit 1
fi
echo "ClaudeBar is running from $APP — look for the cat in your menu bar."
echo "The first time, a Set up ClaudeBar window opens. Run this again after a git pull to update."
