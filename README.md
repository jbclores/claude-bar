# ClaudeBar

A macOS menu bar app: your Claude Code 5h / 7d usage at a glance, your pinned projects (branch, model,
context, status), and a hover peek of Cat Office's cats. Design: `docs/superpowers/specs/2026-10-06-claude-bar-design.md`.

## Install

```sh
scripts/install-statusline.sh          # status line also saves snapshots (backs up the old script)
scripts/build.sh                       # → build/ClaudeBar.app
cp -R build/ClaudeBar.app /Applications/ && open /Applications/ClaudeBar.app
```

Config: `~/.config/claude-bar/projects.json` (Add Folder… / Edit Config in the dropdown).

## Cat Office patch (same cats as the browser)

```sh
scripts/patch-cat-office.sh ~/Downloads/cat-ai-office-with-art-20261006-1038
# then restart Cat Office: stop its dev server, run `npm run dev` again
```

It does a trial run first, backs up the touched files to `<cat-office>/.cat-office/patch-backup-*`, and changes
nothing if a newer Cat Office no longer matches. To undo, copy the backed-up files back (and delete
`server/agent-bridge/cat-assignments.ts` and `tests/sim/cat-assignments.test.ts`).

## Tests

```sh
swift test                                   # unit tests
scripts/test-statusline.sh                   # status line output unchanged + snapshots
CLAUDEBAR_LIVE=1 swift test                  # also against the running Cat Office
```
