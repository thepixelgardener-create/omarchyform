# Claude tasks after the deeper usability review

## Review baseline

Reviewed 2026-09-28 on the-line-says-what-is-next at e8d6563. The commits have
been rebased: Phase 1 is now 99f35a0 and Phase 2 is e8d6563. Their combined
tracked tree is identical to the previously reviewed 2131aa0 tree.

Existing verification therefore still applies: 119 Node tests, 75 Qt tests and
four QML suites passed. Phase 1 was also tested independently before rebasing:
119 Node tests and 71 Qt tests passed. Additional targeted review probes exposed
the defects below. Passing the existing suites does not cover those cases.

The local history now includes the merge of PR #27. Its earlier stacking concern
is superseded in this checkout. This review did not query GitHub for current PR
status. Local main has diverged from its recorded upstream; do not reset or
force-push it as part of these tasks.

## Task 1 — P2: preserve visibility of asynchronous failures

### Finding

Board.qml ranks active connector and text-editing hints above statusText.
That fixes stale success messages, but statusText also carries failures:

- BoardExchange.fail emits finished(message), handled by root.flash(message).
- Clipboard subprocess failures emit finished("Could not reach the clipboard")
  or "Could not copy that picture" directly.
- PNG publication failure also calls root.flash with its error.

These failures do not necessarily set saveError. If a failure arrives while
connecting, the connector hint hides it until the 2.6-second timer discards it.
Starting another connector also clears statusText without checking its meaning.

Confirmed by a Qt probe mounting the real Board with the existing fixture:
linkingFrom=1, linkOutcome="create", then statusText="Could not reach the clipboard".
The expected failure was hidden by "x connects these two". Source inspection
establishes that real clipboard failures reach that same property.

This revises the earlier conclusion that Phase 1 was ready without further work.

### Implementation

Introduce a small explicit distinction between informational feedback and operation
failures. Trace producers through BoardExchange, PNG publication and controller
callbacks. Do not infer severity by matching English text or make every status
message outrank the active gesture again.

Keep persistent save errors, disk conflicts and damaged-board warnings authoritative.
Make operation failures visible while a gesture/editor is active; clearing an old
success when linking starts must not erase a failure. Define a simple lifetime:
a failure must not expire entirely while hidden. Use the existing UI where possible,
with no new notification framework or modal confirmation flow.

### Acceptance

- Stale "Copied"/"Duplicated" feedback cannot cover connector outcomes.
- Clipboard, import/export and PNG failures are visible during linking and typing.
- Starting or cancelling a connector does not silently discard a current failure.
- Success after a retry clears the relevant old failure; unrelated success does
  not incorrectly announce that a failed operation recovered.
- Persistent saving/conflict errors remain visible and actionable.
- Add producer-to-controller tests for real failure callbacks as well as Qt display
  tests. Manually assigning an error string to the UI stub alone is insufficient.
- Cover timers, cancellation, retry and markup escaping for the changed path.

## Task 2 — P2: terminate and clean up a held test run

### Finding

tests/qml/shot.qml's facade hide callback only calls plugin.close(). The held
timer returns forever once the scenes finish. tests/shots.js disables its process
timeout in hold mode. Closing the board therefore hides it without ending qs,
and the parent never reaches temporary-directory cleanup.

Previously reproduced using an isolated live window with automatic dismissal:
opened became false, but the process kept running and required termination.
This is a lifecycle check, not completion of the live pointer matrix.

### Implementation

Add an explicit held-run lifecycle: preparing, ready, closing, finished/failed.
Avoid quitting when a window temporarily disappears during a fullscreen/windowed
switch. Use the controller's accepted close state, not any one surface's visibility.
Wait for relevant pending writes before a successful exit. A failed or stuck write
must produce a bounded, clear failure instead of hanging indefinitely.

