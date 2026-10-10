# Using the board

[Back to the README](../README.md) · [Install](install.md) · [Boards on disk and the command line](files.md) · [Development](development.md)

Press `?` or `F1` on the board for the key list, or `:` to run any command by
name. This page is the long version.

## Fullscreen or windowed

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

Pasting into any of them, or into a note you are typing in, reads at most
1 MiB from the clipboard, the same limit as pasting onto the board. Anything
longer, or longer than the field takes, is refused whole with a message rather
than cut short. A one-line field gets spaces where the pasted text had line
breaks, and the middle button does not paste the primary selection.

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
| `v` / `V` | Split side by side / stacked; the same key again goes back to one pane |
| `o` | Move to the other pane |
| `t` | Timeline: step back through what this board was; `esc` back to now |
| `T` | An earlier version beside the board as it is now |
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

## Item textures and command groups

Notes and shapes start with a plain background. Select one or mark a group,
press `.` (or right-click), and choose **Item texture…**: **Plain**, **Ruled**,
**Grid**, **Dots**, or **Hatch**. Pictures keep their image. Textures follow the
canvas palette and are preserved by undo, duplication, saving, history, and PNG
export. The canvas pattern is a separate setting.

Related commands now open groups: item textures, alignment, layers, canvas
appearance, PNG exports, text colours, and conflict choices. Search still finds
individual commands directly. Inside a group, clear the search and press
Backspace to return to all commands; Escape closes the command list.

## Connectors

Select one item, press `x`, click the other item or move to it with `tab` or
`h` `j` `k` `l`, and press `x` again. A dashed line follows the selection while
you choose, and the line under the header says what the second `x` will do
before you press it.

Clicking a target keeps the source while you choose. Dragging and editing are
paused during this gesture. Connections touching the selected item use the
accent colour, with clearer arrowheads and a small gap at item borders.

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
| `x` twice | Delete (refuses a board open in either pane, and folders containing one) |
| `g` / `G` | First / last |
| `esc` | Leave the search, then close the browser |

Search is a subsequence match over the whole path, so `wpa` finds
`work/project-a`. While you are searching, letters go into the query — press
Escape first if you want `a`, `r` or `x`.

The browser opens in the folder of the board you are on, and the board you are
on is marked `·open`.

### Two at once

`v` splits the board side by side and `V` stacks it. The new pane starts as a
second view of the same board, with its own camera, selection and modes, and
the keyboard goes there; `b` in it opens another board in that pane alone.
Both panes on one board share everything on it — an edit, an undo or a
delete in one shows in the other, which keeps its cursor on the item it was
on. `o` moves to the other pane, and so does a click; the pane the keys go to
has the accent round its edge. Leaving a pane ends whatever was half done
there, typing included.

Pressing the layout's key again goes back to one pane, keeping the one you are
in. A board only that pane was showing is saved first, and a board with two
versions or a failed save keeps its pane open until you have dealt with it.
The layout and both boards are remembered for next time.

Drag the line between the panes to resize them, and double-click it — or run
**Even out the split** from the command list — to put it back in the middle.
Neither pane goes below 320 pixels. In a window too small for two, the pane
you are in has all of it and the line under its header offers `o` for the
other; the split comes back when the room does.

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

External drag-and-drop is disabled. Qt reads a drag source's payload before
application size checks can run, and a source that never stops sending can
exhaust the shared shell's memory. Copy an image to the clipboard and use
`ctrl+v` instead; that path reads through the bounded helper. File-manager
"copy file" operations may offer file URLs rather than image bytes; use an
image viewer's **Copy image** command in that case.

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

## History

`t` opens the timeline for the pane you are in. `h` and `l` step back and
forward through what the board was, `H` and `L` jump to where the history
starts and to the latest step, `space` plays it forward a step a second, and
`1` to `4` play at half, normal, double and four times the speed. `esc` comes
back to the board as it is, and again closes the timeline. The strip along the
bottom says which step is on screen, what it was and when; click or drag along
it to scrub. An earlier version is only to look at: nothing edits, pastes into
or exports it, and the header says so. `T` puts an earlier version beside the
board as it is, in two panes, so you can see what changed.

A board remembers its edits, in order, so a timeline can play it back: each
command, each drag, each pause in typing and each undo is one step. The
history is kept in the board's own file, after the board, and saved with it
under the same lock and backup. It keeps the newest 10,000 steps; past that the
oldest go, a tenth at a time, and the line says so the first time. Holding a
movement or resize key groups repeats until release, focus loss or another
command. Typing is grouped by pauses, with a five-second maximum chunk.
An accepted drag or resize is one step; canceling restores its starting state.

When another process extends the same history, an open timeline keeps its
position and playback endpoint. If its oldest steps have been trimmed, it moves
to the oldest retained step. Replacing the history closes the old timeline.

Text you delete from a note stays in that history. **Forget this board's
history**, in the command list, asks to be run twice and then starts again from
the board as it is. A copy saved to share never includes it, and a board
imported from one starts its own.

A board with history or item textures is format version 7. Older versions open
it read-only to avoid losing features. A board without history and with only
Plain item backgrounds, including a plain copy made to share, is version 5.
Existing version 6 histories continue to load. If a board
was edited by something that does not keep history — a text editor, say — the
difference is recorded as one step, "Changed outside Omarchyform". A history
that cannot be read is kept beside the board's backups, and a new one starts.
The board is read in front of its history and the history is checked on a
thread of its own, so a long one does not hold the shell up when the board
opens.

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

**Theme**, **Lighter**, and **Darker** follow the desktop’s light or dark mode.
Omarchy themes declare `mode` in `colors.toml`; a theme without it falls back
to its background luminance. **Paper** and **Ink** use their own matching
foreground and pattern colours.

### Canvas background

Inside the board, click **Menu → Background** to open the canvas group. Choose
a pattern (**Dots**, **Grid**, **Ruled**, **Plain**) or a colour (**Theme**,
**Lighter**, **Darker**, **Paper**, **Ink**). The current pattern is highlighted.
You can also press
**Ctrl+P** outside a note and search for **background**, **texture**, or **pattern**.
Dots and Theme are the defaults. Paper and Ink also adjust text and item
colours to keep them readable. An existing preference for a plain canvas is preserved.

Patterns use the theme's colours and stay attached to the board as you pan and
zoom. The choice applies immediately and is remembered for bar and keyboard
opening. A choice made here takes precedence over the bar's initial canvas
settings. It applies to the working canvas in both panes; PNG exports follow the chosen canvas colour but
omit its pattern. Item textures are included in exports.
