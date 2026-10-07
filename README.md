# ClaudeBar

A macOS menu bar app: your Claude Code 5h / 7d usage at a glance, your pinned projects (branch, model,
context, status), and a hover peek of Cat Office's cats. Design: `docs/superpowers/specs/2026-10-06-claude-bar-design.md`.

## Run it (no admin password needed)

```sh
git clone <this repo> && cd claude-bar
scripts/run.sh             # checks the tools, builds, and opens ClaudeBar from this folder
scripts/run.sh --install   # or: copy it to ~/Applications and run it from there
```

- **Needs:** a Mac on macOS 14 or newer, and Apple's Command Line Tools with Swift 6 (you have them if `git` works;
  else `xcode-select --install`, which may need IT on a company Mac).
- **No IT credentials:** building happens in this folder, and `~/Applications` is your own folder, not the system
  `/Applications`. A ClaudeBar you build yourself doesn't get macOS's "unidentified developer" warning.
- **First launch:** the Set up ClaudeBar window finds your Cat Office and turns on usage (see below).
- **Updating:** `git pull`, then `scripts/run.sh` again (with `--install` if you installed); it quits the old one.
- **Start at login:** tick Launch at Login in Settings. Use `--install` first, so it doesn't point into this folder.
- **Don't use `swift run`:** it leaves out the setup scripts, sounds and guide that `scripts/build.sh` bundles.

Doing it by hand: `scripts/build.sh` builds `build/ClaudeBar.app`; copy it to `~/Applications` and open it.

Config: `~/.config/claude-bar/projects.json` (Add Folder… / Edit Config in the dropdown).

## Setting up ClaudeBar

On first launch ClaudeBar opens a small **Set up ClaudeBar** window (Welcome → Find Cat Office → Connect → Done). It
finds your Cat Office (or lets you choose its folder, or say you don't use it), then on Connect offers to patch Cat
Office, turn on usage in the menu bar (Claude Code's status line; your own is kept, ClaudeBar reads its data
quietly), and start Cat Office. Nothing on your Mac changes until you click Continue on Connect.

- **Skipping:** "Skip for now" (or closing the window) skips setup; it won't open by itself again. A Mac that's already
  set up (Cat Office known and the status line in place) never sees the window.
- **Reopening:** Settings → **Set up ClaudeBar…**, or the card in the Office tab ("Cat Office isn't set up yet · Set
  up…", or "Some extras are off · Fix…" when the patch or usage is off).
- **Undo the status line:** Settings → **Restore my old status line** (shown only after setup replaced or wrapped a
  status line you already had, while that change is still in place).
- **Click test** (temp folders only, offscreen): `build/ClaudeBar.app/Contents/MacOS/ClaudeBar --test-setup`.

The scripts below still work for doing it by hand.

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

Each floor is drawn from that Cat Office's own layout (`building.json` and its catalogues), so a teammate's ClaudeBar
shows their office. When Cat Office changes how rooms are laid out, re-run the fixtures
(`npx tsx <claude-bar>/scripts/room-fixtures.ts <in-dir> <out.json>` from the Cat Office folder) and `swift test`.

## Tests

```sh
swift test                                   # unit tests
scripts/test-statusline.sh                   # status line output unchanged + snapshots
CLAUDEBAR_LIVE=1 swift test                  # also against the running Cat Office
```
