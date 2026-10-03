# Competitor analysis for 0.4.5

Reviewed 2026-10-02 against local `release-0.4.5` at `f6c4a21` and current
competitor documentation. This is a product recommendation, not an approved
implementation plan. No application code was changed.

Release direction updated 2026-10-03: the connector proposal below is planned
for **0.5**. See the [roadmap](roadmap.md) for the current release scope.

**Recommendation: make connectors editable in 0.4.5.** Add relationship labels,
explicit actions on individual connectors, and pointer endpoint selection while
retaining the keyboard workflow. This addresses a weakness in the existing
notes-and-connectors promise and has a clearer boundary than introducing a
container hierarchy, document embeds, or collaboration.

**Evidence and limits**

Omarchyform findings come from the current README, store, controller, exchange,
and rendering code. Competitor findings come from linked first-party documentation
and repositories, not from installing and testing each competitor. Priorities and
effort are judgments. There is no comparative performance benchmark or user study.
The existing [discovery checklist](usability-checklist.md) explicitly records that
no discovery sessions have been conducted. Competitor parity establishes a gap;
it does not establish how often Omarchyform users encounter it.

**The relevant competitors**

These tools compete for personal spatial thinking and diagramming. The Obsidian
plugins are particularly relevant to the question about other plugins; their host
also supplies file management and knowledge integration that Omarchyform would
otherwise have to implement.

