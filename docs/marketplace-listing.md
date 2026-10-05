# Marketplace discoverability

Checked 2026-10-03 against the [live catalog](https://plugins.omarchy.org/catalog.json)
and the directory's [search code](https://plugins.omarchy.org/assets/js/search.js?v=20261002-03),
and again on 2026-10-05: see [What a push changes](#what-a-push-changes).

## What needed improving

On 2026-10-03 the live Omarchyform listing used snapshot
`0d3d7e3380c4cf74f41344c44fc405d93148d4a4` and version 0.4.0. Its description
called it a “board” and omitted common terms for its purpose. Searching by its name
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

## What a push changes

The section above expected the listing text to wait for a verified update. It
does not. On 2026-10-05 the catalog entry showed the whiteboard description and
version 0.4.5, read from `main` (`upstreamObservedCommit`), while its verified
snapshot (`verificationCommit`) was still `0d3d7e3` and its coverage
`update-unverified`. The directory re-reads each listing's default branch, and
the install command always clones it.

What verification adds is the **Verified** badge for one exact commit. To ask
for it after a release, use the marketplace's
[update process](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/VERIFICATION.md#promoting-a-plugin-update):

- Select **Verify and publish a newer upstream commit** in its verification form.
- Use plugin ID `thepixelgardener.omarchyform`, repository
  `https://github.com/thepixelgardener-create/omarchyform`, and the full SHA of
  the release commit, which has to be the repository's current `HEAD`.
- Every later push returns the badge to "Update unverified" until the next
  request, so one request per release is enough.

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
