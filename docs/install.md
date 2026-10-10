# Install, update and remove

[Back to the README](../README.md) · [Using the board](guide.md) · [Boards on disk and the command line](files.md) · [Development](development.md)

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
[Running from a clone](development.md#running-from-a-clone).

Your boards, backups, trash and pasted pictures are untouched by an update:
they live outside the plugin directory, in `~/.local/share/omarchyform/`. A
board written by a newer version than the one you are running opens read-only
rather than losing what it does not understand, so downgrading is safe too.

From 0.4.7 on, a board starts keeping its history the
first time you edit it, and is then written as format 7 (see
[History](guide.md#history)). Boards you only look at stay as they were. Older versions
open these boards read-only. To take a board back to one, set item textures to
Plain, then save a copy to share (`ctrl+shift+s`), which never carries history,
or run **Forget this board's history** first.

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

## Dependencies

Clipboard integration uses **wl-clipboard**, for `wl-paste` and
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

## Tested against

| | |
|---|---|
| Omarchy | `omarchy-dev 4.0.0.r6863.ga15636b-1`, Quattro shell |
| Qt | 6.12.0 |
| Quickshell | 0.3.2 |
| Compositor | Hyprland `0.56.2`, Wayland |
| Displays attached | 1920×1080 at scale 1.6 and 3840×2160 at scale 2 |
| Clipboard | `wl-clipboard` 1:2.3.0 |

The 0.4.7 automated and live smoke checks passed on this configuration on
2026-10-10. Two of five live runs that day stopped waiting for a synthesized
key to reach the test window; the same commits passed when run again. 0.4.6 was
tested on `omarchy-dev 4.0.0.r6720.g8e02fc8-1` with Qt 6.11.2, Quickshell 0.3.1
and a single 1920×1080 output at scale 1.6, 0.4.5 on
`omarchy-dev 4.0.0.r6713.ga85e29a-1`, and earlier releases on Omarchy
`4.0.0.r2158.gd174d4a-1`. Omarchy 4's plugin contract is still moving; these
results do not establish compatibility with every version.

The live plugin and clipboard fixtures use isolated board data.
[Performance results](performance.md) record the display configuration and
large-board limits of the run they come from.

The live checks do not exercise moving between monitors or every mixed-scale
placement. An unscaled display and other compositors remain untested. Portrait
and small-window layout is covered by the Qt layout suite rather than by hand
on hardware. Overlay placement on those configurations needs further checking.
