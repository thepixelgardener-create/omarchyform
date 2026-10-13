# Security and privacy release screen

Run this for every release and after changes to processes, storage, imports,
rendering, the CLI, desktop integration or dependencies. Record the commit and
working-tree status, commands, results, reviewer and unresolved findings in the
release/PR description. A passing screen is regression evidence, not proof that
there are no vulnerabilities. Do not call the release reviewed until the manual
items below have been checked against that revision.

## Commands

```sh
npm run test:security
npm run test:security:full
```

The first command needs Node, Bash and the existing GNU filesystem tools. It
runs security guards and the filesystem, installer and CLI suites. CI runs the
new guards alongside the existing suites. The full command additionally needs
`qs`, `/usr/lib/qt6/bin/qmltestrunner` (or `QMLTESTRUNNER`), a C++ compiler,
`pkg-config` and Qt development headers. It runs actual QML clipboard/persistence
tests, Qt rendering tests, and native clipboard/IME/drop probes. Missing tools or timeouts
are failures, not skipped checks. All fixtures use temporary directories and
stub clipboard commands; these commands do not touch the user's clipboard.

Also run `npm test` for general regressions. No scan uploads boards or source to
an external service.

## What crosses a boundary

| Input/data | Where it goes | Required property and evidence |
| --- | --- | --- |
| Copied notes | QML → helper → `wl-copy` | Content only on stdin; never argv/environment/logs. `security.js` inspects live Linux process metadata; `tst_clipboard.qml` exercises the QML caller, repeat copies, failure and large Unicode text. |
| Pasted text/images | `wl-paste` → staging → QML/library | Bound bytes before returning text; reject bad image types and excessive supported dimensions; remove staging on success/failure. Filesystem and security tests. |
| Text pasted into a field | Paste keys → `pasteInto` → helper → the field that asked | Qt's own paste reads everything a clipboard owner sends before any limit can count it, so no field may run it. The note editor, command list, find field and browser field hand Ctrl+V and Shift+Insert to the exchange, which reads through `cliptext`'s 1 MiB bound, refuses a paste that would not fit the field, and inserts only while that field is still taking text; failures go to the pane that asked. The line fields also take the middle button (primary selection); the pan surface takes it above the note editor. `security.js` refuses any text field without both; `tst_node.qml` and `tst_pan.qml` show each field no longer pastes for itself; `tst_fieldpaste.qml` runs the real exchange and helper against an owner that never stops sending, a late answer, a destroyed field and a clipboard with no text. |
| Board JSON, titles, paths, errors | Models → Qt text | Explicit plain text for labels. Styled notes escape input first; status escapes variable messages. Source guards, hostile markup tests and Qt title test. |
| Long note text | Board file, import, editor, CLI → text layout on the shell's thread | A note is at most 1 MiB: a board with a longer one opens read-only and empty, import and the CLI refuse one, the editor refuses to grow one. Unbroken runs wrap anywhere, and the editor holds a note only while open, so layout stays linear. Store, controller, node, exchange and CLI tests. |
| Board size | Board file, import, outside writes, CLI → delegates on the shell's thread | At most 5,000 items, 20,000 connectors and 32 MiB. The helper refuses a larger file by its size before any of it is read (`check`, `snapshot`, `filesize`, exit 5) and refuses to commit one; a board over a count opens read-only and empty with the reason and is never written over. Adding, duplicating, connecting, import, timeline steps and the CLI stop at the limits. Store, controller, exchange, timeline, filesystem and CLI tests. |
| JSON text | Board, history, import, state, trash index, IPC → `JSON.parse` on the shell's engines | Qt's parser holds each element of an open array on an unchecked stack and segfaults past about 557,000. Every shell-side parse goes through `parseJson`, which refuses more than 100,000 held at once; the history worker carries an identical copy. Store, history, controller and exchange tests; `contract.js` holds the copies equal; `security.js` refuses any other `JSON.parse` in shell code. |
| Image names from boards | Local image URL, bundle/copy helper | Plain validated names, no URL or traversal; helper rejects symlink components. Logic/filesystem tests. |
| Pictures already in `images/` | File → Qt image reader in the shell | Whatever put it there, a picture is drawn only after `checkimages` holds it to what landing would (size, type, pixels, compressed text). `imagePath` answers a URL only for a picture `pictureState` has cleared; a board read from disk has its pictures checked again, unchanged ones by revision (size, inode, modification and change time). Filesystem, controller and `tst_node` tests; `security.js` refuses any other picture URL. |
| Notes and edits | Helper commit stdin → board/backup | Atomic replacement, revision check, lock, no content in diagnostics, private modes for newly committed files and the folders made for them. Filesystem, CLI and QML persistence tests. |
| The plugin's folders and what the shell writes in them | `private` as the shell starts → data, boards, backups, trash, images, locks | 0700 folders and owner-only files under any umask, existing installs tightened, another account's files left alone and named, never the home folder; the shell writes its own files only inside them; imports are 0600 before they have a name; nothing is staged in the shared `/tmp`. `tests/filesystem.js` (umask 022, an old 0755 install, a linked boards folder, a second account), `tests/security.js`. |
| Shared boards and PNG exports | Staging → chosen external destination | Explicit user action, refuse app-data overwrite, keep unrelated files on failure. Filesystem/exchange tests. |
| Images in foreign shared boards | Landed files → aggregate header check → published board | At most 40,000,000 pixels and 32 MiB of file data across live image items, counting repeated references and offscreen items. Compressed PNG text and profiles are refused before landing. `imagebudget` reads dimensions without decoding rasters; unreadable dimensions or a helper failure refuse publication. Foreign history is discarded first. Filesystem, exchange and `tst_imagebudget.qml` tests. |
| Foreign board fields | Parsed input → normalized canvas → import staging | Only known primitive canvas fields survive, serialized compactly within the UTF-8 byte cap. Unknown nested data is dropped; invalid fields fail without leaving the exchange busy. Store, exchange and real QML regressions. |
| CLI operations | stdin/file → model → helper | Parse as data, no evaluation. Invalid JSON must not echo content. CLI/security tests. |
| Board history | Board file → worker thread → replay models → text layout | Parsed off the shell's thread, never evaluated. Text past 64 MiB is not parsed; more than twice 10,000 records is refused before replay; every record is checked against the board it plays to. A step whose notes break the 1 MiB rule is not shown. Labels are plain text; image names go through the same validation as the live board. Unreadable histories are written whole beside the backups under a flattened name. `tests/history.js`, `tests/recording.js`, `tests/timeline.js`, CLI tests. |
| Desktop install/open | Opt-in launcher files and summon payload | No automatic install hook; ownership/conflict checks, correct path encoding, no shell interpretation. Desktop tests and manual review. |

