#!/bin/bash
# Installs scripts/statusline-command.sh as ~/.claude/statusline-command.sh, keeping a backup.
# Refuses when the installed script has changed since scripts/fixtures/statusline-original.sh was taken
# (other tools, like Cat Office, edit it too): merge those changes into the repo copy first.
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="$HOME/.claude/statusline-command.sh"
NEW=scripts/statusline-command.sh
ORIGINAL=scripts/fixtures/statusline-original.sh

if cmp -s "$TARGET" "$NEW"; then echo "Already installed."; exit 0; fi
if [ -f "$TARGET" ] && ! cmp -s "$TARGET" "$ORIGINAL"; then
  echo "$TARGET has changed since it was copied into this repo; not overwriting." >&2
  echo "Diff it against $ORIGINAL, merge the change into $NEW and the fixture, then rerun." >&2
  exit 1
fi
backup="$TARGET.backup-$(date +%Y%m%d-%H%M%S)"
[ -f "$TARGET" ] && cp -p "$TARGET" "$backup" && echo "Backup: $backup"
cp "$NEW" "$TARGET"
echo "Installed $TARGET"
