#!/bin/bash
# Applies patches/cat-office.patch to a Cat Office folder: checks it's Cat Office, does a trial run,
# backs up the files it touches to .cat-office/patch-backup-<time>/, then applies. A folder carrying an older
# version of the patch (from this repo's git history) is upgraded: that version is taken out first. Changes
# nothing when the trial run fails (e.g. a newer Cat Office changed the same lines).
# With --undo: takes the patch (or an older version of it) out again, after the same trial run and backup;
# --dry-run only says whether it would.
# Usage: patch-cat-office.sh [--undo [--dry-run]] <cat-office-dir>
# Env: CAT_OFFICE_PATCH (patch file), CAT_OFFICE_PATCH_HISTORY (folder of older NN.patch, newest highest; used instead
# of git). Exit: 0 patched / already patched (undo: unpatched / would unpatch / not patched), 2 not Cat Office,
# 3 the patch doesn't fit (undo: ClaudeBar patched this folder, per its .cat-office/patch-backup-*, but the patch doesn't
# come out cleanly), 64 usage.
set -euo pipefail
USAGE="usage: patch-cat-office.sh [--undo [--dry-run]] <cat-office-dir>"
UNDO=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --undo) UNDO=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -*) echo "$USAGE" >&2; exit 64 ;;
    *) break ;;
  esac
done
if [ $# -ne 1 ] || { [ "$DRY" = 1 ] && [ "$UNDO" = 0 ]; }; then echo "$USAGE" >&2; exit 64; fi
DIR="$1"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="${CAT_OFFICE_PATCH:-$REPO/patches/cat-office.patch}"

if ! { [ -f "$DIR/package.json" ] && [ -d "$DIR/server/agent-bridge" ]; }; then
  echo "Not a Cat Office folder: $DIR" >&2; exit 2
fi

# Prints a temp copy of the newest older version of the patch that reverses cleanly in $DIR (nothing if none).
find_older() {
  local revs rev candidate
  if [ -n "${CAT_OFFICE_PATCH_HISTORY:-}" ]; then
    # Names are fixed-width NN.patch, so reverse lexical order = newest first. One path per line (paths may hold spaces).
    revs=$(ls -r "$CAT_OFFICE_PATCH_HISTORY"/*.patch 2>/dev/null || true)
  else
    revs=$(git -C "$REPO" log --format=%h -- patches/cat-office.patch 2>/dev/null || true)
  fi
  while IFS= read -r rev; do
    [ -n "$rev" ] || continue
    candidate=$(mktemp)
    if [ -n "${CAT_OFFICE_PATCH_HISTORY:-}" ]; then
      cp "$rev" "$candidate" 2>/dev/null || { rm -f "$candidate"; continue; }
    else
      git -C "$REPO" show "$rev:patches/cat-office.patch" > "$candidate" 2>/dev/null || { rm -f "$candidate"; continue; }
    fi
    if patch -d "$DIR" -p1 -R --dry-run -s -f < "$candidate" >/dev/null 2>&1; then echo "$candidate"; return; fi
    rm -f "$candidate"
  done <<< "$revs"
}

# True when older version $1 is not what this folder holds, though it reverses: taking it out doesn't leave a folder the
# current patch fits (the upgrade path's rule). That is a folder with the current version plus an edit, where an older
# version lacking the newer pieces reverses "cleanly" and would leave those pieces behind. Nothing is changed in $DIR.
leaves_current() {
  local scratch f fits
  scratch=$(mktemp -d)
  cat "$1" "$PATCH" | grep '^+++ b/' | sed 's|^+++ b/||' | sort -u | while read -r f; do
    if [ -f "$DIR/$f" ]; then mkdir -p "$scratch/$(dirname "$f")"; cp -p "$DIR/$f" "$scratch/$f"; fi
  done
  fits=""
  if patch -d "$scratch" -p1 -R -s -f < "$1" >/dev/null 2>&1 && patch -d "$scratch" -p1 --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then fits=1; fi
  rm -rf "$scratch"
  [ -z "$fits" ]
}

# Copies the files the given patches touch into a new .cat-office/patch-backup-<time>[-N]/ and sets BACKUP.
back_up() {
  local base n f
  base="$DIR/.cat-office/patch-backup-$(date +%Y%m%d-%H%M%S)"
  BACKUP="$base"; n=2
  while [ -e "$BACKUP" ]; do BACKUP="$base-$n"; n=$((n+1)); done   # patch then undo in the same second
  mkdir -p "$BACKUP"
  cat "$@" | grep '^+++ b/' | sed 's|^+++ b/||' | sort -u | while read -r f; do
    if [ -f "$DIR/$f" ]; then
      mkdir -p "$BACKUP/$(dirname "$f")"
      cp -p "$DIR/$f" "$BACKUP/$f"
    fi
  done
}

if [ "$UNDO" = 1 ]; then
  if patch -d "$DIR" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
    REV=$(mktemp); cp "$PATCH" "$REV"
  else
    REV=$(find_older)
    if [ -n "$REV" ] && leaves_current "$REV"; then rm -f "$REV"; REV=""; fi
  fi
  if [ -z "$REV" ]; then
    if patch -d "$DIR" -p1 --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then echo "Not patched: $DIR"; exit 0; fi
    # Neither fits. Only a folder still holding ClaudeBar's patch has something to take out: it has a backup (patching and
    # unpatching both leave one) AND a file the patch touches still names ClaudeBar (the comments the patch adds). Any
    # other (never patched, or patched, unpatched, then updated) has nothing of ClaudeBar's in it.
    ours=""
    if ls -d "$DIR"/.cat-office/patch-backup-* >/dev/null 2>&1; then
      while read -r f; do
        if [ -f "$DIR/$f" ] && grep -q ClaudeBar "$DIR/$f" 2>/dev/null; then ours=1; break; fi
      done < <(grep '^+++ b/' "$PATCH" | sed 's|^+++ b/||' | sort -u)
    fi
    if [ -z "$ours" ]; then echo "Not patched: $DIR"; exit 0; fi
    echo "Can't take the patch out of this Cat Office cleanly; nothing was changed." >&2; exit 3
  fi
  if [ "$DRY" = 1 ]; then rm -f "$REV"; echo "Would unpatch $DIR"; exit 0; fi
  back_up "$REV"
  patch -d "$DIR" -p1 -R -s -f -E < "$REV"
  rm -f "$REV"
  echo "Unpatched $DIR"
  echo "Backup of the changed files: $BACKUP"
  exit 0
fi

if patch -d "$DIR" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
  echo "Already patched: $DIR"; exit 0
fi
# An older version already applied? Find it in git history: it reverses cleanly, and the current one then fits.
OLD=""
if ! patch -d "$DIR" -p1 --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
  OLD=$(find_older)
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

if [ -n "$OLD" ]; then back_up "$PATCH" "$OLD"; else back_up "$PATCH"; fi
if [ -n "$OLD" ]; then
  patch -d "$DIR" -p1 -R -s -f -E < "$OLD"
  rm -f "$OLD"
  echo "Took out the older version of the patch."
fi
patch -d "$DIR" -p1 -s -f < "$PATCH"
echo "Patched $DIR"
echo "Backup of the changed files: $BACKUP"
echo "Restart Cat Office (stop its dev server, then npm run dev) to load the change."
