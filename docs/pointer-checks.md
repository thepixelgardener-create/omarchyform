# Pointer checks, by hand

The one thing the suites cannot answer: whether the compositor delivers a
middle button to this plugin's windows the way Qt delivers it to a test.

`tests/qt/tst_pan.qml` mounts the real `Board.qml` — items, panels, header —
against a stand-in controller and drives it with real `QMouseEvent`s at four
zoom levels. That establishes that the board's own input tree routes the
button correctly. It is **not** a live test of the plugin: there is no
controller, no session, no Quickshell, and the platform is `offscreen`. It says
nothing about the fullscreen layer-shell overlay or the windowed toplevel, which
are the two surfaces a person actually presses on.

There is no way to synthesise a pointer into a running Wayland compositor from
inside this repository — no `ydotool` or `wlrctl`, and `/dev/uinput` is
root-only — and a tool that could would drive the real cursor across the real
desktop. So this is done by hand, once, against an isolated board.

## Setting it up

```bash
node tests/shots.js --hold
```

That is the ordinary screenshot harness with one difference: after the last
picture it leaves the board on screen instead of quitting. Everything it runs
is a scratch copy beside Omarchy's own modules, under a throwaway `HOME`, with
its own boards directory and its own images directory. **The installed plugin
and your real boards are not touched, and must not be used for these checks.**

It leaves a board carrying one of everything below: a pinned background, two
notes, an ellipse, a picture, and a connector between the two notes.

Close it with `esc` `esc` when you are done. That ends the run: the board is
dismissed, whatever it was writing is finished, and the scratch tree it built
is removed. `Ctrl-C` terminates the test process and cleans up its scratch tree;
that cancellation exits 130 (SIGTERM exits 143), rather than claiming the checks
completed. Ordinary close exits 0 only after setup reached readiness and pending
writes finished. Setup errors, unexpected signals and missing completion markers
exit non-zero. Setup has a two-minute deadline; interactive time is unlimited.

Either way it removes **its own** directory and nothing else. If you have a
second held run open in another terminal, its board is still there and still
yours. Should a run ever fail to clean up — a directory that cannot be written
to is also one that cannot be emptied — it prints the path it could not remove;
remove that path, not a pattern, or you will take the other run's boards with
it.

If the board will not write when you close it, the run says so and exits
non-zero rather than sitting there. `npm run test:hold` is what holds that
behaviour in place.

Run it once per window mode. `w` switches between fullscreen and windowed
without losing your place.

## What to check

For each row: **middle-drag** a short distance, then **middle-click without
moving**. Do both at 100% and at one other zoom — `+` a few times, or the
**Zoom** menu, which shows the percentage.

| Press on | A middle-drag should | A middle-click should |
|---|---|---|
| Empty canvas | pan | nothing |
| A note | pan | nothing |
| The ellipse | pan | nothing |
| The picture | pan | nothing |
| The pinned background | pan | nothing |
| The background in `shift+p` mode | pan | nothing |
| The resize grip of a selected note | pan | nothing |
| A note being typed in (`enter`, then press inside the text) | pan | nothing |

"Pan" means the board follows the pointer by the distance the pointer moved, on
screen, at whatever zoom you are at — not further at 400% and not less at 25%.

"Nothing" means: nothing is deleted, nothing moves or resizes, the selection is
where it was, a note being typed in is still being typed in and its text has not
changed, and `u` has nothing new to undo. The middle button pastes the primary
selection into a text field on this platform, so a note being typed in is the
row that matters most.

Then, with a panel open, middle-drag **on the panel**. The board behind it must
not move:

| Open it with | Press on |
|---|---|
| — | the header bar |
| `:` | the command list |
| `?` | the help panel |
| `b` | the board browser |
| — | the conflict panel, if you can raise one |

The conflict panel needs two versions of one board, which is awkward to stage by
hand; `tst_pan.qml` covers it automatically, so skip it here unless one appears.

## Afterwards

Still on the same board, confirm the ordinary things still work:

- `enter` types in a note, and the letters arrive.
- The wheel zooms at the pointer.
- A left-drag on a note moves it; a left-drag on empty canvas sweeps a marquee.
- A right-drag pans; a right-click opens the actions for the selection.
- `del` deletes, and `u` puts it back.

## Recording it

Write down the Omarchy and Qt versions, the compositor, which window modes you
tried, which zoom levels, and every row that did something other than the table
says. A row you did not get to is not a row that passed — leave it blank rather
than ticked.

---

# Results

## 2026-09-29 — every row, both window modes, passed

| | |
|---|---|
| Omarchy | 4.0.0.r2158.gd174d4a-1 |
| Hyprland | 0.56.2 |
| Quickshell | 0.3.1-1 |
| Qt | 6.11.2-3 |
| Output | 1920x1080@60Hz |
| Plugin | `27ce783` |

Driven by hand; verified in two halves. The person at the keyboard reported what
they saw, and the board file was checksummed between batches to establish the
other half — that nothing moved, resized, was deleted or was typed into. The
board was the isolated one `npm run shots -- --hold` builds, so no real board
was touched.

**Windowed**, at 100% and at roughly 400%:

| Press on | Middle-drag | Middle-click |
|---|---|---|
| Empty canvas | pans | nothing |
| A note | pans | nothing |
| An ellipse | pans | nothing |
| A picture | pans | nothing |
| A pinned background | pans | nothing |
| A background in `shift+p` mode | pans | nothing |
| A selected note's resize grip | pans | nothing |
| A note being typed in | pans | nothing, **and no text arrived** |

The header, the command list, the help panel and the board browser each took
the gesture themselves; the board behind did not move.

**Fullscreen** — the layer-shell surface, which is the case no offscreen test
can reach — the same rows, the same answers, including the note being typed in
and the pan at 400% following the pointer one for one rather than by the zoom.

### What the file said

Two changes appeared during the pass and neither was the middle button:

- An empty note, at a fractional position, which is what a **left** double-click
  on bare canvas makes. Confirmed by the person, and
  `test_aMiddleDoubleClickLeavesNothingBehind` was added in the same session to
  hold the other reading shut: two middle clicks inside the double-click
  interval add nothing, on bare canvas or on a note.
- One note resized from 180x140 to 187.478x137.599. Settled by repeating the
  row deliberately in fullscreen: a middle-drag on that same grip left the size
  untouched, so the resize was a left drag during exploration.

### What this does and does not settle

It settles the thing the suite cannot reach: on this compositor, in both window
modes, the middle button reaches the board's pan surface and nothing under it.

It is one machine, one compositor, one output, on one day. It is not a standing
guarantee, and it is not a substitute for the offscreen suite, which is what
catches a regression in the board's own input tree on every push.

If a row fails, note what it did instead and which window mode it was in: the
board's input tree is already covered by the suite, so a failure here is almost
certainly about how the compositor routes the button to a layer-shell surface
rather than about `Board.qml`.
