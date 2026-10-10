# Changelog

Notable changes, newest first. Board file versions are noted where they moved,
since older boards are migrated on load rather than rejected.

## 0.4.8 — 2026-10-10

### Fixed

- **Pasting into a note being typed in, the command list, find or the board
  browser reads at most 1 MiB from the clipboard.** Ctrl+V and Shift+Insert
  used Qt's own paste, which reads everything the clipboard's owner sends
  before the note's 1 MB check could count it, so an application that never
  stopped sending could exhaust the shell's memory. They now go through the
  same bounded helper as pasting onto the board. A paste that would not fit
  is refused whole with a message, a one-line field gets spaces for line
  breaks, and a paste that arrives after you stopped typing is not inserted.
  The middle button no longer pastes the primary selection into the three
  one-line fields; over a note it already panned. Found in the marketplace
  review of 0.4.7.

## 0.4.7 — 2026-10-10

### Added

- Per-item textures for notes and shapes: Plain (the default), Ruled, Grid,
  Dots, and Hatch. Kept through undo, duplication, history, sharing and PNG export.
- Canvas colours: Theme, Lighter, Darker, Paper and Ink, remembered across
  restarts and shared by both panes. Paper and Ink adapt item and text colours.

- Split view: `v` puts a second pane beside the board, `V` stacks it below, and
  the same key again goes back to one pane. Each pane has its own camera,
  selection and board; two panes on one board share it, and each keeps its
  cursor on its item when the other edits. `o` or a click moves between them.
  A board only one pane shows is saved before that pane leaves it, and two
  versions or a failed save keep the pane open. Drag the line between the
  panes to resize them; a window too small for two shows the pane you are in.
  The layout is remembered. A picture dropped on a pane goes on that pane's
  board, wherever the keyboard is.
- Boards remember their edits: every command, drag, pause in typing and undo
  is one step in a history kept in the board's file, newest 10,000 kept.
  **Forget this board's history** clears it. A board with history is format
  version 7, which older versions open read-only; boards without history or
  item textures and plain copies made to share stay version 5. A board is read-only while its history
  is checked on opening, under a second at 10,000 edits, and says **Checking
  history…**. A file another tool has reformatted or reordered keeps its
  whole board, and one whose history is from a newer Omarchyform stays
  read-only and untouched. `bin/omarchyform apply` records each run as one
  step.
- A timeline: `t` steps back through a board's history in the pane you are
  in, `space` plays it forward at up to four times the speed, and `esc` comes
  back to now. An earlier version is read-only. `T` shows one beside the board
  as it is.

### Changed

- Item creation accepts its initial content and dimensions before adding it to
  the model. Paste no longer needs a separate deferred-save path, and pasted
  notes are centered using their final size.
- The README is a short start page that asks for feedback, with issue forms
  for feedback and bugs. The manual moved word for word to `docs/install.md`,
  `docs/guide.md`, `docs/files.md` and `docs/development.md`.
- Development docs distinguish unreleased work, remaining checks and historical
  reviews. Shared history-worker test setup replaces duplicate implementations.
- Related commands open groups, while search still finds individual commands.
  Backspace with an empty query returns from a group to the full list.
- Connections have clearer arrows and highlight the selected item's links.
  Clicking a destination preserves the source; `x` confirms and Escape cancels.
- Connector drawing reuses item lookups, skips offscreen links and batches
  drawing by colour. Item fill weights are read once per theme change.

- The controller is split in three, ahead of split view: `BoardPane.qml` is
  one view of a board and the controller its views read, `BoardDocument.qml`
  is one open board with its undo history and session, and `Omarchyform.qml`
  is the workspace around them. Nothing changes on screen.

### Fixed

- Prevent late history worker replies from saving an old board under a newly opened board's path.
- Preserve valid history when one oversized edit is fully absorbed into the baseline.
- Keep import/export results with their originating pane through completion.
- Keep delayed split closures and board opens correct when focus or another pane's board changes.
- Discard foreign history on import so deleted image references cannot address local library images.
- Return structured CLI diagnostics for malformed nested history without changing boards or backups.

- Escape during a drag or resize cancels only that gesture, without also
  dismissing the board.
- Pasted notes and pictures create one complete history step, without an
  empty placeholder. Dropped pictures use the same transaction.
- External history extensions preserve open timelines, retained cursors and
  playback endpoints. Reformatted files no longer create false conflicts on
  the next external update; replacement histories close the old timeline.
- Canceled drags and resizes restore their starting state and preserve undo
  and redo. Intermediate pointer positions are not saved. Movement and resize
  key gestures finish on release, focus loss or a different command.
- Theme and bar colours explicitly use Omarchy's colour provider, avoiding a
  runtime name collision that silently substituted the fallback palette.
- A board with its format version after its history now receives the same
  version check as any other board. Newer formats cannot be opened for editing
  and overwritten as version 6 because their JSON properties were reordered.
- Malformed nested history now returns a worker error instead of leaving the
  board stuck at **Checking history…**. The existing recovery keeps the bad
  history aside and preserves the live board. Trimming failures also return
  an error without replacing the history.

## 0.4.6 — 2026-10-05

### Changed

- A note can now be at most 1 MB, the same as the largest paste. A board with
  a longer one opens read-only and says why, instead of holding the shell up,
  and one is refused on import. The editor will not grow a note past it, and
  `omarchyform add` and `setText` refuse text that long; `validate` lists a
  board's over-long note under `warnings`.

- A PNG exported in the theme's own colours drew connectors heavier than the
  board does, at 65% of the foreground against the board's 55%. Both now use
  55%, so the picture looks like the board it is of.

### Fixed

- Folders and lock files that the plugin and `omarchyform` create are now
  private, whatever umask the shell started with. Boards and backups already
  were; under a umask of 000 a new boards folder was writable by any user who
  could reach it. Folders that already exist keep the permissions they have.

- An imported board with no `images` key kept the picture names it carried, so
  its picture items could show, and a later copy with its pictures could carry,
  pictures from your own library that it named. Every import now clears picture
  names it did not bring, as one carrying pictures already did.

- A PNG export of a board with pictures could save them as empty frames and
  still say it had worked. It photographed the board a fixed 80ms after asking,
  and phone-sized photos take far longer than that to load. It now waits until
  every picture has loaded or failed to, says so when that takes a while, and
  if no picture arrives for 15 seconds gives up with a message rather than
  saving an incomplete picture.