## Before submitting to the marketplace

A listing passes two checks on the exact commit submitted. The bot's
Automated Security Baseline reads it without running it and matches a short
list of patterns (the marketplace's `SECURITY.md`). Then a maintainer reads
every runtime file of that commit by hand, against no written list, and each
new commit is read again. Documenting a risk does not stand in for fixing it.

```sh
npm run review:marketplace             # the baseline, pinned, against HEAD
npm run review:marketplace -- --latest # against the marketplace's current scanner
```

`tests/marketplace.js` runs the marketplace's own scanner (its `scripts/`,
fetched at a pinned commit), answering the GitHub requests it makes from git,
so it reads exactly the files it would read there. It fails on any finding, on
any capability other than those accepted in it for the paths named, on a
policy version it was not written for, and within a quarter of a scan limit.
CI runs it. At 0.4.9 it reports `review-required` for one capability,
`installer` (`desktop/install.sh`), with the reason in the file; that reason
belongs in the submission's maintainer notes.

What the maintainer review has raised, from 22 recent submission threads, and
where this plugin answers each:

| Raised against plugins | Here | Checked by |
|---|---|---|
| Private files readable by other accounts: a default umask, files in `/tmp`, a file replaced without its mode, an existing install left loose | The helper writes with `umask 077`; the six folders are made private as the shell starts, existing ones and what is in them too; the shell writes only inside them; imports are 0600 before they are named; temporary files are made in the plugin's own folders | `tests/filesystem.js`, `tests/security.js` |
| Private data in process arguments (`/proc/<pid>/cmdline`): message text, dictation, tokens, `sh -c` payloads, search terms | Every helper argument is a reviewed folder, path, name or number; notes, clipboard contents and boards go on stdin or in a staged file; a new argument fails until reviewed | `tests/security.js` (argument table), clipboard and commit tests |
| Downloads not pinned to a digest, `curl \| sh`, unpinned remote git | No network at all; the baseline finds nothing | `tests/security.js`, `npm run review:marketplace` |
| Freezing or exhausting the shared shell: clipboard auto-reads (hidden fields included), Qt's own paste, drag-and-drop payloads, PNG text bombs | No `TextInput`; bounded paste through the helper; drops refused unread; pictures checked on the way in and before they are drawn; JSON guarded; board, note and file limits | `test:clipboard`, `test:drop`, `tests/security.js`, filesystem and controller tests |
| Local services without per-user authentication | Nothing listens; IPC is Quickshell's own | `tests/security.js` |
| Changes outside the plugin without consent | The launcher entry is installed only by hand and replaces or removes only its own unchanged files | `tests/desktop.js` |
| Privilege (setuid, `sudo`) | None | `npm run review:marketplace` |

