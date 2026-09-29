# Claude handoff: a focused Omarchyform usability pass

## Objective

Improve predictable navigation and discovery of existing commands while preserving
Omarchyform's small, keyboard-first canvas. Implement the bounded changes below,
verify them, and report the result. Do not expand this into a general redesign.

Read applicable AGENTS.md instructions and inspect the current working tree first.
Preserve unrelated changes. This plan was prepared from source and the repository
preview on 2026-09-28; no live usability study was performed. Recheck its observations
against the current checkout before editing.

## Product constraints

- Keep keyboard shortcuts, local JSON boards, autosave, theme integration and both
  window modes working.
- Preserve board compatibility and existing persistence safeguards.
- Use existing command dispatch, controller methods and UI components where practical.
- Do not modify the user's installed plugin, desktop configuration or real boards
  just to validate development changes. Use isolated fixtures and preview tooling.
- Do not add dependencies or refactor unrelated controller responsibilities.
- Do not rename the project or CLI.

## 1. Make middle-button panning predictable

### Evidence

Board.qml uses middle-drag to pan. Node.qml accepts the middle button, changes
selection on press, and removes an item on middle-click. A navigation gesture can
therefore become a destructive action depending on where it begins.

### Implementation

Remove middle-click deletion. Make middle-drag pan when started over empty canvas,
notes, shapes, images and pinned backgrounds. A middle-click without movement must
not delete, select, move or edit an item. Preserve Delete/Backspace, existing delete
commands and undo feedback.

Inspect event propagation before choosing an implementation. Simply removing the
delete callback is insufficient if the item still consumes the gesture. Prefer
routing to the existing camera behavior; avoid duplicating coordinate calculations.
Check editing text and resize grips for input interception. Middle-button input
over the canvas's items must not accidentally paste or resize content.

Keep dialogs, menus and other interactive overlays responsible for their own input;
do not pan the canvas through them. Preserve left-drag selection/movement and
right-button behavior.

### Acceptance

- Middle-drag moves the camera by the pointer's screen displacement at different
  zoom levels, regardless of which canvas item is under the pointer.
- Click-only gestures leave items, selection, editing state and undo history intact.
- Panning does not change item geometry or create a board-edit undo entry.
- Left-drag movement, marquee selection, resizing and explicit deletion still work.
- Update documentation and help references to middle-click deletion.

## 2. Make command search understand ordinary words

### Evidence

BoardStore.js matches command display names and shortcuts. For example, searching
"edit" does not find "Type in it". Commands.qml already provides a searchable UI,
so this can be improved without adding a permanent toolbar.

### Implementation

Add optional search aliases to command metadata and teach matchCommands to use
them. Keep command identity, dispatch, visible labels, scope filtering and disabled
state explanations intact. Never dispatch by an alias string.

Start with a small, deliberate vocabulary:

- "edit", "edit text" -> Type in it
- "select all" -> Mark everything
- "add to selection" -> Mark this one as well
- "copy" -> Copy out
- "paste" -> Paste in
- "rectangle" -> New box
- "rename" -> Name this board
- "connect", "link" -> Connect to another
- "disconnect", "unlink" -> Remove its connectors

Existing display-name matches already cover some of these; avoid redundant aliases.
Preserve current shortcut and name ranking, then append alias-only matches in stable
command-table order. A command appears once even if several fields match. Keep
matching case-insensitive and trimmed. No fuzzy-search library is needed.

### Acceptance

- The queries above find the intended commands.
- Empty queries preserve the current list and ordering.
- Existing name/shortcut searches retain their behavior.
- Selection scope still excludes unrelated commands, including alias matches.
- Availability checks remain authoritative when a matching command is executed.

## 3. Clarify existing connector behavior

### Evidence

Omarchyform.qml:addLink currently creates a new directed connection, removes an
existing connection in the same direction, and reverses a connection in the opposite
direction. There is also an action to remove all connectors from the selected item.
Individual removal therefore exists, but the interaction is indirect.

### Implementation for this pass

Inspect the current linking hint, Help and README and make them agree with the
actual behavior. Clearly explain choosing the first item, entering connect mode,
choosing the second item and completing the operation. Distinguish removing one
connection from removing all connections on an item.

Use the existing status/hint area. If the current destination has an existing link,
show the impending outcome: create, reverse or remove that connection. Keep the
wording short and the hint keyboard-accessible. Derive it from the same relationship
semantics used by the mutation; avoid a second inconsistent decision tree.

Do not add connector selection, hit-testing, labels, extra dialogs or new schema
fields in this pass. Direct connector editing remains a separate product decision.

### Acceptance

- Create, reverse and remove outcomes are correctly described before completion.
- Escape cancels linking without modifying the board.
- Existing keyboard behavior and undo/redo remain intact.
- Self-targets and unavailable destinations do not promise a valid operation.
- Documentation accurately describes individual versus bulk removal.

## 4. Verify the changed behavior

Use the existing tests and fixtures rather than building a new testing framework.
Read package.json and test runner requirements before running them.

- Add focused behavior tests for alias matching, ranking, deduplication and scope.
- Add Qt input coverage for middle-button gestures; verify camera movement and
  unchanged item/selection state, rather than checking source-code strings.
- Verify connector outcome hints against create/reverse/remove behavior and cancel.
- Run npm test and npm run test:ui. Run additional relevant QML/integration checks
  if needed to exercise the full canvas, since the Node component suite alone
  cannot establish that canvas input propagation works.
- Use the repository's isolated preview/integration setup for a manual pass at
  100% and one other zoom, in a small window and fullscreen where available.
- Check changed hints in light and dark themes and ensure they wrap without hiding
  the canvas controls. Inspect existing test setup before launching a live runner.
- If the environment cannot run a required check, report it as unverified. Do not
  substitute passing unit tests for a claim that full-surface interaction worked.

Update README/help and CHANGELOG only to describe the implemented behavior.

## Explicitly deferred

Permanent toolbar buttons, persistent numeric zoom, recent boards, shape/colour
pickers, groups, connector labels, structured clipboard transfer, CLI expansion,
export-menu reorganization and broad documentation restructuring.

These are hypotheses, not approved requirements. Do not implement them incidentally.

## Follow-up usability exercise

After this pass, prepare a short checklist for intended users: capture a thought,
connect and disconnect two notes, pan over populated content, reopen another board,
and share a result. Observe wrong actions, requests for help and recovery. Do not
invent user-test results or block the bounded changes above on recruiting users.

Use the observations to decide the next feature. Repeated reconstruction of object
sets across boards would support structured copy; slow board switching would support
recent/previous-board navigation. A feature's absence alone is not evidence of need.

## Final handoff

Report what changed, checks run and their results, any unverified interactions, and
remaining product questions. Keep the diff focused and reviewable. Do not publish,
deploy or change the user's installed desktop as part of this handoff.
