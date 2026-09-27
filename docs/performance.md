# What a board costs to draw

Written by `npm run bench:scene -- --record` on 2026-09-27. Every frame time quoted in the
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

## Milliseconds per frame, mean/p95

| phase | 100 items | 500 items | 1000 items | 3000 items |
| --- | --- | --- | --- | --- |
| idle | 16.7/17.1 | 16.7/17.4 | 16.7/17.0 | 16.7/17.3 |
| pan | 16.7/19.9 | 17.0/22.3 | 29.0/34.8 | 83.5/109.6 |
| zoom | 16.6/19.4 | 19.3/23.5 | 34.3/39.1 | 80.3/105.7 |
| drag 1 | 16.7/19.0 | 16.7/22.9 | 17.9/24.6 | 43.3/65.9 |
| drag all | 16.7/19.9 | 21.7/29.1 | 30.5/39.0 | 116.4/143.7 |
| mark | 16.7/21.6 | 16.7/31.4 | 18.1/44.0 | 20.6/77.4 |
| find | 16.7/27.4 | 17.5/37.0 | 19.8/59.5 | 27.5/125.7 |

The `idle` row is the refresh interval this machine actually reached, and
is the budget the rest are read against: a phase at 16.7ms is vsync-bound and
has room to spare, and a phase above it drops frames while the board is
in use.
