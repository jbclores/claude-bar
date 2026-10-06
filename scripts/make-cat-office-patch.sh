#!/bin/bash
# Regenerates patches/cat-office.patch from a pristine and a patched copy of Cat Office.
# Usage: make-cat-office-patch.sh <pristine-dir> <patched-dir>
set -euo pipefail
ORIG="${1:?pristine dir}"; WORK="${2:?patched dir}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/patches/cat-office.patch"
FILES=(
  server/agent-bridge/cat-assignments.ts
  server/agent-bridge/index.ts
  server/agent-bridge/types.ts
  src/agents/live/actions.ts
  src/agents/live/useAgentCats.ts
  tests/sim/cat-assignments.test.ts
)
: > "$OUT"
for f in "${FILES[@]}"; do
  a="$ORIG/$f"; [ -f "$a" ] || a=/dev/null
  diff -u --label "a/$f" --label "b/$f" "$a" "$WORK/$f" >> "$OUT" || true
done
echo "Wrote $OUT ($(grep -c '^+++ ' "$OUT") files)"
