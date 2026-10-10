# Development

[Back to the README](../README.md) · [Install](install.md) · [Using the board](guide.md) · [Boards on disk and the command line](files.md)

Contributor rules for code changes are in [AGENTS.md](../AGENTS.md); the
[documentation guide](README.md) lists the design notes and reviews.

## Running from a clone

```bash
git clone https://github.com/thepixelgardener-create/omarchyform.git
cp -r omarchyform ~/.config/omarchy/plugins/thepixelgardener.omarchyform
omarchy-shell shell rescanPlugins
omarchy plugin enable thepixelgardener.omarchyform
```

Validate before publishing:

```bash
omarchy plugin validate .
qml_imports=$(mktemp -d)
ln -s "$OMARCHY_PATH/shell" "$qml_imports/qs"
/usr/lib/qt6/bin/qmllint -I "$qml_imports" ./*.qml
rm -rf "$qml_imports"
```

The temporary import tree resolves Omarchy's `qs.Commons` namespace. The
installed QML metadata still produces warnings about `PanelWindow`,
`QProcess::ExitStatus`, the dynamic Style font object and the members of the
shell's plugin API. qmllint also reports unqualified access inside the header
menu's delegate and the export scene, so it exits non-zero. The live test
checks that those types and properties work in the actual runtime. CI fails on
one category only: a property overriding a final one, which is what makes a
surface fail to load.

`keepLoaded: true` keeps this overlay mounted between summons. Save with
`ctrl+s` and wait for the saving indicator to clear before a rescan or a shell
restart; a forced unload can interrupt an asynchronous save.

**After changing QML, restart the shell. Do not trust a rescan to replace it.**

```bash
omarchy restart shell
```

`omarchy-shell shell rescanPlugins` is documented as unloading and recreating
panels and overlays, including kept ones. On Omarchy `4.0.0.r2158.gd174d4a-1`
that did not hold for this plugin, twice, in two different ways:

- **A version that would not compile stayed broken.** After a
  `Cannot override FINAL property` error made `Board.qml` — and so the whole
  overlay — unavailable, the fix on disk was ignored through a reinstall and two
  rescans. The bar icon clicked and did nothing, because there was nothing to
  toggle. Only a restart cleared it.
- **A version that compiled fine was not replaced.** `omarchy plugin update`
  reported success and the new files were on disk, but the running board still
  drew the previous layout until the shell was restarted.

`keepLoaded: true` is the likely reason the second case happens — a kept overlay
that is never unloaded cannot pick up new source — but that is a suspicion from
two observations, not something verified against the shell's own code. Either
way, the safe habit is a restart.

Three symptoms say the shell is not running what is on disk: the board renders a
layout you have already changed; `omarchy plugin list` reports the plugin
`enabled` while the shell never instantiates it; and
`~/.local/share/omarchyform/images/` is missing, because the data directories
are created the moment the plugin's root loads. Compile errors themselves are in
the shell's log, under `/run/user/$UID/quickshell/by-id/*/log.qslog`.

Watch that log rather than trusting a silent rescan. Two checks catch this class
of error before the shell ever sees it —
`./tests/run` fails on any member that shadows a final one, and
`npm run test:omarchy -- --live` loads the whole plugin the way the shell does.
The offscreen Qt suite mounts nodes, boards, split view and supporting chrome
against test controllers; it does not load the complete Omarchy host. The
JavaScript suites execute controller functions without a QML engine. Both are
useful regressions, but the live suite verifies the host integration.

## Layout

| File | Holds |
|------|-------|
| `Omarchyform.qml` | The workspace: settings and state, the library and file exchange, the open boards, and the two surfaces |
| `BoardPane.qml` | One view of a board and the controller its views read: camera, selection, modes and every command |
| `BoardDocument.qml` | One open board: its items and connectors, ids, undo history and the session saving it |
| `Board.qml` | The canvas surface — grid, connectors, keys, cheat sheet |
| `BoardToolbar.qml` | The header: the board's name and save state, the zoom, and the menu |
| `Theme.qml` | Colours, fonts, sizes and weights, all read from the shell's theme with fallbacks |
| `Surface.qml` | The card a panel is drawn on, in the shell's menu colours and the theme's border for them |
| `Node.qml` | One item: note, box, ellipse, diamond or picture. Shapes are `QtQuick.Shapes` geometry, so they stay sharp at any zoom |
| `BoardPalette.qml` | Shared canvas and export colours, including Paper and Ink |
| `Commands.qml` | The command list on `:`, `ctrl+p` and `.` |
| `Conflict.qml` | The question asked when a board has two versions |
| `Browser.qml` | The board browser: draws the library |
| `BoardBar.qml` | The bar widget: the board's presence in the shell |
| `Help.qml` | Scrollable keyboard help |
| `ScrollHint.qml` | The mark that says a panel has more below |
| `BoardStore.js` | Pure logic: parsing, marshalling, geometry. No QML |
| `BoardSession.qml` | Loading, autosave state, and board-switch coordination |
| `BoardLibrary.qml` | The boards folder: browsing, naming, folders and the trash, with no controller of its own |
| `BoardPersistence.qml` | Serialized backup and atomic write, with completion/failure signals |
| `BoardExchange.qml` | Saving a copy to share and opening one, apart from the open board's saves |
| `BoardImage.qml` | The read-only scene a PNG export is drawn from: no grid, grips or selection |
| `BoardFiles.sh` | Confined filesystem operations and exact-path moves |
| `bin/omarchyform` | The board, headless: build, read and change one with no display |
| `bin/store.js` | Loading `BoardStore.js` outside QML, shared by the CLI and the tests |

