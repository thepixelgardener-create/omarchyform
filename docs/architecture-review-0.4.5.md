# Architecture and maintenance review for 0.4.5

Reviewed 2026-10-02 at `f6c4a21` on `release-0.4.5`. This records findings and
recommended work; application code has not been changed.

Release direction updated 2026-10-03: editable connectors are planned for **0.5**.
See the [roadmap](roadmap.md) for the current 0.4.5 and 0.5 scope.

**Recommendation:** put a focused maintenance pass before the connector feature.
The persistence boundaries are useful and the baseline passes. The main debt is
the controller's growing responsibility, coupling between rendering and editing,
and duplicated contracts in tests and documentation. A full rewrite would have
little justification.

## What is worth keeping

- `BoardSession.qml` coordinates loading, autosave, conflicts and board switches.
  `BoardPersistence.qml` owns a single in-flight write. `BoardFiles.sh` provides
  the commit/lock/backup protocol used by both the plugin and CLI. Preserve those
  responsibilities and their race-condition tests.
- `BoardStore.js` holds shared parsing, normalization and geometry. Running the
  actual source in both QML and Node avoids a separate CLI file format.
- `Theme.qml` centralizes host theme access. The controller and models outlive
  the two interchangeable display surfaces.
- Pointer, filesystem, controller and real Quickshell checks cover different
  failure modes. Their overlap is useful; reducing test volume is not the goal.

## Ranked findings

### 1. Establish one connector geometry implementation before adding labels

`Board.qml:196` and `BoardImage.qml:134` independently calculate connector ends,
draw lines and construct arrowheads. They already share `Store.edgePoint`, but
not the complete geometry. Labels and routing would add more parallel changes.

Extract the geometry needed by both renderers: endpoints, arrowhead points, and
eventually label bounds. Keep each renderer's camera, palette and line weight
explicit, because the screen and export intentionally differ. Use the same
geometry for future connector hit-testing. Verify export and screen placement
with ellipses, diamonds and several zoom levels.

This is the most useful refactor directly supporting the proposed next feature.

### 2. Separate display-only nodes from editing behavior

`Node.qml` mixes appearance, text editing, selection, dragging, resizing and
controller callbacks. Consequently `BoardImage.qml:40` constructs a stand-in
controller with selection properties and empty editing methods just to render
disabled nodes. The contract test must keep this stand-in synchronized.

A display-only node component should accept item data and visual state. The
interactive node can wrap it with editing and gestures; the exporter can use it
directly. Share the actual appearance, including text layout, so screen/export
fidelity is preserved. This is more useful than splitting files by line count.

There is also a concrete export readiness concern: `Node.qml:144` loads images
asynchronously, while `BoardImage.qml:177` captures after a fixed 80 ms timer.
No image-ready barrier was found. Delayed image decoding could produce an
incomplete export. That failure was not reproduced in this review. Add a
controlled delayed-image case, then wait for assets and a rendered frame, with
a bounded failure path, instead of assuming elapsed time means readiness.

### 3. Extract board-library operations from the controller

`Omarchyform.qml` is 2,079 lines, and the contract checker identifies 256 declared
members. It owns editing, history, camera, commands, board browsing, trash,
filesystem-process callbacks, settings and surface lifecycle.

The clearest first boundary is a library component that owns directory listing,
rename, folder creation, trash and restoration. Relevant code is around
`Omarchyform.qml:447`, `:1433` and `:1910`. Give it explicit requests and result
signals. Keep document-switch decisions in the session and window lifecycle in
the entry point. Merely moving functions into another file while passing the
entire controller everywhere would retain the same coupling.

Do this as a separate change after the rendering work, or defer it if 0.4.5 is
intended to stay small. Splitting all of `BoardStore.js` at once is lower value;
separating command/help presentation from file-format logic is a reasonable
later boundary when those areas change.

### 4. Remove confirmed unused state and centralize format decisions

