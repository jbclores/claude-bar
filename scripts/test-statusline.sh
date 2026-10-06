#!/bin/bash
# Checks scripts/statusline-command.sh: terminal output identical to the original script,
# and a snapshot file written per session (nothing written without a session_id).
set -uo pipefail
cd "$(dirname "$0")/.."
NEW=scripts/statusline-command.sh
OLD=scripts/fixtures/statusline-original.sh
fail=0
check() { if [ "$1" = ok ]; then echo "PASS $2"; else echo "FAIL $2"; fail=1; fi; }

work=$(mktemp -d)
proj="$work/My Project"
mkdir -p "$proj" && git -C "$proj" init -q -b feat/x
export CLAUDE_BAR_DIR="$work/bar"
# Both scripts also write ~/.cat-office/plan-usage.json: keep that inside the temp folder.
export HOME="$work/home"; mkdir -p "$HOME"

full=$(cat <<JSON
{"session_id":"abc-123","cwd":"$proj","workspace":{"current_dir":"$proj"},"model":{"display_name":"Opus 5.5"},
 "context_window":{"used_percentage":61.2},
 "rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1791280000},"seven_day":{"used_percentage":18.5,"resets_at":1791500000}}}
JSON
)
no_limits=$(cat <<JSON
{"session_id":"def-456","workspace":{"current_dir":"$proj"},"model":{"display_name":"Sonnet 5.5"}}
JSON
)
no_id=$(cat <<JSON
{"workspace":{"current_dir":"$proj"},"model":{"display_name":"Sonnet 5.5"}}
JSON
)

for name in full no_limits no_id; do
  input="${!name}"
  a=$(printf '%s' "$input" | bash "$OLD")
  b=$(printf '%s' "$input" | bash "$NEW")
  [ "$a" = "$b" ] && check ok "same output ($name)" || check bad "same output ($name)"
done
b=$(printf 'garbage' | bash "$NEW"); a=$(printf 'garbage' | bash "$OLD")
[ "$a" = "$b" ] && check ok "same output (invalid json)" || check bad "same output (invalid json)"

snap="$CLAUDE_BAR_DIR/sessions/abc-123.json"
if [ -f "$snap" ] && python3 -I - "$snap" "$proj" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["session_id"] == "abc-123" and d["cwd"] == sys.argv[2], d
assert d["model"] == "Opus 5.5" and d["context_pct"] == 61.2, d
assert d["five_hour_pct"] == 42 and d["five_hour_resets_at"] == 1791280000, d
assert d["seven_day_pct"] == 18.5 and d["seven_day_resets_at"] == 1791500000, d
assert isinstance(d["updated_at"], int), d
PY
then check ok "snapshot written with all fields"; else check bad "snapshot written with all fields"; fi

snap2="$CLAUDE_BAR_DIR/sessions/def-456.json"
if [ -f "$snap2" ] && python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["five_hour_pct"] is None and d["context_pct"] is None and d["model"]=="Sonnet 5.5"' "$snap2"
then check ok "snapshot without rate limits has nulls"; else check bad "snapshot without rate limits has nulls"; fi

count=$(ls "$CLAUDE_BAR_DIR/sessions" | wc -l | tr -d ' ')
[ "$count" = 2 ] && check ok "nothing written without session_id, no temp files left" || check bad "file count is $count, expected 2"

[ -f "$HOME/.cat-office/plan-usage.json" ] && check ok "Cat Office usage file still written (sandboxed)" || check bad "Cat Office usage file still written"
rm -rf "$work"
exit $fail
