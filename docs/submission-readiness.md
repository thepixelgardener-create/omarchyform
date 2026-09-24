# Submission readiness review and fixes

Initial review: 2026-09-24 at `9dbedd9`. The findings below are retained as the
record of that review; remediation is now implemented in the working tree.

## Current status

All six findings have been addressed or rechecked:

- Restore uses exact-path moves, refuses occupied destinations and retains the
  trash entry on failure. Filesystem actions reject traversal and symlink paths.
- Marks clear on board transitions and undo/redo. Backups mirror board paths
  under `backups/v2/`, leaving older backups untouched.
- Slow saves retain writer ownership. An actual blocked-backup test verifies
  that timeout notification cannot let a retry redirect the in-flight save.
- Qt UI tests have a complete Node fixture and fail on runtime errors. The
  extended live test passes, including keyboard input after reopening. The
  earlier stage-42 failure was not reproduced; no specific cause is claimed.
- Browser filesystem operations are serialized. Invalid trash indexes are
  preserved, and index read/write failures remain visible and retryable.
- Background pinning, Shift-click marking, group pointer movement/resizing,
  shape-correct connector endpoints and a 100-step undo cap are implemented.

Pinning uses one boolean and board format v4. `p` pins; `Shift+P` selects
backgrounds to unpin. Foreground pointer handlers step aside in background
selection mode, so covered backgrounds remain reachable. No layer panel,
groups or additional settings were introduced.

Validation after the fixes: 79 pure tests plus controller, contract and
filesystem checks pass; 13 Qt results including setup/cleanup pass without
runtime TypeErrors; real persistence, session and delayed-backup suites pass;
the extended live Wayland test passes. Mutation testing kills 174/190 mutants
(16 survivors, diagnostic only). QML lint exits 0 with the previously documented
Quickshell/Style metadata warnings. Plugin validation and `git diff --check`
pass. Live artifacts: `/tmp/omarchyform-compat-PjcpVJ` (temporary).

Submission destination is still unconfirmed. A fresh registry install/upgrade
check and destination-specific submission requirements remain release steps.
The installed plugin and user board data have not been replaced.

## Original review

The useful promise is: **A local, keyboard-first board for arranging thoughts
on Omarchy.** The original decision was to fix reliability before submission,
without expanding the product into a larger drawing platform.

## Original findings (addressed above)

### 1. Restore can claim success without restoring the board — high

`Omarchyform.qml:722–731` uses `mv -n`, and `1024–1034` removes the trash
index entry on exit status zero. On this machine, moving a file over an
existing file with `mv -n` exits zero while leaving the source untouched.
The UI therefore says “restored” and removes the only browser reference to
the old board. Its bytes remain in trash but recovery requires manual work.
For an existing destination directory, the source is moved *inside* it.

Reproduced both command behaviors with disposable files. Use a move operation
that refuses collisions with a distinguishable failure and treats the target
as an exact path. Keep the index entry until the intended move is confirmed.
Test file collisions and folder collisions through the actual restore handler.
Audit rename and trash moves for the same no-clobber success assumption.

### 2. Trash paths are not confined to their directories — high

`BoardStore.js:316` accepts arbitrary nonempty `file` and `path` strings.
The restore and purge handlers concatenate these into filesystem paths;
purge invokes `rm -rf`. A modified index entry with `file: "../boards"`
is accepted and can target the boards directory after explicit purge.
This is a local metadata trust problem, not a demonstrated remote attack.

Reproduced acceptance through `readTrash`; no destructive command was run.
Validate trash filenames as single safe path segments and original paths as
safe relative paths. Enforce confinement at the filesystem-operation boundary,
including symlink behavior. Apply corresponding validation to `state.lastBoard`.

### 3. Marks leak between boards — high

`BoardSession.qml` resets selection and history on board load but does not
clear `markedIds`. Item IDs are only unique within a board. Mark item 1 on
board A, then load board B containing item 1: B's unrelated item becomes a
target for delete, movement and recoloring without a new mark.

Reproduced using the existing controller harness: after load, marks remain
`[1]`, selectedIndex is reset, and `targets()` nevertheless returns `[0]`.
Clear marks on successful board transitions; also define how marks are
reconciled after undo/redo rebuilds the model.

### 4. Save timeout releases ownership while work may still run — high

`BoardPersistence.qml:29–65` makes the writer available after eight seconds
without cancelling or retiring the pending process/FileView operation.
The callbacks subsequently read mutable `target` and `contents` properties.
A retry can replace those fields before the previous callback arrives.

This is a source-level race finding, not a reproduced slow-filesystem failure.
Keep operation identity and ownership until completion or confirmed cancellation;
ignore stale callbacks. Test timeout during backup, timeout during write,
retry, and late completion before declaring the save pipeline safe.

### 5. Different boards overwrite each other's backups — medium

`Omarchyform.qml:934` flattens `/` to `__`. Both `work/a.json` and
`work__a.json` map to `work__a.json.bak`. Saving one rotates the other's backup.
Confirmed by evaluating the naming transformation.

Use collision-free encoding or a mirrored directory tree. Preserve existing
backups during migration. Test the two paths above and a nested path.

### 6. Runtime verification is not currently clean — release gate

