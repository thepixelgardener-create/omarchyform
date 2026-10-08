# Omarchyform, for the thing reading this

The README is the manual for the person at the keyboard. This is the same
program explained to something that will drive it through files and a command
line, and will not see the screen.

Read it before building a board. Most of what makes a generated board bad is
not a wrong call — every call here is easy — it is not knowing how big a note
is, how far apart two of them have to be, or that a connector between a pair
already joined turns it round instead of adding a second one.

The short version, if you read nothing else:

- Build with `bin/omarchyform`. Never hand-write a board file.
- Items are placed by their **top-left corner**. `y` increases **downwards**.
- `add` makes a **220 × 160** note unless told otherwise. (A note made in the
  board itself starts at 180 × 140, centred where it was asked for.) Leave
  **60** between neighbours; step **280** across and **220** down and they will
  not touch.
- Keep a note under about **six short lines**. Past that it scrolls and shows a
  tab in the corner, which reads as an accident.
- Tint the two or three items that carry the argument. Tinting everything is
  the same as tinting nothing.
- Prefer a board that is not open in the shell; see §8.

---

## 1. What the program is

Omarchyform is an infinite canvas that runs inside the Omarchy shell: notes,
shapes and connectors on a board you pan and zoom. A board is one JSON file.

Its logic lives in `BoardStore.js` — plain JavaScript with one line of QML on
the front — which is why `bin/omarchyform` can read and write boards with no
Qt, no compositor and no display. **The command line and the running app use
the same code to load, repair and save a board.** A board this writes is a
board the shell opens, and the test suite checks exactly that.

### Where things live

```
~/.local/share/omarchyform/
  boards/     the boards. A file here appears in the browser under its name
              without the .json. Folders nest.
  images/     pictures items point at, by plain file name
  backups/    a copy of each board from before the last write
  locks/      one per board, so two writers cannot interleave
  trash/      deleted boards, until destroyed
  state.json  which board was last open, window mode, autosave interval
```

A board anywhere else is still a board — the person opens it with `ctrl+o`, or
a file manager hands it over if it is named `*.omarchyform.json`. **Build
somewhere harmless first** if you are not certain, then move it in.

### What it cannot do

`bin/omarchyform` cannot draw. A picture of a board needs the scene, and the
scene needs the running shell. If someone wants a PNG, tell them: open the
board and press `ctrl+e`. See §7.

It also does not know which board is open right now, and does not touch the
trash or the pictures beside a board. It does keep backups: every write saves
the version it replaced, in `backups/` for a board in the library and as
`<file>.bak` beside one anywhere else.

---

## 2. What a board is made of

```json
{
  "kind": "omarchyform.board",
  "version": 5,
  "nextId": 3,
  "items": [
    { "id": 1, "kind": "note", "x": 0, "y": 0, "w": 220, "h": 160,
      "tint": "foreground", "text": "First", "pinned": false, "src": "" }
  ],
  "links": [ { "from": 1, "to": 2 } ]
}
```

**Items.** `id` is unique within the board and is what connectors point at.
`x`/`y` are the **top-left corner** in board coordinates, `y` down. `w`/`h` are
the size, never below **60**. Paint order is array order: later items are drawn
over earlier ones.

**`kind`** is one of `note`, `rect`, `ellipse`, `diamond`, or `image`. A note is
a rectangle with a rule across the top and its text aligned to the top left;
the others centre their text. An `image` carries a file name in `src` and is
not something to create from here — there is no op for it, because the picture
has to be in the images folder first.

**`tint`** is a theme role — `foreground`, `accent`, `urgent`, `muted` — and
**not a colour**. A board follows whatever theme the desktop is wearing, so a
board that hard-codes colours fights it. There is no way to set a hex colour,
deliberately.

**`pinned`** makes an item a background: it is drawn behind everything, and
normal navigation, mark-all, editing and deletion skip it. Use it for the panel
a cluster sits on, or a label for a region. Pin the shape *after* the items
that go on top of it exist, and give it a `muted` tint.

**`texture`** is optional on notes and shapes: `plain` (default), `ruled`,
`grid`, `dots`, or `hatch`. Textured boards use format 7 even without history.
Images stay plain. Unknown texture values load as plain. `setTexture` sets one.

**Links.** Directed, drawn as an arrow from `from` to `to`. **Only one runs
between any pair.** A connector pointing at an item that is not there is
dropped on load rather than breaking the board.

Note that the command line and the keyboard differ here, deliberately:

| | `link from to` | pressing `x` twice on a pair |
|---|---|---|
| nothing between them | draws one | draws one |
| one already, same way | leaves it, answers `already` | **removes it** |
| one already, other way | turns it round | turns it round |

