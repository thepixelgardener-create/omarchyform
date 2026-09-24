# Product review: an excellent keyboard-first board

Reviewed 2026-09-24. These are proposed product changes, not implemented features.
Evidence: current QML/manifest/README, the live test captures, and the verified
board creation and editing flows. No user study or interaction-latency benchmark
has been performed, so the prioritization below is a design judgment.

## The promise

**Capture a thought, arrange it spatially, get back to work.**

Omarchyform can be a small, local thinking surface that feels immediate from the
keyboard. Its strengths are keyboard navigation, spatial organization, native
theme integration, local files and continuity between overlay and window.
Measure new features against that workflow, not against another application's
feature count. Replace the README's “Think Apple Freeform” comparison with this
positive description once the entry and exchange workflows support it.

## Three biggest grievances, ranked

### 1. Starting is harder to discover than editing

Today, installation does not provide a dedicated launcher entry. The user adds
a bar widget or configures a binding. Opening resumes the remembered board (or
the default board.json). A separate named board requires `b`, `a`, a name,
Enter, then `n` to write. The browser has a textual hint, but the initial blank
canvas has no focused starting action. Naming comes before thinking.

Keep instant resume. Add a launcher entry that uses the existing shell instance,
plus one obvious New board action available without entering the browser.
A proposed Ctrl+N creates an automatically named board and focuses its first
note immediately; naming can happen afterward. Keep `b` for switching, with
search focused when useful. An empty board should show “n: start a note” and
“paste text” when paste-to-note exists. Do not force returning users through a
home dashboard or onboarding wizard.

Acceptance: someone who has never read the README can launch and type a thought;
a returning keyboard user creates a separate board with one command, and can
switch back without opening a filesystem tool.

### 2. The board is disconnected from the rest of the work

Plain JSON gives ownership, but it is not a usable import/export interface.
Text can be pasted inside an active TextEdit; pasting on the canvas does not
create a note. There is no board import command, image drop/paste, or visual
export. An idea copied from an editor needs extra steps to enter the board;
a finished diagram needs a screenshot or manual JSON file handling to leave it.

Smallest useful sequence:

1. Canvas paste creates a plain-text note at the viewport center and selects it.
   Preserve multiline text; do not unexpectedly split it into dozens of notes.
2. Export a board as PNG, fitted to content rather than the current viewport,
   without selection grips, hint text or browser chrome. Give it a readable
   background and deterministic size. This completes the simplest sharing loop.
3. Open/import a native board and save/export an exact editable copy. Validate
   version, copy into a fresh path, never overwrite another board implicitly.
4. Image paste/drop, if users use screenshots as thinking material. This needs
   local asset ownership and portable packaging; references to arbitrary source
   paths are not a complete solution. Repeatedly pasting huge images must not
   freeze the shell.

PDF/SVG can follow when printing or scalable diagrams are demonstrated needs.
For any format, explicitly distinguish a visual snapshot from an editable board.
If migration from Apple Freeform is requested, assess its exported files first;
a PDF or image import is a reference surface, not restoration of editable notes
and connectors. Do not promise a general Freeform converter without a tested
format and fidelity contract.

### 3. The canvas looks sparse rather than deliberately finished

The live captures show useful content but little visual structure. Dots remain
visible through every item; the resize grip is always drawn; notes and shapes
share almost the same treatment. Board identity and command hints live in the
same low-contrast footer, and a transient message replaces that context. There
is no persistent zoom indicator. Keyboard selection, multi-marking and pin mode
ask users to infer too much from outlines and text.

Polish the existing vocabulary before adding tools:

- Keep the board name and save state in a small, stable header. Put zoom/fit
  nearby. Keep command hints separate from temporary feedback.
- Reduce grid emphasis, increase text/surface separation, and give notes more
  readable padding. Preserve Omarchy's font, colors and corner conventions;
  rounded corners alone would not solve this.
- Show resize grips on selected/hovered editable items. Give the keyboard cursor
  a distinct visual treatment from secondary marks, and a clear focus outline.
- Make background-selection mode visibly distinct, not only a footer sentence.
  Its foreground items should recede while the selected background is emphasized.
- Fix content overflow deliberately: long notes need a tested wrapping/scrolling
  or resize policy, rather than text disappearing beyond the item's visible area.

After that, a modest alignment aid or duplicate command may improve spatial
editing more than another shape. Freehand drawing is not required for the
keyboard-first promise; add it only if sketching becomes a core workflow.

Acceptance: empty, typing, selected, marked, pinned, saving and failed-save states
are distinguishable in light/dark themes and at small window sizes. Common
operations remain readable without displaying a permanent shortcut catalogue.

## Does it need a CLI?

Not a full command suite. It needs an easy launch path, and a launcher entry is
more important than requiring a terminal. If a thin CLI helps bindings or other
programs, keep it to open/new (and perhaps a board path), routed through the
existing shell controller. The current payload accepts settings only, so this
would need explicit action/path handling; a wrapper alone cannot safely provide
these operations. Never introduce a second writer for open boards.

Piped capture or headless export should follow real demand. “Keyboard-first”
means excellent keyboard interaction, not that every user action belongs in a
shell command.

## Speed must be tested as interaction

Current benchmarks measure JSON serialization/loading, not warm-open latency,
key-to-feedback time, frame pacing, or delegate creation at board size. Preserve
those unit benchmarks but add measured warm opening, note creation, navigation,
pan/zoom, and switching with representative boards before claiming “instant”.
Use results to justify rendering changes; do not introduce culling or caching
speculatively. A large rewrite would delay the actual usability improvements.

## Code cleanup now versus later

Removed an unused removeProc, an unused browser modifier variable, and the
write-only saveWanted flag. Save completion already serializes the latest model,
which is the actual queued-edit guarantee. Keyboard movement/resizing now reuse
the pointer geometry helpers, keeping target filtering and size limits together.
Existing persistence, controller and live tests verify this cleanup.

The controller still owns browser navigation, filesystem operations, editing,
and window lifecycle in one large file. Extracting a dedicated board-library
component is the next plausible structural refactor, especially before native
import/export. It should have an explicit interface and preserve the current
asynchronous tests; splitting it merely to reduce line count is not worthwhile.
Keep the working session/persistence split. Do not rewrite everything before
shipping the small improvements above.
