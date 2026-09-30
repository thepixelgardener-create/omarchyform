# Next usability pass: make active actions clear

**This is the record of a plan, not a task list.** Written 2026-09-28. Its first
two phases shipped; its third was a proposal to be decided on evidence, and none
has been gathered. What happened is at the end.

## Checked state

Reviewed local main at 2aa8292 on 2026-09-28. The working tree was clean;
local main was two commits ahead of the locally recorded origin/main. No remote
fetch was performed in this check.

The preceding review passed npm test, 61 Qt UI checks and the QML regression
suites. Those results apply to this unchanged implementation. They do not establish
that pointer gestures work on the real compositor in both window modes.

## Confirmed issue: a stale message hides the connector outcome

Board.qml displays statusText before the active connector hint. Success messages
last 2,600 ms. Starting another connector operation during that interval can leave
"Duplicated" or "connector removed" on screen instead of the action that the next
x will perform.

Verified with an isolated copy of the real Board and existing Qt test fixture:
set statusText to "Duplicated", linkingFrom to 1 and linkOutcome to "remove".
The assertion that the line contains "removes this connector" failed; the displayed
text remained "Duplicated". This establishes the display-priority problem, not a
new mutation or data-loss defect. The previous review missed this combination.

## Phase 1 — Fix connector feedback priority

Implement this bounded correction first.

1. Inspect how ordinary success messages, errors, disk conflicts, saving and active
   interaction modes compete for the status line.
2. Give an active connector operation precedence over a stale success message.
   Do not blindly put connector hints above actionable errors or disk conflicts.
3. Keep the existing linkAt outcome logic and keyboard behavior. No changes to
   connection semantics, board format or persistence are needed.
4. Avoid a general notification-system rewrite. Prefer the smallest explicit
   priority change; distinguish critical feedback if its current representation
   makes a safe ordering impossible.

Acceptance:

- After an ordinary success message, beginning and navigating a connector operation
  immediately shows its current create/reverse/remove outcome.
- Save failures and disk conflicts remain visible and actionable.
- A self-target still asks for another endpoint; Escape cancels without mutation.
- Finishing the operation leaves useful completion feedback. Expired messages do
  not reappear because of the fix.
- Add Qt regression coverage for stale success plus each connector outcome, and
  critical-error/conflict combinations. Keep the existing tests for mutation/undo.

Run npm test and npm run test:ui. Broaden testing only for additional changed paths.

## Phase 2 — Close the live pointer verification gap

Use isolated boards and the repository's preview/integration tooling. Do not update
the installed plugin or use real user boards for testing.

In fullscreen and windowed mode, check middle-drag and click-only input over:

- Empty canvas, notes, shapes and an image.
- A pinned background, including background-selection mode.
- A resize grip and an actively edited note.
- The header, command panel, help, browser and conflict panel.

Expected: canvas gestures pan without modifying content or selection; gestures on
panels do not pan the underlying canvas. Check 100% and one non-default zoom.
Verify text editing, wheel zoom and left-drag still work afterward.

The existing automated pointer fixture covers many of these cases but its explicit
panel cases omit the conflict panel. Add that automated case if practical. Do not
describe mounting the full Board with a stub controller as a full-plugin live test.

Record environment, tested cases and failures. If live interaction cannot be
performed, mark it unverified and retain a manual checklist.

## Phase 3 — Evaluate pointer-based connector selection separately

Confirmed current behavior: pointerSelect clears linkingFrom. Clicking the far
endpoint therefore cancels linking. Documentation now explains the keyboard path.
This is an existing interaction limitation, not a regression in the latest commit.

Observe whether intended users try clicking the second endpoint and become stuck.
If that pattern warrants a change, use a separate implementation plan with this
proposed contract:

- Enter connect mode through the existing command or x.
- A plain click on a valid destination selects it and preserves the source.
- Show the impending outcome before an explicit confirmation; do not silently
  delete an existing connector as a side effect of selecting its endpoint.
- Provide confirmation through the existing command interface as well as x.
- Define Escape, empty-canvas clicks, Shift-click and dragging before coding.
- Reject invalid/pinned endpoints and retain one undo step per completed operation.

Do not implement this proposal as part of Phase 1. It changes selection behavior
and needs its own regression coverage and product decision.

## Improve the observation checklist

The current checklist has useful starting tasks, but two conclusions need care:

- "Find a note" can be completed through search or Fit, so it does not establish
  that panning works. Use a separate directed gesture check for panning correctness.
- No task requires moving objects between boards. Absence of cross-board copying
  during that session cannot establish that structured copying is unnecessary.

Keep unprompted discovery tasks separate from directed verification tasks. Ask
about actual recent workflows before adding a task that introduces a new feature
need. Define whether sharing means a readable picture or an editable board, or
record the participant's interpretation before giving more guidance.

## Out of scope

New toolbars, groups, recent boards, connector labels, clipboard formats, CLI
expansion, renaming and architectural cleanup remain deferred. No feature should
be added solely because it appears in a comparison with another canvas app.

## Completion and delivery

Report the specific issue fixed, checks performed, remaining live verification and
any product decisions still open. Keep Phase 1 independently reviewable. Do not
claim the full usability plan is complete because automated checks pass.

This document is a plan only. Application code was not changed during this check.

## What happened to this plan

Recorded 2026-09-30 at `9a30d9b`, so this section dates too.

**Phase 1 — shipped** in `99f35a0`. The line under the header is ranked by what
a message is for rather than by what reached it last, so a stale success no
longer hides the connector outcome, and save failures and conflicts still
outrank the connector. It has since been decided in one place for the board and
the clock alike, and failures of every kind keep their place (`bb9cb3f`).

**Phase 2 — done.** `npm run shots -- --hold` (`e8d6563`) leaves an isolated
board up to be driven by hand, and the matrix in
[pointer-checks.md](pointer-checks.md) was run on 2026-09-29 (`e3fa0f4`): every
row, both window modes, 100% and 400%, passed.

**Phase 3 — not taken up.** Clicking the far end still starts a fresh
selection, and the README says the far end is chosen with the keyboard. This
phase asked for observation before any change, and none has been made.

**The observation checklist** now keeps discovery separate from directed checks:
finding a note is said not to establish that panning works, and the absence of
cross-board copying is said to be a property of the tasks rather than a finding.