| Competitor | Documented advantage relevant here | Implication for Omarchyform |
| --- | --- | --- |
| [Obsidian Canvas](https://obsidian.md/help/plugins/canvas), a core plugin | Labeled, selectable, reconnectable lines; Markdown and file/web cards; groups; snapping and zoom to selection | Stronger for research boards and ordinary pointer diagram editing. |
| [Excalidraw](https://github.com/excalidraw/excalidraw) and its [Obsidian plugin](https://github.com/zsviczian/obsidian-excalidraw-plugin) | The editor has labeled arrows, freehand tools, grouping, shape libraries and SVG export. The plugin adds templates, Obsidian links, Markdown embeds and scene clipboard exchange. | Stronger for expressive diagrams and reusable material connected to notes. |
| [Advanced Canvas](https://github.com/Developer-Mike/obsidian-advanced-canvas), an Obsidian community plugin | Edge styles and routing, collapsible groups, automatic node sizing, presentation mode, portals, and enhanced PNG/SVG export | Illustrates how much diagram organization can grow beyond basic cards and arrows. |
| [tldraw](https://tldraw.dev/sdk-features/default-shapes) | Its current editor documents labeled curved/elbow arrows and frames that move their contents; [groups](https://tldraw.dev/sdk-features/groups) are persistent selectable units | Useful reference for object editing and container behavior. Its [Obsidian plugin](https://github.com/tldraw/obsidian-plugin) provides host integration, but this review does not assume every current SDK feature exists in every released plugin version. |
| [Apple Freeform](https://support.apple.com/guide/freeform/welcome/mac), an adjacent app | A wider range of material, scenes, PDF export, and collaboration across Apple devices | Shows the broader whiteboard expectation, although its platform and account ecosystem differ substantially. |

**What is already competitive**

Omarchyform already supports text and image capture, drag-and-drop images,
multiple boards and folders, search within a board, alignment and distribution,
multiple selection, duplication with internal connectors, undo/redo, autosave,
trash, native board import/export with bundled pictures, and selection PNG export
in theme, light, dark and monochrome palettes. Those are shipped features, not
recommendations for 0.4.5.

Its most distinctive combination is native Omarchy theme integration, a summoned
fullscreen surface that can become a tiled window, keyboard spatial navigation,
ordinary local files, and a headless CLI using the same board logic. These are
reasons to choose it for a brief thinking session beside an editor.

Local storage and JSON are valuable but are not exclusive advantages: Obsidian
Canvas uses an open local format and Excalidraw supports local operation. A native
implementation also does not by itself prove lower latency or memory use.

**Where Omarchyform is missing features or behaves worse**

| Priority | Current gap, verified locally | What the user loses | Competitor reference | Relative scope |
| --- | --- | --- | --- | --- |
| 1 | Connectors store only `from` and `to`, have no labels, cannot be selected directly, and are removed by repeating the connection gesture. Clicking the second endpoint cancels connect mode. | Cannot write “depends on”, “yes”, or “blocks” on a relationship; pointer users cannot complete the existing connect sequence by clicking the target. | Canvas line editing; Excalidraw labeled arrows | Medium |
| 2 | `Ctrl+C` produces one image or concatenated note text, not board objects. Duplication stays within the current board. | Moving a cluster to another board loses layout, shapes and relationships through the ordinary clipboard path. | Excalidraw plugin scene clipboard exchange | Medium |
| 3 | Marks are temporary selections. Pinned backgrounds are scenery; their contents remain independent. | A topic cluster has to be selected again to move or reuse it. A background cannot carry its notes with it. | tldraw groups/frames; Canvas groups | Large |
| 4 | Visual export is PNG only. Editable exchange is the native board format only. | No native vector diagram for documents and no direct editable exchange with Obsidian Canvas. | Excalidraw SVG; [JSON Canvas specification](https://jsoncanvas.org/spec/1.0/) | Medium for SVG; larger for reliable conversion |
| 5 | Notes have a small custom markup, without actionable URL/file/board links or Markdown/PDF document cards. | Research sources and project files remain separate from the ideas on the canvas. | Canvas file/web cards; Excalidraw plugin hyperlinks and embeds | Small-to-medium for explicit URL opening; large for document embeds |
| 6 | Board-browser search matches paths; content search is confined to the current board. Fit frames the whole board rather than the marked set. | Finding an old thought requires knowing its board name; larger boards lack a direct way to focus a chosen cluster. | Canvas zoom to selection; [Freeform board search](https://support.apple.com/guide/freeform/search-your-boards-frfm18ab658ed/mac) | Small for fit to selection; larger for content indexing |
| 7 | Alignment is explicit. No pointer snapping, automatic note sizing or reusable template/library workflow is implemented. | Repeated layouts and tidy pointer placement require manual work; long notes need resizing. | Canvas snapping; Advanced Canvas automatic sizing/templates | Varies; suitable incremental work |
| 8 | No freehand drawing, scenes/presentation flow, or live collaboration. | Sketching and facilitated team sessions require another tool. | Excalidraw drawing; Advanced Canvas presentations; Freeform collaboration | Large; lower fit for the current personal workflow |

Performance is another constraint, but not a proven loss against competitors.
The recorded [scene benchmark](performance.md) reports p95 pan/zoom frame times
of 36.7/39.1 ms at 1,000 items and 104.9/95.7 ms at 3,000 on the documented machine.
Those exceed its 16.7 ms refresh budget. Avoid claims of smooth large-board
interaction, and ensure new connector interaction does not repaint or scan every
item unnecessarily. No equivalent competitor measurements were taken.

**A bounded 0.4.5 proposal**

Make a small decision diagram usable without workarounds. A user should be able
to connect “Ready?” to “Ship”, label that relationship “yes”, select the line,
reverse or delete it explicitly, undo the action, and export a picture that
retains the label.

1. Add an optional plain-text relationship label. Keep labels attached to the
   connector when notes move. Draw them legibly in every supported export palette.
2. Expose individual connectors through a keyboard-accessible list for the
   selected note, with named edit-label, reverse and remove commands. Pointer
   selection of a line should reach those same actions.
3. In connect mode, a plain click on a valid target selects that endpoint and
   preserves the source. Keep the current outcome preview and require an explicit
   confirmation before create, reverse or remove. Define empty-canvas clicks,
   Shift-click, dragging and Escape so selecting cannot silently delete a line.
4. Preserve one undo step per completed change, persistence, read-only behavior,
   duplication, portable export, and the CLI contract. Old boards load with blank
   labels. Version new files so an older plugin cannot silently strip labels.

This needs changes across serialization, history, controller selection, both
rendering scenes, and CLI operations. It is a moderate feature, not a cosmetic
patch. Reuse the current straight-line geometry initially; routing and additional
arrowhead styles can follow separately.

Acceptance should include a keyboard-only and a pointer path, label survival
through save/reload and duplicate, safe cancellation, explicit deletion plus
undo, exports in all four palettes, and older/newer file compatibility. Use
`npm test`, relevant QML/UI regression checks, and isolated live checks in both
window modes. Review label placement visually at low and high zoom. No tests
were run for this documentation-only analysis.

**What should follow**

After connectors, prioritize copying and pasting board objects between boards.
Then add persistent groups, with explicit membership, before considering the
more complex behavior of frames, nested groups or collapse. SVG export and zoom
to selection are useful independent improvements. If discovery sessions show
that users mostly collect sources rather than draw relationships, prioritize
explicit URL/file links ahead of grouping.

Cloud collaboration, comprehensive document rendering, custom CSS, and an AI
generation interface would expand the product substantially. The existing CLI
already provides an automation route. None is needed to complete the recommended
0.4.5 workflow.

The [earlier usability plan](usability-next-pass.md) deferred pointer connecting
until observation. This review proposes revisiting that decision because of a
concrete workflow limitation and documented competitor behavior; it does not
claim that the missing observation has since happened.
