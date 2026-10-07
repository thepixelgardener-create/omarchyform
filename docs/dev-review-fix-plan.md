# Dev review fixes

Date: 2026-10-07. Baseline: `dev` at `789d538`, reviewed against
`origin/main` merge base `03edb49f8526fcd452c475c49d40f5eb8f090a32`.
Status: done on `dev` in `0883789`, `0e87b41` and `f73c571`. Results and
the one manual check left are under "Gate 6 results" in the
[development plan](splitview-timeline-plan.md).

Fix the three reproduced review findings in separate commits, with regression
tests in each. Prioritize the two history issues because they can overwrite
saved data. Preserve the current history format and owner-approved retention
policy. No deployment, shell restart or changes to real boards are part of
this plan's creation.

## 1. Preserve the whole board when JSON properties are reordered — P1

Affected code: `BoardStore.js::splitHistory()`; its consumers in
`BoardSession.qml` and `bin/omarchyform`.

The fast split assumes `history` is the final top-level property. Putting
`history` before `items` can remove the items from the board portion. History
recovery then saves the apparently empty board.

Implementation:

1. Keep the existing `{board, history}` return contract. Only take the fast
   path when the candidate is a top-level history property whose complete
   value ends immediately before the outer object's closing brace, allowing
   JSON whitespace. Property order must never change the loaded canvas.
2. Validate the candidate boundary with a string/escape-aware structural scan
   rather than another substring or regular-expression assumption. Account
   for nested objects/arrays, escaped quotes, braces in strings, and trailing
   whitespace. The scan validates the split boundary; existing parsers still
   validate JSON syntax and supported schemas.
3. If the layout cannot safely be split, return the original text unchanged
   as `board`, with empty `history`, and use the existing full-JSON fallback.
   Do not construct a partial board from uncertain input. Invalid JSON must
   fail loading without entering automatic history recovery/save.
4. Check all split consumers, including stale-save checks and the CLI, against
   the fallback contract. A supported reordered file can be normalized only
   after the entire canvas and history have been loaded successfully.

Regression tests:

- Extend `tests/suite.js` with history first, middle and last; compact and
  indented JSON; CRLF, tabs, trailing whitespace, nested values and strings
  containing escaped quotes/braces/history-like text. Preserve all items,
  links, paint order and `nextId`.
- Extend `tests/recording.js` with the reported history-before-items fixture.
  Drive worker completion and save completion. Assert the resulting canvas
  and history equal the input, with no empty write or spurious unreadable
  history recovery.
- Add a CLI round-trip in `tests/cli.js`: mutate a reordered board and verify
  the intended edit is the only canvas change and history survives.
- Include truncated/malformed inputs and confirm zero automatic writes.

Acceptance: valid JSON property ordering never deletes board content; ordinary
writer output keeps its fast path. Measure scanning on the existing large
history fixtures, since an extra full scan on the GUI thread can be expensive.
If that regresses the main-thread budget, move boundary validation/loading to
the worker rather than weakening validation.

Suggested commit: `fix(history): preserve reordered board properties`.

## 2. Refuse newer histories regardless of formatting — P2

Affected code: `BoardDocument.qml::adoptHistory()` and `checkedHistory()`,
`BoardSession.qml` edit/save guards, and worker-response tests.

The worker already reports `newer: true`, but the document ignores that flag.
Pretty-printed newer histories bypass the synchronous header check and can
be replaced by a supported-version history on the next edit.

Implementation:

1. Handle `answer.newer` before unreadable-history recovery or successful
   normalization. Use the same read-only reason as the synchronous newer
   version path. Preserve the loaded source/history; do not set it aside as
   corrupt, rebase it, append records, trim it or schedule a recovery save.
2. Prevent the race before the worker responds. A board with history awaiting
   validation is temporarily non-editable and non-writable. Display a short
   “Checking history…” state while allowing safe viewing/navigation. Boards
   without history retain their normal load behavior.
3. Enforce the validation state at both document mutation and session save
   boundaries, before `fileText()` can commit edits. Cover timer autosave,
   explicit Save, flush-on-close/switch, asynchronous paste/drop and history
   mutation commands such as Forget History. A UI-only read-only flag is
   insufficient. Preserve pending-switch progress without waiting for a save
   that the validation guard will never start.
4. On a supported result, lift the temporary guard and let normal loading or
   recovery continue. On a newer result, leave the board read-only. Do not
   replay queued edits into an unsupported document. Preserve any already
   pending local changes through existing conflict handling rather than
   silently dropping them during external reload.
