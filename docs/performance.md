# What a board costs to draw

Written by `npm run bench:scene -- --record` on 2026-09-27. Every frame time quoted in the changelog was measured here; a frame time
without the machine under it is not a number anyone can check.

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
| Omarchy | 4.0.0.alpha |

## Milliseconds per frame, mean/p95

| phase | 100 items | 500 items | 1000 items | 3000 items |
| --- | --- | --- | --- | --- |
| idle | 16.6/17.1 | 16.7/17.2 | 16.7/17.1 | 16.7/17.4 |
| pan | 16.6/18.0 | 19.2/23.8 | 29.9/41.1 | 61.7/92.2 |
| zoom | 16.7/20.1 | 20.3/25.7 | 32.2/38.2 | 77.3/105.0 |
| drag 1 | 16.7/19.3 | 16.9/23.0 | 16.6/22.6 | 38.4/70.4 |
| drag all | 16.7/18.2 | 19.7/31.2 | 33.3/39.6 | 102.0/133.1 |
| mark | 16.7/24.1 | 16.7/33.4 | 16.7/32.9 | 21.4/75.9 |
| find | 16.7/30.9 | 18.3/47.1 | 20.0/64.2 | 25.6/108.8 |

The `idle` row is the refresh interval this machine actually reached, and is
the budget the rest are read against: a phase at 16.6ms is vsync-bound and has room to
spare, and a phase above it is dropping frames while the board is in use.
