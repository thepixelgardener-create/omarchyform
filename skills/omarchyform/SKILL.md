---
name: omarchyform
description: >
  Building, reading and changing Omarchyform boards from the command line, with
  no window and no display — `omarchyform new`, `inspect`, `apply`, `validate`,
  `ops`. Use when asked to make a board, a canvas, a mind map or a diagram of
  notes on this machine, to add notes or connectors to an existing board, to
  read what is on one, or to check a board file that looks wrong. Triggers:
  omarchyform, make me a board, sketch this out as a board, mind map, add a
  note to my board, what is on this board, connect these ideas, board file,
  .json board, check this board.
  NOT for changing the plugin itself — that is an ordinary QML project with its
  own notes beside the source.
---

# Driving Omarchyform from the command line

Omarchyform is an infinite canvas that lives in the Omarchy shell. Its board
logic is plain JavaScript, so `bin/omarchyform` can build and change boards
without Qt, a compositor or a display. Every verb answers with JSON on stdout
and exits 0 or 1.

```
omarchyform new <file> [--note TEXT]... [--force]
omarchyform inspect <file> [--full]
omarchyform apply <file> [ops.json|-] [--out FILE] [--dry-run]
omarchyform validate <file>
omarchyform ops
```

Boards live in `~/.local/share/omarchyform/boards/`. A board written there
appears in the board browser (`b` on an open board) under the name of its file
without the `.json`. A board anywhere else is still a board — it opens with
`ctrl+o` — so build somewhere harmless first if you are not sure.

## Making one

`omarchyform new ideas.json --note "First thought" --note "Second"` writes a
board with those notes laid out along a row and answers with how many items it
has. It refuses to write over a file that exists; `--force` means it.

Everything after that is `apply`, which takes a list of operations as JSON on
stdin or in a file:

```
echo '[{"op":"add","args":["ellipse",520,0,200,140,"the question","accent"]},
       {"op":"link","args":[1,3]}]' | omarchyform apply ideas.json -
```

The answer names what each operation did, including the id of anything added,
which is what you need for the operations after it. `--dry-run` answers
without writing. `--out` writes somewhere else and leaves the original.

Run `omarchyform ops` for the current list rather than trusting this one: it
prints the same table `apply` dispatches through, along with the kinds, the
theme roles and the minimum item size.

## Laying a board out

Nothing arranges items for you, so positions are yours to choose. Items are
placed by their top-left corner in board coordinates, y increasing downwards,
and the default item is 220 by 160. Leave about 60 between neighbours or they
read as one block. A row of related thoughts at `x = 0, 260, 520, …` and a
second row at `y = 220` is a reasonable start; `inspect` answers with `bounds`
so you can see what space a board already occupies before adding to it.

An item carries a theme role — `foreground`, `accent`, `urgent`, `muted` — not
a colour, so a board follows whatever desktop theme is in use. Use `accent` for
the thing being argued for and `urgent` for the thing being warned about;
tinting everything defeats it.

## Reading one

`inspect` answers with the counts, the bounds, a tally of kinds, and every
item's id, kind and text. `--full` adds geometry and the connectors, which is
most of the bytes and rarely what the question was. Read the text back to the
person rather than the JSON.

## When a board looks wrong

`validate` says whether it loads and what loading had to repair — items that
could not be used, connectors pointing at nothing. Boards are hand-editable and
syncable, so the file and what would be drawn can differ, and that difference
is what this prints.

A board reported as **newer than this understands** is not a broken one. It was
written by a later Omarchyform and the board itself opens it read-only rather
than losing what it cannot represent. Do not offer to repair or rewrite it; say
it came from a newer version.

## What this cannot do

It cannot draw. A picture of a board needs the scene, and the scene needs the
running shell — `ctrl+e` on an open board exports a PNG, and nothing here does.
It does not touch the trash, the backups or the pictures beside a board, and it
has no idea which board is open in the shell right now. If someone has a board
open, a change made here appears when they next open it, and a save from the
shell will write over it in the meantime: change boards that are not open.