5. Retain the existing request-token check: a late response from a replaced
   document/history must not lock, unlock or save the current one. Check the
   CLI's equivalent behavior against the same fixtures.

Regression tests:

- Extend `tests/recording.js` for compact and pretty-printed newer history,
  including reordered top-level properties from fix 1. After worker completion,
  verify the explanatory read-only state and unchanged original file bytes.
- Hold worker completion; attempt editing, autosave, explicit Save, Forget
  History, close and board switch. Assert no writes to the unvalidated board
  and no stuck navigation. Then deliver supported and newer results separately.
- Deliver an obsolete response after switching/reloading and confirm it cannot
  change the current document's state.
- Add a real worker/session integration case under `tests/qml` and wire it
  into `tests/persistence.js` if needed. Ensure protection works through the
  asynchronous QML path, not just the extracted JavaScript harness.
- Keep current malformed-history recovery tests; malformed and newer histories
  must remain distinct outcomes. CLI edits to newer history must fail without
  changing the input file.

Acceptance: formatting never changes version compatibility. An unsupported
history is preserved byte-for-byte on disk, and cannot be overwritten during
the initial validation window or after the result arrives.

Suggested commit: `fix(history): guard newer histories during validation`.

## 3. Route image drops to the receiving pane — P2

Affected code: `BoardPane.qml::dropFiles()` and
`BoardExchange.qml::importDropped()` / `nextDrop()` / completion handlers.

A drop can arrive at an inactive pane, but the exchange queue currently takes
the active pane as its destination. The wrong board receives the image.

Implementation:

1. Pass the receiving pane explicitly from `dropFiles()` into
   `importDropped(entries, pane)` (or an equivalently explicit signature).
   Capture that pane and its board path for every queued entry. Preserve the
   world coordinates already calculated using the receiving pane's camera.
2. Keep capture independent of keyboard focus; activating the pane is not a
   substitute for identifying the operation's target. Shared filesystem
   helpers can remain workspace-owned.
3. Check the captured pane/document at dequeue and completion. A focus change
   alone must not redirect or cancel the drop. If the target pane closes or
   changes boards, use the existing stale-result rejection behavior and report
   the cancellation; never fall back to the current active pane. Reject a
   result if its target is now read-only, including pending history validation.
4. Carry the captured target through image copying, image-size probing and
   final insertion. Update callers, contract checks and test stubs together.
   Preserve serialized multi-file import behavior.

Regression tests:

- Add a test in `tests/split.js` or a focused exchange harness that executes
  the actual queue functions. With different boards, focus A and drop onto B;
  verify only B changes and coordinates use B's pan/zoom. Repeat in reverse
  and with both panes showing the same document.
- Pause import completion, change focus, then resume: the original receiving
  board gets the image. Switch or close the target pane instead: insertion is
  rejected. Queue several drops and ensure each keeps its own captured target.
- Cover a historical/read-only target and a target whose history validation
  changes while the import is pending.
- Exercise the real `DropArea` path with a synthetic local image on temporary
  boards. If compositor automation cannot inject a drag, perform that specific
  check manually and record it as pending until completed; a direct call to
  `dropFiles()` alone does not prove native drag routing.

Acceptance: the receiving pane determines the destination throughout the
operation, regardless of focus changes. No image lands in another board.

Suggested commit: `fix(split-view): capture the image drop recipient`.

## Validation and completion

For each fix, first demonstrate that its targeted regression fails on the
baseline and passes with the change. Use temporary files and fixture boards.
Then run the combined suites sequentially:

```sh
npm test
npm run test:qml
npm run test:ui
npm run test:omarchy
npm run test:paste
```

The live scripts use temporary boards on the desktop. Do not run `npm test`
concurrently with the UI suite: the contract scanner currently attempts to
read the UI suite's temporary directory as a file. Fixing that independent
test-runner issue is outside these three commits.

Recheck history load/parse timings after fix 1, and measure the temporary
validation delay from fix 2 with the existing history benchmark. Run repository
lint/plugin validation and `git diff --check`. Record exact revisions, results
and any manual checks still pending. Treat the previously passing gate-6 and
live results as a baseline, not evidence that these regressions are fixed.

Completion requires all three reproduced defects to have regression coverage,
successful combined checks, preserved input files on refusal/error paths, and
a short follow-up review of the final diff. Update the main development plan's
release-review results and changelog only after implementation and validation.
