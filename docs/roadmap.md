# Roadmap

Updated 2026-10-05. This is the current release direction. The dated
[architecture review](architecture-review-0.4.5.md) and
[competitor analysis](competitor-analysis-0.4.5.md) explain the findings behind it.

## 0.4.5 — Canvas appearance and discoverability

This release improves the canvas appearance and prepares the directory listing.

- **Background choices — shipped in 0.4.5:** dots, square grid
  and ruled lines, with a plain option. Patterns follow the theme and camera;
  **Menu → Background** remembers the choice. Dots remain the default.
- **Directory discoverability — live:** the directory describes the plugin as
  a whiteboard for brainstorming, mind maps and diagrams; see
  [listing notes](marketplace-listing.md).

## 0.4.6 — Reliability, from the 0.4.5 review

Shipped. The follow-ups from the [architecture review](architecture-review-0.4.5.md)
and a security pass; the [changelog](../CHANGELOG.md) has each one.

- PNG export waits for every picture instead of a fixed 80ms.
- Long notes no longer hold the shell up; a note is at most 1 MB.
- The board and the export draw connectors from one geometry.
- The board library is its own component, `BoardLibrary.qml`.
- New folders and locks are private under any umask; the launcher's
  **New board** action is escaped as desktop entries require.

## Maintenance still open

- **Display-only nodes:** the PNG export draws `Node.qml` against a stand-in
  controller with empty editing methods (review finding 2).
- **Connector drawing cost:** cache the item index between repaints and skip
  connectors that cannot cross the view; keep either only if `bench:scene`
  improves.
- **Reads from slow storage:** a board read blocks the shell for as long as the
  read takes. 1ms on a local disk; network storage is unmeasured.
- A docs index, and CI rejecting new lint diagnostics.

These are planned. Completed changes are recorded in the changelog.

## 0.5 — Editable, labeled connectors

Make relationships useful in a decision diagram: connect “Ready?” to “Ship”,
label the arrow “yes”, and select it to edit, reverse or remove it.

Planned scope:

- Optional plain-text labels that stay attached when items move.
- Pointer selection of individual connectors and a keyboard-accessible list
  of connections for the selected item.
- Named actions to edit a label, reverse a connector and remove it.
- During connect mode, clicking a valid target preserves the source. Show the
  outcome and require explicit confirmation to create, reverse or remove a line.
- Preserve the existing keyboard workflow and straight connectors.

Completion checks:

- Keyboard and pointer paths both work, including cancellation and read-only
  boards; each completed edit is one undo step.
- Labels survive save/reload, duplication, portable board exchange and PNG
  export in every supported palette.
- Old boards load with empty labels. A new board-format version prevents older
  plugin versions from silently discarding labels.
- Labels and selection remain legible at low and high zoom, in both window modes.

## Later candidates

Revisit these after 0.5 and feedback from real use:

- Copy and paste board objects between boards, preserving layout and connections.
- Persistent groups with explicit membership.
- SVG export and zoom to selection.
- Explicit URL/file links if source collection proves a stronger need.
- A timeline: play a board back from its first note to now. Items are numbered
  in the order they were made, so a first version needs no new storage; moves,
  edits and deletions would need history kept in the file.
- Split view. Open question: two boards side by side, or two views of one
  board. Either needs the camera to belong to the view rather than the
  controller.
