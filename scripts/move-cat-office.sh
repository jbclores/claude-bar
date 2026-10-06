#!/bin/bash
# Moves Cat Office to a new folder and brings it back up there, patched for ClaudeBar:
#   1. checks everything first (it's Cat Office, the target is free, the patch fits) — nothing changes if not
#   2. stops the running Cat Office dev server — only its node/npm processes, never shells or editors open in
#      the folder (this ends any Claude session running inside Cat Office)
#   3. moves the folder, applies patches/cat-office.patch, points ClaudeBar's config at the new folder
#   4. starts Cat Office again (log: ~/Library/Logs/ClaudeBar/cat-office.log), unless --no-start
# Usage: move-cat-office.sh <cat-office-dir> <new-dir> [--no-start | --check]
#   --check  only lists the processes it would stop, then exits without changing anything
set -euo pipefail
USAGE="usage: move-cat-office.sh <cat-office-dir> <new-dir> [--no-start | --check]"
FROM="${1:?$USAGE}"
TO="${2:?$USAGE}"
START=1; CHECK=0
case "${3:-}" in --no-start) START=0;; --check) CHECK=1;; "") ;; *) echo "$USAGE" >&2; exit 1;; esac
BRIDGE="${CAT_OFFICE_BRIDGE_FILE:-$HOME/.cat-office/bridge.json}"
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

# This script and the shells above it are never stopped.
protected=" $$ "; p=$$
while [ "$p" -gt 1 ] 2>/dev/null; do p=$(ps -o ppid= -p "$p" | tr -d ' '); [ -n "$p" ] && protected="$protected$p "; done

cwd_of() { lsof -a -p "$1" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'; }
inside() { [ "$1" = "$FROM" ] || case "$1" in "$FROM"/*) true;; *) false;; esac; }
# npm renames itself ("npm run dev"): compare the first word only.
is_node_or_npm() { case "$(basename "$(ps -o comm= -p "$1" 2>/dev/null | awk '{print $1}')")" in node|npm) true;; *) false;; esac; }

# Cat Office's dev server: the pid in its bridge file (patched Cat Office) when it names this folder, else node/npm
# processes running from the folder. Plus their npm parent when it runs from the folder too.
pids=""
if [ -f "$BRIDGE" ]; then
  bpid=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["pid"] if d.get("dir") and __import__("os").path.realpath(d["dir"])==sys.argv[2] else "")' "$BRIDGE" "$FROM" 2>/dev/null || true)
  [ -n "$bpid" ] && kill -0 "$bpid" 2>/dev/null && pids="$bpid"
fi
if [ -z "$pids" ]; then
  for p in $(lsof -a -c node -c npm -d cwd -Fp 2>/dev/null | sed -n 's/^p//p' | sort -u); do
    inside "$(cwd_of "$p")" && is_node_or_npm "$p" && pids="$pids $p"
  done
fi
for p in $pids; do
  parent=$(ps -o ppid= -p "$p" | tr -d ' ')
  [ -n "$parent" ] && is_node_or_npm "$parent" && inside "$(cwd_of "$parent")" && pids="$pids $parent"
done
stop=""
for p in $(echo $pids | tr ' ' '\n' | sort -u); do
  case "$protected" in
    *" $p "*) echo "This script is running inside Cat Office (pid $p); run it from a terminal outside Cat Office. Nothing was changed." >&2; exit 1;;
    *) stop="$stop $p";;
  esac
done
pids=$(echo $stop)

if [ "$CHECK" = 1 ]; then
  echo "Would stop:"; [ -n "$pids" ] && ps -o pid=,command= -p $(echo $pids | tr ' ' ',') | cut -c1-140 || echo "  (nothing running)"
  echo "Would move $FROM → $TO"; exit 0
fi

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
  python3 -I - "$CONFIG" "$TO" <<'PY' || echo "Couldn't update $CONFIG (ClaudeBar still finds Cat Office through its bridge file)." >&2
import json, os, sys
path, new = sys.argv[1], sys.argv[2]
d = json.load(open(path))
home = os.path.expanduser("~")
d.setdefault("catOffice", {})["dir"] = "~" + new[len(home):] if new.startswith(home + "/") else new
tmp = path + ".tmp"
open(tmp, "w").write(json.dumps(d, indent=2, sort_keys=True) + "\n")
os.replace(tmp, path)
print("ClaudeBar config now points at " + new)
PY
fi

if [ "$START" = 1 ]; then
  mkdir -p "$(dirname "$LOG")"
  echo "--- move-cat-office.sh started Cat Office $(date) ---" >> "$LOG"
  (cd "$TO" && nohup npm run dev >> "$LOG" 2>&1 < /dev/null &)
  echo "Starting Cat Office in $TO (log: $LOG) — open http://localhost:5173 in a few seconds."
fi