Submitting, or asking for an update to be verified:

- [ ] `npm test`, `npm run test:security`, `npm run test:ui`, `npm run test:drop`,
  `npm run test:clipboard` and `npm run review:marketplace` pass on the commit
  to be named, and `-- --latest` reports nothing new.
- [ ] The issue names that exact commit, in full, and keeps the form's headings
  as they are: a changed heading stops validation before any scan.
- [ ] A finding is fixed in code for its whole class, not the one line quoted:
  search for every other place the same thing happens. The reply names the
  commit, what changed and the test that shows it.

## Manual release checklist

- [ ] Trace every changed process call through to the final executable. List
  argv, stdin, stdout, stderr, environment, temporary files and cleanup. Search
  for `Process`, `fileCommand`, `spawn`, `exec`, `command`, `console`, `setText`
  and `FileView`; inspect newly added files too. Note text or image bytes must
  never be quietly copied into metadata or diagnostics.
- [ ] Inspect every styled renderer's complete text expression. A count of
  renderers is only a change alarm; it does not establish escaping. New Qt
  controls, image sources, URL handlers or rich text require the same review.
  Qt's [text-format documentation](https://doc.qt.io/qt-6/qml-qtquick-text.html#textFormat-prop)
  warns that automatic/rich text can load remote images. Check filenames,
  titles, error messages and search text as well as note bodies.
- [ ] Check that all file destinations derive from trusted roots or explicit
  user choices. Exercise traversal, absolute paths, option-like names, quotes,
  control characters, dangling symlinks, existing files and failed writes.
  Validate the final bytes, not just a filename or MIME claim.
- [ ] Check input sizes before collection/decoding, plus decoded pixel cost,
  item/link counts and total memory. Test failure halfway through an import,
  malformed JSON/base64 and readers that never finish. A byte limit alone is
  not a decode-memory limit.
- [ ] Review retention: boards, previous versions, trash, images, staging,
  exports and clipboard history. Make sure UI/docs do not promise erasure that
  leaves copies. Test error cleanup and explain what can survive a crash.
- [ ] Check new commands, packages, QML imports, install hooks and workflow
  permissions for network access, privilege changes and dependency risk.
  Actions should remain pinned; do not execute untrusted PR code with secrets.
- [ ] Use synthetic canary notes for screenshots, logs and issue reports.
  Reports should contain test results and paths needed to reproduce, not
  real note contents. Exports intentionally contain selected user data.
- [ ] Record unresolved risks and their disposition. Re-run the screen after
  the final changes; do not reuse a previous commit's green result.

## Known limits and intentional disclosures

