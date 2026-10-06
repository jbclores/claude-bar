#!/bin/bash
# Claude Code status line: folder, git branch, model, context/5h/7d usage bars

input=$(cat)

fields=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
w = d.get("workspace") or {}
m = d.get("model") or {}
c = d.get("context_window") or {}
rl = d.get("rate_limits") or {}
fivehour = rl.get("five_hour") or {}
sevenday = rl.get("seven_day") or {}
u = c.get("used_percentage")
fh = fivehour.get("used_percentage")
sd = sevenday.get("used_percentage")
print(w.get("current_dir") or d.get("cwd") or "")
print(m.get("display_name") or "")
print("" if u is None else u)
print("" if fh is None else fh)
print("" if sd is None else sd)
# Cat Office reads the 5h / 7d usage from here (server/agent-bridge/plan-usage.ts).
if rl:
    try:
        import os, time
        out = os.path.expanduser("~/.cat-office/plan-usage.json")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        tmp = out + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"at": int(time.time() * 1000), "session_id": d.get("session_id"), "rate_limits": rl}, f)
        os.replace(tmp, out)
    except Exception:
        pass

# ClaudeBar reads one snapshot per session from here (~/.claude/claude-bar/sessions).
def write_claude_bar_snapshot():
    import os, tempfile, time
    sid = d.get("session_id")
    if not isinstance(sid, str) or not sid or "/" in sid or sid.startswith("."):
        return
    rec = {
        "session_id": sid,
        "cwd": w.get("current_dir") or d.get("cwd") or "",
        "model": m.get("display_name"),
        "context_pct": u,
        "five_hour_pct": fh,
        "five_hour_resets_at": fivehour.get("resets_at"),
        "seven_day_pct": sd,
        "seven_day_resets_at": sevenday.get("resets_at"),
        "updated_at": int(time.time()),
    }
    base = os.environ.get("CLAUDE_BAR_DIR") or os.path.expanduser("~/.claude/claude-bar")
    out = os.path.join(base, "sessions")
    os.makedirs(out, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out, prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(rec, f)
        os.replace(tmp, os.path.join(out, sid + ".json"))
    except Exception:
        os.unlink(tmp)
        raise

try:
    write_claude_bar_snapshot()
except Exception:
    pass
')

cwd=$(printf '%s' "$fields" | sed -n '1p')
model=$(printf '%s' "$fields" | sed -n '2p')
used=$(printf '%s' "$fields" | sed -n '3p')
five_hour=$(printf '%s' "$fields" | sed -n '4p')
seven_day=$(printf '%s' "$fields" | sed -n '5p')
folder=$(basename "$cwd")

# Git branch (skip optional locks so we never block on a lock file)
branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
fi

DIM="\033[2m"
CYAN="\033[2;36m"
MAGENTA="\033[2;35m"
GRAY="\033[2;37m"
RESET="\033[0m"

SEP=" ${GRAY}│${RESET} "

# Renders a 10-segment unicode progress bar + percentage for a given usage
# value, gradient-colored green/yellow/red. Result left in $BAR_OUT.
render_bar() {
  local u="$1" label="$2" filled empty bar pct color
  BAR_OUT=""
  [ -z "$u" ] && return
  filled=$(awk -v u="$u" 'BEGIN { f = int((u/10) + 0.5); if (f > 10) f = 10; if (f < 0) f = 0; print f }')
  empty=$((10 - filled))
  bar="$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' "$empty" '' | tr ' ' '░')"
  pct=$(awk -v u="$u" 'BEGIN { printf "%.0f", u }')
  color=$(awk -v u="$u" 'BEGIN {
    if (u >= 85) print "\033[1;31m";      # red, bold
    else if (u >= 60) print "\033[1;33m"; # yellow, bold
    else print "\033[1;32m";              # green, bold
  }')
  BAR_OUT="${DIM}${label}${RESET} ${color}${bar}${RESET} ${DIM}${pct}%${RESET}"
}

out="${DIM}${folder}${RESET}"
if [ -n "$branch" ]; then
  out="$out${SEP}${CYAN}${branch}${RESET}"
fi
out="$out${SEP}${MAGENTA}${model}${RESET}"

render_bar "$used" "ctx"
[ -n "$BAR_OUT" ] && out="$out${SEP}${BAR_OUT}"

render_bar "$five_hour" "5h"
[ -n "$BAR_OUT" ] && out="$out${SEP}${BAR_OUT}"

render_bar "$seven_day" "7d"
[ -n "$BAR_OUT" ] && out="$out${SEP}${BAR_OUT}"

printf '%b' "$out"
