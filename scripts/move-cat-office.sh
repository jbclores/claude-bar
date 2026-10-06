#!/bin/bash
# Moves Cat Office to a new folder and brings it back up there, patched for ClaudeBar:
#   1. checks everything first (it's Cat Office, the target is free, the patch fits) — nothing changes if not
#   2. stops the running Cat Office dev server (this ends any Claude session running inside Cat Office)
#   3. moves the folder, applies patches/cat-office.patch, points ClaudeBar's config at the new folder
#   4. starts Cat Office again (log: ~/Library/Logs/ClaudeBar/cat-office.log), unless --no-start
# Usage: move-cat-office.sh <cat-office-dir> <new-dir> [--no-start]
set -euo pipefail
FROM="${1:?usage: move-cat-office.sh <cat-office-dir> <new-dir> [--no-start]}"
TO="${2:?usage: move-cat-office.sh <cat-office-dir> <new-dir> [--no-start]}"
START=1; [ "${3:-}" = "--no-start" ] && START=0
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CLAUDE_BAR_CONFIG:-$HOME/.config/claude-bar/projects.json}"
LOG="$HOME/Library/Logs/ClaudeBar/cat-office.log"

FROM="$(cd "$FROM" && pwd -P)"
[ -f "$FROM/server/agent-bridge/index.ts" ] && [ -f "$FROM/package.json" ] || { echo "Not a Cat Office folder: $FROM" >&2; exit 1; }
[ -e "$TO" ] && { echo "Already exists, not overwriting: $TO" >&2; exit 1; }
PARENT="$(dirname "$TO")"
[ -d "$PARENT" ] || { echo "No such folder: $PARENT" >&2; exit 1; }
TO="$(cd "$PARENT" && pwd -P)/$(basename "$TO")"
case "$TO/" in "$FROM"/*) echo "Can't move a folder into itself." >&2; exit 1;; esac
if ! patch -d "$FROM" -p1 -R --dry-run -s -f < "$REPO/patches/cat-office.patch" >/dev/null 2>&1 \
   && ! patch -d "$FROM" -p1 --dry-run -s -f < "$REPO/patches/cat-office.patch" >/dev/null 2>&1; then
  echo "The ClaudeBar patch doesn't fit this Cat Office; nothing was changed." >&2; exit 1
fi

# Processes running from the folder (the dev server and npm); stopped before the move.
pids=$(lsof -a -d cwd -Fpn 2>/dev/null | awk -v dir="$FROM" '/^p/{pid=substr($0,2)} /^n/{p=substr($0,2); if (p==dir || index(p, dir"/")==1) print pid}' | sort -u)
if [ -n "$pids" ]; then
  echo "Stopping Cat Office (pids: $(echo $pids))…"
  kill $pids 2>/dev/null || true
  for _ in $(seq 1 20); do
    alive=""; for p in $pids; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
    [ -z "$alive" ] && break; sleep 0.5
  done
  [ -n "$alive" ] && { echo "Cat Office didn't stop (pids:$alive); nothing was moved." >&2; exit 1; }
fi

mv "$FROM" "$TO"
echo "Moved to $TO"
bash "$REPO/scripts/patch-cat-office.sh" "$TO"

if [ -f "$CONFIG" ]; then
  python3 -I - "$CONFIG" "$TO" <<'PY'
import json, os, sys
path, new = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d.setdefault("catOffice", {})["dir"] = new.replace(os.path.expanduser("~"), "~", 1)
tmp = path + ".tmp"
open(tmp, "w").write(json.dumps(d, indent=2, sort_keys=True) + "\n")
os.replace(tmp, path)
PY
  echo "ClaudeBar config now points at $TO"
fi

if [ "$START" = 1 ]; then
  mkdir -p "$(dirname "$LOG")"
  echo "--- move-cat-office.sh started Cat Office $(date) ---" >> "$LOG"
  (cd "$TO" && nohup npm run dev >> "$LOG" 2>&1 < /dev/null &)
  echo "Starting Cat Office in $TO (log: $LOG) — open http://localhost:5173 in a few seconds."
fi
