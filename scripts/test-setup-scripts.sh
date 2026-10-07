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

# stop-cat-office.sh against stand-in "node" processes in temp folders (never the real Cat Office). Each stand-in
# gets a unique argument so pgrep finds exactly it; the tiny binary ignores its arguments.
stopmini=$(mktemp -d); mkdir -p "$stopmini/server/agent-bridge" "$stopmini/bin"; echo '{}' > "$stopmini/package.json"
# (a copied system binary is killed on Apple silicon, so build a tiny one)
printf '#include <unistd.h>\nint main(void){sleep(60);return 0;}\n' > "$stopmini/n.c"
clang -o "$stopmini/bin/node" "$stopmini/n.c" 2>/dev/null
standin() { # <cwd> <tag> [args…]: starts a stand-in node from <cwd>; prints its pid
  local cwd="$1" tag="$2"; shift 2
  (cd "$cwd" && exec "$stopmini/bin/node" "$tag" "$@" >/dev/null 2>&1 &)
  sleep 1; pgrep -f "$stopmini/bin/node $tag" | head -1
}
if [ ! -x "$stopmini/bin/node" ]; then echo "SKIP real stop (no C compiler)"; else
# A plain node in the folder (a Claude Code session, tsc --watch, a test runner) isn't Cat Office's dev server.
plain=$(standin "$stopmini" plain-session 60)
if [ -z "$plain" ]; then bad "plain stand-in didn't start"; else
  out=$(CAT_OFFICE_BRIDGE_FILE=/nonexistent bash "$REPO/scripts/stop-cat-office.sh" "$stopmini" 2>&1); code=$?
  if [ $code = 0 ] && kill -0 "$plain" 2>/dev/null; then ok "a plain node in the folder (not the dev server) is not stopped"
  else bad "plain node was stopped ($code: $out)"; fi
  kill "$plain" 2>/dev/null
fi
# Cat Office's dev server: a node in the folder running vite is stopped.
vite=$(standin "$stopmini" dev-server "$stopmini/node_modules/.bin/vite")
if [ -z "$vite" ]; then bad "vite stand-in didn't start"; else
  out=$(CAT_OFFICE_BRIDGE_FILE=/nonexistent bash "$REPO/scripts/stop-cat-office.sh" "$stopmini" 2>&1); code=$?
  if [ $code = 0 ] && ! kill -0 "$vite" 2>/dev/null; then ok "stop kills the vite dev server in the folder and exits 0"; else bad "vite stop ($code: $out)"; kill "$vite" 2>/dev/null; fi
fi
# The bridge file's pid, read without python3: a python3 that fails first in PATH stands for a Mac without the
# developer tools (its shim pops an install dialog). The stand-in's command line isn't vite, so only the bridge names it.
fakebin=$(mktemp -d); printf '#!/bin/sh\ntouch "%s/python-ran"; exit 1\n' "$fakebin" > "$fakebin/python3"; chmod +x "$fakebin/python3"
bridged=$(standin "$stopmini" bridged 60)
if [ -z "$bridged" ]; then bad "bridge stop: stand-in process didn't start"; else
  other=$(mktemp -d)
  printf '{"pid": %s, "dir": "%s"}' "$bridged" "$other" > "$fakebin/bridge-other.json"
  out=$(PATH="$fakebin:$PATH" CAT_OFFICE_BRIDGE_FILE="$fakebin/bridge-other.json" bash "$REPO/scripts/stop-cat-office.sh" "$stopmini" --check 2>&1)
  [[ "$out" == *"nothing running"* ]] && ok "bridge pid of another folder is not stopped" || bad "bridge other folder ($out)"
  printf '{"pid": %s, "dir": "%s"}' "$bridged" "$stopmini" > "$fakebin/bridge.json"
  out=$(PATH="$fakebin:$PATH" CAT_OFFICE_BRIDGE_FILE="$fakebin/bridge.json" bash "$REPO/scripts/stop-cat-office.sh" "$stopmini" 2>&1); code=$?
  if [ $code = 0 ] && ! kill -0 "$bridged" 2>/dev/null && [ ! -e "$fakebin/python-ran" ]; then ok "stop finds the bridge pid without python3"
  else bad "bridge stop ($code: $out; python ran: $([ -e "$fakebin/python-ran" ] && echo yes || echo no))"; kill "$bridged" 2>/dev/null; fi
  rm -rf "$other"