- Every PNG export logged a `QQuickItem::stackAfter` warning in the shell's log
  for each item on the board. It now logs none for a board without
  backgrounds, and one beside each background otherwise.

- A connector whose ends were names like `toString` or `constructor` was
  accepted on load and saved back, though it joins no item. Connector ends are
  now read as item ids, and an id written as `"3"` still means item 3.

- A note with a long stretch of text and no space in it — a pasted base64
  blob, a minified file — froze the whole shell while it was laid out, for a
  time growing with the square of its length: 64 KB was long enough for the
  compositor to offer to kill it. Such a note now wraps anywhere, and opens
  in milliseconds.

- Every note laid its text out twice, once for an editor nobody had opened.
  The editor now holds a note only while it is being edited: a board with a
  1 MB note opens in 47ms rather than 870, and each edit to it takes 41ms
  rather than 255.

- `omarchyform apply` with an operation named after a built-in object method,
  such as `toString`, crashed with a stack trace instead of answering in JSON.

- While connecting, the dashed line to the selection ran between the two
  items' centres, underneath them, so where its dashes fell had nothing to do
  with the connector it was showing. It now runs edge to edge, where that
  connector will, from the same geometry the board and PNG export draw with.

- Opening a board from the file manager did nothing when its file name held a
  newline, a tab or another control character: the path broke the payload
  handed to the shell. `omarchyform-open` now escapes them, and its entry
  version moves to 2 so reinstalling replaces the old one.

- The launcher's **New board** action was written with escapes the desktop
  entry format does not allow. The shell logged a warning about it every time
  it read its applications, and GTK-based launchers could not read the action
  at all. It is escaped as the format asks, and the entry version moves to 3,
  so running `desktop/install.sh` again replaces the old entry.

- The agent guide and skill said a save from the shell would write over a
  change made to an open board, and that the command line keeps no backups.
  Neither is true: an open board reloads or asks which version to keep, and
  every command-line write keeps the version it replaced.

- Every save was followed by a second pause, as long as the save's own: the
  board noticed its file change, and wrote the whole board out again to see
  whether the change was its own save. It now recognises its own save from
  the text it already has. On a 3000-item board that check went from 41ms to
  6ms after every save.

## 0.4.5 — 2026-10-03

### Added

- Canvas patterns: choose Dots, Grid, Ruled or Plain directly in
  **Menu → Background**. Patterns follow the theme and camera. The selection
  applies immediately and persists across bar and keyboard opening.

- `npm run test:security` and `test:security:full`, with a release checklist
  covering process metadata, rendering, filesystem boundaries and retention.
  CI runs the portable security checks on pushes to main and pull requests.

### Fixed

- The plugin description names whiteboards, brainstorming, mind maps, diagrams,
  sticky notes and images so the next marketplace snapshot can match those searches.

- Board titles and other labels explicitly use plain text so filenames cannot
  become markup or cause inline image loads.
- Invalid CLI operation JSON no longer echoes parser excerpts containing input.

- Copied note text now travels through standard input to the clipboard helper
  and `wl-copy`, keeping it out of process command-line metadata.

## 0.4.0

### Added

- **Formatting by name while typing.** `ctrl+p` with a caret in a note opens the
  command list narrowed to what can be done to the words: bold, italic, drawn as
  a key, made a heading, or coloured in one of the four roles — each with its
  chord beside it where it has one, and each found by an ordinary word as well
  (`strong`, `code`, `title`). None of them is on the board's own list, and
  nothing from that list is on this one.

  **Make it a heading** puts a `# ` on every line the selection touches, or
  takes it off when they all have one. A selection that ends at the start of a
  line does not take that line in, a heading written with a tab after the `#`
  counts as one, and on a mix the lines that are headings already are left as
  they are rather than given a second mark.

- **A manual for the thing reading it.** `docs/for-agents.md` is Omarchyform
  explained to something that drives it through files and a command line and
  will never see the screen. The verbs were already documented; what was not is
  everything a generated board gets wrong for want of knowing it — that items
  are placed by their top-left corner, that a default note is 220 by 160 and
  wants 60 between it and the next one, that six short lines is what fits
  before the text starts scrolling, which shape means what, and that two or
  three tinted items on a board of a dozen is the whole budget. It also writes
  down where the command line and the keyboard differ about connectors, which
  they do deliberately: `link` is idempotent and answers `already`, while
  pressing `x` a second time removes the connector.

  `skills/omarchyform/SKILL.md` points at it and keeps its own short version.

- **A picture is now guarded by its pixels, not only by its bytes.** Everything
  about pictures was checked except the one number that decides what drawing one
  costs. A PNG of a single flat colour, twelve thousand square, is a hundred and
  thirty kilobytes on disk and about half a gigabyte decoded — under the 32 MB
  limit, sniffed as a genuine `image/png`, small enough to travel inside a
  shared board, and nothing downstream could decline it: Qt's PNG reader does
  not do scaled reading, so asking it for less does not get less.

  The dimensions are read out of the header now — PNG, GIF and BMP each keep
  them at a fixed offset, which is exact and needs nothing installed — and a
  picture over forty megapixels, or over twenty thousand on a side, is refused
  with its own exit code and its own message. "Too large" over a hundred
  kilobyte file reads as a bug rather than as a limit. All three ways a picture
  arrives are held to it: dropped, pasted, and unpacked from a board somebody
  else made, which is the one nobody chose.

  The limit is generous on purpose. Sixteen megapixels still goes on a board;
  this is a bound, not a suspicion of large pictures. JPEG and WebP keep their
  dimensions behind a walk of the file, so those are left to the byte limit and
  to Qt's JPEG reader, which does scale while decoding.

- **What a note is allowed to cost.** The markup below is applied to text that
  arrives from a board file, and a board file comes from whoever sent it. The
  escaping was already the right shape — everything from the file is escaped
  before any syntax is applied — but nothing bounded how much of it the parser
  was handed: `fillItems` takes a note's text as it finds it, with no limit, and
  every note now goes through a parser on the way to the screen.

  The item still keeps every character, because truncating somebody's note on
  load would lose what they wrote. What is bounded is the parse: 4000
  characters, which is more than twenty times what fits in a note that size and
  is all anyone can see of it.

  Hostile notes are now driven through QML's own engine rather than only the
  one the store suite runs in — a different stack and a different regex
  implementation, so the store's word for it was not enough. Tags, entities,
  quotes where an attribute would be, two thousand levels of nesting and a
  hundred thousand characters: the board renders, and the next note after it
  draws normally. The assertion is that stripping the handful of tags this code
  emits leaves no angle bracket at all, rather than a list of tags to be afraid
  of — `href` and `onload` do appear in that output, as text, which is the
  point.