These are review obligations, not claims covered by a green test:

- The plugin shares the shell's user privileges. It does not defend against
  arbitrary code running as that user, or a concurrent attacker swapping
  symlinks between checks and use. A user-chosen symlinked library root is
  supported. A picture is checked before Qt reads it, but by a separate step:
  a file replaced in between is read as it is then. The next time its board
  is read, the replacement shows in the picture's revision and it is checked
  again.
- Board files are plaintext, and private only by their modes. As the shell
  starts, the helper makes the plugin's six folders 0700 and removes group and
  other access from everything in them that is this user's, existing installs
  included; the files the shell writes itself (its state, staged imports, the
  trash index, a history set aside) take the shell's umask and are kept to
  their owner by those folders. Something in them that is not this user's is
  left as it is and named. A file copied out of them, or an export saved where
  the user chooses, is 0600 when this writes it and then the user's to keep.
- Ordinary deletion is not secure erasure. Backups, trash, image assets,
  exported copies and clipboard managers can retain content. A board's history
  keeps text that was deleted from its notes, in the board file itself, until
  the oldest records are trimmed or **Forget this board's history** is run;
  the backup of the previous write still holds it after a forget, and a
  history set aside as unreadable stays in the backups folder. Copies made to
  share never carry history. Crashes can leave
  staging files; EXIT traps do not run after SIGKILL or power loss.
- `bin/omarchyform new --note TEXT` deliberately accepts text in argv, so it
  can also enter shell history and process metadata. For sensitive text use
  `new FILE` followed by `apply FILE -` with operations fed from a protected
  file or a pipe. Do not put secrets in the shell command that builds the pipe.
  `inspect --full` and exports intentionally emit board contents; filenames and
  paths can appear in process arguments and error messages.
- Local board/CLI reads are not uniformly byte-bounded. A board's size is
  checked before it is read, but by a separate step: a file that grows between
  that check and the read is read whole, up to what the shell can hold. The
  same holds for import size checks and bundle budgets. The CLI reads a board
  of any size (it runs in node, not the shell) and only refuses to write one
  past 32 MiB. Pixel checks cover PNG, GIF, BMP, JPEG and WebP headers, and a
  PNG carrying compressed text (zTXt, compressed iTXt) is refused. Foreign
  imports also have an aggregate pixel budget, described below. This is not
  a process-wide memory cap: existing local boards, subsequent duplication or
  image pastes, split panes and export scenes need separate aggregate resource
  controls. Pixel counts do not include metadata, GPU textures, mipmaps or
  decoder overhead. Do not claim complete denial-of-service coverage.
- The source guards are targeted pattern checks, not a QML parser, taint
  analysis, secret scanner, network monitor or dependency vulnerability audit.
  They do not catch indirect network access or prove every data flow safe.
  `bin/store.js` evaluates the trusted bundled BoardStore source; board data
  must never be substituted for that source.

## Findings from the initial pass

At base commit `8bf4c73`, the screen work found and fixed two further gaps:

1. Several labels relied on Qt automatic text detection. Explicit plain text
   prevents user-controlled titles/filenames from being interpreted as markup.
2. CLI JSON parse errors returned engine error messages, which can include an
   excerpt of private operation input. The response now gives a generic error.

The clipboard argv fix remains covered at both the helper and QML boundaries.

## Marketplace review of 0.4.7

