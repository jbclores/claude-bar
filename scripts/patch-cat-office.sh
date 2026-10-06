#!/bin/bash
# Applies patches/cat-office.patch to a Cat Office folder: checks it's Cat Office, does a trial run,
# backs up the files it touches to .cat-office/patch-backup-<time>/, then applies. Changes nothing
# when the trial run fails (e.g. a newer Cat Office changed the same lines).
# Usage: patch-cat-office.sh <cat-office-dir>
set -euo pipefail
DIR="${1:?usage: patch-cat-office.sh <cat-office-dir>}"
PATCH="$(cd "$(dirname "$0")/.." && pwd)/patches/cat-office.patch"

if [ ! -f "$DIR/server/agent-bridge/index.ts" ] || [ ! -f "$DIR/src/agents/live/useAgentCats.ts" ]; then
  echo "Not a Cat Office folder: $DIR" >&2; exit 1
fi
if patch -d "$DIR" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
  echo "Already patched: $DIR"; exit 0
fi
if ! patch -d "$DIR" -p1 --dry-run -s -f < "$PATCH"; then
  echo "The patch doesn't apply cleanly to this Cat Office; nothing was changed." >&2; exit 1
fi

BACKUP="$DIR/.cat-office/patch-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
grep '^+++ b/' "$PATCH" | sed 's|^+++ b/||' | while read -r f; do
  if [ -f "$DIR/$f" ]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp -p "$DIR/$f" "$BACKUP/$f"
  fi
done
patch -d "$DIR" -p1 -s -f < "$PATCH"
echo "Patched $DIR"
echo "Backup of the changed files: $BACKUP"
echo "Restart Cat Office (stop its dev server, then npm run dev) to load the change."
