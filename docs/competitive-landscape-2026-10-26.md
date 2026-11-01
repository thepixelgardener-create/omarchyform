# Competitive landscape: niche and essential features

Research date: 2026-10-26. This extends the [25 ranked recommendations](competitive-review-2026-10-25.md), rather than replacing their implementation detail or the [release roadmap](roadmap.md). It covers **23 product families, two Obsidian extensions, and one discontinued product**. Ten families and the discontinued case are new to the preceding review. Product capability is documented evidence; relevance, niche fit, and priority are our judgments. No competitor was installed or benchmarked, and no customer demand or market size has been established.

## Decision

The strongest niche hypothesis is **a keyboard-first thinking board beside an editor for Omarchy users: capture an idea, connect a small decision diagram, reuse it, and return to work, with local files and a scriptable CLI**.

The existing tiled window, optional overlay, theme integration, spatial keys, split panes, local boards, and CLI support this hypothesis (see the [current product](../README.md) and [guide](guide.md)). They are an existing combination to make useful and explain clearly. They are not proof of exclusive differentiation. Heimer challenges the native/simple diagram claim; Obsidian challenges local files; Kinopio challenges lightweight connected cards; Eraser challenges developer diagram workflows.

The target job is: “While working on a project, I need to externalize a few related ideas and a decision without opening a larger knowledge workspace.” The initial audience is an Omarchy user who already works with an editor and terminal. Research collection is a secondary niche to test. A global whiteboard market is too broad to guide this product's next release.

## Multiple filters and priority rules

Apply filters together, in this order. These are analysis filters, not implemented application controls. A product can appear in several workflow groups.

1. **Audience/job:** personal thinking, technical diagrams, research/knowledge, visual reference, pen/PDF, or team facilitation.
2. **Environment:** Linux desktop, browser, host plugin, Apple ecosystem, or SDK. Browser availability does not imply offline durability; a desktop client does not imply native UI.
3. **Ownership:** documented local files/local-first, hosted service, or not established here. Unknown is not “no.” Offline availability, open source, portable files, and open formats are separate properties.
4. **Relationship:** direct substitute for the chosen job, adjacent specialist, or implementation reference. SDK capabilities do not establish the feature set of a hosted product.
5. **Study priority:** A = compare the target task first; B = study a specific workflow if it matters; C = boundary/reference only; H = historical. Priority measures usefulness to this decision, not product quality.
6. **Feature decision:** essential to complete the target task; differentiator to preserve; conditional on an audience change; or outside scope. Then check evidence, dependencies, and maintenance cost.

Use AND across dimensions and OR within a dimension. For example: personal thinking AND (Linux desktop OR browser OR host plugin) AND A produces the closest task-comparison set. Adding local ownership narrows it further, but should keep unknowns in a separate verification queue rather than silently rejecting them.

## Landscape matrix

