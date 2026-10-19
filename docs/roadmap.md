# Roadmap

Updated 2026-10-19. This is the current release direction. The dated
[architecture review](architecture-review-0.4.5.md) and
[competitor analysis](competitor-analysis-0.4.5.md) explain the findings behind it.

## 0.4.5 — Canvas appearance and discoverability

This release improves the canvas appearance and prepares the directory listing.

- **Background choices — shipped in 0.4.5:** dots, square grid
  and ruled lines, with a plain option. Patterns follow the theme and camera;
  **Menu → Background** remembers the choice. Dots remain the default.
- **Directory discoverability — live:** the directory describes the plugin as
  a whiteboard for brainstorming, mind maps and diagrams; see
  [listing notes](marketplace-listing.md).

## 0.4.6 — Reliability, from the 0.4.5 review

Shipped. The follow-ups from the [architecture review](architecture-review-0.4.5.md)
and a security pass; the [changelog](../CHANGELOG.md) has each one.

- PNG export waits for every picture instead of a fixed 80ms.
- Long notes no longer hold the shell up; a note is at most 1 MB.
- The board and the export draw connectors from one geometry.
- The board library is its own component, `BoardLibrary.qml`.
- New folders and locks are private under any umask; the launcher's
  **New board** action is escaped as desktop entries require.

## Maintenance still open

- **Display-only nodes:** the PNG export draws `Node.qml` against a stand-in
  controller with empty editing methods (review finding 2).
- **Reads from slow storage:** a board read blocks the shell for as long as the
  read takes. 1ms on a local disk; network storage is unmeasured.
- CI rejecting new lint diagnostics.
- **Opening time:** a board of 5,000 notes takes 6 to 11 seconds to open, and
  about half a minute when every note has a long preview; it is read-only
  until then.
- **Stalls the hostile boards still measure** (`KNOWN` in `tests/hostile.js`):
  20,000 connectors on screen take 2.5 to 3.8 seconds to draw, and checking
  a 32 MB board's text before reading it takes 1.3 to 2.5.

These are planned. Completed changes are recorded in the changelog.

## 0.4.7 — Split view, history and canvas customization

Shipped.

- Side-by-side and stacked panes, board history and timeline playback.
- Per-item textures, canvas colours and grouped commands.
- Connector item-index caching, offscreen rejection and drawing grouped by colour.
- Confirming a connection after selecting its destination with the pointer.
- A short README start page with feedback forms; the manual moved to `docs/`.

