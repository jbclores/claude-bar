#!/bin/bash
# scripts/test-setup-scripts.sh — tests for the setup scripts, in temp folders only.
# Usage: scripts/test-setup-scripts.sh <cat-office-dir>   (read-only: only the patched files are copied out)
set -uo pipefail
CO="${1:?usage: test-setup-scripts.sh <cat-office-dir>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$REPO/patches/cat-office.patch"
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# A mini Cat Office: package.json, server/agent-bridge, and the files the patch touches, unpatched.
mini=$(mktemp -d)
mkdir -p "$mini/server/agent-bridge"; echo '{"name":"cat-office"}' > "$mini/package.json"
grep '^+++ b/' "$PATCH" | sed 's|^+++ b/||' | while read -r f; do
  if [ -f "$CO/$f" ]; then mkdir -p "$mini/$(dirname "$f")"; cp "$CO/$f" "$mini/$f"; fi
done
if patch -d "$mini" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then patch -d "$mini" -p1 -R -s -f < "$PATCH"; fi
# Files the patch creates must not exist in an unpatched copy.
grep -B1 '^+++ b/' "$PATCH" | grep -A1 '^--- /dev/null' | grep '^+++ b/' | sed 's|^+++ b/||' | while read -r f; do rm -f "$mini/$f"; done

out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$mini"); code=$?
[ $code = 0 ] && [[ "$out" == Patched* ]] && ok "patches a fresh copy" || bad "patches a fresh copy ($code: $out)"
out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$mini"); code=$?
[ $code = 0 ] && [[ "$out" == Already* ]] && ok "already patched is not patched twice" || bad "already patched ($code: $out)"

notco=$(mktemp -d)
CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$notco" >/dev/null 2>&1; code=$?
[ $code = 2 ] && ok "not Cat Office exits 2" || bad "not Cat Office exits 2 (got $code)"

broken=$(mktemp -d); cp -R "$mini/." "$broken/"; patch -d "$broken" -p1 -R -s -f < "$PATCH"
# A file the patch modifies (not one it creates: patch overwrites those), so changing it makes the patch not fit.
first=$(awk '/^\+\+\+ b\//{f=substr($0,7); next} /^@@ /{ if (f!="" && $2!="-0,0") {print f; exit} f="" }' "$PATCH")
printf 'changed by a newer Cat Office\n' > "$broken/$first"; before=$(cd "$broken" && find . -type f -not -path './.cat-office/*' -exec md5 -q {} \; | sort | md5 -q)
CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$broken" >/dev/null 2>&1; code=$?
after=$(cd "$broken" && find . -type f -not -path './.cat-office/*' -exec md5 -q {} \; | sort | md5 -q)
[ $code = 3 ] && [ "$before" = "$after" ] && ok "doesn't fit: exit 3, nothing changed" || bad "doesn't fit (got $code)"

# An older version (from a history folder, no git) is upgraded.
hist="$(mktemp -d)/history dir"; mkdir -p "$hist"; git -C "$REPO" log --format=%h -- patches/cat-office.patch | sed -n '2p' | while read -r rev; do
  git -C "$REPO" show "$rev:patches/cat-office.patch" > "$hist/01.patch"; done
if [ -s "$hist/01.patch" ] && ! cmp -s "$hist/01.patch" "$PATCH"; then
  old=$(mktemp -d); cp -R "$mini/." "$old/"; patch -d "$old" -p1 -R -s -f < "$PATCH"; patch -d "$old" -p1 -s -f < "$hist/01.patch" 2>/dev/null
  out=$(CAT_OFFICE_PATCH="$PATCH" CAT_OFFICE_PATCH_HISTORY="$hist" bash "$REPO/scripts/patch-cat-office.sh" "$old" 2>&1); code=$?
  [ $code = 0 ] && patch -d "$old" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1 && ok "upgrades an older patch from a history folder (path with a space)" || bad "upgrade ($code: $out)"
else
  echo "SKIP upgrade from history folder (no older patch in git)"
fi

# stop-cat-office.sh --check on a folder with nothing running.
out=$(bash "$REPO/scripts/stop-cat-office.sh" "$mini" --check); code=$?
[ $code = 0 ] && [[ "$out" == *"nothing running"* ]] && ok "stop --check with nothing running" || bad "stop --check ($code: $out)"

