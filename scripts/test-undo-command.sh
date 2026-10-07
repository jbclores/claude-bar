#!/bin/bash
# scripts/test-undo-command.sh — ClaudeBar --undo against a temp root only (CLAUDEBAR_UNDO_ROOT). Needs build/ClaudeBar.app.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/build/ClaudeBar.app/Contents/MacOS/ClaudeBar"
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# A temp home where setup installed ClaudeBar's status line (no status line before), with its record, and
# ClaudeBar's four folders.
fresh() {
  root=$(mktemp -d); c="$root/home/.claude"; mkdir -p "$c" "$root/home/.config/claude-bar" "$root/home/.claude/claude-bar" \
    "$root/home/Library/Caches/ClaudeBar" "$root/home/Library/Logs/ClaudeBar"
  printf '{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}' > "$c/settings.json"
  cp "$REPO/scripts/statusline-command.sh" "$c/statusline-command.sh"
  printf '{}' > "$c/claude-bar-statusline-original.json"
}

fresh; before=$(md5 -q "$c/settings.json")
out=$(echo n | CLAUDEBAR_UNDO_ROOT="$root" "$BIN" --undo 2>&1); code=$?
[ $code = 0 ] && [[ "$out" == *"[x] Restore your old status line"* ]] && [[ "$out" == *"Nothing was changed."* ]] \
  && [ "$(md5 -q "$c/settings.json")" = "$before" ] && ok "answering n changes nothing" || bad "n ($code): $out"
out=$(CLAUDEBAR_UNDO_ROOT="$root" "$BIN" --undo < /dev/null 2>&1); code=$?
[ $code = 0 ] && [[ "$out" == *"Nothing was changed."* ]] && [ "$(md5 -q "$c/settings.json")" = "$before" ] \
  && ok "no answer (EOF) changes nothing" || bad "EOF ($code): $out"

out=$(echo y | CLAUDEBAR_UNDO_ROOT="$root" "$BIN" --undo 2>&1); code=$?
has=$(plutil -extract statusLine raw "$c/settings.json" >/dev/null 2>&1 && echo yes || echo no)
[ $code = 0 ] && [[ "$out" == *"✓ ClaudeBar's status line is off, as before."* ]] && [[ "$out" == *"All done."* ]] && [ "$has" = no ] \
  && [ "$(plutil -extract model raw "$c/settings.json")" = opus ] && [ -d "$root/home/.config/claude-bar" ] \
  && ok "y restores the status line and keeps ClaudeBar's folders" || bad "y ($code, statusLine $has): $out"
rm -rf "$root"

fresh
out=$(echo y | CLAUDEBAR_UNDO_ROOT="$root" "$BIN" --undo --remove 2>&1); code=$?
left=0; for f in .config/claude-bar .claude/claude-bar Library/Caches/ClaudeBar Library/Logs/ClaudeBar; do [ -e "$root/home/$f" ] && left=$((left+1)); done
[ $code = 0 ] && [[ "$out" == *"[x] Also remove ClaudeBar"* ]] && [[ "$out" == *"Come back anytime."* ]] && [ $left = 0 ] \
  && [ -f "$c/statusline-command.sh" ] && ok "--remove moves the four folders to the Trash, keeps the script" || bad "--remove ($code, left $left): $out"
rm -rf "$root"

echo "$pass passed, $fail failed"; [ $fail = 0 ]
