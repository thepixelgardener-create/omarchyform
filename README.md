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
| `c` | Cycle its colour |
| `w` | Switch between fullscreen and windowed |
| `f` | Fit the whole board on screen |
| `0` | Reset the view |
| `+` / `-` | Zoom |
| `?` / `F1` | Keybinding list |

Mouse works too: drag a note to move it, drag the canvas to pan, wheel to
zoom, double-click empty canvas for a new note, double-click a note to type in
it, drag the bottom-right corner to resize, middle-click to delete.

## Where your board lives

`~/.local/share/omarchyform/board.json`

Plain JSON, written atomically on every change, with one generation kept
beside it as `board.json.bak`. Back it up, sync it, edit it by hand, put it in
git — it is your file. A v1 board from before shapes is migrated on load.

```json
{
  "version": 2,
  "nextId": 3,
  "items": [
    { "id": 1, "kind": "note", "x": 0, "y": 0, "w": 180, "h": 140,
      "color": "#F7D794", "text": "hello" },
    { "id": 2, "kind": "ellipse", "x": 300, "y": 0, "w": 160, "h": 110,
      "color": "#A8D8B9", "text": "there" }
  ],
  "links": [ { "from": 1, "to": 2 } ]
}
```

Connectors reference item ids rather than positions, so they survive
deletions, reordering and hand-editing.

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

Freehand drawing, images, multiple boards, and selecting more than one item
at a time.

## License

MIT
