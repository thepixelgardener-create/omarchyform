# Roadmap

Updated 2026-10-09. This is the current release direction. The dated
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
- **Reads from slow storage:** a board read blocks the shell for as long as the
  read takes. 1ms on a local disk; network storage is unmeasured.
- CI rejecting new lint diagnostics.

These are planned. Completed changes are recorded in the changelog.

## Unreleased on `dev`

- Side-by-side and stacked panes, board history and timeline playback.
- Per-item textures, canvas colours and grouped commands.
- Connector item-index caching, offscreen rejection and drawing grouped by colour.
- Confirming a connection after selecting its destination with the pointer.

The [split-view plan](splitview-timeline-plan.md#gate-6-results) records the
follow-up fixes and checks. Native file-manager drop and IME composition still
need verification. A fully textured 3,000-item board is now
[measured](performance.md#fully-textured-large-board--2026-10-09), with frame-rate
limits recorded. A release version has not been assigned. Boards with history
or textures use format 7.

## 0.5 — Editable, labeled connectors

Make relationships useful in a decision diagram: connect “Ready?” to “Ship”,
label the arrow “yes”, and select it to edit, reverse or remove it.

Planned scope:

- Optional plain-text labels that stay attached when items move.
- Pointer selection of individual connectors and a keyboard-accessible list
  of connections for the selected item.
- Named actions to edit a label, reverse a connector and remove it.
- Retain the destination-selection and explicit-confirmation behavior already
  implemented on `dev` when adding connector labels and individual selection.
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