- **A note can say more than its words.** A board of twenty notes was twenty
  identical rectangles with identical text in them, and no amount of arranging
  fixed that. Notes now carry a small markup: `# a line` is a heading, `*bold*`
  and `_italic_` are emphasis, `` `a key` `` is drawn in the accent the way
  every key in this shell is, and `[accent]…[/]` puts a span in one of the
  theme's four roles.

  Roles rather than colours, for the same reason items carry roles: a board
  follows whatever theme the desktop is wearing, and there is still no way to
  put a hex colour into a board file. An exported picture draws them in whatever
  palette it was asked for, so a note's accent is the light palette's blue on
  white and the board's own accent on the board.

  While typing, `ctrl+b`, `ctrl+i` and `ctrl+k` put a mark round the selection
  and take it off again when pressed a second time; `ctrl+1` to `ctrl+4` colour
  it. Nothing selected leaves the caret between the marks, which is how a bold
  word gets started rather than finished.

  The safety is the order, and it is the one the status line already used.
  Everything arriving from a board file is escaped before any of this is
  applied — a board is a file other people can send you, and the note is the
  part they write — so no tag anyone else wrote survives to reach the renderer.
  A note saying `<b>hello</b>` shows those characters.

  You see the marks while the caret is in the note and the note once it leaves.
  The text being edited and the text being looked at have to be the same string,
  or the caret lands where the characters are not.

- **The editor takes the board's version back.** Typing into a note replaces
  the binding that filled it, so after the first keystroke it held its own copy.
  Anything that changed the item since was invisible there: an undo restored the
  note on screen, which reads the item directly, and left the editor showing
  what had just been undone. It re-reads the item each time the caret arrives.

- **A picture of part of a board, in colours that are not the desktop's.** A
  board is drawn in whatever theme the desktop is wearing, which is usually
  dark, and a dark picture is the wrong thing to put in a document, a slide or
  a printout. The command list now offers the same export **on white**, **on
  black** and **in black and white** beside the one that keeps the board's own
  colours. Each is its own command rather than a mode to be in, so `:` and a
  few letters — `white`, `print` — reach the one you want, and there is nothing
  new on the board to look at.

  The palettes are written out rather than blended from the theme. A fill is
  its tint mixed into the background it sits on, which is right for a board
  that has to match the desktop it belongs to and is mud on a page it was never
  chosen for. What an item says is at least 13:1 against the fill behind it in
  every palette, and every border and connector clears 3:1 against the page;
  `tests/suite.js` holds them there rather than trusting the eye that picked
  them.

  **Mark items first and the picture is of those**, framed around them with the
  same padding an export has always had. Connectors leaving the marked set
  leave with it, so what comes out is what was chosen rather than whatever
  happened to be beside it and got cut off at the edge. Backgrounds are the
  exception: a pinned shape is scenery, so a cluster lifted off a board keeps
  the panel it was sitting on, and the frame is not put round it — a background
  is usually most of the board, and framing to it would undo the crop. Nothing
  marked is still the whole board.

  The live suite reads the picture back: the page of one asked for on white is
  white, and the one framed around a single note of two is narrower than the
  board. Neither is a thing a count of ink can see.

- Super+C and Super+V are the primary copy/paste shortcuts in the help and
  command palette. The canvas accepts them directly; Ctrl+C and Ctrl+V remain
  available. Omarchy’s universal clipboard bindings continue to work.

- **What can be done with what is selected, on `.` or a right-click.** The same
  panel the command palette uses, narrowed to the commands that act on a
  selection — shape, colour, connect, duplicate, pin or unpin, layer order,
  delete — and with every answer the `g` chord has offered by name, so aligning
  two notes no longer needs the second key of a chord you have not learned. It
  is the one command table, filtered: there is no second list to keep in step.

- **Bring things forward, send them back.** `]` and `[` move the selected items
  one step through the order overlapping things are drawn in; `}` and `{` take
  them right to the front or the back. Several at once keep their order relative
  to each other, so a group that overlaps itself moves as a group. Ids and
  connectors are untouched — this moves rows in the board, which is what the
  order has always been — so it survives saving, reopening, duplicating and
  exporting, and undo puts it back. Pinning stays a separate thing: a background
  is still a background afterwards, reordered among the other backgrounds.

- **Every command by name, on `:`.** The keys are quick once they are in the
  hands and useless before that: a board you have not opened in a month was a
  list of letters to remember, and the header menu only ever held six of them.
  `:` — or `ctrl+p`, or **Commands** in that menu — opens a list of all of them.
  Type to narrow it, `enter` runs the highlighted one, `esc` closes it. It costs
  no height until it is asked for, the same bargain the menu makes.

  The list shows each command's key, so it teaches the keyboard while it is
  used, and a command that cannot run at this moment is dimmed and says what it
  is waiting for instead of appearing to do nothing. The commands are one table
  in `BoardStore.js` that the palette dispatches through, and `tests/contract.js`
  checks every entry against the key table in `Board.qml` and the controller
  itself — so a key that moves, or a function that is renamed, cannot leave the
  list teaching something that is no longer true.

- **The command palette's query is a real text field too**, with the same caret
  keys, selection, clipboard and input-method composition the other two have.
  The keys the panel owns — enter, escape, the arrows, tab — go back to it
  through one function, so a letter typed at the palette cannot reach the board
  behind it. Unavailable commands now say what they are waiting for beside
  their key, the row the keyboard is on carries a `›` as well as a tint, and the
  controls this work touched carry accessible names, roles and actions.

- **The find box and the name box are real text fields.** Both were a string
  that grew at the end with a cursor drawn after it, so neither could be moved
  through, selected in, pasted into, or typed in a language that needs an input
  method — and a board can be written in one. They are `TextInput`s now, which
  brings the caret keys, selection, the clipboard and composition with them.
  Renaming opens with the current name selected, so one keystroke still replaces
  it and an arrow key now edits it instead. The keys the board owns — `esc`,
  `enter` — are handed back to it from one place, so a field that has somehow
  not been given the keyboard cannot leave `esc` meaning "close the board".

