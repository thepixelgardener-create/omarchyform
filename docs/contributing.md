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

- Reject external drag offers without reading `urls`, `text`, or raw MIME data.
  Qt's Wayland reader is not byte-bounded; a size check after a getter is too
  late. Keep `test:drop` proving rejection with zero payload retrieval. Do not
  restore external drag-and-drop without a bounded transport.
- Build one-line text fields from `LineField`, never `TextInput`: Qt 6.12.0's
  `TextInput` reads the clipboard's whole text on every clipboard change while
  it is editable. Keep `test:clipboard` at zero content reads with every field
  open, and run it on Qt 6.12.0 as `docs/security-review.md` describes.
- Every picture that lands in `images/` goes through `BoardFiles.sh`, which
  holds it to its bytes, its pixels (`refuse_huge_pictures`) and, for a PNG,
  the compressed text Qt would inflate (`refuse_compressed_text`). A new way in
  calls all three on the bytes that land.
- Nothing private goes on a command line: another account can read it in
  `/proc`. Send contents on stdin or in a staged file in a private folder; a
  new helper argument fails `tests/security.js` until it is added, reviewed,
  to its table.
- Folders are made through the helper's `private`, never a bare `mkdir`; the
  shell writes its own files only inside the plugin's folders; temporary
  files go in those folders, never the shared `/tmp`; nothing listens on a
  socket.
- Before submitting, or asking for an update to be verified, work through
  "Before submitting to the marketplace" in `docs/security-review.md`.
- A picture is drawn only through `imagePath`, which waits for `checkimages`
  to clear the file (`pictureState`). Never build a URL into `images/`
  anywhere else; `tests/security.js` refuses one.
- Parse JSON in shell code with `parseJson`, never `JSON.parse`: Qt's parser
  segfaults on a 1.1 MB array (`MAX_JSON_OPEN` in `BoardStore.js`), and
  `tests/security.js` refuses any other call. Change the guard in
  `BoardStore.js` and `BoardHistory.js` together; `tests/contract.js` holds
  them equal.
- A board holds at most `MAX_ITEMS` items, `MAX_LINKS` connectors and
  `MAX_BOARD_BYTES` on disk. Anything new that adds items or connectors stops
  at the limit with `FULL_ITEMS` or `FULL_LINKS`, and anything that reads a
  board asks `boardLimit` before building it.

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

Report commands actually run and any remaining manual checks. External drops
are intentionally rejected; internal import-queue tests do not establish a
safe external drag transport. IME behavior remains unverified until observed.
