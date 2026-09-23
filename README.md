# Omarchyform

A visual idea platform native to Omarchy.

An infinite canvas. Notes, shapes and connectors on a board you can pan and
zoom, driven from the keyboard, stored as a plain JSON file on your own disk.

Think Apple Freeform, except it is keyboard-first, it matches your Omarchy
theme, and nothing leaves the machine.

## What it is

A native Quickshell plugin. It runs inside the long-running `omarchy-shell`
process — no webview, no Electron, no second Quickshell instance, nothing
running when the board is closed.

It has two surfaces, and `w` switches between them:

- **Fullscreen** — a Hyprland layer-shell overlay above everything, with its
  own keyboard grab. Summon it, think, dismiss it.
- **Windowed** — an ordinary toplevel, so Hyprland tiles it beside your editor
  and browser like any other app.

The camera, the notes and the selection are shared, so toggling never loses
your place. The mode is remembered between sessions.

## Install

```bash
omarchy plugin add https://github.com/thepixelgardener-create/omarchyform.git --enable
```

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + I", "Omarchyform", "omarchy-shell shell toggle thepixelgardener.omarchyform")
```

Check the key is free first with `omarchy menu keybindings --print`, and
validate afterwards with `hyprctl reload && hyprctl configerrors`.

## Keys

Press `?` or `F1` on the board for this list.

| Key | Does |
|-----|------|
| `n` | New note beside the selected one, ready to type |
| `r` / `e` | New box / ellipse |
| `s` | Cycle the shape: note, box, ellipse, diamond |
| `x` | Connect: press on one item, then on another |
| `X` | Remove every connector on this item |
| `u` / `ctrl+r` | Undo / redo |
| `enter` / `i` | Type in the selected note |
| `esc` | Stop typing; again to close the board |
| `h` `j` `k` `l` | Move the selection to the nearest note that way |
| `H` `J` `K` `L` | Push the selected note around |
| `tab` | Cycle through every note |
| `d` / `del` | Delete the selected item |
| `c` | Cycle its theme role: foreground, accent, urgent, muted |
| `b` | Boards: browse, open, create |
| `w` | Switch between fullscreen and windowed |
| `f` | Fit the whole board on screen |
| `0` | Reset the view |
| `+` / `-` | Zoom |
| `?` / `F1` | Keybinding list |

Mouse works too: drag a note to move it, drag the canvas to pan, wheel to
zoom, double-click empty canvas for a new note, double-click a note to type in
it, drag the bottom-right corner to resize, middle-click to delete.

## Boards

`b` opens the board browser: a shell-like walk through your boards directory.

| Key | Does |
|-----|------|
| `j` `k` | Move the cursor |
| `l` / `enter` | Enter a folder, or open a board |
| `h` / `backspace` | Go up a level |
| `/` | Search every board in the tree, not just this folder |
| `a` | New board here |
| `A` | New folder here |
| `r` | Rename |
| `x` twice | Delete (refuses the open board and folders containing it) |
| `g` / `G` | First / last |
| `esc` | Leave the search, then close the browser |

Search is a subsequence match over the whole path, so `wpa` finds
`work/project-a`. While you are searching, letters go into the query — press
Escape first if you want `a`, `r` or `x`.

The browser opens in the folder of the board you are on, and the board you are
on is marked `·open`.

## Saving

There is no save key, though `ctrl+s` works if you want one. Structural
changes — adding, deleting, moving, connecting — are written immediately.
Typing settles for 700ms first, so a sentence is one write rather than forty.
Switching boards or closing flushes whatever is pending. Board switching waits
for writes to finish. A failed backup or write leaves the board open in memory
and shows an error; use `ctrl+s` to retry. Closing the surface keeps an in-flight
save running in the shell; it does not wait for disk completion.

Which board you had open is remembered in `state.json` and reopened next time.

## Where your board lives

```
~/.local/share/omarchyform/
├── boards/
│   ├── board.json
│   └── work/
│       └── project-a.json
└── state.json
```

Each board is plain JSON, written atomically, with one generation kept beside
it as `<board>.json.bak`. The backup completes before replacement, and saves
with unchanged contents do not rotate it. Malformed or unsupported board files
open read-only; no edits or saves are allowed over them. Back it up, sync it,
edit it by hand, put it in git — it is your file. Older boards are migrated on load: v1 had no ids or
shapes, v2 stored fixed pastel hexes which are mapped onto theme roles.

```json
{
  "version": 3,
  "nextId": 3,
  "items": [
    { "id": 1, "kind": "note", "x": 0, "y": 0, "w": 180, "h": 140,
      "tint": "foreground", "text": "hello" },
    { "id": 2, "kind": "ellipse", "x": 300, "y": 0, "w": 160, "h": 110,
      "tint": "accent", "text": "there" }
  ],
  "links": [ { "from": 1, "to": 2 } ]
}
```

Connectors reference item ids rather than positions, so they survive
deletions, reordering and hand-editing.

## It looks like Omarchy, because it asks Omarchy

Nothing about the appearance is invented here. The board takes the theme's
font family and its size tokens, so it follows `omarchy display text size`
like the rest of the desktop. Corners come from `Style.cornerRadius` (square
by default) and borders from `Style.normalBorderWidth`.

Items carry a **theme role** — `foreground`, `accent`, `urgent` or `muted` —
rather than a fixed colour, drawn as a translucent wash plus a hairline of the
same role. Switch your theme and the board switches with it. `c` cycles the
role.

**Day and night** is not a setting here either. Omarchy themes declare
`mode = "light"` or `mode = "dark"` in their `colors.toml`; the board reads
that and adjusts the weight of its washes and its dot grid accordingly. A
third-party theme that omits `mode` falls back to the background's Rec. 709
luminance.

## Layout

| File | Holds |
|------|-------|
| `Omarchyform.qml` | Controller: state, storage, and the two surfaces |
| `Board.qml` | The canvas surface — grid, connectors, keys, cheat sheet |
| `Node.qml` | One item: note, box, ellipse or diamond |
| `Browser.qml` | The board browser |
| `BoardStore.js` | Pure logic: parsing, marshalling, geometry. No QML |
| `BoardPersistence.qml` | Serialized backup and atomic write, with completion/failure signals |

## Tests

The pure logic lives in plain JavaScript so it can be tested without Qt, and
the suite loads the very file the plugin loads — there is no copy to drift.

```bash
npm test        # pure logic and controller regression tests, no dependencies
npm run mutate  # mutation testing
npm run test:qml # headless persistence tests; requires installed Quickshell
```

`npm run mutate` breaks `BoardStore.js` on purpose, one edit at a time, and
checks the suite notices. The command reports its current score and survivors;
it is a diagnostic, not a CI failure threshold.

Controller tests evaluate the actual QML JavaScript functions with delayed I/O
completion to cover damaged files, queued edits, board switching, and retry.
The separate `test:qml` suite runs the real persistence component in an isolated
headless Quickshell instance with temporary files. It checks backup contents,
write ordering, failure handling, and retry; it does not interact with the
running desktop shell. CI runs the Node tests; run `test:qml` on a machine with
Quickshell before release.

## Notes on the platform

Omarchy is pre-release and the shell's `qs.Commons` / `qs.Ui` singletons are
internals, not a versioned API. Every read of them here goes through a guard
with a hardcoded fallback, so a rename upstream costs a wrong colour rather
than a board that will not open. An import disappearing entirely is still
fatal — QML has no optional imports.

The overlay is built through `Variants` so its surface is constructed with its
screen already set, and it opens on whichever output Hyprland has focused.
Assigning `screen` to a window that already exists leaves it unmapped.

## Dependencies

None beyond Omarchy itself. No network access, no external services, no
elevated privileges, no background process.

## Development

```bash
git clone https://github.com/thepixelgardener-create/omarchyform.git
cp -r omarchyform ~/.config/omarchy/plugins/thepixelgardener.omarchyform
omarchy-shell shell rescanPlugins
omarchy plugin enable thepixelgardener.omarchyform
```

Validate before publishing:

```bash
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I "$OMARCHY_PATH/shell" Omarchyform.qml
```

`qmllint` reports `qs.Commons` / `qs.Ui` import failures and
`PanelWindow is not creatable` — both are expected, since it cannot resolve
the shell's own modules outside the running shell.

Note that `keepLoaded: true` means a saved edit does not replace an overlay
that is already loaded. Use `omarchy restart shell` to pick up changes.

## Not there yet

Freehand drawing, images, and selecting more than one item at a time.

## License

MIT
