# What a board costs to draw

Written by `npm run bench:scene -- --record` on 2026-09-30. Every frame time quoted in the
changelog was measured here; a frame time without the machine under it is
not a number anyone can check.

## Hostile boards — 2026-10-16

`npm run test:hostile` on Qt 6.12.0, offscreen with the software renderer,
on the machine below. Wall time to open and draw 20 frames; twenty frames
alone take about 350ms. Each fixture is described in
`tests/hostile-fixtures.js`.

| Fixture | Items, connectors | Open | Opened again |
|---|---|---|---|
| A board at 5,000 items (stacked, grid, shapes, largest ids, duplicate ids, odd values, missing pictures) | 5,000 | 8.9–11.2s | 9.9–11.8s |
| 5,000 items, each with a 4,000-character preview | 5,000 | 29.5s | 31.7s |
| 20,000 connectors on screen | 201, 20,000 | 22.2s | 2.4s |
| 13 notes of joined emoji, 1 MB each | 13 | 5.2s | 5.2s |
| 32 MB that `jsonFits` has to walk | 1 | 1.7–2.0s | — |
| 31 notes of 1 MB: words, one unbroken line, markup | 31 | 1.0–1.5s | 0.8–1.2s |
| 15 notes of 1 MB of newlines | 15 | 0.95s | 0.74s (56s before the fix) |
| Refused: one past each limit, nested past 1,024, a newer version | 0 | under 0.45s | — |

`bin/omarchyform validate` took under 0.45s for every fixture.

The cost of the 5,000-item boards is building each item's delegate on the
shell's thread, about 1.7ms each; parsing, filling the models and writing the
board out again take under 0.3s together. The 20,000-connector board's time
is in its first frame rather than in any step the test times, most likely
the connector canvas; that is not confirmed. Software rendering is not the
desktop's GPU path, so frame costs that are drawing rather than layout may
differ live.

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