## Tests

The pure logic lives in plain JavaScript so it can be tested without Qt, and
the suite loads the very file the plugin loads — there is no copy to drift.

```bash
./tests/run     # everything available on this machine, skipping what is not installed
npm test        # pure logic and controller regression tests, no dependencies
npm run test:security # portable security/privacy screen and boundary regressions
npm run test:security:full # also run Quickshell and Qt tests
npm run mutate  # mutation testing
npm run bench   # board marshalling cost at size
npm run bench:scene # what a board costs to draw, at size; needs a compositor
npm run bench:history # what keeping a board's edit history costs, in node and offscreen Qt
npm run test:qml # headless persistence tests; requires installed Quickshell
npm run test:paste # live canvas image paste test; uses an isolated clipboard stub and board library
npm run test:ui  # Qt Quick pointer, theme, and layout tests
npm run shots -- --hold # leave an isolated board up for docs/pointer-checks.md
npm run test:hold # that held board starts, survives a mode switch, and ends
npm run test:omarchy -- --keep # live desktop smoke test, isolated board data
npm run shots   # photograph every state, for judging by eye
npm run preview # remake the picture at the top of the README
```

`npm run bench:scene` measures the other half of what a board costs. `npm run
bench` times marshalling, which is arithmetic over an array and has never been
the problem; this drives the real scene — delegates, bindings and both canvases
— through panning, zooming, dragging, marking and finding, and reports
milliseconds per frame at each board size. A phase at the refresh interval is
vsync-bound and has room to spare; above it, the board drops frames while you
use it. Like `shots` it asserts nothing and is not in `tests/run`: it needs a
compositor, and frame times on a busy desktop are noisy enough that a single
run can be misleading. Run it before and after a change and compare the
columns.

```bash
npm run bench:scene            # 100, 500, 1000 and 3000 items
npm run bench:scene -- 3000    # one size
npm run bench:scene -- 3000 --textures # every item uses a non-plain texture
npm run bench:scene -- --record  # and write docs/performance.md
```

It prints what it measured on before what it measured — Qt, Quickshell, the
compositor, the refresh rate, the GPU, and the size of the window it was given,
since a window tiled across the whole screen draws more of the board than one
beside an editor — because a frame time without the
machine under it is not a number anyone can check, and the same board is
vsync-bound at 60Hz and dropping frames at 144. `--record` writes that and the
table to [docs/performance.md](performance.md), which is where the figures
quoted in the changelog come from.

`npm run shots` puts the real plugin through every state worth judging by eye —
empty, a cursor beside a mark, typing, backgrounds, finding, arranging, the
command list open and narrowed, what can be done with a selection, the question
asked when two versions of a board exist, help, the browser, naming a board, a
browser with more boards than fit, each of the three things a connector gesture
can be about to do, a failed save, a close-up at working zoom, and the board
at the top of the README — and saves a picture of each into
`~/.cache/omarchyform/shots/`. It asserts nothing: it exists because whether a
tinted item reads as selected, or a hint still fits on one line, is not
something a test can answer, and reading the source instead has been wrong
before. Add a theme name to see another theme, or `--light --dark` for one of
each:

```bash
npm run shots -- --light --dark
```

It runs against the live compositor in an isolated `HOME`, so the installed
copy of the plugin and the running shell are both left alone.

A theme named here is photographed from its own folder, which holds its colours
but not the `shell.toml` Omarchy generates when a theme is applied — so the
shell's surface tokens, such as the menu border a gradient theme gives its
panels, fall back to their defaults. With no name, it is the theme you are using,
as generated, and those are exactly what it shows.

