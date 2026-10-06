# Split view and edit timeline — development plan

Branch: `dev`, cut from `origin/main` at 03edb49 (the 0.4.6 release merge).
No release number is assigned.

Revision 2, 2026-10-06: challenged against mutation, save, library and exchange
code. Decisions below are development defaults; performance budgets are
proposed acceptance targets, not measured results.

Revision 3, 2026-10-06: checked against the test harnesses and the
session's switching code, and brought in line with the board's
keyboard-first chrome. Implementation starts with gate 2. Revision 3 changes
the decisions in the table below. Where a later section disagrees with it,
the section has been updated.

## Progress

| Gate | State on `dev` |
| --- | --- |
| 1. Inventory | Done; see the appendix |
| 2a. `refactor(pane)` | Done in 3c18505. No visible change; every suite and a headless start of the real plugin pass |
| 2b. `feat(split-view)` | Done in cfe2392. `tests/split.js` drives the switching table, shared edits, leaving rules, library guards and restored state; `tests/qt/tst_split.qml` checks placement and activation |
| 2c. Divider and narrow windows | Done; drag, double-click reset, 320 px minimum, active-pane fallback |
| Live checks for gate 2 | Done in ee50f9d and 520b8ce. `test:omarchy` drives split view with real keys in both host modes; `test:paste` passes; `shots` photographs both layouts; `bench:scene` at 3000 items matches `origin/main` after the boards were moved back to single-board depth |
| 3–6. History | Not started |

A saved second board that no longer exists opens empty in its pane, the way a
missing `lastBoard` always has, rather than restoring a single pane.

Measured on the way: every item level between a board and its window costs
about 1.5ms a frame when zooming a 3000-item board, so `BoardSplit.qml`
parents both boards where a single board sat. Fullscreen is a layer surface,
which the live suite cannot send keys to, so its split stages check fullscreen
by geometry and press keys in the window.

## Revision 3 changes

| Revision 2 said | Found in the code | Revision 3 decision |
| --- | --- | --- |
| Separate `BoardWorkspace.qml` and `BoardPane.qml`, with `Board.qml`/`Node.qml` adapted to a new pane interface | `tests/controller.js` compiles the controller's functions out of the QML source by regex, and `tests/contract.js` checks every `ctl.` name each view reads; four live tests drive `plugin.*` | `BoardPane.qml` keeps the controller's shape (`id: root`, the same members, the same commands) and is the `ctl` every view already reads. Views barely change, and the harnesses load the pane instead of the controller. `Omarchyform.qml` becomes the workspace; there is no separate workspace component |
| A two-phase pane switch: load the target, settle the old document, then rebind | `BoardSession.openBoard` already waits for a slow write, drops the switch if the write fails and refuses to leave a conflict, all covered by tests | A pane whose document nobody else is viewing switches in place through the existing `openBoard`. Only switching onto a board the other pane has open, or away from a shared document, rebinds the pane (see "Switching boards in a pane") |
| Keep dirty or conflicted documents alive after their last view leaves | Hidden documents need a place to show their failures | Never keep a document without a view. Leaving the last view waits for a write in flight and refuses on a conflict or failed save, with the reason on the line, as switching boards does today |
| Edit leases between panes | One pointer can only make one gesture, and the keyboard goes to one pane | Only the active pane may hold a mode (typing, connecting, arranging, palette, find). Leaving a pane ends its modes the way Escape does and keeps its selection, so the other pane has nothing to lease from it |
| Every async operation captures `{documentToken, paneId, paneGeneration}` | Paste, drop and image probing already capture the board path and refuse on a mismatch | Capture the pane as well as the path. A result goes to the pane that asked, only if it still shows that board, and is otherwise refused with the existing "Board changed" message |
| A board selector and a timeline control row in every pane | The approved header is one line, and every command already has a key | No new permanent controls. `b` opens the browser into the active pane, whose header already names its board. The timeline is a mode with a slim strip and keys, not a transport bar |
| Persist per-pane camera and zoom | Cameras are not persisted today; a board opens framed | Persist the layout, the split ratio and the second pane's board. Each pane frames its board on open, as today |
| Undo shows the action label | The undo stack holds snapshots without labels | Labels come with history transactions (gate 4), not with split view |