The first 13 families and two extensions retain the [preceding review's primary-source research](competitive-review-2026-10-25.md#competitors-and-what-they-changed), dated 2026-10-25. New entries below were researched on 2026-10-26. Environment labels describe the relevant surface, not an exhaustive platform list. Ownership claims are limited to the cited workflow; they are not security certifications.

| Product / primary source | Job filters | Relevant environment | Ownership evidence | Relation / study priority | Decision it informs |
|---|---|---|---|---|---|
| [Obsidian Canvas](https://obsidian.md/help/plugins/canvas) | Thinking, research | Host plugin | Local canvas files | Direct / A | Why leave an existing vault? Complete connections and reuse first. |
| [Excalidraw](https://github.com/excalidraw/excalidraw#features) | Thinking, diagrams | Browser; host extension separately | Editable files; local operation described | Direct / A | Test sketch-like diagrams versus constrained cards; preserve editable reuse. |
| [tldraw](https://tldraw.dev/sdk-features/camera) | Thinking, diagrams | SDK/editor reference | Deployment-dependent; not assessed | Reference / B | Camera, clipboard, selection, and asset architecture. |
| [diagrams.net](https://www.drawio.com/doc/) | Technical diagrams | Browser/desktop | Local-file workflow documented | Direct / A | A diagram specialist sets expectations for editable relationships and output. |
| [Minder](https://github.com/phase1geo/Minder) | Thinking, mind maps | Linux desktop | Saved mind maps | Direct / A | Keyboard quick entry should make connected thinking easy. |
| [Rnote](https://github.com/flxzt/rnote) | Pen, visual notes | Native desktop | Document files | Adjacent / B | Useful import/export reference; pen UX is a separate commitment. |
| [Xournal++](https://github.com/xournalpp/xournalpp) | Pen, PDF | Desktop | Document files | Adjacent / C | PDF annotation is a different target job. |
| [AFFiNE](https://github.com/toeverything/AFFiNE) | Thinking, knowledge | Workspace app | Describes local-first | Direct / B | Local-first alone cannot distinguish a small board. |
| [Apple Freeform](https://support.apple.com/guide/freeform/welcome/mac) | Thinking, team | Apple ecosystem | Not audited here | Adjacent / C | Saved scenes inform later navigation; not the Linux baseline. |
| [Milanote](https://help.milanote.com/en/articles/1722065-links) | Research, visual reference | Hosted app | Local-file ownership not established here | Adjacent / B | Preserve source references if collecting becomes the job. |
| [Heptabase](https://wiki.heptabase.com/user-interface-logic) | Research, knowledge | Knowledge workspace | Storage contract not audited here | Adjacent / B | Retrieval and reusable notes matter for a research niche. |
| [Miro](https://help.miro.com/hc/en-us/articles/4403828752274-How-to-access-Miro-boards-with-assistive-technologies) | Team, thinking | Hosted board | Local-file ownership not established here | Adjacent / B | Content accessibility is relevant; service collaboration need not be copied. |
| [FigJam](https://help.figma.com/hc/en-us/articles/14477051168791-Use-FigJam-with-a-screen-reader) | Team, thinking | Hosted board | Local-file ownership not established here | Adjacent / B | Study keyboard and screen-reader object workflows. |
| [Heimer](https://github.com/juzzlin/Heimer) | Thinking, diagrams | Qt Linux/Windows desktop | XML-based ALZ save/load | Direct / A | Native simplicity already exists; labels, autosave, undo, fit, and SVG are documented. |
| [VYM](https://github.com/insilmaril/vym) | Thinking, mind maps, tasks | Linux/Windows/macOS desktop | File workflow; detailed format not audited | Direct / A | Native mind mapping also offers task priorities and scripting; avoid competing on a long feature list. |
| [Kinopio](https://kinopio.club/) | Thinking, research, team | Browser | Offline and import/export described; durability not tested | Direct / A | Cards/connections, bulk edits, boxes, and quick capture challenge the lightweight-board pitch. |
| [Scrintal](https://scrintal.com/) | Research, knowledge, team | Workspace app | Storage contract not established here | Adjacent / B | PDFs, linked blocks, and document conversion show the depth of research workflows. |
| [Xmind](https://xmind.com/features) | Thinking, mind maps, tasks | Desktop/web/mobile | Local storage contract not audited here | Direct / B | Structured layouts and task features serve a broader planning job. |
| [Plectica](https://www.plectica.com/pricing) | Thinking, research | Hosted map | Local-file ownership not established here | Direct / B | Cards can contain lists, links, and media; minimal cards alone are not a niche. |
| [Eraser](https://docs.eraser.io/) | Technical diagrams, developer work | Developer workspace | Storage contract not audited here | Adjacent / A | Diagram-as-code and editor/Git integration challenge the developer audience claim. |
| [yEd](https://www.yworks.com/products/yed) | Technical diagrams, graphs | Java desktop, including Linux | Imports and visual exports documented; format contract not audited | Direct / B | Automatic graph layout is mature specialist territory. |
| [PureRef](https://www.pureref.com/handbook/settings/) | Visual reference | Desktop, including Linux in [shortcut docs](https://www.pureref.com/handbook/shortcuts/all-shortcuts/) | Scene files with embedded or linked images | Adjacent / B | Reference boards need image management, portable assets, and source recovery. |
| [Logseq whiteboards](https://github.com/logseq/docs/blob/master/pages/Whiteboard.md) | Knowledge, thinking | Host workspace | Documented local EDN whiteboards | Adjacent / B, version-qualified | Outliner-linked canvases compete for existing knowledge users. Source describes the file-based workflow; do not assume parity with the newer DB app. |
| [Advanced Canvas](https://github.com/Developer-Mike/obsidian-advanced-canvas) | Knowledge, diagrams | Obsidian extension | Host canvas workflow | Extension / B | Sizing, templates, routing, and presentation are optional depth. |
| [Obsidian Excalidraw](https://github.com/zsviczian/obsidian-excalidraw-plugin) | Knowledge, diagrams | Obsidian extension | Host file workflow | Extension / A | Linked-note reuse is more than an Open URL command. |
| [Kosmik sunset notice](https://launchpad.kosmik.app/) | Research, visual reference | Historical service | Current availability ended per notice | Historical / H | Notice announces sunset on May 31, 2026. Do not list it as a current buying alternative. It supports discussing exit paths, not inferring why every canvas business succeeds or fails. |

## Research passes and stopping rule

**Pass 1 — challenge the existing canvas list.** Retained the prior 13 families and two extensions. Repeated patterns were connector editing, object reuse, navigation, retrieval, and accessible content. These remain stronger signals than decorative parity.

**Pass 2 — challenge the native and lightweight niche.** Added Heimer, VYM, Kinopio, and Xmind. This invalidates a positioning claim based only on native UI, keyboard operation, small cards, local operation, or scripting. Heimer's [release notes](https://github.com/juzzlin/heimer/releases) also document selection-aware fit, usable node handles, and grid-density fixes: useful corroboration of existing proposals, not proof of equal performance.

**Pass 3 — test neighboring jobs and lifecycle risk.** Added Scrintal, Plectica, Eraser, yEd, PureRef, Logseq's file-based whiteboards, and the historical Kosmik case. The added signals are developer handoff, image provenance, knowledge reuse, automatic layout, and exit paths. They mostly change audience choices and scope boundaries rather than justify another large batch of core features.

This is sufficient coverage for a provisional niche decision: each proposed audience has a close alternative and a specialist reference; native/local claims face counterexamples; the latest pass adds fewer new essential capabilities. This is qualitative saturation, not an exhaustive market census. Stop expanding names for now and compare actual tasks. Reopen research when a user names a missing substitute, a competitor's status materially changes, or observed work introduces an uncovered job. Prices, market share, latency, accessibility quality, and willingness to switch remain unmeasured.

## Niche choices, filtered and challenged

| Candidate niche | Closest comparison set | Fit with current product | Essential additions if chosen | Decision / falsifier |
|---|---|---|---|---|
| Omarchy thinking board beside an editor | Heimer, Minder, VYM, Kinopio, Excalidraw, Obsidian Canvas | Strong: tiled/overlay, theme, spatial keys, CLI | Editable connections, reuse, rapid connected entry, dependable navigation | **Primary hypothesis.** Reject if people prefer their existing canvas even after the target task is complete. |
| Personal research and source synthesis | Obsidian, Heptabase, Scrintal, Milanote, Logseq | Partial: spatial notes/images and local boards | Explicit sources, cross-board retrieval, reusable fragments; possibly interchange | **Secondary.** Promote only if real boards repeatedly collect sources and retrieval is the main blocker. |
| Developer architecture documentation | diagrams.net, Eraser, yEd, Excalidraw | Partial: CLI, shapes, PNG | Labeled relationships, reuse, durable source/editable handoff; SVG if document workflows require it | **Bounded secondary use.** Do not promise code round-trip or architecture libraries without evidence. |
| Image reference and moodboards | PureRef, Milanote, Kinopio | Partial: images and arrangement | File picker, image memory work, source provenance, convenient image arrangement | **Conditional.** Promote if image-heavy sessions recur and current admission/retention costs are measured. |
| Pen/PDF annotation or team workshops | Rnote/Xournal++; Miro/FigJam/Freeform | Low for current scope | Pen/PDF engine or collaboration service | **Do not pursue now.** Requires an explicit product-direction change. |

Suggested positioning to test: “A local thinking board for Omarchy. Sketch a decision beside your editor, connect ideas with the keyboard, and keep the board as a file.” Do not advertise lower memory, faster launch, smoother large boards, or superiority to these alternatives without measurements.

## Essential feature priorities for the primary niche

These tiers select from the earlier 25 candidates. They do not silently approve implementation or change version commitments. “Essential” means the target workflow should work end to end; existing essentials need validation and preservation, not automatic rewrites. Safety, accessibility, and responsiveness are release conditions across tiers, not optional extras after feature work.

| Priority | Capability / earlier candidate | Status and smallest useful outcome | Why essential / dependency | Evidence that could change priority |
|---|---|---|---|---|
| P0 | Local saving, recovery, undo, portable board, CLI, tiled/overlay, split views | Existing; preserve and validate with a real session | These deliver ownership and the beside-editor workflow | Actual lost work, recovery trouble, or mode-switch friction takes precedence over new features |
| P0 | Predictable input and accessible content (#1–2, #13) | Audit real mouse/trackpad and Orca/AT-SPI; make items and relationships reachable; maintain usable targets | A thinking workflow cannot depend on one device or visual pointer targeting | Device and accessibility findings determine exact fixes; do not infer screen-reader failure solely from missing properties |
| P0 | Responsiveness on ordinary work (#6; profile #17–21) | Measure complete tasks against current targets; fix evidenced stalls | Flow beside an editor is the positioning promise | Use [current targets](performance.md#targets--2026-10-26), not only hostile-test ceilings; optimization choice follows profiling |
| P1 · first feature | Editable, labeled relationships (#3) | Select, label, reverse/remove, cancel, undo, reload and export; preserve explicit connect confirmation | A decision diagram needs “yes”, “blocks”, or “depends on”; follows planned 0.6 | Task observation may narrow controls, but basic relationship meaning remains central |
| P1 · second feature | Reuse editable selections across boards (#4) | Preserve layout, internal links, validated images, remapped IDs, one undo step | Moving a useful cluster should not require reconstruction | If users never reuse clusters, move below connected entry; whole-board exchange is not a substitute |
| P1 · third feature | Rapid connected entry (#7) | One explicit create-neighbor-and-connect action | Strengthens the keyboard-specific reason to choose the app | Compare against existing create/connect steps; require fewer interruptions, not merely a new shortcut |
| P1 · small independent work | Fit selection (#5) and clear image import (#10) | Fit cursor/marks; picker through existing validation | Complete focus and disk-image workflows without a new subsystem | Frequent image-heavy work raises picker and image profiling together |
| P2 | Recent-board switcher (#11), fit text (#14), simple hierarchy (#15) | Bounded recent list, one-shot fit, small explicit roles | Improve returning and reading; do not need full knowledge-workspace semantics | Observe repeated reopening, hidden text, and scanning failures |
| P2 · conditional | Sources/search/templates/groups (#8, #12, #16, #22) | Explicit source first for research; retrieval when library size justifies it; fragments after copying | Strong adjacent needs, but not prerequisites for every brief thinking session | Promote sources and retrieval if research wins; promote groups if users repeatedly move stable clusters |
| P3 | Named views, SVG/interchange, richer routing and layout | Narrow separately after actual handoff/navigation failures | Specialist depth can consume the product without improving the main job | Promote SVG for repeated vector-output demand; editable conversion needs explicit loss reporting |
| Outside current scope | Multiplayer, PDF/pen engine, embedded browser, persistent timeline, built-in AI panel | Retain boundaries in the preceding review | Large new ownership, rendering, or service responsibilities | Requires audience evidence and a deliberate scope change, not competitor counts |

New priorities relative to the previous report are **preserve the existing differentiators as explicit essentials**, **treat rapid connected entry as core to the selected niche**, and **evaluate developer handoff and image provenance as conditional requirements**. This does not add eleven more speculative features. Most landscape expansion strengthened or narrowed existing candidates.

## Validation and next decision

Recruit a small first round of 5–8 relevant Omarchy users; this is a discovery sample, not a statistical market estimate. Ask them to bring a recent task and show their current tool before demonstrating Omarchyform. Include existing Obsidian/Excalidraw and native mind-map users where available. Record device, task, existing workaround, completion, interruptions, recovery mistakes, and whether they return voluntarily over the following week.

Compare the same personal task against the user's current alternative: create a small decision graph, label a relationship, reuse a cluster, return to a working area, reopen the board, and hand off the result. For features not implemented, use an explicitly labeled prototype and separate prototype findings from current-product results. Do not report a failed task as measured until it has actually been observed.

The primary hypothesis gains support if multiple independent users bring this beside-editor job, can finish it, and choose to return without prompting. It weakens if the need is occasional, existing tools remain preferable, or the requested work consistently requires research embeds, pen input, or team coordination. Record why someone stays with another tool. The purpose is to decide what to omit as much as what to build.

After that round, revise this table, choose the smallest release slice, and retain unmet objections. A short showcase should demonstrate the selected job and existing CLI/file ownership; a feature-count comparison cannot demonstrate a reason to switch.

## Work and verification

Documentation research only. Read the contribution rules, current README, roadmap, and prior review; expanded the landscape through three complementary passes using linked primary sources. Current-source checks exposed Kosmik's sunset and a version boundary around Logseq, so neither is represented as an unqualified current equivalent. No application code, roadmap commitments, competitor installations, new performance benchmarks, or user studies changed. Application test suites are not required for these documentation-only edits. Markdown links and whitespace were checked locally; external-source availability and capability claims remain dated evidence.
