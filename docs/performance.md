# What a board costs to draw

Written by `npm run bench:scene -- --record` on 2026-09-30. Every frame time quoted in the
changelog was measured here; a frame time without the machine under it is
not a number anyone can check.

## Measured on

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
