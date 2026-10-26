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
  checking a 32 MB board's text before reading it takes 1.3 to 2.5 seconds.
- **20,000 connectors on screen** take about a second a frame at 100%,
  nearly all of it rasterising translucent lines on the CPU; drawing them
  opaque is a third of that but changes how crossings look
  ([performance.md](performance.md#connectors-and-patterns-drawn-less--2026-10-25)).
- **A zoom draws both canvases again**, at the board's full size in device
  pixels, and so does a pan once a connector reaches past the view.

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

## 0.5.2 — A board read again is parsed once

Shipped. A board that changes on disk while it is open is parsed once on its
way in rather than twice: a 32 MB board that has to be checked all the way
through held the shell for 2.4 to 3.3 seconds when it was read again, and now
takes as long as opening it. `npm run test:hostile` takes every board of a
megabyte or more through a real session, opened and read again, and holds
the command line's replies to what each board should get.

## 0.5.3 — Fixes from the review of 0.5.2

Shipped. A picture whose header does not say how large it is is refused
where it lands, as importing a shared board already refused it. The command
line answers a flag given no value in JSON instead of a stack trace. The
autosave delay and keyboard step in `state.json` are held to the bar's
ranges, and a paste onto the board is held to the view it was asked in, as a
drop is.

## 0.5.4 — Panning draws less

Shipped. A pan moves the connectors and the dot pattern rather than drawing
them again, and a hidden pattern is not drawn: on a laptop's panel a pan step
went from 6 ms of drawing to none. Connectors are drawn in under half the
time, 20,000 on screen in about a second a frame rather than 1.7 to 2.6. The
header is one line, with a disk that says whether the board is saved.
`npm run test:hostile` reports the worst pause and the time until a board is
editable against targets set for each.

## Next maintenance pass

Measured on 2026-10-19, on the machine in
[performance.md](performance.md#baseline-environment--2026-09-30). Making
each probe an instrument comes before the change it measures.

- **Large files read again: shipped in 0.5.2.** An external reload
  went through `acceptDisk`, which read the text with `readFile`, then
  `loadBoard`, which admitted the same text again, in one turn: through a real
  `BoardSession`, a reload of `escaped-quotes` held the shell for 2.9 to 3.3
  seconds at once and `old-history` for 2.4 to 2.8, against 1.2 to 1.8 to open
  them. `test:hostile` now takes every board of a megabyte or more through a
  session, opened and then read again, and `acceptDisk` hands `loadBoard` its
  reading: both now hold the shell as long as opening does, the one `jsonFits`
  walk listed above. `tests/editing.js` counts the parses. Boards of long
  notes still take about twice as long to read again as to open, within
  budget; [performance.md](performance.md#a-board-read-again--2026-10-19)
  has the lead.
- **Connectors in use: shipped in 0.5.4.** On `max-links` a step
  was a 1.8 to 2.5-second frame, 1.2 to 1.45 of it `closePath` measuring the
  whole path once for every head; it is 0.27 to 0.32 seconds at 20% and 0.97
  to 1.15 at 100%, the raster of translucent lines. The walk reads plain
  copies of the models, and a pan moves what is drawn rather than drawing it
  again, which on a 4K output at scale 2 was most of what a pan of a small
  board cost. [performance.md](performance.md#connectors-and-patterns-drawn-less--2026-10-25)
  has the measurements. On a laptop's panel a pan step went from 6 ms of
  drawing to none ([performance.md](performance.md#a-pan-on-the-desktop--2026-10-26));
  the 4K output is still to measure, with `npm run bench:scene -- 4 --timing`.
- **Two numbers, two targets: set on 2026-10-26.** `test:hostile` reports
  the worst pause and the time until a board is editable for every board,
  two of ordinary size among them, and lists the ones over target without
  failing: 100 ms and 1 second for a board in ordinary use, 500 ms and 10
  seconds for the rest, on the laptop
  [performance.md](performance.md#targets--2026-10-26) names. Both ordinary
  boards meet them. Eleven boards miss: 5,000 long previews take 28 to 32
  seconds to become editable; reading a board of long notes again holds the
  shell up to 1.4 seconds, the `jsonFits` walk at 32 MB 1.6, the first frame
  of 20,000 connectors 1.3, and joined emoji 0.6. The 2-second default and
  the 4-second exceptions, tripled in CI, stay the regression ceilings.
  Accept a performance change against the targets, measured back to back.

## 0.6 — Editable, labeled connectors

Make relationships useful in a decision diagram: connect “Ready?” to “Ship”,
label the arrow “yes”, and select it to edit, reverse or remove it.

Planned scope:

- Labels that fit how connectors are drawn once the maintenance pass has made
  that cheaper; they need not be drawn the same way. A label on each of
  20,000 connectors adds to the cost measured there.
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
