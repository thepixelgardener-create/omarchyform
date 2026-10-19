# What a board costs to draw

Written by `npm run bench:scene -- --record` on 2026-09-30. Every frame time quoted in the
changelog was measured here; a frame time without the machine under it is
not a number anyone can check.

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
opening while still passing if it keeps yielding between slices.

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
for boards of a megabyte or more (above). Measure sustained
pan, zoom and dragging before changing how connectors are drawn.

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
