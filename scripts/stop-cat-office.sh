#!/bin/bash
# Stops Cat Office's dev server for a folder — only its node/npm processes, never shells or editors open in the
# folder, and never this script or the shells above it.
# Usage: stop-cat-office.sh <cat-office-dir> [--check]
#   --check  only lists what it would stop
# Exit: 0 stopped (or nothing running); 1 it didn't stop, or this script runs inside Cat Office.
set -euo pipefail
USAGE="usage: stop-cat-office.sh <cat-office-dir> [--check]"
FROM="${1:?$USAGE}"
CHECK=0
case "${2:-}" in --check) CHECK=1;; "") ;; *) echo "$USAGE" >&2; exit 1;; esac
BRIDGE="${CAT_OFFICE_BRIDGE_FILE:-$HOME/.cat-office/bridge.json}"
FROM="$(cd "$FROM" && pwd -P)"

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
  exit 0
fi

if [ -n "$pids" ]; then
  echo "Stopping Cat Office (pids: $(echo $pids))…"
  kill $pids 2>/dev/null || true
  for _ in $(seq 1 20); do
    alive=""; for p in $pids; do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
    [ -z "$alive" ] && break; sleep 0.5
  done
  [ -n "$alive" ] && { echo "Cat Office didn't stop (pids:$alive); it was not stopped." >&2; exit 1; }
fi