- `BoardSession.qml:33–34`: `conflictText` and `conflictBoard` are assigned and
  cleared, but no production code reads them. Some tests assert that
  `conflictText` is retained; that assertion verifies unused storage rather than
  recovery behavior. Resolution reads the disk again. Remove the fields and
  replace those assertions with checks that local edits and the conflict survive
  failure. Retain real conflict/retry coverage.
- The supported format version is repeated in `BoardStore.js:941`, `:974`, and
  `bin/omarchyform:101`, `:324`. Introduce a shared current-version constant and
  shared version classification before connector labels require a schema change.
- Static function-reference checks did not identify an obvious unused function
  to delete. Command names are also invoked through tables, so a search for
  direct calls alone is insufficient evidence of dead code.
- Historical format migrations remain necessary compatibility code. The current
  package and manifest still saying 0.4.0 is normal before the release bump.

### 5. Improve the signal from tests and lint

`tests/controller.js:88` extracts QML functions with indentation-dependent regular
expressions and recreates bindings in JavaScript. There is already a concrete
difference: its `session.canEdit` getter omits `!diskReading`, which the real
`BoardSession.qml:44` includes. The real QML suite provides additional coverage,
but the fake controller can still exercise states the runtime would refuse.

Fix that mismatch now. As logic is extracted, test ordinary JavaScript directly
and use QML tests for bindings and lifecycle. Keep the contract checker as a
guard, not as proof that the bindings behave correctly.

Current lint reports an unused `qs.Commons` import in `Omarchyform.qml`, duplicate
`label` ids in `Browser.qml`, and unqualified delegate access. The duplicate-id
diagnostic does not prevent the tested runtime loading, but should still be
resolved. The Qt run also emits repeated `QQuickItem::stackAfter` warnings around
nodes reparented between foreground/background layers. Investigate the parent
and stacking arrangement; do not suppress the warning without checking order.

CI and `tests/run` currently gate only the final-property lint category. Clean
actionable local warnings, document host-metadata exceptions, then reject new
unexpected diagnostics. Keep the CI and local lint policy in one script.
Bound subprocess waits in filesystem tests too: their `spawnSync` calls have no
timeout, and the sandboxed baseline stalled in a helper call during this review.

## Optimization: measure rendering before changing storage

A fresh `npm run bench` measured 3,000 items at 3.55 ms to serialize and 4.86 ms
to load. This synthetic Node benchmark does not measure disk saves, QML model
cost, images or frames. It gives no reason to replace the persistence protocol.

The recorded [rendering benchmark](performance.md), from 2026-09-30, is more
concerning: p95 pan/zoom is 36.7/39.1 ms at 1,000 items and 104.9/95.7 ms at
3,000, against a 16.7 ms refresh budget. No new live rendering benchmark was run.

Profile these specific costs next:

1. `Board.qml:208` builds an item-id index and visits every connector for every
   connector repaint, even on a camera-only change. Consider caching the index
   across structural changes and skipping lines wholly outside the viewport.
   A line with both endpoints offscreen can still cross the viewport.
2. The `Repeater` creates every node. Visibility culling in `Node.qml:47` reduces
   drawing, but camera bindings and delegate allocation still scale with the
   whole board. Compare boards with equal visible content and different total
   sizes before introducing virtualization. Keyboard selection and editing must
   remain available offscreen.
3. `BoardSession.qml:324` and `BoardExchange.qml:124` use `waitForJob()` during
   file reads. These are synchronous waits in a plugin sharing the shell process.
   Test slow reads and move them to an explicit asynchronous completion path if
   they stall interaction. Import's comment records a previous async-load issue,
   so changing the call alone would be insufficient.

Full-board undo snapshots are another possible cost, but depth is already bounded.
Measure long text and dense connections before replacing them with an operation
log. Neither that rewrite nor a persistent background service is justified yet.

## Documentation housekeeping

