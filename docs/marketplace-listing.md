# Marketplace discoverability

Checked 2026-10-03 against the [live catalog](https://plugins.omarchy.org/catalog.json)
and the directory's [search code](https://plugins.omarchy.org/assets/js/search.js?v=20261002-03).

## What needs improving

The live Omarchyform listing uses snapshot
`0d3d7e3380c4cf74f41344c44fc405d93148d4a4` and version 0.4.0. Its description
calls it a “board” and omits common terms for its purpose. Searching by its name
works; searches for whiteboard, brainstorming, mind map, diagram, sticky notes
and images do not match it.

The directory searches the name, description, author/publisher, plugin ID,
category, kind and tags. README text and arbitrary manifest keywords are not
part of that search. Changing the README alone cannot fix these misses.

## Change prepared for 0.4.5

The root manifest now describes the plugin as:

> An offline whiteboard for brainstorming, mind maps and diagrams. Arrange sticky
> notes, images and shapes on an infinite canvas, with keyboard controls and
> Omarchy themes.

The README introduction and bar description use the same whiteboard wording.
The plugin name and ID stay stable.

Running the live directory's search functions against its catalog entry, then
changing only the description to the prepared value, gave these results for
the directory's `?text=` searches:

| Search | Live listing | Prepared description |
| --- | --- | --- |
| omarchyform | Match | Match |
| whiteboard | No match | Match |
| brainstorming | No match | Match |
| mind map / mindmap | No match | Match |
| diagram | No match | Match |
| sticky notes | No match | Match |
| images | No match | Match |
| canvas | Match | Match |

This checks whether the entry matches. It does not measure ranking or traffic.

## Publish with the release

The directory holds a reviewed snapshot. A local edit or a push alone does not
replace that snapshot's listing text. After the 0.4.5 release commit is on the
repository's default branch, use the marketplace's
[update process](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/VERIFICATION.md#promoting-a-plugin-update):

- Select **Verify and publish a newer upstream commit** in its verification form.
- Use plugin ID `thepixelgardener.omarchyform`, repository
  `https://github.com/thepixelgardener-create/omarchyform`, and the full SHA of
  that release commit.
- After publication, repeat the searches above against the live directory.

Submitting the update is a release step; a GitHub Release alone does not update
the live catalog.

## Directory taxonomy follow-up

The category is already **Productivity**. Current tags are `quickshell`,
`hyprland` and `bar`. The marketplace's
[allowed tags](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md#choose-listing-metadata)
do not include notes, whiteboard or diagrams. Suggest a reusable `notes` tag to
the maintainers; adding an unsupported tag to this manifest would not update
the registry's tags.

The directory also presents the plugin as **Bar widget**. Its
[catalog builder](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/scripts/build-catalog.mjs)
checks `bar-widget` before `overlay` when deriving one kind from the manifest.
A directory improvement could expose both kinds for plugins such as Omarchyform.
Both entry points serve a purpose in the application.