So `link` is safe to repeat and `x` is a toggle. Use `unlink` to remove one
from here; it takes the pair in either order.

**`nextId`** is the next id to hand out. `apply` maintains it; do not set it.

**`history`**, last in the file, is every edit the board remembers, so its
timeline can play it back. A board with history or textures is `"version": 7`;
one with neither is still 5. Version 6 histories still load. `apply` adds one record per run, labelled "Command line",
however many operations it carries, and keeps the newest 10,000. Never edit
the history by hand. If the board itself was edited by hand, the next `apply`
records the difference as one record, "Changed outside Omarchyform". A history
that cannot be played back makes `apply` refuse and leave the file as it was;
`validate` reports it under `history` and `warnings`, and opening the board in
Omarchyform keeps it aside and starts a new one. A copy made to share never
carries a history.

### What a board tolerates

Board files are hand-editable and get synced between machines, so everything
coming in is coerced to something the canvas can draw: a string where a number
belongs, a tint this version has never heard of, a size below the minimum, a
connector to nothing. `validate` prints what loading had to repair.

One thing is not repaired: a note longer than 1048576 characters. The board
opens such a file read-only and empty rather than hold the shell up laying it
out, and refuses to import one. `add` and `setText` refuse text that long,
`validate` lists one under `warnings`, and `setText` is how to shorten it.

A board reported as **newer than this understands** is not broken. A later
Omarchyform wrote it, and it opens read-only rather than losing what it cannot
represent. Do not offer to repair or rewrite it; say where it came from.

---

## 3. Driving it

```
omarchyform new <file> [--note TEXT]... [--force]
omarchyform inspect <file> [--full]
omarchyform apply <file> [ops.json|-] [--out FILE] [--dry-run]
omarchyform validate <file>
omarchyform ops
```

Every verb answers with JSON on stdout and exits 0 or 1. **Run `omarchyform
ops` rather than trusting any list of operations written down elsewhere,
including this one** — it prints the table `apply` dispatches through, so the
two cannot drift.

`new` writes a board with the given notes along a row and refuses to write over
an existing file; `--force` means it.

`apply` takes a list of operations as JSON, on stdin or in a file:

```bash
echo '[{"op":"add","args":["note",0,0,220,160,"The question","accent"]},
       {"op":"add","args":["note",280,0,220,160,"One answer"]},
       {"op":"link","args":[1,2]}]' | omarchyform apply ideas.json -
```

The answer names what each operation did, **including the id of anything
added**, which is what the operations after it need. `--dry-run` answers
without writing. `--out` writes elsewhere and leaves the original.

Ids are handed out in order from `nextId`, so on a board you just created you
can predict them — but read them out of the answer rather than assuming, and
never assume on a board you did not create.

---

## 4. Making a board that reads well

This is the part that decides whether the result looks made or generated.

### Size and spacing

A default note is **220 × 160**. The minimum is 60 in each direction.

Leave about **60 between neighbours** — closer and two notes read as one block.
In practice: step **280** across and **220** down, and nothing touches.

```
x:  0     280   560   840
y:  0     a row of four
    220   the next row
```

Connectors are drawn between the *edges* of items, so items that overlap leave
no room for an arrow and the board stops being readable. Spacing is not
decoration.

### How much text

Keep a note to about **six short lines**, or roughly 150 characters at the
default size. Past that the text scrolls inside the item and a small tab
appears in the bottom-left corner — correct behaviour, but on a generated board
it reads as something that went wrong.

If you have more to say, that is two items and a connector, not a bigger note.
A note that has to be 400 tall to fit its text is a paragraph someone pasted
into a canvas.

### Markup in a note

A note is plain text carrying a small syntax, so write it into `text` like any
other characters:

```
# A heading          bigger and heavier — one per note, at the top
*bold*               emphasis
_italic_             quieter emphasis
`a key`              drawn in the accent, the way keys are drawn everywhere here
[accent]span[/]      a span in one of the four roles
```

Roles, not colours — `foreground`, `accent`, `urgent`, `muted` — the same four
an item's `tint` uses, so text follows the theme like everything else.

**Give every note a heading.** It is the single biggest difference between a
board that reads and a board that is twenty grey rectangles, and it costs two
characters. Then keep the budget below as it was: emphasis inside the body is
worth one or two words a note, not a sentence.

Everything you write is escaped before the syntax is applied, so a note is safe
to fill with anything — but that also means you cannot emit HTML and have it
render. `<b>x</b>` in a note's text draws those characters.

### Shapes

Use them for what they are, not for variety:

| Shape | For |
|---|---|
| `note` | something said — text, top-aligned, the default |
| `rect` | a thing, a component, a step |
| `ellipse` | a start or an end |
| `diamond` | a decision, a branch |