`--hold` takes the pictures and then leaves the board on screen instead of
quitting, on the isolated boards that run built, carrying one of everything a
pointer can be pressed on — a background, notes, a shape, a picture and a
connector. It is there for `docs/pointer-checks.md`: a pointer cannot be
synthesised into a running compositor from here, so whether the middle button
reaches the fullscreen overlay and the windowed toplevel is checked by hand, and
it must not be checked on the installed plugin or on real boards. Close it with
`esc` `esc`, or `Ctrl-C` the terminal: either way the board is dismissed, what
it was writing is finished, and the scratch tree that run built is removed —
that one, by name, so a second held run in another terminal keeps its boards. A
board that cannot be written when it closes says so and exits non-zero rather
than hanging. `npm run test:hold` drives all four of those without a hand on
the keyboard.

```bash
npm run shots -- --hold
```

The last of those states is the picture at the top of the README, and
`npm run preview` is how it gets there: it takes the shots, crops the top of
the window to 16:9 and writes `preview.png`. The board in it is a saved board
file, framed by `tests/qml/shot.qml` rather than arranged by hand, so the next
one can be taken the same way — the one before this was arranged by hand and
went on showing a header and a hint row that had both since moved. The file is
kept outside the repo so it never ships: by default
`../omarchyform-examples/From spark to shipped.omarchyform.json`, or wherever
`OMARCHYFORM_SHOWCASE` points.

Take it where the window gets the whole width of the screen, on a workspace of
its own. Tiled beside another window it is tall and narrow, a 16:9 crop of its
top is half the board, and the line under the header wraps.

`npm run mutate` breaks `BoardStore.js` on purpose, one edit at a time, and
checks the suite notices. The command reports its current score and survivors;
it is a diagnostic, not a CI failure threshold.

Review survivors when changing the pure logic; a passing mutation command is
not a substitute for the runtime and filesystem regression tests.

A contract check reads the names the views and the session reach for on the
controller and fails if any of them is missing — including from the stubs the
QML session and exchange tests use in the controller's place. QML resolves those names at
runtime, so a missing one is a TypeError in a suite CI cannot run, which is
how two of them reached `main` behind green checks.

Controller tests evaluate the actual QML JavaScript functions with delayed I/O
completion to cover damaged files, queued edits, board switching, and retry.
The separate `test:qml` suite runs the real persistence and session components
in isolated headless Quickshell instances with temporary files. It checks backup
contents, write ordering, failure handling, retry, queued edits, and switching
between fresh, saved, and damaged boards. It does not interact with the running
desktop shell. CI runs the Node and Qt Quick tests. Run `test:qml` and
`test:omarchy` on an Omarchy machine before release. The live test opens test
surfaces and targets keyboard events at its own process; it preserves your
installed plugin, boards, and theme.

See [the compatibility review](omarchy-compatibility.md) for the tested
versions, first-party references, results, and remaining limits.

## Speed

`npm run bench` prints what a board costs to serialise and to load, at size.
Loading used to be superlinear — every connector scanned the whole item list to
resolve its two ends — so a 3000-item board took about 19ms to load and a
1000-item one about 3.6ms. Resolving the ends through a single index instead
makes it linear: roughly 6ms and 2ms.

Saving costs about 50ms, and costs it whatever the board's size: a 15KB board
and a 480KB one land within a millisecond of each other, because almost none of
it is the writing. One `bash` does the whole commit — it stages the board it was
handed on standard input, takes the lock, checks the file is still the revision
it last read, keeps the version it is about to replace, and renames the new one
into place. Starting that process accounts for about 12ms of the total; the rest
is the copy and the renames reaching disk. Measured on btrfs under `$HOME`,
twenty saves at each size after five warm-up runs.

Doing the copy in-process would remove part of that, but the backup is what
guarantees the previous version is safely on disk before the board is
overwritten, the lock is what stops two writers from both believing they are
updating the same board, and the obvious rewrites broke the first of those. Both
are left alone deliberately, behind the autosave delay, rather than traded for
speed.

## Notes on the platform

The shell's `qs.Commons` singletons are internals, not a versioned API.
`Theme.qml` uses qualified names to avoid runtime name collisions and guards
token reads with fallback values, so a renamed token need not prevent the
board from opening. An import disappearing entirely is still fatal — QML has
no optional imports.

The overlay is built through `Variants` so its surface is constructed with its
screen already set, and it opens on whichever output Hyprland has focused.
Assigning `screen` to a window that already exists leaves it unmapped.

Pasting onto the canvas accepts up to 1 MiB of text or 32 MiB per picture.
An oversized paste is rejected in full. Picture formats are checked from their
contents, including pictures supplied by the clipboard.
