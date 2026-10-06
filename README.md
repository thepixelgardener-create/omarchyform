# Omarchyform

A local whiteboard for brainstorming, mind maps and diagrams on Omarchy.

An infinite canvas. Sticky notes, images, shapes and connectors on a board you can pan and
zoom, driven from the keyboard, stored as a plain JSON file on your own disk.

Capture a thought, arrange it spatially, get back to work. It follows your
Omarchy theme and keeps your boards on your own machine.

Find it in the [Omarchy plugin directory](https://plugins.omarchy.org/?text=omarchyform).

![Omarchyform](preview.png)

![The same board in eleven Omarchy themes](preview-themes.webp)

## What it is

A native Quickshell plugin. It runs inside the long-running `omarchy-shell`
process — no webview, no Electron, and no separate application service.
The controller stays loaded between opens; canvas surfaces exist only while
open, and pending saves can finish after closing.

It has two surfaces, and `w` switches between them:

- **Fullscreen** — a Hyprland layer-shell overlay above everything, with its
  own keyboard grab. Summon it, think, dismiss it.
- **Windowed** — an ordinary toplevel, so Hyprland tiles it beside your editor
  and browser like any other app.

The camera, the notes and the selection are shared, so toggling never loses
your place. The mode is remembered between sessions.

## Install

```bash
omarchy plugin add https://github.com/thepixelgardener-create/omarchyform.git --enable
```

It asks where to put the icon — left, center or right — and puts it there. The
bar is the way to reach the board without knowing a keybinding, so answer the
question rather than skipping it.

Nothing asks if you add it non-interactively or with `--yes`, and enabling it
later with `omarchy plugin enable` does not ask either: both put the icon on
the right. Say where yourself, then or at any time after:

```bash
omarchy bar move thepixelgardener.omarchyform --section center
```

The sticky-note icon opens and closes the board, and carries the accent colour while it is
open. Its defaults — autosave delay, keyboard step, canvas pattern, and whether the
board opens windowed — live on the bar entry and are handed to the board when
it opens, then remembered, so opening from the keyboard uses the same values.
Choose the canvas appearance inside the board with **Menu → Background**;
that choice takes precedence over the bar's canvas defaults.

For the keyboard route, bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + I", "Omarchyform", "omarchy-shell shell toggle thepixelgardener.omarchyform")
```

Check the key is free first with `omarchy menu keybindings --print`, and
validate afterwards with `hyprctl reload && hyprctl configerrors`.

The plugin also ships `hypr/bindings.lua` with that same binding in it, for
people who would rather load plugin bindings than write their own. Omarchy
does not read those files on its own — `hyprland.lua` only loads your
`hypr/bindings.lua` — so add a loader to it once:

```lua
-- Load keybindings shipped by installed Omarchy plugins.
local plugins = os.getenv("HOME") .. "/.config/omarchy/plugins"
local found = io.popen("find " .. plugins .. " -maxdepth 3 -name bindings.lua 2>/dev/null")
if found then
  for file in found:lines() do dofile(file) end
  found:close()
end
```

Use the loader or your own `o.bind`, not both: the same key declared twice is
declared twice.

## Updating it

```bash
omarchy plugin update thepixelgardener.omarchyform
```

That reloads the plugin itself, so there is no rescan to run afterwards. Close
the board first, or save with `ctrl+s` and wait for the saving indicator to
clear: a reload unloads the overlay, and a forced unload can interrupt a save
that is still in flight.

If the board does not open after an update, or opens looking like the version
you just replaced, run `omarchy restart shell`. A reload does not reliably
replace a plugin's loaded QML on the version tested; see
[Development](#development).

Your boards, backups, trash and pasted pictures are untouched by an update:
they live outside the plugin directory, in `~/.local/share/omarchyform/`. A
board written by a newer version than the one you are running opens read-only
rather than losing what it does not understand, so downgrading is safe too.

If you installed the desktop entry, re-run its installer,
`desktop/install.sh` in the plugin's folder, after an update to pick up any
change to it. It replaces only an entry it installed itself and leaves your
edits alone; see below.

## Opening a board someone sent you

The desktop installer, `desktop/install.sh` in the plugin's folder, also
registers the board file type and a small `omarchyform-open` command, so a
board can be opened from a file manager.

A board in your library is an ordinary `.json` and opens from the browser on
`b`. A board saved to share — `ctrl+shift+s` — is named `*.omarchyform.json`,
and that is what a file manager recognises. The double extension is the honest
way to claim it: a board *is* JSON, and claiming `*.json` outright would hand
every JSON file on the machine to a note-taking program. Import still accepts
any `.json`, so a board from before this is still a board.

Opening one brings it into your library rather than editing it where it sits,
which is what `ctrl+o` has always done: the file you were sent is left alone.

## Removing it

If you installed the desktop entry, remove it first, while the plugin's folder
is still there — removing the plugin deletes the folder, and the uninstaller
with it:

```bash
~/.config/omarchy/plugins/thepixelgardener.omarchyform/desktop/install.sh --uninstall
```

That removes the launcher entry, the file type and the `omarchyform-open`
command, and only the ones this installer wrote and you have not edited since;
otherwise it says what it found and leaves the file alone.

Then remove the plugin:

```bash
omarchy plugin remove thepixelgardener.omarchyform
```

That takes the bar icon with it. To put it away without uninstalling, use
`omarchy plugin disable thepixelgardener.omarchyform`; enabling it again
restores the icon where it was. Delete the binding from
`~/.config/hypr/bindings.lua` too, if you added one.

Your boards are left alone. They live in
`~/.local/share/omarchyform/`, and removing the plugin does not touch them, so
reinstalling picks up exactly where you left off. Delete that directory
yourself if you want them gone.

## Keys

Press `?` or `F1` on the board for this list. The board's name, the menu and
whatever it is currently telling you all sit together at the top; the rest of
the canvas is yours.

You do not have to know any of them. `:` — or `ctrl+p`, or **Commands** in the
header menu — opens a list of every command by name: type a few letters, press
`enter`. It shows the key beside each one, so the list teaches the keyboard
while you use it, and a command that cannot run just now is dimmed and says
what it is waiting for rather than doing nothing when you pick it.

`.` — or a right-click on the canvas — opens the same list narrowed to what can
be done with whatever is selected: change its shape or colour, connect it,
duplicate it, pin or unpin it, bring it forward, delete it, and every answer the
`g` chord has, by name. So aligning two notes does not need the second key of a
chord you have not learned yet.

The boxes you type in — the query above, find on the board, the board name, the
search in the browser — are real text fields: caret keys, selection, the
clipboard and input-method composition all work, and renaming opens with the
current name selected so one keystroke replaces it. Where the keyboard is is
marked with a `›` as well as a tint, so it does not depend on telling two
colours apart, and the controls carry names and roles for a screen reader.

| Key | Does |
|-----|------|
| `n` | New note beside the selected one, ready to type |
| `r` / `e` | New box / ellipse |
| `p` / `Shift+P` | Pin as background / select backgrounds to unpin |
| `s` | Cycle the shape: note, box, ellipse, diamond |
| `x` | Connect: `x` on one, `tab` or `hjkl` to the other, `x` again |
| `x` on a connected pair | Turn that connector round, or remove it — the line under the header says which |
| `X` | Remove every connector on this item at once |
| `u` / `ctrl+r` | Undo / redo |
| `ctrl+n` | New board, already waiting for the first note |
| `F2` | Rename the board you are on |
| `super+v` / `ctrl+v` | Paste a picture from the clipboard, or text as a note |
| `ctrl+o` | Open a board file from anywhere |
| `ctrl+shift+s` | Save a copy of this board somewhere else |
| `ctrl+e` | Export a PNG — the whole board, or just what is marked |
| `enter` / `i` | Type in the selected note |
| `esc` | Stop typing, drop the marks, then close the board |
| `h` `j` `k` `l` | Move the selection to the nearest note that way |
| `H` `J` `K` `L` | Push the selected note around |
| `Ctrl+HJKL` | Resize selected items |
| `tab` | Cycle through every note |
| `space` | Mark this item as well, so the next command takes both |
| `a` | Mark everything |
| `del` / `backspace` | Delete what is marked, or the one under the cursor |
| `ctrl+d` | Duplicate it, and the connectors between the copies |
| `m` | Show or hide the menu in the header |
| `m` then `h` `l` / `tab` | Walk the menu; `enter` picks, `esc` closes |
| `super+c` / `ctrl+c` | Copy it out: a picture as a picture, anything else as its text |
| `/` | Find: type to search the notes, `enter` steps through the matches |
| `g` then `h` `j` `k` `l` | Align the marked items on that edge |
| `g` then `c` / `m` | Align their centres on one vertical / horizontal line |
| `g` then `H` `J` `K` `L` | Spread them evenly; the outermost two stay put |
| `c` | Cycle its theme role: foreground, accent, urgent, muted |
| `b` | Boards: browse, open, create |
| `w` | Switch between fullscreen and windowed |
| `f` | Fit the whole board on screen |
| `0` | Reset the view |
| `+` / `-` | Zoom |
| `]` / `[` | Bring forward / send backward, where things overlap |
| `}` / `{` | Bring right to the front / send right to the back |
| `?` / `F1` | Keybinding list |
| `:` / `ctrl+p` | Run any command by name, without knowing its key |
| `ctrl+p` while typing | Format selected text: bold, italic, key, heading or colour |

Overlapping items are drawn in the order the board file lists them, and `]` `[`
`}` `{` move the selected ones through that order. Several at once keep their
order relative to each other, ids and connectors are untouched, and undo puts it
back. Pinning is separate: a background stays a background, and reordering it
moves it among the other backgrounds.

`space` marks the item under the cursor. Moving, resizing, recolouring,
changing shape and deleting then apply to everything marked, and the cursor
item decides what the rest become, so a mixed selection lands on one colour
rather than each cycling from its own. With nothing marked, every command
applies to the cursor alone, so the keys behave exactly as before until you
ask for more.

Mouse works too. Drag across empty canvas to sweep a rectangle: everything it
touches gets marked, and holding Shift keeps whatever was marked already.
Shift-click marks items one at a time, dragging a marked item moves the whole
set, and the bottom-right corner resizes them. Middle-drag or right-drag pans,
the wheel zooms at the pointer, double-clicking empty canvas leaves a new note,
and double-clicking a note types in it.

A middle-drag pans wherever it starts — over bare canvas, a note, a shape, a
picture or a pinned background — and a middle-click that does not move does
nothing at all: it will not select, move, resize, type into or delete what it
lands on. Deleting is `del`, `backspace`, or **Delete** in the command list,
and it can be undone with `u`.

The header shows the zoom on the right, beside the menu, and clicking it fits the
board to the window, as `f` does. To pick a level, the header menu includes
**Zoom**: open it with `m`, use `Tab` / `Shift+Tab` to reach Zoom, then press
`Enter`. Choose 25%, 50%,
75%, 100%, 125%, 150%, 200%, 300%, or 400% with Tab and Enter. **Back** returns
to the main menu; `Esc` closes it. Zoom presets keep the canvas centre fixed.

## What a note can say

A note is plain text with a little markup in it, so a board can have a shape
rather than being twenty identical grey rectangles.

| Type | Or press, with text selected | Gives you |
|---|---|---|
| `# a line` | — | a heading: bigger and heavier |
| `*bold*` | `ctrl+b` | emphasis |
| `_italic_` | `ctrl+i` | quieter emphasis |
| `` `a key` `` | `ctrl+k` | drawn in the accent, the way every key in this shell is |
| `[accent]text[/]` | `ctrl+1` … `ctrl+4` | a span in one of the theme's four roles |

The chords wrap whatever is selected and take the marks off again when pressed
a second time, so there is one key to learn rather than two. Nothing selected
puts the marks down and leaves the caret between them.

Colours are the same four roles the rest of the board uses — foreground,
accent, urgent, muted — so coloured text follows whatever theme your desktop is
wearing. There is still no way to put a hex colour in a board.

While you are typing you see the marks; step out and you see the note. That is
deliberate: the text you are editing and the text you are looking at have to be
the same string, or the caret lands where the characters are not.

**A board is a file other people can send you, and the note is the part they
write.** Everything arriving from a board file is escaped before any of this is
applied, so nothing anyone else wrote reaches the screen as markup — a note
saying `<b>hello</b>` shows you those characters.

## Connectors

Select one item, press `x`, move the selection to the other with `tab` or
`h` `j` `k` `l`, and press `x` again. A dashed line follows the selection while
you choose, and the line under the header says what the second `x` will do
before you press it.

The far end is chosen with the keyboard: clicking an item starts a fresh
selection, which ends the half-made connector without drawing anything.

Only one connector runs between any two items, so drawing one over a pair that
already has one changes the one that is there rather than adding a second:

- **connects these two** — there is nothing between them yet, so a new arrow is
  drawn from the first to the second.
- **turns this connector round** — an arrow already runs the other way, so it
  is reversed to point the way you just drew it.
- **removes this connector** — an arrow already runs exactly this way, so
  drawing it again takes it away.

`Esc` cancels while you are choosing: nothing on the board changes, and the
board is not saved. Every one of the three outcomes can be undone with `u`.

That is how a single connector is removed: select the item it starts at, press
`x`, select the item it ends at, press `x`. `X` is the bulk answer — it removes
every connector on the selected item at once, in both directions, in one undo
step. There is no way to click a connector itself; they are drawn, not selected.

## Pictures of a board

`ctrl+e` writes a PNG of the board with none of the controls in it — no header,
no grid, no selection rings, no resize grips.

**Mark some items first and you get a picture of those**, framed around them
with the same padding. Connectors that leave the marked set leave with it, so
the picture is of what you chose rather than of what happened to be next to it.
Backgrounds are the exception: a pinned shape is scenery, so a cluster lifted
off a board keeps the panel it was sitting on, and the frame is not put round
it. Nothing marked is the whole board, which is what `ctrl+e` has always meant.

A board is drawn in whatever theme your desktop is wearing, which is usually
dark — and a dark picture is the wrong thing to put in a document, a slide or a
printout. The command list has the same export in three other palettes:

| Run | Gives you |
|-----|-----------|
| **Export a PNG** (`ctrl+e`) | The board in its own colours |
| **Export a PNG on white** | A white page, dark text, colour kept for the tints |
| **Export a PNG on black** | A dark page that does not depend on your theme |
| **Export a PNG in black and white** | One ink, for printing — the tints differ by weight rather than hue |

Type `:` then `white`, or `print`, or `png`. Each is its own command, so the
one you want is a few letters away and there is nothing new on the board to
look at. What a picture says is at least 13:1 against the fill behind it in
every palette, and every border and connector clears 3:1 against the page.

The line under the header afterwards tells you what it made: what it was of,
and what it was drawn in.

## Backgrounds

Place and resize a shape, then press `p` to pin it. It stays behind notes and
connectors, moves with the canvas, and leaves your mouse free to pan or create
notes over it. Normal navigation, mark-all, editing and deletion skip pinned items.

Press `Shift+P` to select backgrounds with Tab, HJKL or the mouse, then `p` to
unpin the selected one. Escape leaves background selection. Pinning supports
undo/redo and is saved with the board. Notes can be pinned as labels too; items
inside a background remain independent.

## Boards

`b` opens the board browser: a shell-like walk through your boards directory.

| Key | Does |
|-----|------|
| `j` `k` | Move the cursor |
| `l` / `enter` | Enter a folder, or open a board |
| `h` / `backspace` | Go up a level |
| `/` | Search every board in the tree, not just this folder |
| `a` | New board here |
| `A` | New folder here |
| `r` | Rename |
| `x` twice | Delete (refuses the open board and folders containing it) |
| `g` / `G` | First / last |
| `esc` | Leave the search, then close the browser |

Search is a subsequence match over the whole path, so `wpa` finds
`work/project-a`. While you are searching, letters go into the query — press
Escape first if you want `a`, `r` or `x`.

The browser opens in the folder of the board you are on, and the board you are
on is marked `·open`.

Deleting a board or a folder moves it to `~/.local/share/omarchyform/trash/`
rather than destroying it, and records where it came from, so `t` and `enter`
put it back exactly where it was. An occupied destination is refused and the
item stays in the trash. Filesystem operations reject traversal and symlinks
inside the boards, backups and trash folders; those folders themselves may be
symlinks. If the trash index cannot be saved, the browser keeps its pending state
and shows `ctrl+s` to retry; keep the application running until that succeeds. Only `x` inside the trash actually destroys
something, and it asks twice.

## Getting things in and out

A board is a file, so it can leave and come back. `ctrl+shift+s` writes a copy
wherever you choose, with its pictures inside it — the board in your library
keeps only their file names, which mean nothing on the machine you send it to, so
a shared board of screenshots used to arrive as a board of holes. `ctrl+o` reads
one back in as a new board rather than overwriting the one you are on, writing
the pictures it carried into your own `images/` under names it picks, so a copy
you were sent can never end up addressing a picture of yours that happens to
share a name.

A copy either carries everything it names or is not written at all. If a picture
is missing from your library, or the pictures come to more than 16 MB, the copy
is refused with the reason and the file you were saving over is untouched.
**Save a copy without its pictures** is the other thing you can ask for, by that
name, and says so when it is done. An export is a picture of one moment: what it
writes is the board as it was when you asked, however much you edit or switch
boards while its pictures are being read.

Coming in, a file over 32 MB is refused by its size before it is read, a picture
over 32 MB or a set of them over 16 MB is refused from the length of the text
rather than by decoding it, and a board that carries a picture this cannot read
is refused whole: nothing is imported, the file you were given is untouched, and
you are told which. Pictures that had already landed from that attempt stay in
`images/` unreferenced, in the same way a picture whose item you deleted does.
A board with no `images` key at all — every board written before this, and every
copy saved without its pictures — imports the same way, as one that carried
nothing: its notes, shapes and connectors arrive, and a picture item arrives as
an empty note, because the name it carries means nothing here. That includes
re-importing your own copy without its pictures on the machine that saved it.
`ctrl+e` renders the board to a PNG for
sharing. `ctrl+v` asks the clipboard for a picture first and drops it on the board at its
own proportions; failing that, it turns the text into a note, however many lines
it is.

`ctrl+c` goes the other way. A picture on its own lands on the clipboard as a
picture, ready to paste into a chat or an editor; anything else goes as its text,
and several items arrive as paragraphs in board order. Backgrounds are left out,
the way they are left out of every other bulk command.

Pictures can also be dragged in from a file manager or a browser's downloads and
land where you let go of them. Several at once arrive staggered rather than in
one stack. What a file claims to be is ignored: the type is read from the
content, the name and the folder are chosen here, and anything that is not a
picture — or is larger than 32 MB — is refused with a reason rather than left on
the board as a broken frame.

`ctrl+n` makes a board and puts you straight into its first note, so a thought
can be captured before it is named; `F2` names it afterwards.

The plugin also ships a desktop entry, so the board can be opened from a
launcher, with a *New board* action for the same instant capture. Its installer
is in the plugin's folder:

```bash
~/.config/omarchy/plugins/thepixelgardener.omarchyform/desktop/install.sh
```

It writes three files, all in your home: the launcher entry,
`~/.local/share/applications/omarchyform.desktop`; the board file type,
`~/.local/share/mime/packages/omarchyform.xml`; and the small command the entry
runs, `~/.local/bin/omarchyform-open` (under `$XDG_DATA_HOME` and
`$XDG_BIN_HOME` when those are set). Then it refreshes the launcher and
file-type caches in that same data directory, when their tools are installed.

It checks all three before writing any, and refuses rather than overwriting
anything it did not put there: a file someone else owns at one of those paths,
or one of its own that you have since edited. Both cases print what was found
and exit non-zero; `--force` replaces the file once you have decided that is
what you want. `--uninstall` removes them under the same rule. Nothing outside
your home is touched, and it never needs `sudo`.

## Saving

There is no save key, though `ctrl+s` works if you want one. Structural
changes — adding, deleting, moving, connecting — are written immediately.
Typing settles for 700ms first, so a sentence is one write rather than forty.
Switching boards or closing flushes whatever is pending. Board switching waits
for writes to finish. A failed backup or write leaves the board open in memory
and shows an error; use `ctrl+s` to retry. A slow save stays in progress until
the disk operation completes; retrying cannot replace its destination. Closing the surface keeps an in-flight
save running in the shell; it does not wait for disk completion.

When a conflict is resolved with **Use disk version**, the latest content and
its revision are read together under the write lock. A failed read or replacement
keeps your local edits and the conflict available for retry. If a save detects a
conflict while switching boards, that switch is cancelled; resolving the conflict
leaves the current board editable so you can switch again.

Which board you had open is remembered in `state.json` and reopened next time.

## Where your board lives

```
~/.local/share/omarchyform/
├── boards/
│   ├── board.json
│   └── work/
│       └── project-a.json
├── trash/
│   ├── index.json
│   └── 20260924-133036-work__sprint.json
├── images/
│   └── paste-1758801036123.png
├── backups/
│   └── v2/
│       ├── board.json.bak
│       └── work/project-a.json.bak
└── state.json
```

Each board is plain JSON, written atomically. One generation back is kept in
`~/.local/share/omarchyform/backups/`, under `v2/`, mirroring the board directory tree — out of the boards tree, which is meant to be browsed, hand-edited
and committed without `.bak` files in the way. Older flattened backups are
left untouched; new saves use the mirrored paths to avoid naming collisions. The backup completes before replacement, and saves
with unchanged contents do not rotate it. Malformed or unsupported board files
open read-only; no edits or saves are allowed over them. Back it up, sync it,
edit it by hand, put it in git — it is your file, and a board that changes while
it is open is noticed rather than overwritten.

Every write to a board goes through one coordinated step: the file is replaced
under a lock, and only if it is still the version the writer last read. The
version it replaces is kept first. So two writers that both read the same board
cannot both believe they are updating it — the second one is told. That applies
to the plugin and to `bin/omarchyform` alike, because both go through the same
helper. Locks live in `~/.local/share/omarchyform/locks/` and never beside your
boards. This needs `flock` (util-linux) on the path, alongside the `bash` and
coreutils the plugin already uses. Older boards are migrated on load: v1 had no ids or
shapes, v2 stored fixed pastel hexes which are mapped onto theme roles. Version 4 adds
background pinning, version 5 pasted pictures; older plugin versions open these
files read-only instead of silently losing that state.

A pasted picture is written to `images/` and the item keeps only its file name,
so a screenshot is not re-encoded into every autosave — and the same picture on
four boards is stored once. A copy saved to share is the exception: it carries
the bytes in an `images` object beside the items, because a file name is not
something another machine can resolve. That key is ignored by anything that does
not know it, so such a copy still opens in an older Omarchyform. Nothing deletes
the files in `images/`: a board in the trash still points at its pictures, and so
does a copy exported last month. An item whose picture has gone says so on the board rather
than drawing an empty frame.

```json
{
  "version": 5,
  "nextId": 4,
  "items": [
    { "id": 1, "kind": "note", "x": 0, "y": 0, "w": 180, "h": 140,
      "tint": "foreground", "text": "hello", "pinned": false },
    { "id": 2, "kind": "ellipse", "x": 300, "y": 0, "w": 160, "h": 110,
      "tint": "accent", "text": "there", "pinned": false },
    { "id": 3, "kind": "image", "x": 0, "y": 200, "w": 360, "h": 203,
      "tint": "foreground", "text": "", "pinned": false,
      "src": "paste-1758801036123.png" }
  ],
  "links": [ { "from": 1, "to": 2 } ]
}
```

Connectors reference item ids rather than positions, so they survive
deletions, reordering and hand-editing. They are directed: `from` and `to`
decide which end carries the arrowhead, and only one runs between any pair.

## It looks like Omarchy, because it asks Omarchy

Nothing about the appearance is invented here. The board takes the theme's
font family and its size tokens, so it follows `omarchy display text size`
like the rest of the desktop. Corners come from `Style.cornerRadius` (square
by default) and borders from `Style.normalBorderWidth`.

Items carry a **theme role** — `foreground`, `accent`, `urgent` or `muted` —
rather than a fixed colour, drawn as a translucent wash plus a hairline of the
same role. How strong the wash and the hairline are is the shell's call too:
`Style.normalFillAlpha`, `Style.selectedFillAlpha` and `Style.normalBorderAlpha`,
the weights its own surfaces use. Switch your theme and the board switches with
it. `c` cycles the role.

The board's panels — the command list, the browser, the shortcut list and the
question asked when a board has two versions — are drawn the way the shell draws
its own menu: a solid card in the menu's colours and font, inside the theme's
border for it (a gradient, where the theme has one), with the board dimmed
behind. Their lists have the menu's rows — a glyph, a name at heading size, and
the keyboard cursor as a soft fill with its label in the accent, which the shell
keeps for that row alone. The shortcut list is in labelled sections, as the
shell's panels are, and the header's controls are its soft-filled buttons.

**Day and night** is not a setting here either. Omarchy themes declare
`mode = "light"` or `mode = "dark"` in their `colors.toml`; the board reads
that and adjusts the weight of its canvas pattern accordingly. A third-party theme
that omits `mode` falls back to the background's Rec. 709 luminance.

### Canvas background

Inside the board, click **Menu → Background**, then choose **Dots**, **Grid**,
**Ruled**, or **Plain**. The current choice is highlighted. You can also press
**Ctrl+P** outside a note and search for **background**, **texture**, or **pattern**.
Dots are the default, and an existing preference for a plain canvas is preserved.

Patterns use the theme's colours and stay attached to the board as you pan and
zoom. The choice applies immediately and is remembered for bar and keyboard
opening. A choice made here takes precedence over the bar's initial canvas
settings. It applies to the
working canvas; PNG exports keep their plain background.

## Layout

| File | Holds |
|------|-------|
| `Omarchyform.qml` | The workspace: settings and state, the library and file exchange, the open boards, and the two surfaces |
| `BoardPane.qml` | One view of a board and the controller its views read: camera, selection, modes and every command |
| `BoardDocument.qml` | One open board: its items and connectors, ids, undo history and the session saving it |
| `Board.qml` | The canvas surface — grid, connectors, keys, cheat sheet |
| `BoardToolbar.qml` | The header: the board's name and save state, the zoom, and the menu |
| `Theme.qml` | Colours, fonts, sizes and weights, all read from the shell's theme with fallbacks |
| `Surface.qml` | The card a panel is drawn on, in the shell's menu colours and the theme's border for them |
| `Node.qml` | One item: note, box, ellipse, diamond or picture. Shapes are `QtQuick.Shapes` geometry, so they stay sharp at any zoom |
| `Commands.qml` | The command list on `:`, `ctrl+p` and `.` |
| `Conflict.qml` | The question asked when a board has two versions |
| `Browser.qml` | The board browser: draws the library |
| `BoardBar.qml` | The bar widget: the board's presence in the shell |
| `Help.qml` | Scrollable keyboard help |
| `ScrollHint.qml` | The mark that says a panel has more below |
| `BoardStore.js` | Pure logic: parsing, marshalling, geometry. No QML |
| `BoardSession.qml` | Loading, autosave state, and board-switch coordination |
| `BoardLibrary.qml` | The boards folder: browsing, naming, folders and the trash, with no controller of its own |
| `BoardPersistence.qml` | Serialized backup and atomic write, with completion/failure signals |
| `BoardExchange.qml` | Saving a copy to share and opening one, apart from the open board's saves |
| `BoardImage.qml` | The read-only scene a PNG export is drawn from: no grid, grips or selection |
| `BoardFiles.sh` | Confined filesystem operations and exact-path moves |
| `bin/omarchyform` | The board, headless: build, read and change one with no display |
| `bin/store.js` | Loading `BoardStore.js` outside QML, shared by the CLI and the tests |

## From the command line

`bin/omarchyform` builds and changes boards with no window and no display. The
board's logic is plain JavaScript that already runs outside QML — it is what
the test suite exercises — so the same code that draws a board can build one
headlessly. Every verb answers with JSON on stdout and exits 0 or 1. It runs on
Node.js, which the board itself never needs.

```bash
bin/omarchyform new ideas.json --note "First thought" --note "Second"
bin/omarchyform inspect ideas.json
echo '[{"op":"add","args":["ellipse",520,0,200,140,"the question","accent"]},
       {"op":"link","args":[1,3]}]' | bin/omarchyform apply ideas.json -
bin/omarchyform validate ideas.json
bin/omarchyform ops          # what apply accepts, the kinds, the theme roles
```

Boards written into `~/.local/share/omarchyform/boards/` appear in the browser
on `b`. Writing the board that is open is fine too: the board watches its file,
so a board the CLI changes appears in front of you.

If you have unsaved changes on screen as well, both versions are kept and
neither is guessed at. Autosaving stops, the header says `Changed on disk`, and
`ctrl+s` puts the three choices on screen:

| | |
|-|-|
| Keep the version from disk | what is on screen is lost |
| Save my changes as a copy | both versions survive, the copy under a name of its own |
| Replace the version on disk | the one it replaces goes to backups |

Nothing else resolves it. Leaving the board, closing it, renaming it and the
autosave timer all leave both versions where they are, and switching boards
waits until you have chosen. Until then your edits live only on screen, so the
choice is worth making rather than leaving.

The CLI is told the same way. An `apply` whose board changed between being read
and being written answers `{"ok": false, "error": "… changed since it was read"}`
and exits 1, leaving the other writer's board alone; `--force` is the explicit
overwrite, and keeps what it replaced.

It cannot draw: a picture of a board needs the running shell, so `ctrl+e`
on an open board exports a PNG and nothing here does.

`skills/omarchyform/SKILL.md` ships alongside it, so a coding agent asked to
sketch something out as a board can do it without being told any of this, and
[`docs/for-agents.md`](docs/for-agents.md) is the long version — this same
program explained to something that drives it through files and will never see
the screen. Most of it is the part a command list cannot teach: how big a note
is, how far apart two of them have to be before they read as two, how much text
fits before it scrolls, which shape means what, and how little of a board to
tint. A board built without that reads as generated whatever is written on it.

## Tests

The pure logic lives in plain JavaScript so it can be tested without Qt, and
the suite loads the very file the plugin loads — there is no copy to drift.

```bash
./tests/run     # everything available on this machine, skipping what is not installed
npm test        # pure logic and controller regression tests, no dependencies
npm run test:security # portable security/privacy screen and boundary regressions
npm run test:security:full # also run Quickshell and Qt tests
npm run mutate  # mutation testing
npm run bench   # board marshalling cost at size
npm run bench:scene # what a board costs to draw, at size; needs a compositor
npm run test:qml # headless persistence tests; requires installed Quickshell
npm run test:paste # live canvas image paste test; uses an isolated clipboard stub and board library
npm run test:ui  # Qt Quick pointer, theme, and layout tests
npm run shots -- --hold # leave an isolated board up for docs/pointer-checks.md
npm run test:hold # that held board starts, survives a mode switch, and ends
npm run test:omarchy -- --keep # live desktop smoke test, isolated board data
npm run shots   # photograph every state, for judging by eye
npm run preview # remake the picture at the top of this README
```

`npm run bench:scene` measures the other half of what a board costs. `npm run
bench` times marshalling, which is arithmetic over an array and has never been
the problem; this drives the real scene — delegates, bindings and both canvases
— through panning, zooming, dragging, marking and finding, and reports
milliseconds per frame at each board size. A phase at the refresh interval is
vsync-bound and has room to spare; above it, the board drops frames while you
use it. Like `shots` it asserts nothing and is not in `tests/run`: it needs a
compositor, and frame times on a busy desktop are noisy enough that a single
run can be misleading. Run it before and after a change and compare the
columns.

```bash
npm run bench:scene            # 100, 500, 1000 and 3000 items
npm run bench:scene -- 3000    # one size
npm run bench:scene -- --record  # and write docs/performance.md
```

It prints what it measured on before what it measured — Qt, Quickshell, the
compositor, the refresh rate, the GPU, and the size of the window it was given,
since a window tiled across the whole screen draws more of the board than one
beside an editor — because a frame time without the
machine under it is not a number anyone can check, and the same board is
vsync-bound at 60Hz and dropping frames at 144. `--record` writes that and the
table to [docs/performance.md](docs/performance.md), which is where the figures
quoted in the changelog come from.

`npm run shots` puts the real plugin through every state worth judging by eye —
empty, a cursor beside a mark, typing, backgrounds, finding, arranging, the
command list open and narrowed, what can be done with a selection, the question
asked when two versions of a board exist, help, the browser, naming a board, a
browser with more boards than fit, each of the three things a connector gesture
can be about to do, a failed save, a close-up at working zoom, and the board
at the top of this README — and saves a picture of each into
`~/.cache/omarchyform/shots/`. It asserts nothing: it exists because whether a
tinted item reads as selected, or a hint still fits on one line, is not
something a test can answer, and reading the source instead has been wrong
before. Add a theme name to see another theme, or `--light --dark` for one of
each:

```bash
npm run shots -- --light --dark
```

It runs against the live compositor in an isolated `HOME`, so the installed
copy of the plugin and the running shell are both left alone.

A theme named here is photographed from its own folder, which holds its colours
but not the `shell.toml` Omarchy generates when a theme is applied — so the
shell's surface tokens, such as the menu border a gradient theme gives its
panels, fall back to their defaults. With no name, it is the theme you are using,
as generated, and those are exactly what it shows.

`--hold` takes the pictures and then leaves the board on screen instead of
quitting, on the isolated boards that run built, carrying one of everything a
pointer can be pressed on — a background, notes, a shape, a picture and a
connector. It is there for `docs/pointer-checks.md`: a pointer cannot be
synthesised into a running compositor from here, so whether the middle button
reaches the fullscreen overlay and the windowed toplevel is checked by hand, and
it must not be checked on the installed plugin or on real boards. Close it with
`esc` `esc`, or `Ctrl-C` the terminal: either way the board is dismissed, what
it was writing is finished, and the scratch tree that run built is removed —
that one, by name, so a second held run in another terminal keeps its boards. A
board that cannot be written when it closes says so and exits non-zero rather
than hanging. `npm run test:hold` drives all four of those without a hand on
the keyboard.

```bash
npm run shots -- --hold
```

The last of those states is the picture at the top of this file, and
`npm run preview` is how it gets there: it takes the shots, crops the top of
the window to 16:9 and writes `preview.png`. The board in it is a saved board
file, framed by `tests/qml/shot.qml` rather than arranged by hand, so the next
one can be taken the same way — the one before this was arranged by hand and
went on showing a header and a hint row that had both since moved. The file is
kept outside the repo so it never ships: by default
`../omarchyform-examples/From spark to shipped.omarchyform.json`, or wherever
`OMARCHYFORM_SHOWCASE` points.

Take it where the window gets the whole width of the screen, on a workspace of
its own. Tiled beside another window it is tall and narrow, a 16:9 crop of its
top is half the board, and the line under the header wraps.

`npm run mutate` breaks `BoardStore.js` on purpose, one edit at a time, and
checks the suite notices. The command reports its current score and survivors;
it is a diagnostic, not a CI failure threshold.

Review survivors when changing the pure logic; a passing mutation command is
not a substitute for the runtime and filesystem regression tests.

A contract check reads the names the views and the session reach for on the
controller and fails if any of them is missing — including from the stubs the
QML session and exchange tests use in the controller's place. QML resolves those names at
runtime, so a missing one is a TypeError in a suite CI cannot run, which is
how two of them reached `main` behind green checks.

Controller tests evaluate the actual QML JavaScript functions with delayed I/O
completion to cover damaged files, queued edits, board switching, and retry.
The separate `test:qml` suite runs the real persistence and session components
in isolated headless Quickshell instances with temporary files. It checks backup
contents, write ordering, failure handling, retry, queued edits, and switching
between fresh, saved, and damaged boards. It does not interact with the running
desktop shell. CI runs the Node and Qt Quick tests. Run `test:qml` and
`test:omarchy` on an Omarchy machine before release. The live test opens test
surfaces and targets keyboard events at its own process; it preserves your
installed plugin, boards, and theme.

See [the compatibility review](docs/omarchy-compatibility.md) for the tested
versions, first-party references, results, and remaining limits.

## Speed

`npm run bench` prints what a board costs to serialise and to load, at size.
Loading used to be superlinear — every connector scanned the whole item list to
resolve its two ends — so a 3000-item board took about 19ms to load and a
1000-item one about 3.6ms. Resolving the ends through a single index instead
makes it linear: roughly 6ms and 2ms.

Saving costs about 50ms, and costs it whatever the board's size: a 15KB board
and a 480KB one land within a millisecond of each other, because almost none of
it is the writing. One `bash` does the whole commit — it stages the board it was
handed on standard input, takes the lock, checks the file is still the revision
it last read, keeps the version it is about to replace, and renames the new one
into place. Starting that process accounts for about 12ms of the total; the rest
is the copy and the renames reaching disk. Measured on btrfs under `$HOME`,
twenty saves at each size after five warm-up runs.

Doing the copy in-process would remove part of that, but the backup is what
guarantees the previous version is safely on disk before the board is
overwritten, the lock is what stops two writers from both believing they are
updating the same board, and the obvious rewrites broke the first of those. Both
are left alone deliberately, behind the autosave delay, rather than traded for
speed.

## Notes on the platform

Omarchy is pre-release and the shell's `qs.Commons` singletons are
internals, not a versioned API. Every read of them here goes through a guard
with a hardcoded fallback, so a rename upstream costs a wrong colour rather
than a board that will not open. An import disappearing entirely is still
fatal — QML has no optional imports.

The overlay is built through `Variants` so its surface is constructed with its
screen already set, and it opens on whichever output Hyprland has focused.
Assigning `screen` to a window that already exists leaves it unmapped.

Pasting onto the canvas accepts up to 1 MiB of text or 32 MiB per picture.
An oversized paste is rejected in full. Picture formats are checked from their
contents, including pictures supplied by the clipboard.

## Dependencies

One external program of its own: **wl-clipboard**, for `wl-paste` and
`wl-copy`. Pasting (`ctrl+v`) and copying out (`super+c`) need it — without it,
a paste reports an empty clipboard and a copy says the clipboard could not be
reached — and nothing else does, so a board without it still opens, edits,
saves, imports, exports and renders a PNG. Omarchy ships it, so on a stock
install there is nothing to do.

Saving also uses **flock** (util-linux) — the lock that stops two writers from
both believing they are updating the same board — and pictures are recognised
by their content with **file**, alongside the `bash` and coreutils the
filesystem helper has always used. All four are part of a base Arch install;
`flock` and `file` are the ones added since 0.3.0.

The command line, `bin/omarchyform`, runs on **Node.js**, and so do the test
suites. The board itself does not: nothing the plugin runs starts Node, so it
is needed only to use the command line or to work on the plugin.

Everything else is already in the shell: Qt 6 Quick, and the Quickshell process
and file primitives. No network access, no external services, and no elevated
privileges — saving uses short-lived local filesystem commands, and the plugin
never calls `sudo`, `pkexec`, or a package manager.

Licences: this plugin is MIT (see `LICENSE`). `wl-clipboard` is GPL-2.0-or-later
and is invoked as a separate process, not linked or redistributed here.

## Development

```bash
git clone https://github.com/thepixelgardener-create/omarchyform.git
cp -r omarchyform ~/.config/omarchy/plugins/thepixelgardener.omarchyform
omarchy-shell shell rescanPlugins
omarchy plugin enable thepixelgardener.omarchyform
```

Validate before publishing:

```bash
omarchy plugin validate .
qml_imports=$(mktemp -d)
ln -s "$OMARCHY_PATH/shell" "$qml_imports/qs"
/usr/lib/qt6/bin/qmllint -I "$qml_imports" ./*.qml
rm -rf "$qml_imports"
```

The temporary import tree resolves Omarchy's `qs.Commons` namespace. The
installed QML metadata still produces warnings about `PanelWindow`,
`QProcess::ExitStatus`, the dynamic Style font object and the members of the
shell's plugin API. qmllint also reports unqualified access inside the header
menu's delegate and the export scene, so it exits non-zero. The live test
checks that those types and properties work in the actual runtime. CI fails on
one category only: a property overriding a final one, which is what makes a
surface fail to load.

`keepLoaded: true` keeps this overlay mounted between summons. Save with
`ctrl+s` and wait for the saving indicator to clear before a rescan or a shell
restart; a forced unload can interrupt an asynchronous save.

**After changing QML, restart the shell. Do not trust a rescan to replace it.**

```bash
omarchy restart shell
```

`omarchy-shell shell rescanPlugins` is documented as unloading and recreating
panels and overlays, including kept ones. On Omarchy `4.0.0.r2158.gd174d4a-1`
that did not hold for this plugin, twice, in two different ways:

- **A version that would not compile stayed broken.** After a
  `Cannot override FINAL property` error made `Board.qml` — and so the whole
  overlay — unavailable, the fix on disk was ignored through a reinstall and two
  rescans. The bar icon clicked and did nothing, because there was nothing to
  toggle. Only a restart cleared it.
- **A version that compiled fine was not replaced.** `omarchy plugin update`
  reported success and the new files were on disk, but the running board still
  drew the previous layout until the shell was restarted.

`keepLoaded: true` is the likely reason the second case happens — a kept overlay
that is never unloaded cannot pick up new source — but that is a suspicion from
two observations, not something verified against the shell's own code. Either
way, the safe habit is a restart.

Three symptoms say the shell is not running what is on disk: the board renders a
layout you have already changed; `omarchy plugin list` reports the plugin
`enabled` while the shell never instantiates it; and
`~/.local/share/omarchyform/images/` is missing, because the data directories
are created the moment the plugin's root loads. Compile errors themselves are in
the shell's log, under `/run/user/$UID/quickshell/by-id/*/log.qslog`.

Watch that log rather than trusting a silent rescan. Two checks catch this class
of error before the shell ever sees it —
`./tests/run` fails on any member that shadows a final one, and
`npm run test:omarchy -- --live` loads the whole plugin the way the shell does.
The unit suites do not: `npm run test:ui` mounts `Node.qml` rather than the
surfaces, and the JavaScript suites never load QML at all, which is exactly why
this reached a desktop in the first place.

## Not there yet

Freehand drawing is outside the current scope.

## Tested against

| | |
|---|---|
| Omarchy | `omarchy-dev 4.0.0.r6720.g8e02fc8-1`, Quattro shell |
| Qt | 6.11.2 |
| Quickshell | 0.3.1 |
| Compositor | Hyprland `0.56.2`, Wayland |
| Displays attached | 1920×1080 at scale 1.6, single output |
| Clipboard | `wl-clipboard` 1:2.3.0 |

The 0.4.6 automated and live smoke checks passed on this configuration on
2026-10-05. 0.4.5 was tested on `omarchy-dev 4.0.0.r6713.ga85e29a-1` with a
1920×1080 output at scale 1.6 and a 3840×2160 output at scale 2, and earlier
releases on Omarchy `4.0.0.r2158.gd174d4a-1` with a single 1920×1080 output at
scale 1.6. Omarchy 4's plugin contract is still moving; these results do not
establish compatibility with every version.

The live checks do not exercise moving between monitors or every mixed-scale
placement. An unscaled display and other compositors remain untested. Portrait
and small-window layout is covered by the Qt layout suite rather than by hand
on hardware. Overlay placement on those configurations needs further checking.

## Support

Planned improvements and features are tracked in the [roadmap](docs/roadmap.md).

Bugs and questions belong in
[GitHub issues](https://github.com/thepixelgardener-create/omarchyform/issues).
Security reports go through the private route in [SECURITY.md](SECURITY.md)
instead.

## License

MIT. `wl-clipboard`, the one external program this calls, is
GPL-2.0-or-later and is not redistributed here.
