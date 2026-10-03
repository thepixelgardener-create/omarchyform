# Reporting a security issue

Report privately through GitHub's
[report a vulnerability](https://github.com/thepixelgardener-create/omarchyform/security/advisories/new)
form, which is not public. If that is unavailable to you, open a normal issue
saying only that you have a security report and asking for a private channel —
no details in the public issue.

Expect an acknowledgement within a week. There is no bounty; this is one
person's plugin.

Please include the plugin version or commit, your Omarchy version
(`omarchy-version`), and what an attacker would gain. A proof of concept helps
more than a description.

## What is in scope

This plugin runs as unsandboxed QML inside the long-running Omarchy shell
process, and reads and writes files under `~/.local/share/omarchyform/`. The
things worth attacking are:

- **A board file.** Boards are plain JSON, meant to be hand-edited, shared and
  committed, so a board is untrusted input. A board that reads or writes a path
  outside the data directory, or that makes the shell load a file of its
  choosing, is a vulnerability. Image items carry only a plain file name for
  this reason.
- **The clipboard.** `ctrl+v` runs `wl-paste`. The clipboard chooses its own
  format and contents; the plugin chooses the destination name and directory.
  Clipboard contents steering where bytes land is a vulnerability.
- **`BoardFiles.sh`.** Paths are passed as arguments, never as shell source.
  Every path a board file, the clipboard or the board browser can influence is
  checked against its root before use: no `..`, no symlink below the root, no
  control characters. The paths it takes without a root are ones the person
  chose (a file dropped on the board or picked for import, and where an export
  is saved, which must be outside the data folder), the two metadata lookups
  (`revision` and `filesize`), and the command line's saves, which write the
  file they were given. A path
  that escapes its root, or that is interpreted rather than used, is a
  vulnerability.
- **`desktop/install.sh`.** It writes the launcher entry, the board file type
  and the small command they call, and refuses to replace a file it did not
  write. Overwriting or removing an unrelated file is a vulnerability.

## Security and privacy screen

Run `npm run test:security` for the portable regression screen, or
`npm run test:security:full` on a machine with Quickshell and Qt test tools.
Follow [the release review checklist](docs/security-review.md) as well; it
records the data flows, intentional disclosures and limits of these checks.

Copied note contents must not appear in process arguments, environment
variables or diagnostics. User-controlled labels must render as plain text;
formatted notes and status messages must escape user content before markup.

## What is not

- The plugin has no intentional network operations. Imported boards, images,
  filenames and clipboard contents are still untrusted inputs.
- Anyone who can already run code as your user can read your boards directly;
  the data directory has no protection beyond ordinary file permissions.
- Omarchy loads plugin QML with the shell's own privileges. That is the Quattro
  plugin model, not a flaw in this plugin — report shell sandboxing concerns to
  [Omarchy](https://github.com/basecamp/omarchy).

## On the automated scans

The marketplace baseline scan and the portable linters used here are
deterministic checks for documented patterns against an exact commit. Their
output is evidence for that commit. None of them is a security audit, and a
passing result is not a warranty.