# Quiet status line: writes the snapshot, prints nothing.
home=$(mktemp -d)
json='{"session_id":"t1","workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"context_window":{"used_percentage":12}}'
out=$(printf '%s' "$json" | HOME="$home" CLAUDE_BAR_DIR="$home/cb" CLAUDEBAR_STATUSLINE_QUIET=1 bash "$REPO/scripts/statusline-command.sh")
[ -z "$out" ] && [ -f "$home/cb/sessions/t1.json" ] && ok "quiet status line: data saved, nothing printed" || bad "quiet status line (out: $out)"
out=$(printf '%s' "$json" | HOME="$home" CLAUDE_BAR_DIR="$home/cb" bash "$REPO/scripts/statusline-command.sh")
[ -n "$out" ] && ok "normal status line still prints" || bad "normal status line"

# A real stop exits 0: a stand-in "node" process whose cwd is inside a temp folder (never the real Cat Office).
stopmini=$(mktemp -d); mkdir -p "$stopmini/server/agent-bridge" "$stopmini/bin"; echo '{}' > "$stopmini/package.json"
# (a copied system binary is killed on Apple silicon, so build a tiny one)
printf '#include <unistd.h>\nint main(void){sleep(60);return 0;}\n' > "$stopmini/n.c"
clang -o "$stopmini/bin/node" "$stopmini/n.c" 2>/dev/null
if [ ! -x "$stopmini/bin/node" ]; then echo "SKIP real stop (no C compiler)"; else
(cd "$stopmini" && exec "$stopmini/bin/node" 60 >/dev/null 2>&1 &)
sleep 1; standin=$(pgrep -f "$stopmini/bin/node" | head -1)
if [ -z "$standin" ]; then bad "stop: stand-in process didn't start"; else
  out=$(CAT_OFFICE_BRIDGE_FILE=/nonexistent bash "$REPO/scripts/stop-cat-office.sh" "$stopmini" 2>&1); code=$?
  if [ $code = 0 ] && ! kill -0 "$standin" 2>/dev/null; then ok "stop kills the running process and exits 0"; else bad "stop ($code: $out)"; kill "$standin" 2>/dev/null; fi
fi
# The bridge file's pid (cwd outside the folder, so only the bridge names it), read without python3: a python3 that
# fails first in PATH stands for a Mac without the developer tools (its shim pops an install dialog).
fakebin=$(mktemp -d); printf '#!/bin/sh\ntouch "%s/python-ran"; exit 1\n' "$fakebin" > "$fakebin/python3"; chmod +x "$fakebin/python3"
(cd / && exec "$stopmini/bin/node" 60 >/dev/null 2>&1 &)
sleep 1; standin=$(pgrep -f "$stopmini/bin/node" | head -1)
if [ -z "$standin" ]; then bad "bridge stop: stand-in process didn't start"; else
  other=$(mktemp -d)
  printf '{"pid": %s, "dir": "%s"}' "$standin" "$other" > "$fakebin/bridge-other.json"
  out=$(PATH="$fakebin:$PATH" CAT_OFFICE_BRIDGE_FILE="$fakebin/bridge-other.json" bash "$REPO/scripts/stop-cat-office.sh" "$stopmini" --check 2>&1)
  [[ "$out" == *"nothing running"* ]] && ok "bridge pid of another folder is not stopped" || bad "bridge other folder ($out)"
  printf '{"pid": %s, "dir": "%s"}' "$standin" "$stopmini" > "$fakebin/bridge.json"
  out=$(PATH="$fakebin:$PATH" CAT_OFFICE_BRIDGE_FILE="$fakebin/bridge.json" bash "$REPO/scripts/stop-cat-office.sh" "$stopmini" 2>&1); code=$?
  if [ $code = 0 ] && ! kill -0 "$standin" 2>/dev/null && [ ! -e "$fakebin/python-ran" ]; then ok "stop finds the bridge pid without python3"
  else bad "bridge stop ($code: $out; python ran: $([ -e "$fakebin/python-ran" ] && echo yes || echo no))"; kill "$standin" 2>/dev/null; fi
  rm -rf "$other"
fi
rm -rf "$fakebin"
fi
rm -rf "$stopmini"

rm -rf "$mini" "$notco" "$broken" "$hist" "${old:-/nonexistent}" "$home"
echo "$pass passed, $fail failed"; [ $fail = 0 ]
