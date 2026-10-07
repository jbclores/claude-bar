# ClaudeBar

A macOS menu bar app: your Claude Code 5h / 7d usage at a glance, your pinned projects (branch, model,
context, status), and a hover peek of Cat Office's cats. Design: `docs/superpowers/specs/2026-10-06-claude-bar-design.md`.

## Install

```sh
scripts/install-statusline.sh          # status line also saves snapshots (backs up the old script)
scripts/build.sh                       # → build/ClaudeBar.app
mkdir -p ~/Applications && rm -rf ~/Applications/ClaudeBar.app && cp -R build/ClaudeBar.app ~/Applications/
~/Applications/ClaudeBar.app/Contents/MacOS/ClaudeBar --launch-at-login on   # or tick it in the dropdown
open ~/Applications/ClaudeBar.app
```

`~/Applications` needs no admin rights (use `/Applications` if you have them). After a rebuild, quit ClaudeBar
and copy the new build over the old one.

Config: `~/.config/claude-bar/projects.json` (Add Folder… / Edit Config in the dropdown).

## Cat Office patch (same cats as the browser, found wherever it lives)

To move Cat Office and patch it in one go (stops it, moves it, patches it, updates the config, starts it):

```sh
scripts/move-cat-office.sh ~/Downloads/cat-ai-office-with-art-20261006-1038 ~/Documents/projects/cat-ai-office-with-art-20261006-1038
```

Or patch it where it is:

```sh
scripts/patch-cat-office.sh <cat-office-folder>
# then restart Cat Office: stop its dev server, run `npm run dev` again
```

The patched Cat Office writes `~/.cat-office/bridge.json` (address, token, its folder) while it runs, so ClaudeBar
finds it on any port and remembers its folder for starting it after a move.

It does a trial run first, backs up the touched files to `<cat-office>/.cat-office/patch-backup-*`, and changes
nothing if a newer Cat Office no longer matches. To undo, copy the backed-up files back (and delete
`server/agent-bridge/cat-assignments.ts` and `tests/sim/cat-assignments.test.ts`).

## Floors

The Office tab and the hover peek show Cat Office's building one floor at a time: idle cats in the Lounge, working
cats on their project's floor (else the Desk pool), helpers beside their parent. The floor menu, ▲▼ and the strip pick
a floor; Follow (on whenever the dropdown opens) shows where things happen. Cats ride the elevator between floors.

## Tests

```sh
swift test                                   # unit tests
scripts/test-statusline.sh                   # status line output unchanged + snapshots
CLAUDEBAR_LIVE=1 swift test                  # also against the running Cat Office
```
