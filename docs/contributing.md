# Contributing

[Back to the README](../README.md) · [Development](development.md)

Omarchyform is a Quickshell/QML app with shared JavaScript codecs and a Node
CLI. This page holds the rules a code change has to keep. Running the plugin
from a clone, the source layout and the test commands are in
[Development](development.md); [for-agents.md](for-agents.md) describes using
the CLI to create boards and is not a contribution guide.

## Ownership and persistence invariants

- A `BoardDocument` owns saved content and history; a `BoardPane` owns focus,
  selection and camera. Two panes can share one document. Test both shared and
  independent documents when changing split behavior.
- Invalidate history worker and replay ownership **before changing a document's
  path**, not only when the next file loads. Never combine content from the old
  board with the new board's path or revision. Pending saves must finish before
  the switch actually begins. Exercise late `reload`, check and trim replies.
- Resolve a delayed open by the requested path when it completes: a captured
  document may have switched paths meanwhile. A delayed split close must leave
  `activePane` pointing to the surviving, non-null document even if focus moved.
- Keep an exchange operation's pane owner through every asynchronous stage and
  through its completion/error signal. QML change handlers run immediately;
  clearing `busy` can change bindings before the next statement executes.
- History trimming must preserve the original request cutoff separately from
  the last retained record. All records can be trimmed into the baseline. Keep
  edits made after the request exactly once and verify replay equals the saved
  canvas, including after the next edit and reload.
- External imports start a new history baseline. Remap live images into this
  library and discard foreign history, which may reference deleted images with
  names that collide with unrelated local files. Local loads and conflict copies
  preserve their own history.
- Treat nested JSON history as untrusted, including baseline items/links and
  patch entries. CLI failures must remain JSON; validation reports an unplayable
  history, and rejected edits must leave both files and backups unchanged.

## Regression checks

For these paths, run `npm test` and `npm run test:qml`. Changes to QML interaction
or bindings also need `npm run test:ui`. Use temporary boards and isolated data
folders; do not test by editing a user's real boards or restarting their shell.

Relevant suites: `tests/split.js`, `tests/exchange.js`, `tests/recording.js`,
`tests/timeline.js`, `tests/suite.js`, `tests/cli.js`, and `tests/qml/`.
The JavaScript harness executes production QML functions but models signals and
bindings; retain real QML coverage for lifecycle or binding changes. Add a
reproduction that fails on the old behavior and assert user-visible outcomes or
saved content, not just a helper's implementation. Include adverse completion
ordering, empty retention, and malformed nested inputs where applicable.

Report commands actually run and any remaining manual checks. Automated drops
are not evidence that dragging from a native file manager into an inactive
split pane works. Keep that check and IME behavior explicitly unverified until
observed.