The verification review of `6eb82bb`
([omacom/omarchy-plugin-marketplace#10902](https://github.com/omacom/omarchy-plugin-marketplace/issues/10902))
found that the note editor still accepted Qt's own Ctrl+V and Shift+Insert,
bypassing `cliptext`: Qt's Wayland data-offer reader appends until the sender
stops, so a hostile clipboard owner could exhaust the shell's memory before
the editor's 1 MiB check ran. The same was true of the command list, find and
browser fields. Fixed in 0.4.8 as described in the table above. The review
also named middle-click primary-selection paste in the note editor; that
button was already taken by the pan surface (`tst_pan.qml`,
`test_middleDragOverAnEditorPansInsteadOfPasting`), and the three line fields,
which the pan surface does not cover, now take it themselves.

The follow-up review identified the same unbounded read through `drop.urls`.
External drag offers are now rejected on entry and on drop, without reading
URLs, text or raw MIME payloads. Drag-and-drop image import is disabled; image
paste still uses the bounded helper. Re-enabling external drops requires a
transport that enforces byte/time limits before Qt collects the payload.

`npm run test:drop` injects URI and text offers through Qt's window-system drag
entry points in single and split views. Its instrumented `QMimeData` counts
payload retrieval and requires zero reads and rejected drag/drop responses.
This is not a native Wayland streaming attack test: it proves the production
handlers do not request payload bytes at the Qt application boundary. The
static security screen also rejects payload access or acceptance in DropAreas.

The next follow-up, at `0f12e80`, found the three one-line fields still
`TextInput`s, and Qt 6.12.0's `TextInput` reading the clipboard's whole text
whenever the clipboard changes while it is editable, with nobody pasting:
`QQuickTextInput::q_canPasteChanged` calls `QMimeData::text()` (qtdeclarative
`v6.12.0`; 6.11, the 6.12 branch since and `dev` check `hasText()` only). No
handler here runs before that read. `TextEdit` asks only which formats are on
offer, and the note editor already was one.

The find field, the board browser's field and the command list's query are now
`LineField.qml`, a plain-text `TextEdit` held to one line: Return, Enter and Tab
never reach the text, a paste is handed to the owner's bounded `pasteInto`, and
the middle button stops at a guard. Input methods still compose into them. The
static screen refuses `TextInput` anywhere in the plugin.

`npm run test:clipboard` builds `tests/qt/clipboard_watch.cpp` against the
installed Qt, opens each field in turn — find, the command list, the browser
searching and naming a board, a note being typed in, and two panes at once —
and changes the clipboard three times in each, counting
`QMimeData::retrieveData`. It requires no requests, and checks that a
deliberate read is counted. The Qt it runs on decides what it proves: Qt 6.4
does not read on a change, so the old fields pass there too. On Qt 6.12.0 the
same binary, built against the system Qt and run on PySide6 6.12.0's
libraries, which Qt's binary compatibility allows:

```
g++ -std=c++17 -fPIC tests/qt/clipboard_watch.cpp -o /tmp/clipboard_watch \
  $(pkg-config --cflags --libs Qt6Quick Qt6Gui)
QT=<site-packages>/PySide6/Qt   # pip install pyside6-essentials==6.12.0
LD_LIBRARY_PATH=$QT/lib QT_PLUGIN_PATH=$QT/plugins QML_IMPORT_PATH=$QT/qml \
  CLIPBOARD_WATCH=/tmp/clipboard_watch npm run test:clipboard
```

| Fields at | Qt 6.4.2 | Qt 6.12.0 |
|---|---|---|
| `0f12e80` (`TextInput`) | 0 requests | 36 requests on 3 changes, with nothing open |
| `LineField` | 0 requests | 0 requests, in every state |

`npm run test:ui` passes on both versions the same way, with
`LD_LIBRARY_PATH`, `QT_PLUGIN_PATH` and `QML_IMPORT_PATH` set. Like the drop
test, this proves what the plugin asks Qt for, not behaviour under a real
streaming Wayland owner.

The review of `336e0e9` confirmed that and found that a pasted PNG was held
only to its bytes (32 MiB) and its IHDR dimensions, which say nothing about
the text inside it. Qt's PNG reader keeps every text chunk
(`QPngHandlerPrivate::readPngTexts`, before and after the image data) and sets
none of libpng's limits, so libpng's defaults apply: a zTXt or compressed iTXt
chunk is inflated to just under 8 MB, and up to about a thousand are kept.
Measured on Qt 6.12.0 with `QImageReader`, on a PNG two pixels square:

| Compressed text | On disk | Extra memory to load it |
|---|---|---|
| none | 74 B | +1 MB |
| 10 × 4 MB | 39 KB | +203 MB |
| 10 × 7.9 MB | 77 KB | +400 MB |
| 100 × 4 MB | 392 KB | +1.9 GB |

About five bytes per inflated character, linear in the text: the thousand
chunks libpng keeps, at 7.9 MB each, are a file of about 8 MB asking for some
40 GB. Pasted through `0f12e80`'s `clipimage`, the 392 KB file landed and cost
the shell 1.9 GB when loaded.

`BoardFiles.sh` now refuses a PNG with a zTXt chunk or a compressed iTXt chunk
on every way a picture arrives: pasted, dropped or picked, and carried inside a
shared board. Exit 9 says so, and each route reports it as compressed text
rather than as an unreadable picture. Plain tEXt and uncompressed iTXt cost no
more than their bytes, so a screenshot tool's metadata still lands. A file
without either chunk name in its bytes, which is every ordinary picture, costs
one `grep`; one with the name is walked chunk by chunk in a single `od` pass
into `awk`, so the same four bytes inside the image data are not taken for a
chunk. That pass is bounded by the file's size rather than by how many chunks
it holds (about a second for 8 MiB), and a walk that does not reach IEND is a
refusal. `tests/filesystem.js` runs each route against zTXt before and after
the image data, compressed and malformed iTXt, a file cut off before IEND, and
the names inside image data and inside a tEXt value; `tests/exchange.js` checks
the three messages, and the static screen requires every way a picture lands
in `images/` to run both the pixel and the text check first.

That check is on the way in. A picture already in the folder, copied or
synced in by hand, or pasted before the check existed, never went through it,
and Qt read it all the same. Every picture is now checked before it is first
drawn: `imagePath`, the only place a picture's name becomes a URL, answers one
only once `BoardFiles.sh checkimages` has held the file to everything landing
holds it to. Until then the picture counts as loading, so an export waits for
it; a refused one shows why in its place. A board read from disk has its
pictures checked again. One unchanged since it was found fit is known by its
revision, which includes the change time, so a file rewritten in place with
its modification time put back is still read again. That costs one `stat` for
the lot: 65 ms for 300 pictures. A fresh check took about 14 ms a picture where
this was measured, and goes 32 at a time so a board fills in rather than waits. On
Qt 6.12.0, with the real `Node.qml` and the 392 KB picture already in the
folder:

| Picture already in `images/` | `336e0e9` | Checked first |
|---|---|---|
| plain PNG | drawn, +2 MB | drawn, +2 MB |
| 100 × 4 MB zTXt, 392 KB | drawn, +1,154 MB still held, 6.9 s | not loaded, +0 MB, "carries compressed text" |

While that was open, two more ways a board alone could stop or crash the
shell were found and closed here.

A board had no limit on how much it held. Every item is a delegate built on
the shell's thread, with the bar and everything else waiting. Measured on
Qt 6.12.0, offscreen, with the real board and the smallest item a file can
describe:

| Items | Board file | Time to open | Extra memory |
|---|---|---|---|
| 1,000 | 0.04 MB | 2.1 s | +138 MB |
| 5,000 | 0.22 MB | 12.3 s | +675 MB |
| 20,000 | 0.89 MB | 92 s | +2.7 GB |

`docs/performance.md` benchmarks up to 3,000, where pan and zoom are already
over the frame budget. A board now holds at most 5,000 items and 20,000
connectors, and its file at most 32 MiB (the import limit it already had).
One over a count opens read-only and empty with the reason, like a note over
1 MiB, and is never written over; one over the size is refused by the helper
before any of it is read, on opening and when it is written over from outside.
Turning one away costs reading its rows: 9 ms for 5,001 items. Adding,
duplicating, connecting, import and timeline steps stop at the limits, the CLI
refuses to add past them and `validate` names them, and the helper refuses to
commit a board larger than 32 MiB, so nothing here writes a board it would
then refuse to open.

Measuring that turned up the second. Qt's `JSON.parse` allocates a
`ScopedValue` for each element of an array in the array's own scope, so every
element of an array still being read stays on the engine's JavaScript stack,
and scoped allocations do not check the stack's limit (4 MiB of 8-byte values,
plus its margin, about 557,000). On Qt 6.12.0:

| JSON | Size | Result |
|---|---|---|
| one array of 540,000 zeros | 1.08 MB | parsed in 70 ms |
| one array of 560,000 zeros | 1.12 MB | segfault |
| 300,000 inside 300,000 | 1.2 MB | segfault |
| 300,000 beside 300,000 | 1.2 MB | parsed |
| an object of 600,000 members | 7.1 MB | parsed |
| 1,100 arrays deep | 2 KB | parse error, no crash |

A board file of 1.12 MB took the shell down through `Store.readFile`, and a
history would through the worker, which runs in the same process. `split`,
`match`, `stringify`, `sort`, `slice` and `Object.keys` on two million elements
were all fine; the plugin never spreads an array into a call.

Every `JSON.parse` in shell code now goes through `parseJson` (`BoardStore.js`,
with an identical copy in `BoardHistory.js` for the worker), which refuses text
holding more than 100,000 elements at once on the way in. Anything this writes
stays under 40,000 (a full history's 10,000 records, one holding 20,000
connectors). A text with fewer commas and brackets than that is settled by
counting them; anything else is walked, strings stepped over, which took
208 ms for a 34 MiB board and a second for a full history (their parses took
186 ms and 875 ms). The 1.12 MB board that crashed the committed `readFile`
on Qt 6.12.0 now reads as unreadable in about 150 ms, and the real worker,
included the way the shell includes it, answers it as it answers text that
does not parse. A board refused this way opens read-only with the reason.

Everything from the follow-up on drops onward, with the private folders and
the routine in [Before submitting](#before-submitting-to-the-marketplace), was
released in 0.4.9.

## Aggregate image follow-up — 2026-10-13

The [marketplace follow-up](https://github.com/omacom/omarchy-plugin-marketplace/issues/10902#issuecomment-6137223238)
confirmed the compressed-PNG-text fix at
`cb4a80c0a8d8f0fb23f78e148a735c00a695981a`, then identified a separate gap:
many individually accepted compact PNGs could exhaust the shell when an
imported board opened. `Node` keeps an active image source even while culled,
and `cache: false` means repeated references also need separate accounting.

The correction on `codex/aggregate-image-budget`, based on that commit, adds
`BoardFiles.sh imagebudget` between unbundling and publication.
`BoardExchange` supplies the remapped live image names on stdin, once per item,
including offscreen items. The helper sums width × height, allowing at most
40,000,000 pixels and 32 MiB of file data, and refuses unreadable dimensions.
Both totals count repeated references separately. Header walks cover JPEG
and the three WebP headers as well as PNG, GIF and BMP; raster and compressed
metadata are never decoded for this calculation. These added dimension readers
also apply to the existing per-image landing and load checks.

Until the helper succeeds, no board is staged or published and no `created`
signal can open it. Failure retains the requesting pane through its error
signal, then releases the busy state for another import. Foreign history is
discarded by the existing remapping step. The external file is unchanged;
images already unbundled remain unreferenced in the library, as they do after
other partial import failures. This check introduces no new executable,
dependency, network operation or data-bearing command-line argument: its only
argument is the trusted images directory, with file names on stdin.

Three additional foreign-input findings were reproduced and corrected:

- **Repeated metadata retention.** A native Qt 6.12.0 probe with four invisible
  `Image` objects (`cache: false`, asynchronous) retained four copies of a
  65,536-character PNG text field despite accounting for only four pixels.
  The per-item file-data budget now bounds this independently of pixels.
  Compressed PNG colour profiles (`iCCP`) could bypass that byte accounting;
  they are now refused on every landing route and when checking existing
  pictures (exit 11), alongside the existing compressed-text refusal (exit 9).
  This deliberately excludes otherwise valid profiled PNGs: re-export without
  the embedded profile to use one. Plain metadata remains accepted within the
  budgets. The probe was small; it did not attempt to exhaust the shell.
- **Unknown-field serialization amplification.** Actual Qt expanded an
  accepted 20,645-byte foreign tree into 2,091,566 bytes while pretty-printing
  unknown nested fields. `importBoard` now keeps only primitive fields from
  the flat canvas schema, discards foreign history and unknown fields, and
  serializes compactly. `withSharedImages` checks the resulting UTF-8 size
  before staging. Local history loading remains unchanged.
- **Malformed-field import lockout.** An object used as `src`, with null
  coercion methods, threw during remapping and left the exchange busy.
  Foreign canvas fields now have explicit primitive type checks before image
  landing, remapping uses own-property lookups, and import completion paths
  release busy state and report failure on exceptions. A subsequent valid
  import succeeds without restarting the plugin.

### Reconciliation with the local development tree

The candidate starts at published 0.4.10, rather than applying upstream changes
over the dirty 0.4.8 development checkout. That original checkout is preserved.
The candidate retains upstream private folders, PNG compressed-text refusal,
board/JSON caps, image load checks and the 0.4.10 window-mode migration.

| Overlap | Resolution |
|---|---|
| `LineField.qml` | Ported the local bounded typing/IME behavior, separator normalization and surrogate-safe truncation. Production fields retain bounded helper paste and zero automatic clipboard reads. |
| `BoardExchange.qml` | Ported local field-paste board-path and document-generation ownership, plus field-close invalidation; retained upstream private staging and added the import guards above. |
| `tests/qml/tst_windowmode.qml` | Current local and upstream copies are byte-identical; retained upstream. |
| `tests/windowmode.js` | Retained upstream's broader suite, including migration from 0.4.9 and bar-versus-keyboard behavior. |
| Clipboard and field-paste regressions | Ported local tests, retained the upstream test controller's private data directory, and test with production `LineField`. CI now runs the native clipboard/IME probe. |

The version remains 0.4.10 with changes recorded under Unreleased; this is a
review candidate, not a published release or marketplace approval.

### Validation

Evidence from this candidate:

- `tst_imagebudget.qml` exercises the real exchange and helper with valid,
  compact PNG streams: three distinct 20 MP files; three references to one
  20 MP file; 40 MP plus one pixel; exactly 40 MP; and a small import after
  refusals. It additionally rejects repeated plain metadata over 32 MiB and
  malformed image fields, recovers after each, and strips nested extra fields.
  It checks error delivery, absence of publication and recovery.
  The new test fails on `cb4a80c` with `many must fail before publication` and
  passes with the correction. It never instantiates a hostile board's images.
- Filesystem tests independently cover the exact boundary, repeated names,
  mixed formats, truncated dimensions, missing files, traversal and symlinks,
  repeated metadata, and compressed profile refusal on landing and load.
  Exchange tests cover a focus change while awaiting the aggregate result,
  including a helper failure and an unmeasurable image.
- `npm test` and `npm run test:security:full` passed: source/process guards,
  filesystem/installer/CLI suites, nine real QML scenarios, 189 Qt UI checks,
  zero clipboard payload reads, synthetic native IME commits (normalization
  and overflow), and zero drop payload reads in single and split panes.
  Installed Qt was 6.12.0. This verifies delivered input-method events, not a
  manual session with each platform's IME.
- `npm run test:windowmode` passed on live Wayland with isolated boards and
  windows. Bash syntax, manifest shape/entry points and the QML final-property
  override check passed; plain `qmllint` still lacks Quickshell import metadata.
  `git diff --check` was clean. The filesystem suite's
  existing second-account ownership check was skipped because this run was
  not root. Initial sandboxed runs could not exercise private Qt IPC and
  clipboard subprocesses; successful runs used isolated fixtures outside
  those sandbox restrictions.

The 40 MP limit applies to the imported canvas, not the whole shell's memory.
It does not add runtime admission control for subsequent local edits, existing
local boards, split panes or export scenes, nor measure decoder/GPU overhead.
The small native metadata-retention probe is not a whole-shell RSS ceiling or
an exhaustive image-decoder audit. No marketplace submission was performed.

The known limits above remain open hardening areas, not completed fixes.
