# Omarchy compatibility review

Reviewed on 2026-09-24 against the installed system:

- Omarchy `4.0.0.r2158.gd174d4a-1`
- Quickshell `0.3.1`, Qt `6.11.2`
- Hyprland `0.56.2` (`efb50993780079460b0cbed1363e2166a2de1d9f`)

This is a review of this build, not a promise of compatibility with every
Omarchy release. The user's installed plugin has independent uncommitted
changes, so it was neither overwritten nor restarted. Tests use temporary
board data and an isolated plugin instance on the actual Wayland compositor.

## Documentation and first-party baseline

The authoritative baseline was the documentation and source shipped with the
installed package:

| Reference | What was checked |
| --- | --- |
| `/usr/share/omarchy/shell/README.md` | Manifest, injection, scoped capabilities, lifecycle, installation, reload |
| `/usr/share/omarchy/shell/plugins/README.md` | First-party overlay examples and discovery |
| `shell/plugins/emojis/Emojis.qml` and `manifest.json` | `opened`, `open`, `close`, `dismiss`, exclusive overlay keyboard focus, Style/Color tokens |
| `shell/plugins/clipboard/Clipboard.qml` | Cleanup of transient state in host-triggered `close()` |
| `shell/services/PluginShellApi.qml` | Third-party lifecycle facade |
| `shell/services/PluginRegistry.qml` and `omarchy plugin validate` | Manifest schema and entry-point validation |
| `shell/shell.qml` | Loader property injection, `hide()` calling `close()`, panel unload on plugin rescan |
| `shell/Commons/Style.qml`, `Color.qml` | Fonts, spacing, palette, theme updates |

Paths beginning with `shell/` above are relative to `/usr/share/omarchy`.
Keyboard injection uses the current [Hyprland Lua dispatchers](https://wiki.hypr.land/configuring/core/dispatchers/),
targeting only the test process by PID.

## Findings addressed

- **Host lifecycle:** `close()` now flushes pending edits and clears transient
  editing, linking, help, and browser state. `dismiss()` uses the same cleanup
  before notifying the scoped shell facade.
- **Keyboard continuity:** deleting an item restores the board's keyboard
  owner; otherwise the live test found subsequent shortcuts stranded on the
  outer focus scope.
- **Theme rendering:** the dot grid, connector canvas, and painted shapes now
  request repaint when their bound colors change. A pixel-level Qt test checks
  an ellipse after its fill changes; live captures also verified the grid.
- **Narrow windows and larger fonts:** footers wrap, the browser reserves space
  for its footer, and help is a bounded, scrollable component. Help consumes
  keyboard commands so reading shortcuts cannot delete notes behind it.
- **Search mode:** an empty search query still shows the search prompt.
- **Saving while typing:** Ctrl+S is handled by the note editor as well as the
  board command handler. An in-flight save is visible in the footer.
- **Dependency and development guidance:** removed the unused `qs.Ui` import;
  corrected the README's reload and idle-resource descriptions.

## Follow-up validation: reliability and background pinning

The subsequent working-tree changes pass 79 pure tests plus controller,
contract and filesystem regressions; 13 Qt results including setup/cleanup;
and persistence, session and real delayed-backup tests. The extended live
suite verifies pin/unpin rendering and persistence, mark-all exclusions,
trash restoration and the existing keyboard/window/monitor workflows.
Mutation testing reports 174/190 killed, 16 survivors. QML lint still has only
the metadata warnings described below. The initial follow-up run failed after
reopen (stage 42); later complete runs passed without a focus-specific fix.
A browser-readiness guard required the harness to await index loading before
issuing its next filesystem command.

Current live artifacts: `/tmp/omarchyform-compat-PjcpVJ` (temporary). This still
is not a registry installation or in-place upgrade test.

## Original validation results

| Check | Result |
| --- | --- |
| `omarchy plugin validate .` | Passed against the installed validator |
| `npm test` | 69 pure-logic tests plus controller scenarios passed |
| `npm run mutate` | 137/151 mutants killed; 14 survivors; diagnostic, not a gate |
| `npm run test:ui` | 8 behavior tests passed; QtTest reports 12 including setup/cleanup |
| `npm run test:qml` | Real backup/write ordering, failure, retry, and session tests passed |
| `npm run test:omarchy -- --keep` | Full plugin passed on live Wayland with installed Commons and shell-facade code |
| QML lint with the installed `qs` import tree | No import failures; remaining metadata warnings described below |
| `git diff --check` | Passed |
| Main shell health after testing | `omarchy-shell shell ping` returned `ok` |

The live test covers:

- Mounting a tiled window and fullscreen overlay; rendering and reopening.
- Focused-monitor selection and overlay dimensions. Runs during this review
  rendered on HDMI-A-1 (3840×2160 physical) and eDP-1 (1920×1080 physical), at
  scale 1.6. The runner also exercises a second output when one is available.
- Real targeted keyboard input: new note, text, Escape, browser open/close,
  help open/close, and shortcuts after deleting a note.
- Notes, shapes, connectors, undo/redo, nudging, recoloring, and fitting.
- Board/folder creation and rename, following an open board through a folder
  rename, refusing deletion of its folder, cancelling deletion confirmation,
  and confirmed deletion after switching away.
- Host-style close and reopen, plus the actual window visibility-close path
  notifying the injected facade.
- Theme updates without changing the user's theme files or live shell palette.

Qt Quick tests additionally send actual pointer events for dragging, resizing,
and double-click editing, verify read-only behavior, test Ctrl+S inside the
editor, and exercise help/browser layout at 480×360 with a 24px body font.

## Limits and follow-up work

- The full-plugin harness loads the installed Commons and scoped facade, but
  does not install this branch into the user's already-modified plugin checkout
  or replace the running shell's registry. It does not claim an in-place plugin
  upgrade test.
- `qmllint` still reports Quickshell's `PanelWindow` creatability and
  `QProcess::ExitStatus` metadata warnings, plus dynamic Style font-object
  property warnings. The live runtime loads these types and properties without
  warnings. Do not blanket-ignore unrelated future lint warnings.
- Power loss, forced process termination, disk exhaustion, and monitor hotplug
  were not fault-injected. Write failure and failed backup are exercised with
  invalid filesystem targets, not a full physical disk.
- Plugin reload destroys overlay instances even with `keepLoaded: true`.
  Pending asynchronous writes are not guaranteed to survive forced unload or
  shell termination. Finish saving before rescan/restart; crash recovery or a
  durable save journal remains follow-up work.
- Large-board performance, IME/accessibility, and external sync conflict
  handling still need dedicated work. The existing one-generation backup is
  not conflict detection or version history.

## Reproduction

```sh
omarchy plugin validate .
npm test
npm run test:ui       # Qt Quick test runtime, no desktop needed
npm run test:qml      # installed Quickshell, isolated headless instances
npm run test:omarchy -- --keep  # actual Omarchy desktop; opens test surfaces
```

The live command prints an artifact directory containing the runtime log and
captures of the window, help, themed canvas, and overlay. All board operations
use its temporary home. Without `--keep`, it removes the directory afterward.