- **A copy saved to share carries its pictures.** A board in the library keeps
  only the file name of a picture, so a screenshot is stored once however many
  boards use it — and a copy sent to someone else arrived as a board of holes,
  because a file name means nothing on a machine that has never seen your
  `images/`. `ctrl+shift+s` now writes the bytes into the copy, base64 in an
  `images` object beside the items, and `ctrl+o` writes them into your own
  `images/` under names it picks before pointing the board at them.

  Not a format bump: a key an older Omarchyform does not know is a key it
  ignores, so such a copy still opens there with its pictures missing exactly as
  they are missing today. A name that did not land is cleared rather than left
  alone — a name from somebody else's board must never end up addressing a
  picture in your library that happens to share it — and a picture that will not
  decode is reported instead of leaving a hole. A board whose pictures come to
  more than 16 MB is copied without them and says so, because half a board's
  pictures is not something the person saving it could act on.

  A pasted picture is held to the same 32 MB limit a dropped one always was. The
  clipboard can hold a screenshot of a 4K desktop, and only one of the two ways
  in was checking.

- **A board you were sent opens by double-clicking it.** The installer now
  registers a file type and a small `omarchyform-open` command beside the
  launcher entry, and the board accepts a path from the shell — so a file
  manager can hand one over. Opening brings it into your library rather than
  editing it where it sits, which is what `ctrl+o` has always done.

  A board in the library stays an ordinary `.json`; a copy saved to share is
  `*.omarchyform.json`, and that is what is recognised. Claiming `*.json`
  outright would hand every JSON file on the machine to a note-taking program.
  Boards also carry a `kind` marker now, written first so a file can be
  identified by its contents — not a format bump, so an older Omarchyform
  still opens them, and older boards pick it up on their next save.

- **Boards from the command line.** `bin/omarchyform new | inspect | apply |
  validate | ops` builds and changes boards with no window and no display,
  answering with JSON on stdout and exiting 0 or 1. The board's logic was
  already plain JavaScript running outside QML — it is what the test suite has
  always exercised — so this is a front end over code that was already there
  and already tested. It cannot draw: a picture of a board needs the running
  shell.

  `skills/omarchyform/SKILL.md` ships with it, so an agent asked to sketch
  something out as a board can, which is the idea borrowed from omashow.

  Every board the CLI writes is checked against `readFile`, `fillItems` and
  `fillLinks` — the three calls the plugin makes on the way to drawing — and
  the live suite now builds a board with the CLI before the shell starts and
  has the running shell open it.

- `npm run bench:scene` prints what it measured on before what it measured —
  Qt, Quickshell, the compositor, the refresh rate, the GPU, the CPU — and
  `--record` writes that and the table to `docs/performance.md`. Every frame
  time this changelog quotes was measured on one machine at one refresh rate,
  and none of it said so: the same board is vsync-bound at 60Hz and dropping
  frames at 144, so a figure without the machine under it is not a number
  anyone can check. Borrowed from omashow's `bin/sbom`, which records the
  versions its published numbers were measured against.

- **A scroll mark on the panels that scroll.** The shortcut list and the board
  browser both run past their panel, and neither said so: the list ended
  mid-row, and a directory of thirty boards looked like a directory of twenty.
  A slim rule down the inside edge now says how much there is and how far down
  it you are, and appears only when something is out of sight. It is a mark,
  not a scrollbar — these panels are driven from the keyboard, and a thumb that
  invites a grab it does not answer is worse than no thumb at all. The wheel
  and a drag still work as they did.

- `npm run bench:scene` measures what a board costs to *draw*, at size:
  delegates, bindings and both canvases, driven through panning, zooming,
  dragging, marking and finding, reported as milliseconds per frame. `npm run
  bench` only ever measured marshalling, which is arithmetic over an array and
  was never the problem — which is why the thing that was went unnoticed. Like
  `shots`, it asserts nothing and is not part of `tests/run`.

- The live smoke test checks the exported PNG has the board in it rather than
  only that the export reported success. An item that draws itself as nothing
  still exports at the right size, so neither the file nor its dimensions would
  have noticed. `tests/png.js` reads the picture back with nothing installed,
  Node's own zlib being enough.

- `npm run shots` photographs the plugin in every state worth judging by eye, in
  any theme, into
  `~/.cache/omarchyform/shots/`. It asserts nothing and is not part of
  `tests/run`; it is for the questions only eyes answer.

  `--hold` takes the pictures and then leaves the board on screen, on the
  isolated boards that run built, carrying one of everything a pointer can be
  pressed on. It is there for `docs/pointer-checks.md`: a pointer cannot be
  synthesised into a running compositor from this repository, so whether the
  middle button reaches the fullscreen overlay and the windowed toplevel is
  checked by hand — and must not be checked on the installed plugin or on real
  boards.

  Closing it ends the run. The first version of it did not: hiding a window is
  not closing a board, so the process stayed up with nobody watching it and a
  scratch tree nobody removed. It follows the controller's own state now rather
  than any one surface's, which is also why moving between fullscreen and
  windowed no longer looks like leaving — one surface goes and another arrives,
  and the board was never closed. Dismissing it waits for what it was writing
  and exits; a write that fails, or will not finish in five seconds, says which
  and exits non-zero instead of hanging. `Ctrl-C` closes the board first and
  then cleans up. Each run removes its own directory by name, never a pattern,
  so a second held board in another terminal keeps its boards.
  A successful held run now requires both readiness and completion markers.
  Setup timeouts and unexpected child signals fail; Ctrl-C exits 130 and SIGTERM
  exits 143 after cleanup. The runner prints its child PID, and the interruption
  test verifies that exact process has exited. Deterministic subprocess tests
  cover failure exits, missing markers, interruption and forced termination.
  `npm run test:hold` drives the live lifecycle without a hand on the keyboard.

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

### Fixed

- **The README removes the plugin in an order that works, and says what it
  runs.** It had you remove the plugin and then run the desktop entry's
  uninstaller, which removing the plugin had just deleted; the uninstaller now
  comes first, by its full path. It said the desktop installer writes one file,
  where it writes three and refreshes the launcher and file-type caches, and it
  listed `wl-clipboard` for pasting alone. Copying out needs it too, pictures are
  recognised with `file`, and the command line runs on Node.js, which nothing in
  the plugin itself starts.
