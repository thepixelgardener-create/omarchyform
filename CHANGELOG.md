# Changelog

Notable changes, newest first. Board file versions are noted where they moved,
since older boards are migrated on load rather than rejected.

## Unreleased

### Added

- **A trash.** Deleting a board or a folder moves it aside and records where it
  came from, so putting it back is exact rather than a guess. `t` in the
  browser shows what is in there, `enter` restores, and only `x` inside the
  trash destroys anything — asking twice, as deleting always has.
- A contract check, run in CI, that reads the names the views and the session
  reach for on the controller and fails if one is missing — including from the
  stub the QML session test puts in the controller's place. QML resolves those
  names at runtime, so a missing one is a TypeError in a suite CI cannot run.
- A randomised ordering test for saves, board switches and completions, which
  asserts that a write lands on the board it was serialised for and that the
  writer never stays busy.
- **More than one item at a time.** `space` marks the item under the cursor and
  `a` marks everything; moving, resizing, recolouring, changing shape and
  deleting then apply to the whole set. Marks are held as ids, so a delete
  cannot renumber them, and `esc` drops them. With nothing marked every command
  applies to the cursor alone, so the keys are unchanged until you ask for more.
- A line under the board says what a destructive key just did, and that `u`
  takes it back.
- Connectors point somewhere. An arrowhead is drawn at the target end, and
  drawing the same pair again turns the connector round; drawing it a third
  time, in the direction it already runs, removes it.

### Changed

- Keyboard moves and resizes are the same distance on screen whatever the
  zoom. A step was measured in the canvas, so one press moved an eighth as far
  zoomed out and four times as far zoomed in.
- Undo depth follows the size of the board. A snapshot holds the whole board,
  so a hundred steps of three thousand items held twenty-four megabytes.

### Fixed

- A completion for one board could become the baseline for another. Two empty
  boards serialise the same, so creating a board straight after switching away
  from an empty one could skip writing it.
- A save asked for while the writer was busy was dropped rather than queued.
- A save that never reports back no longer wedges the board. If `state.json`
  named a board file that had been deleted, every later save, board switch and
  the status line stuck at "saving…" with no way out.

## 0.2.0

### Added

- **A presence on the bar.** A sticky-note icon opens and closes the board
  through the shell, the same route the keybinding takes, and carries the
  accent colour while the board is open. Add it with
  `omarchy bar put thepixelgardener.omarchyform --section right`.
- **Settings**, declared as a schema on the bar entry: autosave delay,
  keyboard step, dot grid, and whether the board opens windowed. They travel
  to the board when it opens and are then remembered, so the keyboard route
  gets the same configuration.
- **Multiple boards** in a real directory tree, with a shell-like browser on
  `b`: `jk` to move, `l` to descend or open, `h` to go up, `/` to search every
  board by subsequence, `a` and `A` to create, `r` to rename, `x` to delete.
  Deleting the open board, or the folder holding it, is refused.
- **Autosave.** Structural edits write immediately; typing settles first.
  Switching boards or closing flushes whatever is pending.
- **Keyboard resize**: `ctrl` plus a movement key, mirroring `shift` plus one
  to move.
- `hypr/bindings.lua` ships with the plugin, for anyone loading plugin
  bindings rather than writing their own.
- `npm run bench`, which prints what a board costs to serialise and load.

### Changed

- **The look comes from the theme** rather than being invented: font family
  and size tokens, corner radius, border width. Items carry a theme role —
  foreground, accent, urgent, muted — instead of a fixed colour, so a board
  follows the desktop theme. Day and night follow the theme's own `mode` key,
  with luminance as the fallback for themes that omit it. *(board v3)*
- The board opens on the output Hyprland has focused, rather than wherever
  Quickshell picked.
- Loading is linear. Connectors resolved their ends by scanning the whole item
  list, so a 3000-item board took about 19ms to load and now takes about 6ms.
- Backups moved out of the boards tree into `backups/`. That tree is meant to
  be browsed, hand-edited and committed.
- Split into `Omarchyform.qml`, `Board.qml`, `Node.qml`, `Browser.qml`,
  `BoardBar.qml`, `BoardSession.qml`, `BoardPersistence.qml` and
  `BoardStore.js`.

### Removed

- `windowMode` from board files. It was written on every save and never read
  back, and it put one machine's window preference into a file meant to be
  synced.

### Fixed

- A board that could not be parsed is no longer treated as an empty one, so a
  damaged file is never overwritten by an autosave.
- An empty board is never written over a board that had contents.
- Undo beyond the first step. Rebuilding the item model tears down every
  delegate and takes the keyboard with it; focus is now reclaimed explicitly.
  The same fault affected switching boards and reopening the browser.
- Every save re-ran the loader, discarding undo history and the selection:
  `FileView.setText()` makes the view emit `loaded` again.
- Completing a save parsed the text it had just written, only to count items it
  already knew.
- Ids, sizes, positions, kinds and connectors are validated on load, so a
  hand-edited board cannot produce items with unusable geometry, duplicate ids
  that make connectors join the wrong things, or connectors to nothing.

## 0.1.0

First release. An infinite canvas with notes, shapes and connectors, undo and
redo, fullscreen or windowed, saved as plain JSON. *(board v1, then v2 when
items gained ids and shapes)*
