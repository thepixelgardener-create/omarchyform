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
`qs` and `/usr/lib/qt6/bin/qmltestrunner` (or `QMLTESTRUNNER`). It runs actual QML
clipboard/persistence tests and Qt rendering tests. Missing tools or timeouts
are failures, not skipped checks. All fixtures use temporary directories and
stub clipboard commands; these commands do not touch the user's clipboard.

Also run `npm test` for general regressions. No scan uploads boards or source to
an external service.

## What crosses a boundary

| Input/data | Where it goes | Required property and evidence |
| --- | --- | --- |
| Copied notes | QML → helper → `wl-copy` | Content only on stdin; never argv/environment/logs. `security.js` inspects live Linux process metadata; `tst_clipboard.qml` exercises the QML caller, repeat copies, failure and large Unicode text. |
| Pasted text/images | `wl-paste` → staging → QML/library | Bound bytes before returning text; reject bad image types and excessive supported dimensions; remove staging on success/failure. Filesystem and security tests. |
| Board JSON, titles, paths, errors | Models → Qt text | Explicit plain text for labels. Styled notes escape input first; status escapes variable messages. Source guards, hostile markup tests and Qt title test. |
| Long note text | Board file, import, editor, CLI → text layout on the shell's thread | A note is at most 1 MiB: a board with a longer one opens read-only and empty, import and the CLI refuse one, the editor refuses to grow one. Unbroken runs wrap anywhere, and the editor holds a note only while open, so layout stays linear. Store, controller, node, exchange and CLI tests. |
| Image names from boards | Local image URL, bundle/copy helper | Plain validated names, no URL or traversal; helper rejects symlink components. Logic/filesystem tests; manually inspect direct Qt loads. |
| Notes and edits | Helper commit stdin → board/backup | Atomic replacement, revision check, lock, no content in diagnostics, private modes for newly committed files and the folders made for them. Filesystem, CLI and QML persistence tests. |
| Shared boards and PNG exports | Staging → chosen external destination | Explicit user action, refuse app-data overwrite, keep unrelated files on failure. Filesystem/exchange tests. |
| CLI operations | stdin/file → model → helper | Parse as data, no evaluation. Invalid JSON must not echo content. CLI/security tests. |
| Board history | Board file → worker thread → replay models → text layout | Parsed off the shell's thread, never evaluated. Text past 64 MiB is not parsed; more than twice 10,000 records is refused before replay; every record is checked against the board it plays to. A step whose notes break the 1 MiB rule is not shown. Labels are plain text; image names go through the same validation as the live board. Unreadable histories are written whole beside the backups under a flattened name. `tests/history.js`, `tests/recording.js`, `tests/timeline.js`, CLI tests. |
| Desktop install/open | Opt-in launcher files and summon payload | No automatic install hook; ownership/conflict checks, correct path encoding, no shell interpretation. Desktop tests and manual review. |

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
  supported. Direct Qt image reads need separate review from helper confinement.
- Board files are plaintext. Existing files, QML staging/state files and
  user-chosen directories can have different permissions from helper-created
  board files. The mode test covers new helper commits and their backups, and
  the folders and locks the helper creates, under a umask of 000. The plugin
  creates its own data folders 0700. Neither changes a folder or file that is
  already there, so this does not certify all existing storage as private.
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
- Local board/CLI reads are not uniformly byte-bounded. Import size checks and
  bundle budgets can race concurrent file changes. Pixel checks cover PNG,
  GIF and BMP headers; JPEG/WebP and aggregate decoded image memory require
  further resource-limit work. Do not claim complete denial-of-service coverage.
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
The known limits above remain open hardening areas, not completed fixes.