- **What is drawn on top is what the board says is on top.** On a board that
  starts with a background, which is how one is usually built, bringing an item
  forward could change the file and leave the screen as it was until the board
  was next loaded. Each item was stacked after the one before it on the board,
  and that fails when the one before is a background, which lives in the layer
  underneath. Items are now stacked by their place on the board.
- **The two-versions question holds all it says.** Its height counted two of
  the gaps between its lines and not the other two, so with room for its line
  of hints that line sat on the panel's bottom edge, and in a small window the
  last choice ran past it. A board name long enough to wrap the question onto a
  fourth line now gives way instead of a choice. The command list was see-through
  at 0.92, and the board's own text read faintly behind its rows; it is solid.
  Both open below the line under the header rather than a fixed distance under
  the header, where the second row of a wrapped hint line drew over them.
- **The board is framed below the hint line, not only the header.** `f`, and
  keeping the selection in view, framed the board from the bottom of the header;
  but the line of hints sits under it and wraps in a narrow window, so the top
  row of a board could land behind the hints. Both frame from below everything
  laid over the canvas now: the header, the backgrounds banner, and the hint
  line or the find box.
- **A paste is bounded while it is read, not after.** Text from the clipboard is
  capped at 1 MiB and a picture at 32 MiB as the bytes arrive, so an oversized
  paste is refused whole rather than collected first or cut short into a partial
  note. A pasted picture's type is read from its content, as a dropped file's
  already was, and a picture is never moved over a file that is already there.
  A BMP stored top-down is measured by its real height rather than as enormous
  and refused.
- **Part of the live smoke test was not running, and nothing said so.** Its
  stages are numbers matched down one if/else chain, and two of them were used
  twice. The second of each pair was unreachable, so whether the blocks between
  them ran at all came down to which branch the timing picked: a tick that
  arrived while a write was in flight fell past the first `62` to the second,
  and skipped the pin run entirely — that a pinned item draws in the background
  layer, that pinning is saved to disk, that mark-all passes backgrounds over,
  that background selection reaches one, and that unpinning puts it back. Five
  assertions, silently not run, on a suite that reported ok.

  The stages in that run are their own numbers now, and a check counts them:
  no duplicates, nothing branched on that is never set.

  The same timing was the long-standing flake in that suite. Stages waited for
  `saving` to be false, which is not waiting for a write — it reads false
  before one starts as well as after one ends, so under load the check ran
  against the file as it was before the change and failed on "and the file says
  so too". They wait for the write itself now: armed before the thing that
  causes it, satisfied only once one has both started and finished. Four runs
  under a mutation pass, which is what used to fail it.

- **The export gate was measuring the display.** The live smoke test asked what
  fraction of the exported picture was not its commonest colour and wanted a
  fifth. An export is the board's bounds plus padding, and one of the two notes
  in that board is pasted — which lands at the centre of the *view*. So on a
  wider window the notes ended up further apart, the frame grew, and the same
  complete export scored less: on one screen the notes fell 728px apart and it
  came out at 16% against a threshold of 20%. It failed there and passed
  everywhere else, and nobody watching it pass could have told.

  The board is pinned to a fixed shape before the export now, so the frame does
  not depend on the window at all. And what is asked of the picture no longer
  depends on the frame: each item's own rectangle is measured instead. A note
  fills its rectangle with its tint blended into the canvas, so one that drew
  reads about 100% and one culled out reads 0%, with no threshold in between to
  tune. Connectors are checked at the midpoint between the two notes, where
  nothing else draws, and a corner of the padding is checked for being clean —
  ink there means the frame does not line up and nothing else measured meant
  anything.

  `tests/export.js` is the gate itself under test, on pictures built in memory
  rather than on a desktop: each fault caught separately, at three scales
  including a fractional display scale, plus the old whole-frame score kept as
  a measurement to show why it was the wrong question. Until now the only thing
  ever demonstrated about that gate was that it passed.

- **The line under the header is decided in one place.** Its precedence was
  written out twice: once in the view that draws it, and once in the controller,
  which has to know whether a failure is on screen so that it can stop timing
  one that is not. The two disagreed about a closed board, and a failure
  reported into one spent its six seconds where nobody could read it — the exact
  thing the timer exists to prevent. `Store.statusTier` answers it now, for both,
  from one state the controller gathers; the view only joins and colours what it
  is told. The order is unchanged, and `tests/suite.js` walks every tier against
  every tier below it, so one quietly moving down the list is caught here rather
  than by somebody watching the board.

- **Copying out and pasting in are two operations.** They shared a failure kind,
  so a copy that worked took down "clipboard has no available text" as though it
  had answered it. A clipboard that accepted a copy says nothing about there
  being anything in it to paste.

- Each newly reported failure gets a fresh six-second display interval. Replacing
  a visible failure no longer inherits the previous message's expiry deadline.
  Failures received while the board is closed still wait until it opens.

- **A failure no longer waits behind whatever you started next.** Ranking the
  connector outcome above a flash fixed a stale "Duplicated" covering it — and
  would have buried a clipboard that never answered under the same rule, because
  both arrive on the same property. A subprocess answers on its own time: by
  then the person is somewhere else on the board, and a failure they were not
  looking at is one they never learn about.

  The producers say which is which now, at the point they know. `BoardExchange`
  answers on `finished` or on `failed`, and both carry which operation they are
  about — the clipboard, a board file, a picture, a PNG — so a later success can
  take down the failure it recovered from and leave the others alone. Copying
  something out after the clipboard would not answer means the clipboard is
  working; saving a PNG says nothing about it. Severity is never read out of the
  words: "Could not" is a phrase, not a type, and `tests/contract.js` refuses a
  call site that does not name a kind from the list.

  A failure sits under the four things that stop the board saving — a failed
  write, a trash index that will not save, two versions of a board, a board that
  could not be read — and above everything the person has started since. Its
  time only runs while it is the thing on screen, so it cannot expire behind a
  conflict, under the browser, or while the board is closed. A live regression
  closes the board for seven seconds and checks the failure after reopening.
  Escape takes it down once nothing else is
  waiting for escape, which means the keystroke that dismisses an answer is
  never also the one that closes the board.