A board where every item is a different shape for its own sake is harder to
read than one where they are all notes.

### Tint

Four roles, and the discipline is to use few:

- `foreground` — the default. Most of the board should be this.
- `accent` — the thing being argued for, the answer, the path taken.
- `urgent` — the risk, the blocker, the thing being warned about.
- `muted` — context, background panels, the thing that is only there for
  reference.

Two or three tinted items on a board of a dozen. Tinting everything is the same
as tinting nothing, and it is the most common way a generated board looks
wrong.

### Direction

Connectors carry meaning by pointing. Draw them the way the thing flows —
cause to effect, question to answer, step to next step — and keep a board
consistent about it. If your arrows point in every direction, the reader has to
work out the rule for each one.

### Shape of the whole

Boards read best as a **left-to-right flow** or a **centre with things around
it**. Pick one before placing anything.

- **Flow**: a row per stage, `y` stepping down for detail under each stage.
- **Hub**: the subject in the middle, related items in a ring at 280–400 out,
  connectors from the middle.
- **Columns**: one column per category, headed by a `muted` pinned rectangle
  behind each with the category name.

Twelve to twenty items is a board someone takes in. Past about forty it needs
backgrounds grouping it, and past a hundred it wants to be several boards.

### A worked example

Notes in, board out — the shape most requests take:

```bash
board=~/.local/share/omarchyform/boards/review.json
omarchyform new "$board"
cat <<'OPS' | omarchyform apply "$board" -
[{"op":"add","args":["ellipse",0,220,200,120,"Notes from the review","muted"]},
 {"op":"add","args":["note",280,0,220,160,"Status line had two owners","urgent"]},
 {"op":"add","args":["note",280,220,220,160,"Held runs never ended"]},
 {"op":"add","args":["note",280,440,220,160,"Pointer matrix still unrun","urgent"]},
 {"op":"add","args":["rect",560,220,220,160,"One decision in BoardStore","accent"]},
 {"op":"link","args":[1,2]},{"op":"link","args":[1,3]},{"op":"link","args":[1,4]},
 {"op":"link","args":[2,5]}]
OPS
omarchyform inspect "$board"
```

A hub on the left, three findings in a column, the fix to the right of the one
it fixes. Two `urgent`, one `accent`, the rest plain.

---

## 5. Changing a board that already exists

`inspect` first — always. It answers with the counts, the bounds, a tally of
kinds, and every item's id, kind and text. `--full` adds geometry and the
connectors, which is most of the bytes and rarely what the question was.

`bounds` is what tells you where there is room. Adding at `maxX + 280` puts new
items beside what is there instead of on top of it.

Read the text back to the person in their words, not as JSON.

---

## 6. Checking your work

Three things, in order, before you say you are done:

```bash
omarchyform validate board.json     # does it load, and did loading repair anything
omarchyform inspect board.json      # is it the board you meant
```

`validate` reporting repairs means the file and what would be drawn differ —
usually a connector to an item you removed, or a size below the minimum.

Then look at the geometry in `inspect --full` and ask: does any pair of items
overlap? Is anything further than about 400 from its nearest neighbour for no
reason? Is more than a third of the board tinted? Those three questions catch
most of it.

You cannot see the board. Say so rather than claiming it looks good.

---

## 7. Pictures

Exporting is the shell's job, not this one's. Tell the person:

- `ctrl+e` writes a PNG of the board, with no header, grid or selection rings.
- **Marking items first** (`space` on each, or `a` for everything) gives a
  picture of just those, framed around them. Backgrounds come along as scenery.
- The command list (`:`) has the same export **on white**, **on black** and
  **in black and white** — type `:` then `white` or `print`. A board is drawn
  in the desktop's theme, which is usually dark, and a dark picture is the
  wrong thing to put in a document.

---

## 8. What not to do

- **Do not hand-write or patch a board file.** Use `apply`. The loader repairs
  what it must, and a file you edited by hand is a file whose repairs you did
  not see.
- **Do not change a board that is open in the shell without saying so.**
  Nothing is lost: the board reloads with your change, or, if the person has
  unsaved edits, stops saving and asks them which version to keep. But that
  question interrupts them. Ask which board is open, or work on a new one.
- **Do not assume `link` behaves like pressing `x`.** From here it is
  idempotent and answers `already`; at the keyboard the second press removes
  the connector. `unlink` is how you remove one from here.
- **Do not set `nextId`, or reuse an id you saw in a file.** `apply` hands out
  ids; take them from its answer.
- **Do not put hex colours anywhere.** Tints are roles, and that is what makes
  a board follow the theme.
- **Do not fill a board to make it look substantial.** Twelve items that say
  something beat forty that repeat each other, and the person can see the
  difference immediately even if you cannot.
