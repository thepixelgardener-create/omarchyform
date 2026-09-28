# A session to watch, and what to watch for

Tasks to give someone who has never seen a board, and the things worth writing
down while they do them. It is short on purpose: a list long enough to tire the
person is a list whose last item is never reached.

Nobody has been through this yet. Nothing below is a finding — it is what to
look for, so that the next feature is chosen from what happened rather than from
what seemed likely. **Do not write results here that were not observed.**

This is for discovery: what someone reaches for when nothing has been explained.
It is not how correctness is checked. Whether a gesture does the right thing is
a directed check with a known answer — those live in
[`pointer-checks.md`](pointer-checks.md) — and the two must not be run as one
session. A person hunting for a note will find it by any means that works, which
tells you they are resourceful and nothing about whether panning is correct.

## Before they start

Give them a board with nothing on it, the keyboard, and the mouse. Do not
explain anything, including that `?` exists. Say only: "tell me what you are
trying to do as you go."

Sit where you can see the screen and the hands. Keep a timer running and note
roughly when each task starts. If they are stuck for more than a minute, ask
what they are looking for, and only then help — the question is what they
reached for, not whether they eventually found it.

## First, ask about the last month

Before any task. These are about what they already do, not about this board, and
they are asked first so the tasks cannot plant the answers:

- What did you last use a whiteboard, a diagram or a notes canvas for?
- Was any of it work you had done before and were rebuilding?
- Did any of it end up somewhere else — a document, a chat, a ticket?
- How many separate boards or files was it spread across?

Write the answers down verbatim. A feature is worth considering when it answers
something they describe here, not when a task invented for the session makes it
look necessary.

## The tasks

1. **Capture a thought.** "Put a note on the board that says what you had for
   breakfast."
2. **Connect two notes, then disconnect them.** "Add a second note, draw an
   arrow from the first to the second, then take that arrow away again."
3. **Work on a board bigger than the window.** Open a board with thirty or so
   items on it. "Add a note next to the one that says X" — where X is off
   screen, in a corner. The note has to be *placed*, so getting there is part of
   the task rather than something a search can finish on its own.
4. **Reopen another board.** "Go back to the board you made at the start."
5. **Share a result.** "Send me what is on this board." Do not say what that
   means. If they ask, ask them back what they would expect, write down the
   answer, and only then say: a picture of it, or a copy they could open and
   edit. Which one they assumed is the finding.

Task 3 is about what they do when the thing they need is not on screen — pan,
zoom out, fit, search, or give up. It does not establish that panning works;
`pointer-checks.md` does that.

## What to write down

For each task, four columns and nothing else:

| | |
|---|---|
| **First action** | The very first thing they did — the key or the click, before any correction. |
| **Wrong turns** | Every action that did not move them toward the goal, in order. |
| **Asked for help** | Whether they opened `?`, the menu, the command list, or asked out loud. |
| **Recovered how** | What got them unstuck: undo, escape, a hint they read, a guess, or you. |

Write what happened, not what it means. "Pressed `c` three times, then said
'where is delete'" is worth more than "confused by the shortcuts."

Three things worth noting whenever they happen, in any task:

- **A gesture that did something they did not expect.** Especially the mouse
  buttons: the middle button only pans, and anyone carrying a habit from another
  canvas app may expect it to do something else.
- **Reading the line under the header.** It is where every mode explains itself.
  Note whether their eyes go there at all, and whether they act on what it says
   — particularly while connecting, where it names the outcome before they
  commit to it.
- **Clicking the second item while connecting.** A click starts a fresh
  selection and ends the half-made connector; the far end is reached with `tab`
  or `hjkl`. If people keep doing it, that is the evidence a separate plan for
  pointer-driven connecting would need.

## Reading it afterwards

The point is to choose the next feature, and the bar for that is a pattern
across people, not a single struggle.

- Several people describing rebuilt work in the opening questions, and going
  looking for a way to carry objects between boards, would argue for structured
  copy. Not seeing it during a five-task session argues nothing: no task here
  requires moving anything between boards, so its absence is a property of the
  script, not of the need.
- Several people slow on task 4, or going the long way round to a board they had
  open minutes ago, would argue for recent-board navigation.
- Nobody finding the command list on their own would argue for making the way in
  more visible, not for adding more commands to it.

A feature being absent is not evidence that it is wanted, and neither is another
canvas app having it. If a session produces no pattern, that is a result: write
"no pattern" and keep the board as it is.