Keys for split view: `v` toggles **Side by side** and `V` toggles **Stacked**.
In vim, `:vsplit` and `:split` make the same two layouts. Pressing a layout's
own key again goes back to one pane. `o` moves to the other pane. All three
are also in the palette. Letters avoid `|`, which needs AltGr on a German
keyboard. `t` stays free for the timeline.

## Challenges to the first plan

| Earlier assumption | Problem | Revised decision |
| --- | --- | --- |
| Design history first, benchmark near release | Every autosave rewrites the file and copies its predecessor to backup; unbounded snapshots amplify both costs | Prove a bounded checkpoint/patch format before connecting all mutations |
| One step per text session; finalize if autosave needs it | Makes history depend on disk timing and can produce several steps for one drag | Define edit boundaries independently; save only completed document state |
| Rename is a history event | A filesystem move and a JSON edit are separate commits; the existing title is the filename | Exclude library rename/move from canvas history in MVP |
| Registry plus an active pane solves routing | Paste, import, image probing and export can finish after focus or board changes | Capture document identity and pane generation when each operation starts |
| Retain dirty documents after closing a pane | An invisible conflicted document could remain unreachable indefinitely | Block the last view from leaving on save failure/conflict and expose every retained save |
| Reuse the second pane for comparison | Silently replaces the board the user was comparing | Reuse it only if already showing the same board; otherwise ask through an explicit UI choice |
| Pick snapshot limits later | The existing undo stack is already bounded by board size; permanent history has a much larger lifetime | Set initial budgets and a safe continuation path before accepting history edits |

Two workstreams share document ownership, but split view does not depend on
timeline storage. Deliver a working split-only milestone before integrating
history; keep both on the requested feature branch with separate review gates.

## Outcome and scope

Show two boards, or two views of the same board, side by side or stacked.
Each pane has its own board, camera, zoom, selection, modes and history
cursor. A new split starts as a second view of the same board; `b` in a pane
opens another board there. A timeline lets the user step, scrub and play through completed edits.
One pane can remain live while the other shows an earlier state.

MVP includes two panes, both orientations, a resizable divider with a saved
ratio, independent board selection, persistent edit history, timeline controls
and a “Compare with current” command. Build fixed 50/50 splits first, then
add resizing before completion. Use the labels **Side by side** and **Stacked**
to avoid ambiguity about whether “vertical” describes the divider or panes.

Defer animated interpolation, synchronized cursors, more than two panes,
restoring a historical revision, branching history, bookmarks, authorship,
history filters and cross-board object transfer.
History-bearing share/export is also deferred. Existing share commands export
the current canvas only, and imports begin a new local history.

## What the existing code requires

- `Omarchyform.qml` owns one item/link model, camera, selection, undo stack,
  current board and `activeBoard`. Duplicating `Board.qml` alone would share
  these and route painting, focus and export through only one surface.
- `BoardSession.qml` owns loading, autosave, conflict detection and board
  switching. Its single-board transition logic clears selection and undo.
  Two panes need concurrent document sessions, with only one writer per board.
- `Node.qml` changes models during typing and gestures; `pushUndo()` captures
  pre-edit state. History must capture completed edits, not autosave events or
  every pointer move. Autosave coalesces edits, so it cannot define the timeline.
- `BoardStore.js` and `bin/omarchyform` share serialization. A format change
  must cover both writers, import/export, backups and older-version protection.
- Fullscreen and windowed hosts already share controller state. Preserve that
  behavior for the entire workspace, including both panes.
- `BoardLibrary.qml` protects only `currentBoard` and its containing folder
  from trash, and rename checks one board's save/conflict state. These guards
  must cover all open or retained documents, not just the active pane.
- `BoardExchange.qml` has one operation context and an import size limit;
  `BoardImage.qml` is mounted per `Board`. Keep one workspace exchange/export
  operation at a time in MVP, and instantiate heavy export scenes on demand.

## Ownership and component boundaries

