# Roadmap

Updated 2026-10-03. This is the current release direction. The dated
[architecture review](architecture-review-0.4.5.md) and
[competitor analysis](competitor-analysis-0.4.5.md) explain the findings behind it.

## 0.4.5 — Canvas appearance and discoverability

This release improves the canvas appearance and prepares the directory listing.

- **Background choices — shipped in 0.4.5:** dots, square grid
  and ruled lines, with a plain option. Patterns follow the theme and camera;
  **Menu → Background** remembers the choice. Dots remain the default.
- **Directory discoverability — description prepared:** describe the plugin as
  a whiteboard for brainstorming, mind maps and diagrams. Publish the updated
  marketplace snapshot with 0.4.5; see [listing notes](marketplace-listing.md).

## Next maintenance pass

- **PNG export readiness:** reproduce the delayed-image case and make capture
  wait for images and a rendered frame, with a bounded failure path.
- **Maintenance:** share connector geometry between the board and export
  rendering.

These maintenance items are planned. Completed changes are recorded in the changelog.

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