The README is 964 lines and several review documents retain old findings with
later completion notes. They clearly label themselves historical, so preserve
the records. Add a short docs index distinguishing current usage, development,
release checks, proposals and historical reviews; move detailed development
instructions out of the main getting-started path.

Concrete inconsistencies to fix:

- `docs/for-agents.md:61` says the CLI does not touch backups. It writes through
  the shared commit helper and does create backups.
- That guide describes a default note as 220×160, which is the CLI default;
  `Omarchyform.qml:711–715` creates a UI note at 180×140. Name the distinction instead
  of presenting one global default. CLI placement is top-left; UI creation takes
  a center position. A common item factory could make these choices explicit.
- The agent guide says not to edit an open board, while README explicitly
  supports it through conflict handling. Explain the agent caution about unsaved
  human work without implying the capability is absent.
- `docs/omarchy-compatibility.md` still says IME/accessibility have not been
  addressed. Real text fields and accessible panel controls have since shipped;
  node accessibility remains deliberately absent. Update its follow-up status
  precisely, without claiming a full accessibility audit.
- README's lint description says two unused imports; this run reported one.
  Prefer named remaining issues over a count that quickly becomes stale.
- `CHANGELOG.md` says security CI runs on every push; the workflow triggers
  pushes to `main` and pull requests. Align the wording with the actual trigger.

## Proposed release order

1. Fix documentation, unused state, duplicated version constants, the stale test
   binding, and actionable lint warnings in a small housekeeping change.
2. Share connector geometry and prove PNG image readiness before adding labels.
3. Measure the rendering candidates and retain optimizations only when a
   before/after benchmark improves the relevant workload.
4. Add editable connectors on that foundation. Extract library operations in a
   separate change if the release can absorb it; avoid combining every refactor
   with a file-format change.

## Validation performed

`./tests/run` passed outside the sandbox: all portable suites, shell syntax and
final-property checks, 116 Qt results, and the five real Quickshell suites
(persistence, session, timeout, exchange, clipboard). The initial sandboxed run
stalled and separate sandbox probes reported subprocess `EPERM`; that run was
stopped before repeating with the necessary access. Full qmllint still reports
the diagnostics discussed above. `npm run bench` completed.

No new compositor interaction, delayed-image reproduction, slow-disk profile,
mutation run, or security-specific suite was performed for this review.

## Since this review

Recorded 2026-10-03 against the housekeeping change that followed 0.4.5, so
this section dates too.

**Resolved:**

- Finding 4: `conflictText` and `conflictBoard` are gone, and the tests that
  asserted them now check that a failed replacement keeps the conflict and the
  edits on screen. The format version is one constant, `FORMAT_VERSION` in
  `BoardStore.js`, which the command line reads too.
- Finding 5: the controller test's `canEdit` includes `!diskReading`, with a
  check that editing waits while the disk version is read. The unused
  `qs.Commons` import and the duplicate `label` id are fixed. The filesystem
  tests bound every subprocess with a timeout.
- Documentation: the agent guide and skill describe backups and open boards as
  they behave, and name the command line's note size separately from the
  board's. The compatibility notes say what shipped for input methods and
  accessibility, and README names its remaining lint warnings instead of
  counting them.
- Finding 2's export concern, 2026-10-04: reproduced, then fixed. Five
  phone-sized photos came out four or five empty frames in an export that
  reported success. The export now waits for every picture to load or fail and
  for the connectors to paint, and gives up with a message when no picture has
  arrived for 15 seconds. `tests/qt/tst_export.qml` reads the file back, and
  fails against the old timer.

**Still open:** one connector geometry for the board and export (finding 1),
display-only nodes (2), extracting library operations from the controller
(3), the docs index, CI's lint gate, and the `stackAfter` warnings. Those
appear in the export scene too, where nothing is pinned, so they come from a
delegate setting its own `parent` at all, not from pinning.