| Owner | State and responsibility |
| --- | --- |
| `Omarchyform.qml` (workspace) | Plugin lifecycle, theme, settings and `state.json`, host windows, library, exchange, PNG publishing, layout, split ratio, the two panes, the active pane and the document registry |
| `BoardDocument.qml` | Live item/link models, `nextId`, `nextColor`, undo/redo, one `BoardSession`, its path; later its history |
| `BoardPane.qml` | The `ctl` the views read: document reference, camera, selection, marks, modes, find, palette, menu, status line and every board command. Same shape as today's controller |
| `BoardSplit.qml` | View: one or two `Board`s and the divider, inside either host window |
| `Board.qml` / `Node.qml` | Render and interact through their pane, unchanged in shape |
| `BoardHistory.js` | Pure history validation, transaction records and reconstruction (gate 3) |

The two panes are long-lived objects. The second pane holds no document while
the layout is single. Documents are created when a pane needs a board that no
open document holds. A document is destroyed once its last view has left and
its last write has completed.

### Switching boards in a pane

| The pane's document | The target board | What happens |
| --- | --- | --- |
| Not viewed by the other pane | Not open | In place: `BoardSession.openBoard`, as today |
| Not viewed by the other pane | Open in the other pane | Leave this document (below), then view the other pane's |
| Also viewed by the other pane | Not open | Create a document for the target and view it; the old one keeps its other view |
| Also viewed by the other pane | The same board | Nothing to do |

Leaving a document that has no other view: a conflict refuses and opens the
conflict choice, and a failed save refuses with its error. A write in flight
makes the switch wait. The switch runs when the write completes and is
dropped if the write fails. This is the rule `openBoard` already applies, so
neither a single pane nor a split can strand edits where nobody sees them.
Closing the split leaves the inactive pane's document by the same rule.

Proposed component names are implementation seams, not existing APIs.

The registry is the list of open documents, looked up by library-relative
path. Paths arrive already validated by `Store.safeRelative` and the helper's
`check`. Do not weaken confinement or symlink rules. At most one document
holds a path, so two panes on one board share live models, undo/redo and save
state. Different boards have independent sessions, each with its own watcher,
lock and backup. A rename sets the moved document's path, and the next lookup
finds it there. A persistent history lineage identifies record IDs, not the
registry entry: copied files are separate documents even with copied history.
Hiding the application keeps documents loaded, as today.

The library's guards cover every open document: trash refuses any open board
and any folder holding one. A rename waits until every open document is
settled and none is conflicted. `library.busy` already blocks editing while
the move runs. On success, every document under the moved path follows it.
Failure keeps the original paths.

Keyboard commands go to the active pane. Clicking a pane's header or canvas
makes it active. While split, the active pane carries the accent outline.
Painting follows the document: each pane's delegates repaint their own
connectors, and changes to the connector list repaint every pane on that
document. Fit, paste position, selection and export use the pane's own
viewport.

Modes belong to the active pane. When a pane stops being active, it finishes
typing, ends connecting, arranging, find and the palette, and keeps its
selection and marks. Two panes on one board therefore never both have an
editor open. Marks are item ids and survive another pane's edits. The cursor
is an index, so after the other pane edits the document, a pane looks its
cursor's item up by id again and drops it if the item is gone. Undo/redo
belongs to the document, whichever pane made the edit. Historical panes keep
their own selections.

Asynchronous results go to the pane that asked: paste, drop and image probing
capture the pane and the board path. A result whose pane no longer shows that
board is refused with the existing "Board changed" message, never applied to
another board. One exchange operation and one PNG export run at a time across
the workspace. The export renders from a snapshot of the pane that asked, and
editing pauses everywhere while it renders.

## History contract and persistence

History is an ordered record of accepted document changes, independent of
undo/redo. Each record has a stable ID, monotonic sequence, timestamp, action,
and the data needed to reconstruct the resulting state. Ordering uses the
sequence, not the wall clock. A pane stores a record ID or `live`, not a
mutable array index; convert IDs to slider positions for display.

Define `beginEdit(action)`, `commitEdit()` and `cancelEdit()` around mutations.
Each completed transaction produces at most one history record and publishes
an immutable committed head. Cancel restores its pre-edit state; unchanged
transactions produce no record. Undo and redo append resulting states as new
timeline records without consuming or rebuilding the undo stack from history.
Text undo grouping remains an independent policy; history chunking must not
silently change existing undo behavior.

