# Example boards

Two boards built with `bin/omarchyform` — the command line, not by hand — and
drawn through `BoardImage.qml`, the same scene `ctrl+e` exports, in Omarchy's
default Tokyo Night colours.

| Board | What it is |
|---|---|
| `how-omarchyform-works.json` | The whole program on one board: open, make, arrange, format, keep. 28 items, 9 connectors. |
| `omarchy-logo.json` | The Omarchy wordmark, drawn from Omarchy's own `logo.txt`: one box per run of blocks, 71 in all. |

To open one, copy it into your library and press `b` on the board:

```bash
cp examples/*.json ~/.local/share/omarchyform/boards/
```

On an open board, `ctrl+o` opens one from wherever it is instead.

The pictures beside them are what those boards look like. Yours will follow
whatever theme your desktop is wearing.

The logo is Omarchy's, from `logo.txt` in
[basecamp/omarchy](https://github.com/basecamp/omarchy) (MIT).
