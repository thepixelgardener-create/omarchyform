# Contributing

[Back to the README](../README.md) · [Development](development.md)

Omarchyform is a Quickshell/QML app with shared JavaScript codecs and a Node
CLI. This page holds the rules a code change has to keep. Running the plugin
from a clone, the source layout and the test commands are in
[Development](development.md); [for-agents.md](for-agents.md) describes using
the CLI to create boards and is not a contribution guide.

## Ownership and persistence invariants

- A `BoardDocument` owns saved content; a `BoardPane` owns focus, selection
  and camera. Two panes can share one document. Test both shared and
  independent documents when changing split behavior.
- Bump the document's `loadSerial` **before changing its path**, not only when
  the next file loads, so a pointer gesture begun on the old board cannot
  write. Never combine content from the old board with the new board's path or
  revision. Pending saves must finish before the switch actually begins.
- Resolve a delayed open by the requested path when it completes: a captured
  document may have switched paths meanwhile. A delayed split close must leave
  `activePane` pointing to the surviving, non-null document even if focus moved.
- Keep an exchange operation's pane owner through every asynchronous stage and
  through its completion/error signal. QML change handlers run immediately;
  clearing `busy` can change bindings before the next statement executes.
- Read a board file whole, as any JSON reader would, through `readFile`; never
  part of it as if it were the whole. The edit history 0.4.7 to 0.4.10 kept in
  a board's file is parsed with the rest and dropped, so a key after it counts,
  on any line. Writing a board leaves the history out.
- A board with an old history, or laid out by hand, is not what this would
  write, so its file never equals `lastSavedText`. Until the session first
  writes it, the bytes it loaded (`loadedText`) are still its own: the same
  bytes under a new revision are a touch, not someone else's version.
- External imports remap live images into this library and discard the rest,
  foreign history included, which may reference deleted images with names that
  collide with unrelated local files.
- External imports serialize only the flat, primitive canvas schema through
  `importBoard`; discard unknown fields before serialization and enforce the
  resulting UTF-8 byte limit. Malformed fields must release exchange ownership
  and busy state so another import can succeed.
- New items get their ids from `newIds`, never `nextId + 1`: a board can
  arrive with an id at `MAX_ID`, and one past it is renumbered on the next load,
  which drops its connectors. Look things up by id in plain objects:
  `tests/security.js` refuses an array written at an id, because the array is
  as long as the id.
- Anything that reads board, clipboard, state or CLI input in a new way, a new
  feature reading an old field included, gets the
  [cost trace](security-review.md#cost-trace) before merge: what its time and
  memory grow with, each bounded where the input arrives, and a fixture at
  each bound in the engine the cost depends on. Benchmarks on realistic boards
  are not that fixture.
- CLI failures must remain JSON, and rejected edits must leave both files and
  backups unchanged.

- Reject external drag offers without reading `urls`, `text`, or raw MIME data.
  Qt's Wayland reader is not byte-bounded; a size check after a getter is too
  late. Keep `test:drop` proving rejection with zero payload retrieval. Do not
  restore external drag-and-drop without a bounded transport.
- Build one-line text fields from `LineField`, never `TextInput`: Qt 6.12.0's
  `TextInput` reads the clipboard's whole text on every clipboard change while
  it is editable. Keep `test:clipboard` at zero content reads with every field
  open, and run it on Qt 6.12.0 as `docs/security-review.md` describes.
- Keep one-line limits on typing and IME commits, not only paste. A delayed
  field paste belongs to its pane, board path and document generation; closing
  the field invalidates it even when that same field is reopened before reply.
- Every picture that lands in `images/` goes through `BoardFiles.sh`, which
  holds it to its bytes, its pixels (`refuse_huge_pictures`) and, for a PNG,
  compressed text and colour profiles (`refuse_compressed_text`). A new way in
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
- A foreign board with embedded images must pass `imagebudget` before
  publication. Count every live image item, including repeated file names and
  offscreen items; unique-file or encoded-byte totals do not bound retained
  decodes. Bound both aggregate pixels (40 MP) and per-item file bytes (32 MiB),
  since each instance can retain metadata. Unknown dimensions fail closed.
  Keep the real QML import regression
  covering refusal, the exact boundary and a successful import after failure.
- Parse JSON in shell code with `parseJson`, never `JSON.parse`: Qt's parser
  segfaults on a 1.1 MB array (`MAX_JSON_OPEN` in `BoardStore.js`), and
  `tests/security.js` refuses any other call.
- A board holds at most `MAX_ITEMS` items, `MAX_LINKS` connectors and
  `MAX_BOARD_BYTES` on disk. Anything new that adds items or connectors stops
  at the limit with `FULL_ITEMS` or `FULL_LINKS`, and anything that reads a
  board asks `boardLimit` before building it.

## Regression checks

For these paths, run `npm test` and `npm run test:qml`. Changes to QML interaction
or bindings also need `npm run test:ui`. Use temporary boards and isolated data
folders; do not test by editing a user's real boards or restarting their shell.

Relevant suites: `tests/split.js`, `tests/exchange.js`, `tests/editing.js`,
`tests/suite.js`, `tests/cli.js`, and `tests/qml/`.
The JavaScript harness executes production QML functions but models signals and
bindings; retain real QML coverage for lifecycle or binding changes. Add a
reproduction that fails on the old behavior and assert user-visible outcomes or
saved content, not just a helper's implementation. Include adverse completion
ordering, empty retention, and malformed nested inputs where applicable.

Report commands actually run and any remaining manual checks. External drops
are intentionally rejected; internal import-queue tests do not establish a
safe external drag transport. IME behavior remains unverified until observed.