| Interaction | History boundary |
| --- | --- |
| Drag / resize | Release commits one record; cancellation restores the starting state |
| Discrete command / grouped command | One successful command, covering all affected items |
| Held move / resize keys | Key release, focus loss or command change ends the gesture |
| Text | 750 ms idle, blur, explicit completion, or 5 s maximum chunk duration |
| IME text | No boundary through uncommitted composition; commit the accepted text afterward |
| CLI | One successful mutation/batch; failed or no-op commands add nothing |

Timer boundaries are deterministic editor events, independent of save
completion. Continuous typing can therefore produce several labeled text
chunks. Entering history, changing boards or hiding the host finishes accepted
text and ends gestures before moving the pane; Escape during ordinary text
editing still keeps text as today. Define pointer-cancel separately from text
Escape. Explicit Save completes the current accepted edit before flushing.
Camera, selection, layout, playback and scrubbing never create history.

Start old boards at an explicit “History starts here” baseline. Do not infer
past edits from item IDs. Canvas history includes items, links, paint order,
and ID allocation. Library rename/move/trash are outside MVP history. Future
in-file board properties must be included when introduced. Theme, camera and
split direction are local state, not document edits.

Recommended MVP storage: versioned history inside the board JSON, committed
with the live state by the existing lock/revision/backup/atomic-replace path.
This avoids a two-file commit where the document and history can disagree.
Bump the board format so older writers refuse to silently discard history.
Preserve unknown/future history as read-only, with a clear reason.

Production candidate: one baseline plus forward patches keyed by stable item
IDs, with explicit link changes, paint order and `nextId`. Start with checkpoint
spacing of 100 records, but budget additional persisted checkpoints to at most
4 MiB within the history limit; increase spacing when necessary. Removing a
redundant checkpoint must not remove any event. Benchmark the resulting longer
replay distances, and cache only a bounded number of reconstructed states.
Snapshots serve as the test oracle, not the production event representation.
Validate schema, record IDs, ordering, references and the reconstructed head
against the stored live state. Never silently repair a corrupt history into a
writable document. Cap input size and record count before expensive replay.

Initial candidate limits: 16 MiB serialized history or 10,000 records per
lineage, whichever comes first. These are bounded-history defaults, not a
promise to retain unlimited edits. At the limit, keep the existing history
intact and offer **Continue in a new board**: write a current-state-only copy
with a fresh baseline using the existing unique publish path, then switch
only after success. Failed copy leaves the original open. No automatic purge,
silent recording pause or overwriting of history. Capacity checks happen
before accepting a completed change. If the change crosses the limit, retain
its working snapshot, stop further mutations in that document, and offer to
publish that snapshot as the new board's baseline. The original committed
head and history remain saveable; canceling the continuation keeps the draft
available, with an explicit discard option. CLI capacity failure leaves the
original file untouched and explains how to copy the current board first.
The limit counts checkpoints too. Validate these limits through gate 3 measurements and document
any adjustments before integration. Image bytes have separate existing limits.

Autosave persists all pending completed steps even when writes are coalesced.
It serializes the immutable committed head, not transient dragging/typing
models, so disk timing cannot split a gesture. Live panes can show transient
state; the timeline latest record shows the latest completed edit. Saving an
earlier head must leave later completed changes dirty and schedule another
write. Successful completion acknowledges the captured head revision only.
Failed saves retain live changes and history together for retry; the UI must
not claim those steps are durable. A crash can lose unsaved steps, as it can
lose unsaved edits today. An in-progress gesture remains unsaved until it ends;
text's maximum chunk duration bounds continuous-typing exposure except while
IME composition is uncommitted. Save state
must distinguish pending edits from the last durable head.

Update the CLI's `readBoard`/`writeBoard` pipeline to carry history, not just
the codec; it currently reconstructs an object containing only live state.
An accepted external reload that extends the same lineage keeps valid cursors.
A non-extension is a replacement: pause playback, invalidate affected cursors
and explain the reset. A valid historyless file gets a new baseline; an
inconsistent history-bearing file is read-only. Never invent intermediate
edits or claim a single total order across conflicting writers.

Conflict handling stays explicit and per document. Use Disk adopts its whole
state/history. Replace Disk writes the local state/history under the existing
explicit resolution path; it does not merge timelines. Save a Copy preserves
the local version and its history in a separate file. Pending operations must
retain their captured document identities throughout resolution.