The Qt UI suite reports 12 passes but emits a TypeError because its controller
stub lacks `isMarked`. The live desktop suite fails at stage 42: after reopening,
the injected `n` does not produce the expected new item in edit mode. The test
does not establish whether this is a focus/input-delivery issue or a harness
assumption. Diagnose that distinction before changing application behavior.

Add the missing fixture contract and make unexpected QML runtime errors fail
the UI runner. Obtain a clean full live run; do not reuse the previous review's
green result as evidence for this checkout.

## Smaller correctness and presentation work

- `nameIsValid` accepts newline characters, but `find` output is parsed by
  newline. Such a name can be created but cannot be represented faithfully in
  the browser. Reject control characters or use unambiguous listing framing.
- Trash index writes have no save-failure handling. A successful move followed
  by a failed index write can strand recoverable data. Surface failures and
  retain enough information to recover/reconcile the move.
- Browser processes keep mutable pending metadata and have no visible busy
  guard. Rapid repeated operations need a targeted test before assuming each
  completion refers to the originally requested operation.
- `edgePoint` intersects a bounding rectangle for every shape. Diagonal
  connectors visibly miss the actual outline of ellipses and diamonds. Add
  shape-specific intersections if these shapes are advertised in the release.
- README says multi-selection is missing even though it documents marks.
  It also implies moving/resizing marked items applies universally, while
  pointer dragging clears marks and resizing changes one item. Describe the
  keyboard behavior precisely or make pointer behavior consistent.
- README omits Ctrl+HJKL from its main key table. The existing compatibility
  report's counts predate this review. Keep detailed testing history in docs;
  shorten the main README to purpose, install, essential controls and storage.
- The undo comment promises 100 steps on small boards, but the formula allows
  20,000 snapshots for a one-item board. Choose an explicit upper cap; item
  count alone also does not account for very long note text.

## Small background-pinning design

Interpret “anchor” as **fixed in board coordinates and behind working items**.
It should move with pan and zoom. Viewport-fixed elements would be a separate
feature and are not needed for background shapes.

Proposed interaction:

1. Select an item, size/place it, press `p` to pin it as background.
2. It renders behind connectors and ordinary items, and stops intercepting
   normal pointer gestures. Dragging its empty area pans; double-clicking
   creates a note, just like the canvas.
3. Pinned items are skipped by ordinary directional navigation, Tab and
   mark-all. They cannot be accidentally moved, resized, edited or deleted.
4. `Shift+P` temporarily exposes pinned items for selection; select one and
   press `p` to unpin it. Escape exits that mode. A short footer message makes
   the mode visible. No additional panel is necessary.
5. Pin/unpin is undoable and persists in the board. Background bounds count
   towards “fit board”. Existing connectors remain intact.

Use one boolean, `pinned`, rather than introducing groups, nesting, arbitrary
z-order controls, a layer list or multiple locking settings. A pinned note can
serve as a label; shapes can define visual areas. Pinning must not imply that
contained notes move with their background.

Implementation touches serialization, undo snapshots, model roles, target
filtering, pointer handling, help and rendering. Separate background and
foreground rendering around the connector canvas: setting only Node.z inside
the current world Item cannot place backgrounds behind the sibling connector
canvas. Maintain item identity rather than sorting/reindexing the model.

Old boards default to unpinned. Consider a new board format version when
writing pin state: existing v3 readers silently discard unknown item fields,
which would otherwise silently lose pinning on an older installation.

Acceptance tests: pin after foreground items already exist; pan/zoom and create
a note over the background; mark-all/delete leaves it intact; reveal/unpin
works with overlapping backgrounds; undo/redo and save/reopen preserve state;
old boards still load; keyboard focus survives surface switches.

## Verification performed

| Check | This review |
| --- | --- |
| `npm test` | Pass: 75 pure tests, controller scenarios and contract checks |
| `npm run test:ui` | 12 passes including setup/cleanup, but runtime TypeError |
| `npm run test:qml` | Pass outside sandbox; initial sandbox run had IPC/EPERM failures |
| `npm run test:omarchy -- --keep` | Failed at stage 42; keyboard creation after reopen |
| `omarchy plugin validate .` | Exit 0 |
| `npm run bench` | 3,000 items: serialize 4.27 ms, load 6.21 ms; not a rendering benchmark |
| Targeted probes | Restore collision, path validation, backup collision and mark leakage confirmed |

Live failure log: `/tmp/omarchyform-compat-iocFeE/runtime.log` (temporary).
Mutation testing and full QML lint were not rerun in this review. No installed
plugin, user board, theme or desktop configuration was modified.

## Route to submission

1. Fix filesystem confinement, restore semantics, backup identity, stale marks
   and save-operation ownership. Add focused regression coverage for each.
2. Resolve the live test failure and remove runtime errors from the UI suite.
3. Implement the single pinning behavior if desired for this release; do not
   expand it into a general layer/group system.
4. Reconcile README/help/manifest claims and rerun the release checks against
   the exact final revision. Perform an isolated fresh install and upgrade
   smoke test; the current live harness bypasses actual plugin installation.
5. Confirm the submission destination, check its actual requirements, and
   prepare the release description and a representative preview.

The initial review made no application changes. The subsequent implementation
addresses the findings as recorded in Current status. Nothing has been submitted.
