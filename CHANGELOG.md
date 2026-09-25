# Changelog

Notable changes, newest first. Board file versions are noted where they moved,
since older boards are migrated on load rather than rejected.

## Unreleased

### Added

- `npm run shots` photographs the plugin in twelve states, in any theme, into
  `~/.cache/omarchyform/shots/`. It asserts nothing and is not part of
  `tests/run`; it is for the questions only eyes answer.

### Changed

- **The header is one line.** The board's name and save state sit on the left,
  the menu after them, the zoom on the right — where the name, the state and a
  row of six buttons used to take three stacked rows and most of the bar's
  height. The menu is hidden until `m` shows it, and closes again when a command
  is picked or `esc` is pressed. Closed, it leaves a clickable `menu · m` behind,
  so the commands are still reachable without knowing the key.
- The README said a rescan recreates overlays, which holds for a working plugin
  but not for one the shell has already failed to compile: that failure outlives
  `rescanPlugins` and a reinstall, and only `omarchy restart shell` clears it.
  Documented with the two symptoms that identify it and where the shell logs the
  original error.
- **Selection no longer borrows the item's colour.** A tinted item sitting idle
  could look more selected than the cursor did, because selection worked by
  brightening and thickening the item's own border — which an accent tint
  already does. The cursor is now a solid ring outside the item and a secondary
  mark a lighter one, in one colour at one width whatever the item is tinted.
  Drawn for ellipses and diamonds too, where an outline on the shape itself is
  hard to follow.
- Background mode said the same thing twice, in two different wordings: the
  banner now names the mode and the footer carries the keys, as it does for
  every other mode.
- The "more text than fits" marker was an ellipsis in the text colour, which
  read as punctuation belonging to the note. It is a small tinted tab now, in
  the opposite corner from the resize grip.
- The footer mentions `/`, and every footer line uses one separator style.

### Added

- **`ctrl+c` copies out.** A picture on its own goes to the clipboard as a
  picture, so it can be pasted into anything that takes an image; anything else
  goes as its text, several items arriving as paragraphs in board order. The
  round trip with `ctrl+v` is closed in both directions.
- **Pictures can be dragged onto the board** from a file manager or a browser,
  landing where they are let go of. Several at once are copied one at a time and
  staggered rather than stacked. The type is read from the file's content rather
  than its name, the destination name and folder are chosen here, and a file that
  is not a picture or is over 32 MB is refused with a reason.
- **`/` finds a note by its text.** Typing narrows as you go: the first match is
  selected and centred, matches take the accent outline, and everything else
  recedes the way it does in background mode. `enter` steps through the matches
  and wraps; `esc` puts the board back. It is navigation rather than editing, so
  it works on a board that opened read-only.
- **`g` arranges what is marked.** Then `h` `j` `k` `l` for an edge, `c` or `m`
  for centres on one line, or `H` `J` `K` `L` to spread them evenly with the
  outermost two staying put. The footer says what the second key can be while it
  waits, and anything else cancels rather than running its usual command.
- **`ctrl+d` duplicates.** The copies land offset from their originals and
  become the selection, so duplicating and then pushing the copy somewhere is
  two commands. A connector is copied when both of its ends were; an image copy
  points at the same file rather than duplicating it.

## 0.3.0

### Fixed

- A pasted picture was placed half its own width away from where it was meant to
  go: the item was centred at its default size before its real size was known.
- **The board opens again.** The marquee rectangle declared `left` and `top`,
  which are final on `Item`, so the shell refused `Board.qml` outright and the
  board did not open on a real desktop. `tests/run` and CI now fail on any
  member that shadows a final one.

### Changed

- **The desktop entry installer owns only what it wrote.** It refuses to replace
  a launcher entry someone else put at that path, or its own entry that you have
  edited since, and says what it found; `--force` replaces it once you have
  decided. `--uninstall` removes it under the same rule. Previously it
  overwrote whatever was there and left the file behind on removal.
- The README documents the one external dependency, `wl-clipboard`, which
  `ctrl+v` has always needed. It previously claimed none.

### Added

- **Pictures on the board.** `ctrl+v` now asks the clipboard for an image
  before it asks for text, and drops it at its own proportions. The file is
  written beside the boards in `images/` and the item keeps only its name, so a
  screenshot is not re-encoded into every autosave; a board whose picture has
  gone says so instead of drawing an empty frame. Board format v5 carries
  `src`; v1–v4 boards still load.
- **Getting things in and out.** `ctrl+shift+s` saves a copy of the board
  anywhere, `ctrl+o` reads one back as a new board, `ctrl+e` renders it to a
  PNG, and `ctrl+v` turns the clipboard into a note. Imports never overwrite
  the board you are on.
- **Capture before naming.** `ctrl+n` opens a new board already waiting for its
  first note, and `F2` names it once the thought is down. A desktop entry with
  a *New board* action does the same from a launcher.
- A header showing which board is open and whether it is saved.

- Background pinning: `p` pins items behind the working canvas; `Shift+P`
  selects backgrounds to unpin. Normal edits and mark-all skip pinned items.
  Board format v4 preserves pinning; v1–v3 boards still load.
- Shift-click marking; pointer dragging and resizing respect marked items.
- Regression coverage for restore collisions, unsafe paths, delayed saves,
  background pinning and board-local selection.

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

- Switching boards while a slow save is still running waits for the save
  instead of being silently dropped.
- A broken trash index no longer stops the browser opening folders and boards;
  only restoring from the trash waits for it to be repaired.
- A boards, backups or trash folder that is itself a symlink works again. A
  board reached through a symlinked folder inside the boards folder is refused
  on load and shown read-only, rather than opening and then never saving.
- Restore refuses occupied destinations without discarding the trash entry.
  Filesystem operations reject traversal and symlink components, and browser
  mutations serialize their pending metadata. Trash index write failures are
  visible and retryable.
- Slow saves retain exclusive writer ownership until completion. Marks reset
  on board switches and history restoration.
- Backups mirror board paths under `backups/v2/`; older backups are retained.
- Ellipse and diamond connectors meet their outlines. Undo has a 100-step cap.
- Qt UI tests now reject runtime TypeErrors and validate the Node test fixture.

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