Plain and portable sharing use a distinct current-state serializer that omits
history; internal saves, backups and conflict copies preserve history. Explain
that sharing omits previous revisions. External import validates the input
and starts a new baseline from the accepted current canvas. Retain image
assets referenced by internal history, including images absent from the live
board. Do not add image garbage collection in this branch. A missing asset
shows a placeholder without preventing navigation. Keep existing bundle/import
limits explicit; a large internal file is not automatically a shareable bundle.

## Pane and timeline behavior

Persist the layout as `single`, `side-by-side` or `stacked`, the split ratio
and the second pane's board in `state.json`. `lastBoard` stays the first
pane's board, so an older plugin still reads the file. Cameras are not
persisted: each pane frames its board when it opens one, as today. Selection
and editor state are transient. Restore panes at Live with playback paused
after restart. Preserve cursors and cameras when switching between fullscreen
and windowed, and pause playback during the switch. A saved second board that
no longer exists or fails the path check restores a single pane.

The timeline is a mode of the active pane, like find or arrange, not a row
of controls. `t` enters it and draws a slim strip along the bottom of the
pane. The strip shows the position, the edit's action and time, and a
read-only marker in the header. The keys are `h`/`l` to step, `H`/`L` for the
baseline and the latest edit, `space` to play or pause, `1`–`4` for 0.5×, 1×,
2× and 4×, and `esc` to return to Live. The hint line under the header says
these keys, as it does for every mode. A pointer can click or drag the strip
to scrub. At 1× playback advances one completed edit per second, whatever
the original idle time was. Play from the final record restarts at the
baseline. Play from Live starts at the baseline and captures the current
completed head as its endpoint. Playback pauses when scrubbing, changing
boards, closing the surface or reaching the playback endpoint. Use a QML
Timer, never a blocking loop.

Live is an explicit state. A historical cursor remains on the same record
when new edits arrive. Playback captures an endpoint at Play and stops there;
only Live resumes following incoming edits. Disable unavailable navigation
for empty/baseline-only history. Handle invalid saved board references safely.

Historical rendering uses separate preview models. Panning, zooming and
inspection remain available; editing, undo/redo, paste/drop and document
mutations are blocked at the command layer as well as in controls. Scrubbing
must never replace live models, trigger saves or disturb another pane's editor.
For MVP, disable export from historical panes with an explanatory command
state; historical export can be added deliberately later. An active pane must
finish its own edit before entering preview; this does not finish or cancel
an editor in another pane.

Throttle pointer scrubbing to at most one reconstruction per display frame;
latest requested record wins, and obsolete work must not display afterward.
Use the nearest checkpoint and retain the exact selected record after release.
Do not interpolate camera or item positions in MVP. Each pane has at most one
playback timer; stop and release it on pane destruction. Baseline-only history
disables Play as well as unavailable step controls.

“Compare with current” puts the active historical view beside a Live view of
the same board. If the other pane shows a different board, the command offers
an explicit “Replace other pane” choice showing that board's name, then uses
the same safe switch lifecycle. Cancel keeps both views. When invoked from
Live, put the previous completed edit in the comparison pane (baseline if no
previous edit), with a clear no-history state where appropriate.
Divider limits keep both panes at least 320 px across. In a window too small
for two panes, show the active pane alone, with `o` on its hint line,
and keep the requested layout for when space returns. Drag the divider to
resize and double-click it to reset to 50/50. The palette's **Even out the
split** does the same from the keyboard.

## Implementation sequence and review gates

1. **Map contracts and mutation paths.** Inventory every `ctl` member used by
   views, session, library and exchange, plus direct model writes. Assign each
   to workspace, document or pane; identify async completion ownership. Gate:
   a checked-in inventory covers every write path, including CLI and text.
   Done in revision 3; see the appendix.