fi
# A stale bridge whose pid is now something else (not node/npm), even running from the folder, is not stopped.
(cd "$stopmini" && exec /bin/sleep 61 >/dev/null 2>&1 &)
sleep 1; sleeper=$(pgrep -f "^/bin/sleep 61$" | head -1)
if [ -z "$sleeper" ]; then bad "stale bridge: sleep didn't start"; else
  printf '{"pid": %s, "dir": "%s"}' "$sleeper" "$stopmini" > "$fakebin/bridge-stale.json"
  out=$(CAT_OFFICE_BRIDGE_FILE="$fakebin/bridge-stale.json" bash "$REPO/scripts/stop-cat-office.sh" "$stopmini" 2>&1); code=$?
  if [ $code = 0 ] && kill -0 "$sleeper" 2>/dev/null; then ok "a stale bridge pid naming a non-node process is not stopped"
  else bad "stale bridge pid was stopped ($code: $out)"; fi
  kill "$sleeper" 2>/dev/null
fi
rm -rf "$fakebin"
fi
rm -rf "$stopmini"

# --- Undo (--undo). An unpatched original to compare against.
orig=$(mktemp -d); cp -R "$mini/." "$orig/"; rm -rf "$orig/.cat-office"
if patch -d "$orig" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then patch -d "$orig" -p1 -R -s -f -E < "$PATCH"; fi
tree_sum() { (cd "$1" && find . -type f -not -path './.cat-office/*' | sort | while read -r f; do echo "$f $(md5 -q "$f")"; done | md5 -q); }

u=$(mktemp -d); cp -R "$orig/." "$u/"
CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$u" >/dev/null 2>&1
out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo --dry-run "$u" 2>&1); code=$?
[ $code = 0 ] && [[ "$out" == "Would unpatch"* ]] && patch -d "$u" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1 \
  && ok "undo --dry-run says it would unpatch and changes nothing" || bad "undo --dry-run ($code: $out)"
out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo "$u" 2>&1); code=$?
backups=$(ls -d "$u"/.cat-office/patch-backup-* 2>/dev/null | wc -l | tr -d ' ')
[ $code = 0 ] && [[ "$out" == Unpatched* ]] && [ "$(tree_sum "$u")" = "$(tree_sum "$orig")" ] && [ "$backups" = 2 ] \
  && ok "patch then undo gives the original back, with its own backup (no collision)" || bad "undo ($code, backups $backups: $out)"

out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo "$u" 2>&1); code=$?
[ $code = 0 ] && [[ "$out" == "Not patched"* ]] && [ "$(tree_sum "$u")" = "$(tree_sum "$orig")" ] \
  && ok "undo on an unpatched copy: nothing to do" || bad "undo unpatched ($code: $out)"

e=$(mktemp -d); cp -R "$orig/." "$e/"; CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$e" >/dev/null 2>&1
printf 'edited after patching\n' > "$e/$first"; before=$(tree_sum "$e")
CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo "$e" >/dev/null 2>&1; code=$?
[ $code = 3 ] && [ "$(tree_sum "$e")" = "$before" ] && ok "undo after an edit: exit 3, nothing changed" || bad "undo after an edit (got $code)"

CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo "$notco" >/dev/null 2>&1; code=$?
[ $code = 2 ] && ok "undo on a non-Cat Office folder exits 2" || bad "undo non-Cat Office (got $code)"
bash "$REPO/scripts/patch-cat-office.sh" --dry-run "$u" >/dev/null 2>&1; code=$?
[ $code = 64 ] && ok "--dry-run without --undo is a usage error" || bad "--dry-run alone (got $code)"

if [ -s "$hist/01.patch" ] && ! cmp -s "$hist/01.patch" "$PATCH"; then
  o=$(mktemp -d); cp -R "$orig/." "$o/"; patch -d "$o" -p1 -s -f < "$hist/01.patch" >/dev/null 2>&1
  out=$(CAT_OFFICE_PATCH="$PATCH" CAT_OFFICE_PATCH_HISTORY="$hist" bash "$REPO/scripts/patch-cat-office.sh" --undo "$o" 2>&1); code=$?
  [ $code = 0 ] && [[ "$out" == Unpatched* ]] && [ "$(tree_sum "$o")" = "$(tree_sum "$orig")" ] \
    && ok "undo takes out an older version of the patch" || bad "undo older version ($code: $out)"
  rm -rf "$o"
else
  echo "SKIP undo of an older version (no older patch in git)"
fi
rm -rf "$orig" "$u" "$e"
rm -rf "$mini" "$notco" "$broken" "$hist" "${old:-/nonexistent}" "$home"
echo "$pass passed, $fail failed"; [ $fail = 0 ]