- **The line under the header stopped promising the wrong thing.** A flash sits
  on the line for two and a half seconds, and it outranked the connector
  outcome: press `x`, connect two notes, press `x` again on a pair that already
  has one, and "connector removed · u to undo" was still on screen while the
  next gesture was being aimed — the one line that says what the next keystroke
  will do, saying what the last one did instead.

  The order was the cause, and it was inconsistent: three of the modes were
  ranked above a flash and the rest below it, which also put a message that
  fades in front of two things that do not. It reads in four tiers now — the
  board is not being saved and here is why, then what the keyboard is about to
  do, then what it just did, then what it is busy with. So a failed write, a
  conflict with the version on disk and a board that could not be read are no
  longer covered by a flash or by a mode that stays open, which matters because
  each of those stops the session saving at all; and typing outranks a held
  connector, because while there is a caret in a note, `x` is the letter x.

  Starting a connector also drops whatever the line was holding, so a message
  from the previous gesture cannot come back out from underneath this one when
  it finishes. Its own timer is still what expires it: nothing held back
  reappears later than it would have.

- **A middle-drag over an item no longer deletes it.** Middle-drag was the pan
  gesture on the canvas, and a middle-click on an item removed it, so the same
  motion moved the view or destroyed what it happened to begin on — and the
  destructive reading was the one that needed no movement at all. Middle-click
  deletion is gone. The board now takes the middle button once, on a surface
  above the canvas and below the header and the panels, and hands the pointer's
  screen displacement straight to the camera. So a middle-drag pans wherever it
  starts — bare canvas, a note, a shape, a picture, a pinned background, a
  resize grip, a note being typed in — and a middle-press that never moves does
  nothing at all: it does not select, move, resize, type into, paste into or
  delete what it lands on.

  Taking the button in one place rather than declining it in each is the point.
  An item that merely ignored the press would still have swallowed it, and the
  editor inside a note being typed in would still have pasted the primary
  selection into it, which is what the middle button means to a text field on
  this platform. Nothing under the pan surface is ever offered the button.

  Deleting is `del`, `backspace`, **Delete** in the command list, or the
  actions panel on `.` — all of them undone with `u`, as before. Left-drag
  selection and movement, the marquee, the resize grip, right-drag panning,
  right-click and the wheel are unchanged, and the header, the command list,
  the conflict panel, the browser and the help panel each take every button
  pressed on them rather than letting the canvas slide about behind them.
  `tests/qt/tst_pan.qml` drives the whole board with a pointer — four zoom
  levels, every kind of thing a gesture can start on, and the chrome — and
  `tests/qt/tst_node.qml` checks that an item lets the button through instead
  of only that it does nothing with it.

- Pasted and dropped pictures now finish loading onto the canvas. The image
  probe explicitly reads its own status instead of the status label in scope.
  Added a live canvas regression for repeated pastes, undo/redo and saving.

- Conflict resolution now reads the latest disk content and its revision under
  the same lock as writes. Late replies cannot replace another board or newer
  local edits. Failed replacements retain the disk snapshot and local edits,
  and a save rejected during board switching cancels the pending switch so
  resolution restores editing. Controller, filesystem and real QML regressions
  cover these paths.

- **A copy saved to share is a picture of one moment.** Collecting a board's
  pictures takes long enough for the board to change underneath it: the export
  read the live models *after* the pictures came back, so editing or switching
  boards while it ran mixed two moments into one file. Everything the export
  needs — the board as text, the pictures it names, which board it was and where
  it is going — is taken when it starts and carried through every step, and an
  answer belonging to an export that is no longer running is dropped rather than
  published.

- **A portable copy carries everything it names, or is not written.** A missing
  picture, or pictures over the 16 MB a copy can carry, used to publish a copy
  without them and mention it in a line that fades. Both now refuse before the
  destination is touched, and **Save a copy without its pictures** is a separate
  thing to ask for by name.

  Coming the other way, a file over 32 MB is refused by its size before it is
  read; a picture over 32 MB, or a set over 16 MB, is refused from the length of
  its base64 rather than by decoding it; and a board carrying a picture that
  cannot be read is refused whole rather than imported with items pointing at
  nothing. The file you were given is never touched either way. Boards without
  pictures — which is every board written before this — import as they always
  did.

- **Nothing resolves two versions of a board except choosing between them.**
  Watching the file caught a board that changed underneath, but the flag that
  said so was cleared by `flushSave()` — which closing, switching boards and
  renaming all call. So walking away from a board wrote over the other version
  without anyone deciding to. Flushing is routine again and resolves nothing;
  switching boards waits for the choice; and the choice is three named
  outcomes, on screen with what each one costs: keep the version from disk,
  save your changes as a copy under a name of their own, or replace the version
  on disk and keep what it replaced in backups. A resolution that fails puts
  the question back with the edits still in hand.

- **Every write to a board is coordinated.** Watching a file cannot be enough on
  its own: a write can land before its notification arrives. Both the plugin and
  `bin/omarchyform` now go through one helper that takes a lock, checks the file
  is still the revision the writer read, keeps the version it is replacing, and
  renames the new one into place. Two writers that read the same board cannot
  both believe they are updating it — the second is refused and told, and the
  CLI says so in its JSON and exits 1 rather than winning by arriving later.
  `--force` is the explicit overwrite. This adds `flock` (util-linux) to the
  `bash` and coreutils the plugin already needed.

- **The command line and an open board no longer overwrite each other.** The
  CLI writes a board straight to disk; the board kept its own copy in memory
  and never looked at the file again, so `omarchyform apply` on the board you
  had open was undone by your next keystroke, and the reverse lost whatever the
  CLI had just written. The open board watches its file now. With nothing
  unsaved on screen the newer version simply appears — run the CLI against the
  open board and you watch it change. With changes on both sides the screen is
  kept and autosave stops, the header says `Changed on disk` and the board says
  what `ctrl+s` will do; an explicit save, or leaving the board, decides for the
  screen and the version it replaces goes to backups like any other.

  The CLI writes through a temporary and renames it into place, because
  something watching the file must never be able to read half a board. A write
  it cannot make is now an answer — `{"ok": false, …}` and exit 1 — instead of a
  stack trace, and nothing is left beside the board.