2. **Extract ownership; deliver split view.** Three commits, each leaving the
   board usable and every suite green:
   - *2a `refactor(pane)`.* Move the models, ids, undo/redo and the session
     into `BoardDocument.qml`. Move the camera, selection, modes and commands
     into `BoardPane.qml`. `Omarchyform.qml` keeps one pane and one document.
     Users see no change. `tests/controller.js` loads the pane, document and
     workspace sources, and `tests/contract.js` checks the views against the
     pane and the session against the document.
   - *2b `feat(split-view)`.* Add the second pane, `BoardSplit.qml`, `v`/`V`/`o`,
     switching boards per pane, the library guards over every open document,
     pane-captured async results, the accent outline on the active pane, and
     the layout in `state.json`.
   - *2c.* Add divider dragging and reset, the narrow-window fallback, help
     and README.

   Gate: existing tests pass. In both host modes, same-board and
   different-board splits save and route input correctly. A failed save or a
   conflict cannot be hidden by closing a pane. This is a usable milestone
   independent of history and format changes.
3. **Prove history storage and resource budgets.** Prototype patch/checkpoint
   codec and transaction boundaries in an isolated test harness. Measure full
   save/backup/reload and random seek, not only patch size. Gate: fixtures meet
   targets below; settle limits and continuation UX before recording real edits.
   If embedded rewrites fail the gate, write a separate storage design for a
   journal with crash recovery; do not quietly add a sidecar halfway through.
4. **Integrate recording and migration.** Wire every mutation, committed-head
   autosave, CLI, format bump, validation, copy/share and capacity handling.
   Gate: each boundary produces the expected event, replay equals live state,
   and delayed writes, failures, conflicts and old files preserve correctness.
5. **Add previews and timeline.** Independent read-only models first, then
   scrub, steps, playback speeds and comparison. Gate: preview never mutates
   live state/undo/save status; stale callbacks and new edits cannot move a
   pinned cursor; playback stops deterministically.
6. **Release review.** Repeat resource tests with real QML rendering and both
   panes; complete isolated live checks, help, README and migration notes.
   Gate: all criteria below pass and limitations are documented. Do not ship
   recording if storage or recovery still has unresolved correctness issues.

Use separately reviewable commits for each gate, splitting refactors from
behavior changes. Avoid assigning a release until the ownership and storage
gates are proven. Keep editable connector work separate or explicitly rebase
this plan if its format change lands first.

Suggested commit groups: `refactor(pane)` → `feat(split-view)` →
`feat(history-codec)` → `feat(history-recording)` → `feat(timeline)`.
Keep tests with the behavior they protect. The feature branch stays usable
between groups; experimental storage fixtures must not rewrite users' boards.

## Resource gates

Measure on the supported Omarchy machine, report hardware, baseline and p95
over repeated runs. These initial targets can be revised with evidence at
gate 3; none is an existing benchmark result.

| Workload | Initial acceptance target |
| --- | --- |
| 1,000 items / 5,000 mixed edits, two panes | Scrub input to displayed selected revision p95 ≤100 ms |
| 3,000 items / 10,000 mostly position edits | Same seek metric p95 ≤200 ms; visible loading feedback beyond 100 ms |
| Main-thread history work | No single encode/reconstruct task over 50 ms; chunk work if needed |
| Save plus predecessor backup, local disk | p95 ≤250 ms at the candidate history limit; no input blocking during filesystem work |
| Two panes plus history cache | Incremental process RSS ≤128 MiB over the same two panes without history |

The ordinary mixed-edit and position-edit fixtures must fit the candidate
capacity; failing early at the size cap is not a passing performance result.
In particular, checkpoint spacing must not consume the budget before those
workloads can be represented.

Measure large text replacements and image-heavy boards separately; reaching a
documented capacity limit is acceptable, silently dropping their edits is not.
Check library loads and CLI buffer limits against maximum accepted files.
Do not pre-create preview/export models for every retained document. Bound the
reconstruction cache and evict clean, unreferenced document sessions promptly.

## Validation

- Pure JS tests: baseline/migration, event ordering, no-op transactions,
  undo/redo events, stable cursors and exact snapshot/patch reconstruction.
  Add generated mutation sequences checked against a snapshot oracle, including
  item deletion/recreation, paint order, ID allocation and malformed patches.
- Controller and filesystem tests: delayed writes, retry, conflicts, CLI
  round-trips, concurrent panes, rename/trash, external reload and backups.
- QML tests: independent cameras, selection, focus, read-only preview,
  slider endpoints, timer cancellation, divider limits and restored layouts.
- Transaction tests with controlled clocks: text idle/max-duration boundaries,
  IME composition, canceled drags, held keys and autosave during an edit.
