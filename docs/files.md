# Boards on disk and the command line

[Back to the README](../README.md) · [Install](install.md) · [Using the board](guide.md) · [Development](development.md)

## Where your board lives

```
~/.local/share/omarchyform/
├── boards/
│   ├── board.json
│   └── work/
│       └── project-a.json
├── trash/
│   ├── index.json
│   └── 20260924-133036-work__sprint.json
├── images/
│   └── paste-1758801036123.png
├── backups/
│   └── v2/
│       ├── board.json.bak
│       └── work/project-a.json.bak
└── state.json
```

Each board is plain JSON, written atomically. One generation back is kept in
`~/.local/share/omarchyform/backups/`, under `v2/`, mirroring the board directory tree — out of the boards tree, which is meant to be browsed, hand-edited
and committed without `.bak` files in the way. Older flattened backups are
left untouched; new saves use the mirrored paths to avoid naming collisions. The backup completes before replacement, and saves
with unchanged contents do not rotate it. Malformed or unsupported board files
open read-only; no edits or saves are allowed over them. Back it up, sync it,
edit it by hand, put it in git — it is your file, and a board that changes while
it is open is noticed rather than overwritten.

Every write to a board goes through one coordinated step: the file is replaced
under a lock, and only if it is still the version the writer last read. The
version it replaces is kept first. So two writers that both read the same board
cannot both believe they are updating it — the second one is told. That applies
to the plugin and to `bin/omarchyform` alike, because both go through the same
helper. Locks live in `~/.local/share/omarchyform/locks/` and never beside your
boards. This needs `flock` (util-linux) on the path, alongside the `bash` and
coreutils the plugin already uses. Older boards are migrated on load: v1 had no ids or
shapes, v2 stored fixed pastel hexes which are mapped onto theme roles. Version 4 adds
background pinning, version 5 pasted pictures; older plugin versions open these
files read-only instead of silently losing that state.

A pasted picture is written to `images/` and the item keeps only its file name,
so a screenshot is not re-encoded into every autosave — and the same picture on
four boards is stored once. A copy saved to share is the exception: it carries
the bytes in an `images` object beside the items, because a file name is not
something another machine can resolve. That key is ignored by anything that does
not know it, so such a copy still opens in an older Omarchyform. Nothing deletes
the files in `images/`: a board in the trash still points at its pictures, and so
does a copy exported last month. An item whose picture has gone says so on the board rather
than drawing an empty frame.

```json
{
  "version": 5,
  "nextId": 4,
  "items": [
    { "id": 1, "kind": "note", "x": 0, "y": 0, "w": 180, "h": 140,
      "tint": "foreground", "text": "hello", "pinned": false },
    { "id": 2, "kind": "ellipse", "x": 300, "y": 0, "w": 160, "h": 110,
      "tint": "accent", "text": "there", "pinned": false },
    { "id": 3, "kind": "image", "x": 0, "y": 200, "w": 360, "h": 203,
      "tint": "foreground", "text": "", "pinned": false,
      "src": "paste-1758801036123.png" }
  ],
  "links": [ { "from": 1, "to": 2 } ]
}
```

Connectors reference item ids rather than positions, so they survive
deletions, reordering and hand-editing. They are directed: `from` and `to`
decide which end carries the arrowhead, and only one runs between any pair.

## From the command line

`bin/omarchyform` builds and changes boards with no window and no display. The
board's logic is plain JavaScript that already runs outside QML — it is what
the test suite exercises — so the same code that draws a board can build one
headlessly. Every verb answers with JSON on stdout and exits 0 or 1. It runs on
Node.js, which the board itself never needs.

```bash
bin/omarchyform new ideas.json --note "First thought" --note "Second"
bin/omarchyform inspect ideas.json
echo '[{"op":"add","args":["ellipse",520,0,200,140,"the question","accent"]},
       {"op":"link","args":[1,3]}]' | bin/omarchyform apply ideas.json -
bin/omarchyform validate ideas.json
bin/omarchyform ops          # what apply accepts, the kinds, the theme roles
```

Boards written into `~/.local/share/omarchyform/boards/` appear in the browser
on `b`. Writing the board that is open is fine too: the board watches its file,
so a board the CLI changes appears in front of you.

If you have unsaved changes on screen as well, both versions are kept and
neither is guessed at. Autosaving stops, the header says `Changed on disk`, and
`ctrl+s` puts the three choices on screen:

| | |
|-|-|
| Keep the version from disk | what is on screen is lost |
| Save my changes as a copy | both versions survive, the copy under a name of its own |
| Replace the version on disk | the one it replaces goes to backups |

Nothing else resolves it. Leaving the board, closing it, renaming it and the
autosave timer all leave both versions where they are, and switching boards
waits until you have chosen. Until then your edits live only on screen, so the
choice is worth making rather than leaving.

The CLI is told the same way. An `apply` whose board changed between being read
and being written answers `{"ok": false, "error": "… changed since it was read"}`
and exits 1, leaving the other writer's board alone; `--force` is the explicit
overwrite, and keeps what it replaced.

It cannot draw: a picture of a board needs the running shell, so `ctrl+e`
on an open board exports a PNG and nothing here does.

`skills/omarchyform/SKILL.md` ships alongside it, so a coding agent asked to
sketch something out as a board can do it without being told any of this, and
[`docs/for-agents.md`](for-agents.md) is the long version — this same
program explained to something that drives it through files and will never see
the screen. Most of it is the part a command list cannot teach: how big a note
is, how far apart two of them have to be before they read as two, how much text
fits before it scrolls, which shape means what, and how little of a board to
tint. A board built without that reads as generated whatever is written on it.
