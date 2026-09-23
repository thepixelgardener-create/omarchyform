# Omarchyform

An infinite canvas for Omarchy. Sticky notes on a board you can pan and zoom,
driven from the keyboard, stored as a plain JSON file on your own disk.

Think Apple Freeform, except it is keyboard-first, it matches your Omarchy
theme, and nothing leaves the machine.

## What it is

A native Quickshell `overlay` plugin. It runs inside the long-running
`omarchy-shell` process on a Hyprland layer-shell surface — no webview, no
Electron, no second Quickshell instance, nothing running when the board is
closed.

## Install

```bash
omarchy plugin add https://github.com/YOURNAME/omarchyform.git --enable
```

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + I", "Omarchyform", "omarchy-shell shell toggle omarchyform")
```

Check the key is free first with `omarchy menu keybindings --print`, and
validate afterwards with `hyprctl reload && hyprctl configerrors`.

## Keys

Press `?` or `F1` on the board for this list.

| Key | Does |
|-----|------|
| `n` | New note beside the selected one, ready to type |
| `enter` / `i` | Type in the selected note |
| `esc` | Stop typing; again to close the board |
| `h` `j` `k` `l` | Move the selection to the nearest note that way |
| `H` `J` `K` `L` | Push the selected note around |
| `tab` | Cycle through every note |
| `d` / `del` | Delete the selected note |
| `c` | Cycle its colour |
| `f` | Fit the whole board on screen |
| `0` | Reset the view |
| `+` / `-` | Zoom |
| `?` / `F1` | Keybinding list |

Mouse works too: drag a note to move it, drag the canvas to pan, wheel to
zoom, double-click empty canvas for a new note, double-click a note to type in
it, drag the bottom-right corner to resize, middle-click to delete.

## Where your board lives

`~/.local/share/omarchyform/board.json`

Plain JSON, one entry per note, written atomically on every change. Back it
up, sync it, edit it by hand, put it in git — it is your file.

```json
{
  "version": 1,
  "notes": [
    { "x": 0, "y": 0, "w": 180, "h": 140, "color": "#F7D794", "text": "hello" }
  ]
}
```

## Dependencies

None beyond Omarchy itself. No network access, no external services, no
elevated privileges, no background process.

## Development

```bash
git clone https://github.com/YOURNAME/omarchyform.git
cp -r omarchyform ~/.config/omarchy/plugins/omarchyform
omarchy-shell shell rescanPlugins
omarchy plugin enable omarchyform
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

Freehand drawing, images, shapes, connectors between notes, multiple boards,
undo. Notes and the canvas are the foundation those sit on.

## License

MIT
