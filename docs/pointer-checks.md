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

Close it with `esc` `esc` when you are done — that ends the run and cleans up
the temporary tree. If you kill it instead, remove `/tmp/omarchyform-shots-*`
by hand.

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

If a row fails, note what it did instead and which window mode it was in: the
board's input tree is already covered by the suite, so a failure here is almost
certainly about how the compositor routes the button to a layer-shell surface
rather than about `Board.qml`.