- Routing tests: paste/image/import/export completion after focus change,
  board replacement, pane removal or rename; no effect on the wrong board.
- Integration: same board Live/Live and Live/History; different boards;
  deleting a selected item in the other pane; closing with a pending save;
  changing host window mode; missing historical image; malformed history.
  Also cover folder rename with two affected documents, trash protection for
  the inactive board, capacity continuation failure, and a non-extending
  external lineage while a pane is playing.
- Run `npm test`, `npm run test:qml` and `npm run test:ui`, plus repository
  validation/lint and isolated Omarchy live checks before release. Extend
  `npm run bench` and `npm run bench:scene` for two panes and long histories.
  Include 1,000/3,000-item fixtures, thousands of edits and large text/images;
  record hardware and measured results against the proposed budgets above.

No application tests are needed for this planning-only document. Runtime and
performance claims remain acceptance criteria until implementation is tested.

## Appendix: gate 1 inventory

Taken from `origin/main` at 03edb49. "Reads" are the `ctl.` names each file
uses; `tests/contract.js` enforces them by name.

| Reader | Members it reads | Owner after 2a |
| --- | --- | --- |
| `Board.qml`, `Node.qml`, `BoardToolbar.qml`, `Commands.qml`, `Conflict.qml`, `Help.qml`, `Browser.qml` | Camera, selection, marks, modes, palette, menu, find, status, every command, `items`/`links`, save state, `theme`, `library`, `showGrid`, `canvasPattern`, `imagePath`, `dataDir` | Pane. Document and workspace members are forwarded read-only under their current names |
| `BoardSession.qml` (`session.ctl.`) | `items`, `links`, `nextId`, `nextColor`, `undoStack`, `redoStack`, `currentBoard`, `boardPath`, paths and helpers, `autosaveMs`, `stateReady`, `writeState`, `library`; resets `selectedIndex`, `markedIds`, `showPinned`, `editIndex`, `linkingFrom`; calls `resetView`, `repaintLinks`, `focusKeys`, `flash`, `decideConflict` | Document. The five selection writes become one `resetSelection()`, which the document passes to each pane viewing it, as it does the view calls |
| `BoardExchange.qml` | `currentBoard`, `items`, `links`, `nextId`, `canEdit`, `boardLoaded`, `activeBoard`, `pasteText`, `imagePasted`, `imageDropped`, `exportPng`, `stopEditing`, `focusKeys`, paths | Workspace-owned, bound to the active pane when an operation starts. Paste and drop completions use the pane they captured |
| `BoardImage.qml` | `items`, `links`, `imagePath`, `minItemSize`, `theme` | Pane (its own Board) |
| `BoardLibrary.qml` (told, not reading) | `currentBoard`, `boardConflicted`, `boardSettled`; signals `openRequested`, `currentMoved`, `aboutToRename` | Workspace. Told the active pane's board and every open board. `currentMoved` becomes a move of any open document |

Write paths into a document's models, all in the pane after 2a:

| Path | Entry | Ends with |
| --- | --- | --- |
| Commands | `addItem`, `duplicateTargets`, `removeAt`, `layerTargets`, `recolorItem`, `cycleKind`, `togglePin`, `addLink`, `unlinkSelected`, `applyMoves` (align, spread), `nudgeSelected`, `resizeSelected` | `pushUndo` before, `save()` after |
| Pointer gestures | `Node.qml` drag and resize grip: `pushUndo` on the first move, `moveTargets`/`resizeTargets` per frame | `save()` on release |
| Text | `Node.qml` writes `itext` per keystroke after `editSelected`'s `pushUndo` | `scheduleSave()`; `flushSave()` on blur |
| Clipboard and files | `pasteText`, `pasteImage` (via `imagePasted`, `imageDropped`, the board's size probe) | `save()` |
| Undo/redo | `restore` refills both models | `save(true)` |
| Session | `loadBoard` (open, external reload, Use Disk) refills the models | Baseline for the next write |
| CLI | `bin/omarchyform` rewrites the file | The document's watcher: reload, or a conflict |

Every pane write ends in `save()`, `save(true)` or `scheduleSave()`, so that
is where a pane tells the document it has edited. The document passes this to
the other pane, which then looks its cursor up by id again.