Ensure terminal interruption terminates the child and allows the parent to clean
up only this run's temporary directory. Do not recommend wildcard deletion of other
active runs. Never change the installed plugin or use real boards for this work.

### Acceptance

- Once ready, dismissing the board exits successfully and removes its scratch tree.
- Switching modes leaves the held session alive.
- Closing during a delayed save waits for completion; a failing save exits with
  an explicit failure under the documented policy.
- A close refused because an export is active does not prematurely kill the run.
- Ctrl+C leaves no child process or abandoned scratch tree.
- Add an automated lifecycle regression using isolated data; report separately
  whether it used the actual compositor or a stubbed process.

## Task 3 — P2: reject failed setup in hold mode

### Finding

The new hold branch in tests/shots.js checks only result.status === 0. Meanwhile
the QML screenshot timeout logs SHOTS_TIMEOUT and calls Qt.quit(), which can exit
zero. Unlike ordinary mode, hold mode never verifies SHOTS_DONE or readiness.

Reproduced with a stub qs process that printed "SHOTS_TIMEOUT at scene 0" and
exited zero: node tests/shots.js --hold printed "0 pictures" and exited zero.
This probe verifies runner result handling, not rendering.

### Implementation

Preserve live terminal output while tracking explicit readiness and failure results.
Use captured/forwarded output or a small per-run result file. Require evidence that
setup completed and the held board became ready before a normal close can succeed.
Keep a deadline for setup even when interactive time is unlimited.

### Acceptance

- Setup timeout, startup/load failure, missing ready marker, or a failed screenshot
  yields a nonzero result even if the child exits zero.
- A completed ready session followed by normal close succeeds.
- Interruptions are distinguished from successful completion.
- Child spawn failures are surfaced with their reason.
- Test with stub processes for determinism, plus the isolated real-harness smoke
  check from Task 2. Check that ordinary screenshot mode still works.

Tasks 2 and 3 can share process-lifecycle code, but keep their acceptance cases
distinct. Prefer one coherent tooling commit to duplicate subprocess wrappers.

## Task 4 — Improve validation accuracy and record the remaining gap

This is supporting work, not another product feature.

- The "12-failed-save" screenshot currently calls flash with a fabricated message.
  It does not establish the persistent saveError state or the header's "Save failed"
  presentation. Stage a genuine isolated failure, or inject the actual failure state
  explicitly and label it as a visual fixture. Reset that state before the next scene.
- Keep one scenario with an active connector plus a real save error, so the image
  exercises the priority that the change is meant to guarantee.
- Remove the claim in pointer-checks.md that a live failure is "almost certainly"
  compositor routing. Controller state, focus and lifecycle are also absent from
  the stubbed Qt fixture. Investigate the observed failure before assigning a cause.
- After repairing hold mode, run the documented live matrix if the environment
  supports it. Record each mode/zoom/case actually checked; leave others unverified.
- The conflict-panel live case is currently optional. A skipped case remains a gap
  even when its offscreen test passes. Prefer a reproducible isolated fixture if
  full coverage is claimed.
- Refresh instructions so exit/cleanup behavior matches the repaired implementation.

## Delivery

1. Read applicable repository instructions and preserve unrelated work. The untracked
   docs/usability-next-pass.md belongs to the prior planning pass; do not overwrite it.
2. Implement Task 1 in its own reviewable commit.
3. Implement Tasks 2 and 3 together or in independently passing commits.
4. Put validation/documentation updates with the behavior they describe or in a
   separate final commit. Avoid making Phase 1 depend on test-tool changes.
5. Run npm test, npm run test:ui and relevant QML checks after changes. Add targeted
   lifecycle/result-handling checks; existing green totals are not proof of these fixes.
6. Report commit IDs, checks and exact results, plus live cases left unverified.
   Do not merge, publish, deploy or force-push as part of this handoff.

No new canvas features, new commands, connector labels, groups, schema changes or
broad refactors are requested. The next pass is about visible failures and reliable
test tooling.
