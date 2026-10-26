# What a board costs to draw

Written by `npm run bench:scene -- --record` on 2026-09-30. Every frame time quoted in the
changelog was measured here; a frame time without the machine under it is
not a number anyone can check.

## Targets — 2026-10-26

Two numbers say how a board opens, and each now has a target: the **worst
pause**, the longest the board or its session held the shell at once, and
**editable**, the time until the board can be edited, its items and
connectors in. The budgets in `tests/hostile.js`, 2 seconds and the ceilings
listed there by name, are what a change may not make worse; the targets are
what it is measured against before it is accepted. `npm run test:hostile`
reports both numbers for every board and lists the boards over target,
without failing them.

| Boards | Worst pause | Editable |
|---|---|---|
| In ordinary use: `ordinary-50`, `ordinary-500` | 100 ms | 1 s |
| Every other: at a limit, past one, or refused | 500 ms | 10 s |

A response within about a tenth of a second reads as immediate, and a
second is about as long as a wait can be without losing the thread of what
someone was doing
([Nielsen](https://www.nngroup.com/articles/response-times-3-important-limits/)).
A board at a limit is one someone else wrote, or one grown far past use: a
pause of half a second there is noticed but is not a hang, and ten seconds is
about as long as attention holds on a board that says how far it has got.

The machine is a laptop, the one under
[Baseline environment](#baseline-environment--2026-09-30): AMD Ryzen 5 PRO
4650U with Radeon (Renoir) graphics, 14 GB, Qt 6.12.0, Quickshell 0.3.2,
Omarchy 4.0.0.r7320.g4601078-1. The board is drawn offscreen by the software
renderer in an 1100×700 window, as `test:hostile` draws it. On another
machine, or another renderer, the targets do not apply as they stand.

Two runs back to back on `896cca8` with the change that reports them; a
range is the two. Editable is the board's slices and connectors in, or the
session's opening where that is longer, which includes reading the file.

| Board | Worst pause | Editable | |
|---|---|---|---|
| `ordinary-50`: 50 items, 53 connectors | 80–81 ms | 34–35 ms | met |
| `ordinary-500`: 500 items, 548 connectors | 81–83 ms | 0.30–0.34 s | met |
| 5,000 items: stacked, grid, shapes, largest ids, duplicate ids, odd values, extreme geometry, missing pictures | 0.30–0.43 s | 5.6–8.9 s | met |
| `notes-bidi`, `unknown-field`, `whitespace`, `dangling-links`, `open-list-under`, `nesting-at-limit` | 0.06–0.47 s | under 0.6 s | met |
| Refused: one past each limit, nested past 1,024, a newer version, not a board | 39–82 ms | — | met |
| `max-items-previews`: 5,000 notes of 4,000-character previews | 1.16–1.38 s | 27.9–32.3 s | both over |
| `escaped-quotes`: 32 MB `jsonFits` has to walk | 1.44–1.56 s | 1.47–1.53 s | pause over |
| `old-history` | 1.30–1.31 s | 1.26–1.37 s | pause over |
| `max-links`: 20,000 connectors on screen | 0.91–1.32 s | 0.20–0.22 s | pause over |
| 1 MB notes: words, unbroken, markup, newlines, tabs | 0.96–1.03 s | 0.53–1.12 s | pause over |
| `notes-emoji-zwj` | 0.61–0.62 s | 4.4–4.5 s | pause over |
| `notes-one-cluster` | 0.52–0.53 s | 0.37–0.39 s | pause over |

The ordinary boards' worst frame is the board zoomed out to 20%; opening
them held the shell 35 to 44 ms. Where the misses come from, which is what
to work on:

- **Reading a board of long notes again.** On seven boards of long notes,
  the worst pause is the session reading the board again once another
  process has changed it: 0.52 to 1.38 seconds, 1.6 to 1.9 times what
  opening the same board holds (0.30 to 0.73). This is the lead
  [A board read again](#a-board-read-again--2026-10-19) left.
- **5,000 long previews** take 28 to 32 seconds to become editable, three
  times the target: building the delegates and laying out their text, as
  [Hostile boards](#hostile-boards--2026-10-17) describes.
- **The `jsonFits` walk** holds the shell 1.2 to 1.6 seconds on the two
  boards of 32 MB, opening and reading again, in the board and the session
  alike.
- **20,000 connectors on screen** take 0.91 to 1.32 seconds for their first
  frame, the raster
  [Connectors and patterns drawn less](#connectors-and-patterns-drawn-less--2026-10-25)
  left.
- **Joined emoji** hold one frame for 0.61 seconds while 13 notes of 1 MB
  are laid out.

## A pan on the desktop — 2026-10-26

The pan of
[Connectors and patterns drawn less](#connectors-and-patterns-drawn-less--2026-10-25),
measured on the desktop rather than offscreen: the laptop's own panel,
1920×1080 at scale 1.5 and 60 Hz, drawn by the GPU, on the machine of the
targets above. `npm run bench:scene -- 4 --timing` opens a board of four
items and three connectors, all in view, with the dot pattern, in window
mode, here tiled beside another window at 621×670 logical pixels. `dev` at
`896cca8` against 0.5.3 from a worktree with the same harness, alternating.

Every phase of both took 16.7 ms a frame, the refresh interval: neither drops
a frame at this size, and a frame time cannot say how much of the frame was
left. Qt's own timing of each frame can, in whole milliseconds; the medians
of each phase's 59 recorded frames, a range over three runs of each:

| Four items | 0.5.3 | Now |
|---|---|---|
| Pan: polish, GUI thread | 5–6 ms | 0 ms |
| Pan: sync and render, render thread | 1 ms | 0 ms |
| Zoom: polish | 4 ms | 4–5 ms |
| Zoom: sync and render | 1 ms | 1 ms |

A pan step drew both canvases, each 0.94 megapixels here, and now draws
neither; a zoom still draws both. The 4K output at scale 2 where the cost was
found has nine times those pixels and was not connected: a pan there is
still to measure, with the same command.

## Connectors and patterns drawn less — 2026-10-25

Four changes, each measured on the machine below with Qt 6.12.0, offscreen
with the software renderer, against `dev` at `a5db4ea` in a worktree of its
own: two runs of each, alternating, so a range is the two.

- **A head is left for `fill()` to close.** Context2D's `closePath` measures
  the bounds of the whole path it is given (`QQuickContext2D::closePath` takes
  `m_path.boundingRect()`), so closing each head in the path every head shares
  made the paths quadratic: the 1.2 to 1.45 seconds of the table below were
  that call. `fill()` closes them anyway; a pixel comparison of the two found
  none different. Without it, a Context2D call costs about 0.2 µs.
- **The walk reads plain copies of the items and connectors.** Board.qml keeps
  each item's place, size and kind and each connector's ends beside the
  models, read again only for the rows that changed, and builds them only
  once a board has a connector, since a board opens its items before its
  connectors. The walk is `Store.connectorsInView`.
- **A pan moves what is drawn.** The pattern canvas is a step larger than the
  board and is held where the camera puts it, so a pan never draws it again;
  the connectors' canvas is moved with the camera while it holds every
  connector whole, and drawn again otherwise. Both sit in a clipped item, so
  nothing moved shows past the board.
- **A hidden pattern is not drawn.** A canvas that is not shown still paints
  when asked, and every zoom asks: with the pattern off, a zoom step at 25%
  drew 7,700 dots nobody saw, 54 ms a frame in a 1100×700 window and 85
  fullscreen, against 21 now. This was so before any of the above.

`npm run bench:connectors`, medians of each phase's frames, all four phases
in one range, with the first two changes; its steps ask for the connectors
to be drawn every time, so the pan does not reach it:

| Board | At | Geometry | Paths | Frame before | Frame after |
|---|---|---|---|---|---|
| `chain-300` | 100% | 3 → 1 ms | 0 ms | 21–23 ms | 21–24 ms |
| | 20% | 3–5 → 2 ms | 1 ms | 32–44 ms | 30–42 ms |
| `chain-3000` | 100% | 24–25 → 7–8 ms | 0 ms | 20–39 ms | 21–26 ms |
| | 20% | 29–30 → 9–11 ms | 2 → 0–1 ms | 35–67 ms | 26–52 ms |
| `mesh-20000` | 100% | 73–77 → 21–46 ms | 0 ms | 81–108 ms | 35–57 ms |
| | 20% | 98–99 → 49–51 ms | 10 → 1–2 ms | 116–167 ms | 55–91 ms |
| `max-links` | 100% | 150–152 → 89–93 ms | 1,162–1,168 → 9–10 ms | 2,151–2,580 ms | 971–1,147 ms |
| | 20% | 162–179 → 98–99 ms | 1,387–1,388 → 11 ms | 1,721–1,764 ms | 267–320 ms |

What is left on `max-links` at 100% is the raster, 0.84 to 1.15 seconds
before and after alike. Drawn opaque it takes about a third of the time
(16,000 random connectors, 0.75 to 0.77 against 2.2 to 2.3 seconds), but the
connectors are translucent by design, and drawing them opaque under the
canvas's own opacity does not look the same: where two cross, or a head
meets a line, they blend once rather than twice.

`npm run test:hostile` on the boards with the most items and connectors,
back to back the same way (worst frame, then the whole opening):

| Fixture | Opening before | Opening after | Zoomed out before | after |
|---|---|---|---|---|
| `max-links` | 2.32–2.40 s (2.84–2.94) | 0.81–0.90 s (1.45–1.54) | 1.73–1.81 s | 0.33 s |
| `max-id`, 5,000 items, 4,999 connectors | 0.22–0.28 s (6.7–7.0) | 0.26 s (6.9–7.8) | 0.09 s | 0.08 s |
| `max-items-stacked` | 0.21–0.22 s (8.1–9.0) | 0.23 s (8.2–9.6) | 0.10 s | 0.10 s |

`max-links` is held to the 2-second default now. Opened again, it took
0.59–0.66 seconds before and 0.91 after: the harness's reopening never
asked for the connectors to be drawn, as BoardSession's `finishLoad` does,
and drew them only because the copies now listen to the connectors; it asks
for them now.

A pan of a small board, three notes, a diamond and one connector, with the
dot pattern (`npm run bench:connectors -- --pan`), the median of 20 steps;
"camera only" moves the camera and draws neither canvas, what the items
alone cost:

| Window, scale | Camera only | Both canvases drawn (before) | Panned (now) |
|---|---|---|---|
| 1100×700, 1 | 21 ms | 21 ms | 21 ms |
| 1920×1080, 1 | 21 ms | 25 ms | 21 ms |
| 1100×700, 2 | 21 ms | 34 ms | 21 ms |
| 1920×1080, 2 | 23 ms | 60 ms | 23 ms |

Each canvas costs its pixels, not what is on it, and every earlier
measurement here ran in a window of 1100×700 or smaller at scale 1. A
board filling a 4K output at scale 2 is the bottom row: a pan drew two
canvases of 3840×2160 every step. Now it draws neither. A zoom still
draws both, and so does a pan once a connector reaches past the view.

A zoom costs a little more for it. The pattern canvas is a step larger
than the board, and changes size as the step does: a zoom step of an empty
board with the dot pattern, asked for as `BoardPane.zoomAt` asks, took
55–56 ms at 25% and 21 at 100% in a 1100×700 window before, 56–57 and 21–22
after; fullscreen 82–83 and 22–23 before, 85–87 and 24–25 after. At 25% it
is the dots, 7,700 to 21,000 of them a step. One path and one fill for all
of them took 1.4 seconds to rasterise, as 0.4.7 found; a square for each
was no cheaper.

`bench:connectors`' zoom steps never asked the pattern to be drawn, as the
pane's zoom always has. The canvas now draws itself when the step changes,
so on the code with all four changes its zoom phase at 20% includes the
dots: 62 ms on `chain-300` and 80 on `chain-3000` in one run, against 40–42
and 52 in the table above. That is the bench measuring what a zoom costs,
not a zoom costing more.

Of the targets proposed on 2026-10-24: `max-links` is under a second at 20%
and opens within the default, but is 0.97 to 1.15 seconds at 100%, its
raster. `mesh-20000` at 100% walks in 21 to 46 ms, not under 10, but its
frames are within 30 ms of `chain-3000`'s in pan, selection and dragging,
and 31 ms off in zooming. No phase on the chains is slower than its range
before.

The software renderer is not the desktop's: these say which costs went,
not what a frame on the desktop now takes.
[A pan on the desktop](#a-pan-on-the-desktop--2026-10-26) measures one on a
laptop's panel; the 4K output is still to do.

## Connectors in use — 2026-10-24

`npm run bench:connectors` (`tests/connectors.js`), on the machine below with
Qt 6.12.0, offscreen with the software renderer in a 1100×700 window. Each
board is panned, zoomed, selected through and dragged, one step a frame and
twelve steps each, at 100% and at 20%; the real `Board` draws it, with
`PaneStub` asking for the connectors' repaint the way `BoardPane` does.
Frame is the longest frame a step took, what the eye sees; an idle frame here
is 20 ms. Raster is the Canvas drawing the paths into its image, from the
end of its `onPaint` to `painted()`. The script before it is timed apart,
because nothing marks when a frame's polish starts: geometry is the paint's
loop over every connector, culling and `Store.connectorGeometry`, and paths
is `paintConnectors` handing what it found to a Context2D. Two runs back to
back; a range is the two, a single figure is both. Frame and raster are
medians of a phase's steps, the worst in brackets.

| Board | At | Shown | Geometry | Paths | Raster | Frame |
|---|---|---|---|---|---|---|
| `chain-300`, 300 items | 100% | 15 | 2 ms | 0 ms | 2–3 ms | 21–23 ms (34) |
| | 20% | 270 | 2–5 ms | 1–2 ms | 3–7 ms | 33–45 ms (60) |
| `chain-3000`, 3,000 items | 100% | 15 | 25 ms | 0 ms | 1–2 ms | 21–39 ms (72) |
| | 20% | 330 | 27–28 ms | 2 ms | 3–5 ms | 38–65 ms (75) |
| `mesh-20000`, 5,000 items | 100% | 60 | 74 ms | 0 ms | 2 ms | 88–114 ms (148) |
| | 20% | 1,395 | 98–99 ms | 10 ms | 10–13 ms | 126–192 ms (389) |
| `max-links`, 201 items | 100% | 15,930 | 126–155 ms | 1,208–1,222 ms | 945–1,058 ms | 2,336–2,456 ms (2,833) |
| | 20% | 17,306 | 187–192 ms | 1,439–1,452 ms | 192–218 ms | 1,779–1,851 ms (2,057) |

Pan, zoom, selection and dragging cost the same on each board within a run,
because each repaints every connector the same way, so they share a row. The
parts add up to the frame: on `max-links` at 100%, 126 + 1,222 + 1,055 ms
against a pan of 2,456. Three costs, then, and the walk is the smallest of
them where it matters most:

- **Building the paths.** On `max-links`, `paintConnectors` takes 1.2 to 1.45
  seconds for 16,000 to 17,000 connectors: six Context2D calls each, about 12
  µs a call, eight to ten times the geometry it draws.
- **Rasterising them.** About a second at 100% and a fifth of that at 20%,
  where the same connectors are a fifth as long: it follows the pixels
  covered, not the number of connectors.
- **Walking connectors off screen.** `mesh-20000` shows 60 connectors at 100%
  and still spends 74 ms a frame looking at the other 19,940. The frames of
  `chain-3000` and `mesh-20000` above that, with next to nothing drawn, are
  the 3,000 and 5,000 delegates, which this does not separate.

### Targets proposed for the change that follows

On this machine and renderer, measured back to back with the change and
without:

1. `max-links`: every phase's median frame under 1 second at both zooms, from
   1.8 to 2.5; and its opening worst frame in `test:hostile` within the
   2-second default, so its 6-second ceiling there can go.
2. `mesh-20000` at 100%: geometry under 10 ms, so connectors off screen cost
   next to nothing, and frames within 30 ms of `chain-3000`'s.
3. `chain-300` and `chain-3000`: no phase's median frame more than 10% slower.

These are proposals, not assertions: the runner reports and checks nothing,
and it is not in CI.

## A board read again — 2026-10-19

The session part of `npm run test:hostile`, on the machine below with Qt
6.12.0, offscreen: every board of a megabyte or more opened by a real
`BoardSession`, then replaced by another process with one more byte and read
again. The time is the longest the session's thread was held at once, the
widest gap between ticks of a 1 ms timer; nothing is drawn. 0.5.1 parsed a
board read again twice, in `acceptDisk` to check it and in `loadBoard` to
open it; now `acceptDisk` hands `loadBoard` its reading. Three runs of each,
the first two pairs back to back; the third run of 0.5.1 was slower all
round, its openings included.

| Fixture | Opening | Read again, 0.5.1 | Read again, now |
|---|---|---|---|
| `escaped-quotes`, 32 MB | 1.42–1.77s | 2.98–3.26s | 1.46–1.50s |
| `old-history`, 29 MB | 1.18–1.44s | 2.40–2.84s | 1.23–1.27s |

The full run with the change held every board of a megabyte or more within
the 2-second default:

| Fixture | Opening | Read again |
|---|---|---|
| Eight boards of about thirty 1 MB notes (`notes-*`) | 0.26–0.59s | 0.44–1.15s |
| `max-items-previews`, 5,000 long previews, 32 MB | 0.70s | 1.23s |
| `odd-values`, 27 MB | 0.33s | 0.40s |
| `unknown-field`, 32 MB | 0.23s | 0.23s |
| `whitespace`, 32 MB | 0.09s | 0.11s |
| `one-past-note`, refused and shown read-only | 0.01s | not read again |

In single runs, not back to back, the long-note boards went from 0.51–1.48s
to 0.44–1.15s to be read again, and the long previews from 1.78s to 1.23s:
they parsed their text twice as well. Boards of long notes still hold the
shell about twice as long to be read again as to open, though their text needs no `jsonFits` walk. A reload also
writes the whole board out to compare it, in `measuredDisk`, `requestDisk`
and `acceptDisk`; whether that is the difference, these runs do not say.

## Hostile boards — 2026-10-17

`npm run test:hostile` on Qt 6.12.0, offscreen with the software renderer,
on the machine below: the longest the board held the shell at once (its
worst frame) while opening, and the same on 2026-10-16, before boards were
opened a slice at a time, editors and shapes were built only when used, and
connectors lost their round ends. Each fixture is described in
`tests/hostile-fixtures.js`.

| Fixture | Items, connectors | Worst frame | Before |
|---|---|---|---|
| A board at 5,000 items (stacked, grid, shapes, largest ids, duplicate ids, odd values, missing pictures) | 5,000 | 0.14–0.37s | 7.5–10.5s |
| 5,000 items, each with a 4,000-character preview | 5,000 | 0.47s | 24.4s |
| 20,000 connectors on screen | 201, 20,000 | 2.5–3.8s | 21.4s |
| 13 notes of joined emoji, 1 MB each | 13 | 0.94s | 3.5s |
| 32 MB that `jsonFits` has to walk | 1 | 1.3–2.5s | 1.3–1.7s |
| 31 notes of 1 MB: words, one unbroken line, markup | 31 | 0.43–0.48s | 0.7–1.2s |
| 15 notes of 1 MB of newlines, opened again | 15 | 0.28s | 55s |
| Refused: one past each limit, nested past 1,024, a newer version | 0 | under 0.12s | — |

`bin/omarchyform validate` took under 0.6s for every fixture.

A board at 5,000 items still takes 6 to 11 seconds to fill in, and 26 to 35
when every note carries a full 4,000-character preview; the shell draws
throughout, and the board is read-only until it is in. Each item costs about
1ms to build, against 1.7ms before the note editor and the shape moved into
Loaders. Connector painting still walks every connector and works out the
geometry of each one in view in JavaScript before stroking it, on every pan
and zoom step as well as on opening; these measurements do not separate those
costs. Software
rendering is not the desktop's GPU path, but the connectors are a Canvas,
which QPainter rasterises on the CPU either way.

These are regression measurements, not a general responsiveness guarantee.
The runner allows 2 seconds per worst frame by default, 6 for `max-links` and
4 for `escaped-quotes` and `old-history`; CI triples those ceilings. Total
opening time is reported but has only a process timeout, not its own
performance assertion. A board can therefore become much slower to finish
opening while still passing if it keeps yielding between slices. Since
2026-10-26 the time until a board is editable is reported against a
[target](#targets--2026-10-26), and still fails nothing.

Two full runs on 2026-10-19, on the machine below with Qt 6.12.0 and Omarchy
4.0.0.r7083.g81fd2d2, show how far those totals move. A 5,000-item board's
fill differed by up to half between them (stacked 9.2 and 14.4 seconds,
missing pictures 6.9 and 10.9), and the 5,000 long previews took 26 and 35
seconds to open, 32 and 49 to open again, with a worst frame of 0.37 and
0.98 seconds. Boards of a few dozen items agreed within a few percent. Compare
totals only between runs made back to back: run that way on `f4973be` and on
0.5.1, the long previews took 25.8 seconds to open on both.

The harness renders the real `Board`, but reproduces admission and filling
with a `PaneStub` and `wait(1)` instead of running `BoardSession` and its timer.
Its reopen is from normalized saved text. Picture validation is not timed
at all, and file reading and an external reload only by the session part,
for boards of a megabyte or more (above). Sustained pan, zoom,
selection and dragging are measured by `npm run bench:connectors`
([above](#connectors-in-use--2026-10-24)).

## Fully textured large board — 2026-10-09

Final `dev` validation used `npm run bench:scene -- 3000`, then the same
command with `--textures`. The latter alternates Ruled, Grid, Dots and Hatch
on every note and shape, including the timeline's baseline. Each phase measures
60 frames after 20 settling frames. No product optimization is inferred from
the small differences between these single runs.

Environment: Qt 6.12.0, Quickshell 0.3.2, Hyprland 0.56.2, Omarchy
4.0.0.r6815.g50d687a-1, Ryzen 5 PRO 4650U / Radeon Vega. Both runs used a
367×818 logical-pixel window; the reported focused display was 1920×1080 at
1.25×, with two outputs. The probe reported 60 Hz; the measured idle interval
was 13.3 ms, so these figures should not be treated as calibrated refresh-rate
measurements or compared directly with earlier display configurations.

| Phase | Plain, mean/p95 ms | All textured, mean/p95 ms |
| --- | --- | --- |
| Idle | 13.3/13.7 | 13.3/13.8 |
| Pan | 32.7/38.8 | 32.0/38.0 |
| Zoom | 51.1/58.2 | 49.9/56.6 |
| Drag one | 13.5/16.8 | 13.5/16.0 |
| Drag all | 73.0/77.8 | 70.7/76.2 |
| Mark | 14.4/45.3 | 14.4/46.6 |
| Find | 24.3/130.5 | 23.5/113.6 |
| Scrub | 54.4/78.4 | 48.5/71.0 |
| Scrub, two panes | 74.9/153.1 | 82.2/142.5 |
| Play | 39.9/53.3 | 42.0/58.4 |

Texture overhead is not dominant in this fixture. At 3,000 items, pan, zoom,
whole-board movement and timeline playback already exceed the frame budget
with plain items. Two-pane scrub p95 remains below the plan's 200 ms target
in both runs. The scrub and play phases measured the timeline, which has since
been removed; `bench:scene` no longer runs them. This closes the missing
textured-board measurement, not the broader large-board performance work; tiny-zoom or all-items-visible layouts
and other display arrangements may behave differently.

## Baseline environment — 2026-09-30

| Part | Value |
| --- | --- |
| Qt | 6.11.2 |
| Quickshell | 0.3.1 |
| Compositor | Hyprland 0.56.2 |
| Refresh | 60.0 Hz |
| GPU | Advanced Micro Devices, Inc. [AMD/ATI] Renoir [Radeon Vega Series / Radeon Vega Mobile Series] (rev d3) |
| CPU | AMD Ryzen 5 PRO 4650U with Radeon Graphics |
| OS | Omarchy |
| Omarchy | 4.0.0.r2158.gd174d4a-1 |
| Display | 1920×1080 at 1.6x, single output |
| Window | 569×651 logical px |

## Milliseconds per frame, mean/p95

| phase | 100 items | 500 items | 1000 items | 3000 items |
| --- | --- | --- | --- | --- |
| idle | 16.7/17.3 | 16.7/17.1 | 16.7/17.1 | 16.7/16.9 |
| pan | 16.6/19.4 | 16.7/21.1 | 29.1/36.7 | 62.4/104.9 |
| zoom | 16.6/18.4 | 19.2/32.9 | 33.6/39.1 | 68.1/95.7 |
| drag 1 | 16.7/18.8 | 16.7/22.0 | 18.1/23.5 | 34.2/64.1 |
| drag all | 16.7/19.1 | 20.7/29.4 | 37.4/45.5 | 98.8/128.0 |
| mark | 16.7/21.3 | 16.7/17.1 | 17.2/44.6 | 20.6/75.7 |
| find | 16.7/25.7 | 16.9/40.1 | 19.8/61.7 | 25.3/109.7 |

The `idle` row is the refresh interval this machine actually reached, and
is the budget the rest are read against: a phase at 16.7ms is vsync-bound and
has room to spare, and a phase above it drops frames while the board is
in use.


## Command groups, canvas colours and restored textures — 2026-10-08

A matched-size comparison of the existing uncommitted command-group/canvas-colour
pass before completion and the completed pass, using `npm run bench:scene -- 1000`.
Both used a 470×510 logical-pixel window, a 3840×2160 display at 2× with two
outputs, 60 Hz, Ryzen 5 PRO 4650U/Radeon Vega, Qt 6.11.2, Quickshell 0.3.1,
Hyprland 0.56.2 and Omarchy 4.0.0.r6720.g8e02fc8-1.

| Phase | Before mean/p95 (ms) | Completed mean/p95 (ms) |
| --- | --- | --- |
| idle | 16.7/17.6 | 16.7/17.0 |
| pan | 25.8/34.3 | 23.9/34.6 |
| zoom | 28.6/34.0 | 30.3/35.8 |
| drag one | 16.7/17.4 | 16.7/21.5 |
| drag all | 28.0/37.6 | 26.6/32.7 |
| mark | 16.7/28.3 | 16.7/29.5 |
| find | 20.4/72.0 | 19.4/56.0 |
| scrub | 22.8/35.5 | 21.9/35.3 |
| scrub, two panes | 21.9/30.2 | 22.2/33.2 |
| play | 17.8/26.8 | 17.5/24.3 |

The completed pass retains cached connector lookups, offscreen rejection and
batched connector drawing. Theme fill/border weights are now resolved once per
theme change. Plain items create no texture geometry, offscreen textures are
unloaded, and each texture has bounded density.

An attempted single fill for all canvas dots increased mean panning time to
42.1 ms on this setup; it was removed. The final figures show small gains in
some operations and small losses in others, not an overall guaranteed speedup.
These are diagnostic desktop runs subject to system load. The scene uses Plain
items, so this does not measure a fully textured board.