- Import and export had no way to report a failure. Three error paths called an
  `exchange.fail()` that was never written, and a staging write that failed had
  no handler at all — so a board that could not be read, a file that was not a
  board, and a full disk each raised a `TypeError` or nothing, left the busy
  flag set, and stranded importing and exporting for the rest of the session.
  There is a `fail()` now: it clears the flag and says what happened.

- The contract check reads what each file calls on itself. It had always
  compared the names the views read off `ctl` against the controller, but a file
  addressing itself by its own id was checked by nothing, which is how three
  calls to a function that did not exist sat in `BoardExchange` until a review
  found them. Only calls are checked: a property read off an id can come from
  the base type, a method almost never does.

- A picture dropped just before a board switch could land on the wrong board.
  Each queued drop already remembered the board it was let go of, but the check
  ran before the copy rather than after it, and the size the scene measures
  comes back later still — so switching boards while a drop was in flight put
  the picture on whatever was open when the measurement arrived, at a point that
  was never on that board. The board is carried all the way through both
  queues now, and anything answering for a board that has closed is dropped
  with a line saying so.

- CI installs `qml6-module-qtquick-shapes`, which the board now needs. It ships
  inside `qt6-declarative` on a real Omarchy machine, so there is no new
  dependency for anyone installing the plugin — only for the Ubuntu runner,
  which installs its QML modules one package at a time.

- The contract check reads the Qt layout test's stand-in controller too. It
  covered the controller, the session's stub and the one the PNG export
  draws against, but not the stub that drives the toolbar, the help panel and
  the browser — so a member missing from that one was caught by nothing.
  Reading an undefined colour off it is silent on Qt 6.11 and fatal on the 6.4
  CI runs, which is a green suite locally and a red one on push. Four members
  had been missing from it for some time.

- Clicking near the edge of the shortcut panel closed it. The panel is a plain
  rectangle, which lets a click through, and its scroller stops short of the
  border — so the ring between the two reached the layer that dismisses the
  help. It holds on to its own clicks now, from underneath the scroller, where
  it costs neither the wheel nor the drag.

- `npm run mutate` reported 100% no matter what. `tests/mutant-run.js` reached
  for `require("./run")` and found the extensionless `tests/run` shell script
  beside it rather than `run.js`, which threw above the `catch` that reads an
  exit code as a killed mutant — so every mutant "died" on the same syntax
  error and none of them ran. It names `run.js` now; the true score is 87.5%,
  and the survivors it had been hiding are printed.

- `desktop/install.sh` was committed without its executable bit, so the
  `./desktop/install.sh` the README gives you failed with permission denied on
  every clone. The bit is committed now, and a test asserts it survives.

### Changed

- **The panels are drawn the way the shell draws its own.** The command list,
  the browser, the shortcut list and the two-versions question sit on a solid
  card in the menu's colours, inside the theme's border for summoned surfaces —
  so under a theme with a gradient edge they wear the gradient, as the Omarchy
  menu beside them does, where each had drawn a grey hairline of its own. The
  board dims behind every one of them by the shell's own amount. The keyboard
  cursor in their lists and in the header menu is the menu's too: a soft fill,
  with the row's label in the accent, where it had been a band of accent. The
  `›` stays, so the cursor never depends on telling two colours apart.

  The lists have the menu's rows as well: fifty pixels at least, a glyph for
  every command, the name at heading size, and the prompt written in the field
  until you type over it — "Run a command…" — where it had said `run:` in the
  small print the rows were in. Keys sit beside the names in the text colour
  rather than the accent, which the shell keeps for the row the cursor is on;
  the scroll mark is the text colour too. The command list and the browser use
  the menu's font, so `OMARCHY_MENU_FONT` reaches them.

  The shortcut list is in eight sections under small bold labels, with a rule
  between, as the shell's panels break a long list. The header's zoom, menu
  button and menu entries are the shell's soft-filled buttons rather than bare
  words. The two-versions question has the ordinary edge, as the shell's own
  confirmation dialog does, and says it is urgent in its heading — the theme's
  urgent colour, behind a warning mark — instead of a red frame.
- **Tints take the shell's own weights.** How strong an item's wash and hairline
  are comes from `Style.normalFillAlpha`, `Style.selectedFillAlpha` and
  `Style.normalBorderAlpha`, the weights the shell's own surfaces use, rather
  than from numbers of this plugin's own for light and dark themes. A plain note
  stays quiet enough that its text carries the hierarchy, and a tinted one gets
  a little more ink. The rule across the top of a note is one border wide
  rather than three.
- The picture at the top of the README is of a board built through
  `bin/omarchyform` and retaken with the current header, rather than five shapes
  placed by hand.
- **The command list answers to the ordinary word as well as its own.** The
  names say what a command does in the board's words — "Type in it", "Mark
  everything", "Name this board" — and searching for the word every other
  program uses found nothing: `edit` matched no command at all. Commands now
  carry optional search aliases, and the list matches them from their start
  after it has matched names and keys, so `edit`, `select all`, `add to
  selection`, `rectangle`, `rename`, `link`, `unlink` and `disconnect` each
  find what they mean. Nothing dispatches by an alias and no visible label
  changed: it is a way in, not a second name. Names and keys keep the order
  they had, a command appears once however many of its fields match, and the
  scope a selection's action panel is narrowed to is still checked first, so an
  alias cannot smuggle an unrelated command into it.

- **The board says what a connector gesture is about to do.** Only one
  connector runs between any pair of items, so drawing one is three different
  operations depending on what is already there: it creates, it reverses, or it
  removes. While the far end is being chosen the line under the header now says
  which — "x connects these two", "x turns this connector round", "x removes
  this connector" — and says "pick the other end" when there is no valid one
  yet, including on a background or on the item the gesture started from. The
  line and the change ask one shared question of one table, so the promise
  cannot drift from what happens; `esc` still cancels without touching the
  board. The help list and the README now distinguish removing one connector
  this way from `X`, which removes every connector on an item at once, and say
  that the far end is walked to with `tab` or `hjkl` — a click starts a fresh
  selection, which has always ended the gesture without drawing anything.

