#!/bin/bash
# Applies patches/cat-office.patch to a Cat Office folder: checks it's Cat Office, does a trial run,
# backs up the files it touches to .cat-office/patch-backup-<time>/, then applies. A folder carrying an older
# version of the patch (from this repo's git history) is upgraded: that version is taken out first. Changes
# nothing when the trial run fails (e.g. a newer Cat Office changed the same lines).
# Usage: patch-cat-office.sh <cat-office-dir>
# Env: CAT_OFFICE_PATCH (patch file), CAT_OFFICE_PATCH_HISTORY (folder of older NN.patch, newest highest; used instead
# of git). Exit: 0 patched / already patched, 2 not Cat Office, 3 the patch doesn't fit.
set -euo pipefail
DIR="${1:?usage: patch-cat-office.sh <cat-office-dir>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="${CAT_OFFICE_PATCH:-$REPO/patches/cat-office.patch}"

if ! { [ -f "$DIR/package.json" ] && [ -d "$DIR/server/agent-bridge" ]; }; then
  echo "Not a Cat Office folder: $DIR" >&2; exit 2
fi
if patch -d "$DIR" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
  echo "Already patched: $DIR"; exit 0
fi
# An older version already applied? Find it in git history: it reverses cleanly, and the current one then fits.
OLD=""
if ! patch -d "$DIR" -p1 --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
  if [ -n "${CAT_OFFICE_PATCH_HISTORY:-}" ]; then
    revs=$(ls -r "$CAT_OFFICE_PATCH_HISTORY"/*.patch 2>/dev/null || true)
  else
    revs=$(git -C "$REPO" log --format=%h -- patches/cat-office.patch 2>/dev/null || true)
  fi
  for rev in $revs; do
    candidate=$(mktemp)
    if [ -n "${CAT_OFFICE_PATCH_HISTORY:-}" ]; then
      cp "$rev" "$candidate" 2>/dev/null || { rm -f "$candidate"; continue; }
    else
      git -C "$REPO" show "$rev:patches/cat-office.patch" > "$candidate" 2>/dev/null || { rm -f "$candidate"; continue; }
    fi
    if patch -d "$DIR" -p1 -R --dry-run -s -f < "$candidate" >/dev/null 2>&1; then OLD="$candidate"; break; fi
    rm -f "$candidate"
  done
  if [ -z "$OLD" ]; then
    patch -d "$DIR" -p1 --dry-run -s -f < "$PATCH" || true
    echo "The patch doesn't apply cleanly to this Cat Office; nothing was changed." >&2; exit 3
  fi
  # Trial run of the whole upgrade on a scratch copy of the touched files.
  scratch=$(mktemp -d)
  cat "$OLD" "$PATCH" | grep -E '^\+\+\+ b/' | sed 's|^+++ b/||' | sort -u | while read -r f; do
    if [ -f "$DIR/$f" ]; then mkdir -p "$scratch/$(dirname "$f")"; cp -p "$DIR/$f" "$scratch/$f"; fi
  done
  if ! { patch -d "$scratch" -p1 -R -s -f < "$OLD" && patch -d "$scratch" -p1 -s -f < "$PATCH"; } >/dev/null 2>&1; then
    rm -rf "$scratch" "$OLD"
    echo "Can't upgrade the older patch in this Cat Office cleanly; nothing was changed." >&2; exit 3
  fi
  rm -rf "$scratch"
fi

BACKUP="$DIR/.cat-office/patch-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
{ cat "$PATCH"; if [ -n "$OLD" ]; then cat "$OLD"; fi; } | grep '^+++ b/' | sed 's|^+++ b/||' | sort -u | while read -r f; do
  if [ -f "$DIR/$f" ]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp -p "$DIR/$f" "$BACKUP/$f"
  fi
done
if [ -n "$OLD" ]; then
  patch -d "$DIR" -p1 -R -s -f -E < "$OLD"
  rm -f "$OLD"
  echo "Took out the older version of the patch."
fi
patch -d "$DIR" -p1 -s -f < "$PATCH"
echo "Patched $DIR"
echo "Backup of the changed files: $BACKUP"
echo "Restart Cat Office (stop its dev server, then npm run dev) to load the change."