The [split-view plan](splitview-timeline-plan.md#gate-6-results) records the
follow-up fixes and checks. External file-manager drops are now disabled
pending a bounded drag transport; use clipboard image paste. IME composition
is still unverified. A fully textured
3,000-item board is [measured](performance.md#fully-textured-large-board--2026-10-09),
with frame-rate limits recorded. Boards with history or textures use format 7.

## 0.4.8 — Bounded paste in text fields

Shipped. Every text field reads a paste through the clipboard helper's 1 MiB
limit instead of Qt's unbounded reader, from the marketplace review of 0.4.7;
see the [security review](security-review.md#marketplace-review-of-047).

## 0.4.9 — Hardening from the marketplace review

Shipped. From the follow-up reviews of 0.4.8: external drops are refused
before Qt reads them, the one-line fields no longer read the clipboard when it
changes, and a PNG carrying compressed text is refused, including one already
in the images folder. A board holds at most 5,000 items, 20,000 connectors and
32 MB, nothing the shell reads as JSON can crash it, and the plugin's folders
are private on existing installs too. The [security review](security-review.md#before-submitting-to-the-marketplace)
has the checks to run before submitting. Changing the bar's **Open in a window
rather than fullscreen** setting now takes effect after the first open too.

## 0.4.10 — Tiled by default

Shipped. The board opens as an ordinary tiled window, after feedback that a
forced fullscreen got in the way; `w` still switches to the overlay and back.

## 0.4.11 — History removed

Shipped. The edit history, its timeline and **Forget this board's history** are gone:
they cost more than they gave, and a board shared with an item id near the
largest there is could stall the shell for 25 seconds when the timeline
opened. A board's old history is ignored, and left out at its next save. New items on a board with that largest id now get ids it keeps.

## 0.5.0 — Plain-text notes and private board names

Shipped. Notes are plain text: formatting is gone, after a shared board could
make its parser hold the shell for 8 seconds. Board file operations go through
a Python helper that takes every name on stdin, so a board's title no longer
shows in the process list. The board stops before reading anything when its
folders cannot be made private, and says what to repair.

## 0.5.1 — Large boards open a slice at a time

Shipped. A board opens a slice at a time with the board drawn in between,
read-only until it is all in, and a change to its file meanwhile is read once
it is. The 5,000-item boards with short notes stop the shell for at most a
third of a second at once, where they held it for 8 to 11 seconds; long
previews, connector-heavy boards and large files still have the costs listed
above. A reload no longer hands every long note's text to the editor, which
held a shared board of long notes for 56 seconds. `npm run test:hostile` opens
a board at every limit and holds each to a time. The live checks, held back
for the release, ran on it afterwards and passed.

## Next maintenance pass

Measure before choosing it, and before adding connector labels:

- **Connectors in use.** Every pan and zoom step repaints all connectors:
  `Board.qml` walks every one and works out the geometry of each in view
  before stroking, with only the id index cached. One zoom change on
  `max-links` is a 1.8-second frame. Measure repeated pan, zoom, selection and
  dragging there and on ordinary diagrams (`npm run bench:scene` draws one
  connector per item), and separate the JavaScript from the stroking before
  choosing an optimization. `test:hostile` times opening, one zoom change and
  reopening, not sustained use.
- **Large files through the real session.** An external reload goes through
  `acceptDisk`, which reads the text with `readFile`, then `loadBoard`, which
  admits the same text again, in one go: a 32 MB board that needs the full
  `jsonFits` walk pays it twice. `test:hostile` calls `admitBoard` directly,
  so it measures neither that path nor the first open's file read. Measure
  both through `BoardSession`, and keep the parser's crash guard and
  whole-file reading in any change.
- **Two numbers, two targets.** Record the worst pause and the time until the
  board is editable separately, the 5,000 long previews included, and set a
  target for each on a named machine before accepting a performance change.
  The 2-second default and the 4- and 6-second exceptions, tripled in CI, are
  regression ceilings, not responsiveness goals.

The code alone does not say whether the JSON walk or the connectors should go
first; the measurements decide.

## 0.6 — Editable, labeled connectors

Make relationships useful in a decision diagram: connect “Ready?” to “Ship”,
label the arrow “yes”, and select it to edit, reverse or remove it.

Planned scope:

- Cheaper connector drawing first: working out where 20,000 go and stroking
  them is one of the stalls still open above, and labels would add to it.
- Optional plain-text labels that stay attached when items move.
- Confirm the labeled-arrow workflow is useful before committing to the full
  feature. Define per-label and aggregate text limits, and bounded work for
  drawing and pointer selection, before adding a field to the board format.
- Pointer selection of individual connectors and a keyboard-accessible list
  of connections for the selected item.
- Named actions to edit a label, reverse a connector and remove it.
- Retain the destination-selection and explicit-confirmation behavior already
  implemented on `dev` when adding connector labels and individual selection.
- Preserve the existing keyboard workflow and straight connectors.

Completion checks:

- Keyboard and pointer paths both work, including cancellation and read-only
  boards; each completed edit is one undo step.
- Labels survive save/reload, duplication, portable board exchange and PNG
  export in every supported palette.
- Old boards load with empty labels. A new board-format version prevents older
  plugin versions from silently discarding labels.
- Labels and selection remain legible at low and high zoom, in both window modes.
- The `max-links` hostile board, every connector labeled at the chosen text
  limits, meets explicit opening and interaction targets from the maintenance
  pass; merely retaining the existing six-second exception is insufficient.
  Cover one-past-limit refusals, repeated pan/zoom/drag, picking and export too.

## Later candidates

Revisit these after 0.5 and feedback from real use:

- Copy and paste board objects between boards, preserving layout and connections.
- Persistent groups with explicit membership.
- SVG export and zoom to selection.
- Explicit URL/file links if source collection proves a stronger need.

Freehand drawing is outside the current scope.