- **Ellipses and diamonds are drawn as geometry rather than as a picture of
  geometry.** They were painted into a `Canvas`, which rasterises at the
  item's own size — and the board then magnifies that texture with its world
  transform, so a shape went soft the moment you zoomed into it. Measured at
  400% on the same pixel row: the outline crossed fifteen interpolated pixels
  and nineteen shades of red, while the selection ring beside it, an ordinary
  `Rectangle`, changed colour in one pixel. As a `Shape` it crosses none and
  takes four — background, stroke, stroke, fill — and looks like the notes
  around it at any zoom.

  It also drops the plumbing. The canvas repainted itself from seven
  `Connections` handlers, one per property that could change how it looked,
  and an eighth property meant remembering to add an eighth handler. The
  replacement is bindings, and the path itself is arithmetic in `BoardStore.js`
  where a diamond that misses its own corners can be caught by a test rather
  than by eye.

  The grid and the connectors stay on `Canvas`: they are drawn in screen
  space, once per frame, at the size they are displayed, so they were never
  the ones going soft.

  It is not free. Qt re-tessellates a `Shape` when the scale it is drawn at
  changes, which is exactly what keeps it crisp, so zooming costs more on
  boards with many shapes on screen at once: unchanged within noise at a
  thousand items, and about a quarter slower at three thousand, where zooming
  was already far from smooth. `Shape.CurveRenderer` would likely remove that,
  and needs a Qt floor of 6.6 — see the note on the version gap below.

- **The hint lines name their keys the way btop does.** The key a command
  answers to is coloured inside the word that names it, so the word carries
  the key rather than saying it twice: `note`, `rect`, `ellipse`, `menu`,
  `Fit`, `rename`, `the trash`. Where the key does not lead the word — `esc`,
  `/`, `x`, a two-key chord — it is still named in front, because a colour
  cannot point at a letter that is not there. A key in the *middle* of a word
  was tried and dropped: lighting the `a` of `board` read as a rendering fault
  rather than as a cue, so `a` and `A` name what they do instead, `add board`
  and `Add folder`, and lead those.

  These lines are drawn as markup now, so everything reaching them from a
  board file, a file name or the keyboard is escaped on the way in. The board
  itself still refuses rich text outright; this is the one place that renders
  tags, and nothing that arrives from a board can open one.

- **A board costs what is on the screen, not what is on the board.** Marking
  everything on a thousand-item board froze it for two thirds of a second, and
  a search froze it for half of one: every item on the board restyled itself —
  a ring to draw, a fill to blend, an opacity to change — whether or not it was
  anywhere a person could see it. An item outside the viewport now reads as
  unmarked, as no match, and at full strength, and is not drawn at all, so the
  scene graph can skip it instead of walking it. It tells the truth again the
  moment the camera reaches it, and the cursor and whatever is being typed in
  stay live wherever they are, because the keyboard can walk the selection off
  the edge of the screen.

  Measured with `npm run bench:scene`, 95th-percentile milliseconds per frame
  at a thousand items: marking 638 → 58, finding 503 → 64, dragging everything
  94 → 40. Marking a three thousand item board now costs less than marking a
  hundred-item one used to. What is left scales with the window, not the board.

- Marks are held as a set beside the list rather than searched for in it, the
  find query is lowered once per keystroke rather than once per item per
  keystroke, and a batch of items moving asks for one repaint rather than two
  per item. Each of these was a real cost and none of them was the cost: they
  are here because they are plainly right, not because the numbers moved.

- The install instructions no longer force the bar icon to the right. `omarchy
  plugin add --enable` asks which section to put it in — left, center or right
  — and the README said to follow it with a command that names one. It now says
  to answer the question, and gives `omarchy bar move` for changing your mind
  or for an install that never asked.

- **`d` no longer deletes.** It sat in the key table beside `s`, `c` and `e`,
  so a finger one key out destroyed what it was aiming at. `del` and
  `backspace` do it, as they did before and as they do everywhere else.

- **The shortcut list reads as two columns.** Titled "Keyboard shortcuts", with
  the keys right-aligned in the theme's accent and the descriptions left-aligned
  beside them, so the eye can run down either column. The key column is measured
  from the widest label rather than guessed at, and never takes more than half
  the panel. The panel itself is opaque now — the canvas under it can be
  translucent, and a shortcut list read through a wallpaper is not one.

- **The menu can be walked from the keyboard.** `h` `l` or `tab` move along it,
  `enter` picks, `esc` closes; the item the keyboard is on takes the accent the
  pointer's hover does, so both read the same. The dispatch moved to the
  controller, so a click and an `enter` cannot diverge, and the command list is
  one definition shared with the header.
- **Secondary text is readable whatever the theme.** The save state, the zoom
  and a missing image's name used the theme's `muted` token, which a theme is
  free to set almost to its own background — azure-glow does, giving 1.28:1,
  near enough invisible. They are the foreground held back to 0.85 now. In the
  header that is 9.9:1 on that theme and 4.7:1 at worst, on rose-pine, across
  the 24 themes installed here — all past the 4.5:1 the guidelines ask for body
  text.
- **All the chrome is at the top.** The status and hint line moved from the
  bottom edge to directly under the header, so the board's name, its commands
  and whatever it is telling you are one block to look at, and the bottom of the
  canvas belongs to the board. In background mode it sits under the mode banner
  rather than behind it.
- **The header wears the theme's bar colour.** `bar.background` and `bar.text`
  from the theme's `shell.toml`, so the board's own menu bar reads as the same
  kind of surface as the bar it was opened from, and a theme that gives its bar
  a background of its own gets it here too. It had been the canvas colour, and
  briefly transparent, which let the dot grid run through the chrome and made
  the header look like part of the board rather than something sitting on it.
- **The header is one line.** The board's name, in bold, and its save state sit
  on the left; the zoom and the menu sit on the right, where they stay however
  long the name is — where the name, the state and a row of six buttons used to
  take three stacked rows and most of the bar's height. The zoom is always shown,
  and clicking it fits the board to the window. The menu is a button: `m` or a
  click opens it as a row of its own under the name, and it closes again when a
  command is picked or `esc` is pressed. In a narrow window the save state steps
  aside, unless what it has to say is that a save failed.
- The README now says plainly that a rescan cannot be trusted to replace a
  plugin's loaded QML, and to restart the shell after changing it. The first
  version of this note blamed compile failures; a second case then showed a
  version that compiled fine also going unreplaced by `omarchy plugin update`,
  so the advice is no longer conditional. Lists the three symptoms of a shell
  running something other than what is on disk.
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
