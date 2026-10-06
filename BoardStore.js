.pragma library

// Pure board logic: no QML, no side effects beyond the models handed in.
// Everything here is testable by reading it, which is the point of the split.

var MIN_SIZE = 60
var KINDS = ["note", "rect", "ellipse", "diamond"]
var CANVAS_PATTERNS = ["Dots", "Grid", "Ruled"]

// Items carry a theme role, not a hex colour, so a board follows the desktop
// theme instead of fighting it. The shell exposes these four.
var TINTS = ["foreground", "accent", "urgent", "muted"]

// An image lives beside the board rather than inside it: a screenshot in
// base64 would be megabytes rewritten on every autosave. The item keeps only
// the file name, and a name out of a board file is never trusted — boards are
// hand-editable and shareable, so only a plain name in the images folder is
// ever loaded.
function imageIsValid(name) {
  return typeof name === "string" && name.length > 0 && name.length <= 128
    && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name) && name.indexOf("..") < 0
}

// Far enough that the copy is visibly its own item, near enough that it is
// obviously related to the one it came from.
var DUPLICATE_OFFSET = 24

// v2 boards stored fixed pastels. Map them onto tints by position so an old
// board keeps its variety instead of going flat.
var LEGACY_SWATCHES = ["#F7D794", "#F3A0A0", "#A8D8B9", "#A3C4E8", "#D4B5E8", "#F0C9A0"]

function normalizeTint(value) {
  if (!value) return TINTS[0]
  if (TINTS.indexOf(value) >= 0) return value
  var legacy = LEGACY_SWATCHES.indexOf(value)
  if (legacy >= 0) return TINTS[legacy % TINTS.length]
  return TINTS[0]
}

// Each entry owns its label and action, so reordering the menu cannot change
// what a click or keyboard choice runs. Navigation entries keep the menu open.
// What making each kind of item is called in a board's history.
var ADD_LABELS = { note: "New note", rect: "New box", ellipse: "New ellipse", diamond: "New diamond", image: "Picture" }

var MENU_COMMANDS = [
  { id: "new", label: "New", run: "newBoard" },
  { id: "boards", label: "Boards", run: "openBrowser" },
  { id: "import", label: "Import", run: "importBoard" },
  { id: "save-copy", label: "Save copy", run: "exportBoard" },
  { id: "export-png", label: "Export PNG", run: "choosePng" },
  { id: "help", label: "Help", run: "showHelp" },
  { id: "commands", label: "Commands", run: "beginPalette" },
  { id: "background", label: "Background", run: "chooseCanvasBackground" },
  { id: "fit", label: "Fit", run: "fitToItems" },
  { id: "zoom", label: "Zoom", run: "openZoomMenu", keepOpen: true }
]

var ZOOM_LEVELS = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4]
var ZOOM_COMMANDS = [{ id: "back", label: "Back", run: "backToMenu", keepOpen: true }]
  .concat(ZOOM_LEVELS.map(function(level) {
    return { id: "zoom-" + level, label: Math.round(level * 100) + "%", run: "setZoom", arg: level }
  }))

function menuEntries(zoomMenu) { return zoomMenu ? ZOOM_COMMANDS : MENU_COMMANDS }
function menuIndex(id) {
  for (var i = 0; i < MENU_COMMANDS.length; i++)
    if (MENU_COMMANDS[i].id === id) return i
  return -1
}

// The outline of a painted shape, as SVG path data for a ShapePath.
//
// Arithmetic rather than drawing commands, so it can be checked without a
// scene: a diamond that misses its own corners, or an ellipse that is a
// pixel out on one side, is not something a screenshot makes obvious.
//
// Inset by a pixel the way the canvas that came before it was, so the stroke
// sits inside the item's own bounds rather than straddling them.
function shapePath(kind, w, h) {
  var cx = w / 2
  var cy = h / 2
  if (kind === "ellipse") {
    // Two half-arcs: SVG cannot draw a full ellipse in one, because a start
    // and end at the same point describe no sweep at all.
    var rx = Math.max(0.5, (w - 2) / 2)
    var ry = Math.max(0.5, (h - 2) / 2)
    return "M " + (cx - rx) + "," + cy
      + " A " + rx + "," + ry + " 0 1 0 " + (cx + rx) + "," + cy
      + " A " + rx + "," + ry + " 0 1 0 " + (cx - rx) + "," + cy + " Z"
  }
  var right = Math.max(1, w - 1)
  var bottom = Math.max(1, h - 1)
  return "M " + cx + ",1 L " + right + "," + cy + " L " + cx + "," + bottom
    + " L 1," + cy + " Z"
}

// ------------------------------------------------------------------- hints
// btop's way with a menu: the key a command answers to is coloured inside the
// word that names it, so the word carries the key rather than saying it twice.
// Where the key is not in the word — esc, /, a two-key chord — it is named in
// front instead, because a colour cannot point at a letter that is not there.
//
// The key has to be the letter the word starts with. btop colours a shortcut
// wherever it falls, and `a` for a new board did light the middle of `board` —
// which on screen read as a rendering fault rather than as a cue, so it is not
// worth the letter it saves. A key that does not lead its word is named in
// front of it.
//
// An uppercase key means shift, so it only matches an uppercase letter: the
// `A` that makes a folder must not light the `a` that starts a word, which
// would promise a key that does something else. A lowercase key matches
// either, so `f` lights the `F` of `Fit`.
function keyLeads(key, label) {
  if (typeof key !== "string" || typeof label !== "string" || key.length !== 1) return false
  if (key >= "A" && key <= "Z") return label.charAt(0) === key
  return label.charAt(0).toLowerCase() === key.toLowerCase()
}

// These lines are drawn as markup so one word in them can be a different
// colour, which means anything reaching them from a board file, a file name or
// something somebody typed has to arrive as text rather than as tags.
function escapeMarkup(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function hex2(value) {
  var byte = Math.round(Math.max(0, Math.min(1, value)) * 255).toString(16)
  return byte.length === 1 ? "0" + byte : byte
}

// A colour as markup understands it. StyledText wants a string, and a QML
// colour prints its alpha first, which it then reads as red.
function hexColor(color) {
  return color ? "#" + hex2(color.r) + hex2(color.g) + hex2(color.b) : "#000000"
}

function keyMarkup(key, color) {
  return '<font color="' + color + '">' + escapeMarkup(key) + "</font>"
}

function hintMarkup(key, label, color) {
  if (!keyLeads(key, label)) return keyMarkup(key, color) + ": " + escapeMarkup(label)
  return keyMarkup(label.slice(0, 1), color) + escapeMarkup(label.slice(1))
}

// The separator is drawn as markup, where a run of spaces collapses to one —
// so a line separated by spaces alone arrives with its hints run together.
// Every caller passes something visible.
function hintLine(hints, color, separator) {
  var out = []
  for (var i = 0; i < hints.length; i++) out.push(hintMarkup(hints[i][0], hints[i][1], color))
  return out.join(separator === undefined ? " · " : separator)
}

// What each surface offers, as data: the view joins and colours them, and the
// help panel below stays the one long list.
// The palette answers to `:` as well, which is the sibling of `/` and the one
// worth learning — but a key drawn in front of its own separator reads as
// ":: commands", which looks like a typo on the one line that is meant to
// teach. The chord is what this line says; the help list names both.
var BOARD_HINTS = [["n", "note"], ["r", "rect"], ["e", "ellipse"], ["x", "connect"],
                   ["ctrl+p", "commands"], ["/", "find"], ["?", "keys"], ["esc", "close"]]
var FIND_HINTS = [["enter", "next"], ["esc", "done"]]
var ARRANGE_HINTS = [["hjkl", "edges"], ["c/m", "centres"], ["HJKL", "spread evenly"],
                     ["esc", "cancel"]]
var PINNED_HINTS = [["tab/hjkl or click", "select"], ["p", "unpin"], ["esc", "done"]]
// `add board` rather than `board`, so the key leads the word and does not have
// to be said in front of it. The capital on `Add folder` is the shift the key
// wants, which is the one place capitalisation here is load-bearing.
var BROWSER_HINTS = [["jk", "move"], ["l/enter", "open"], ["h", "up"], ["/", "search"],
                     ["a", "add board"], ["A", "Add folder"], ["r", "rename"],
                     ["x", "trash"], ["t", "the trash"]]
var TRASH_HINTS = [["jk", "move"], ["l/enter", "put it back"], ["x", "destroy it"],
                   ["t or esc", "back to the boards"]]
var PALETTE_HINTS = [["tab", "next"], ["enter", "run"], ["esc", "close"]]
// Leaving is a real answer here, so it says what leaving means rather than
// calling itself "close": the two versions are both still there afterwards.
var CONFLICT_HINTS = [["1 2 3 or tab", "choose"], ["enter", "do it"],
                      ["esc", "decide later; nothing is lost either way"]]
var PROMPT_HINTS = [["enter", "confirm"], ["esc", "cancel"]]
var EMPTY_HINTS = [["a", "add a board"], ["A", "Add a folder"]]
var START_HINTS = [["n", "New note"], ["Ctrl+V", "Paste text"]]

// ------------------------------------------------------------- failures
// What an operation that can fail on its own time belongs to. A subprocess
// answers whenever it answers — a clipboard that never replied, a file the
// helper would not read — and by then the person is somewhere else on the
// board, so the line has to hold the answer rather than flash it past them.
//
// The kind is what tells a later success from an unrelated one: copying
// something out after a failed copy means the clipboard is working again;
// saving a PNG after a failed copy means nothing about the clipboard. Only a
// success of the same kind takes the failure down.
//
// Severity is not read out of the message. Every producer says which of these
// it is at the point it knows, because "Could not" is a phrase, not a type,
// and a line that guesses from the words is one translation away from lying.
// Copying out and pasting in are two operations, not one resource. A clipboard
// that took a copy says nothing about whether there is anything in it to paste,
// and treating them as one meant a successful copy took down "clipboard has no
// available text" as though it had answered it.
var FAILURE_KINDS = ["copy", "paste", "board", "picture", "png"]

function isFailureKind(kind) { return FAILURE_KINDS.indexOf(kind) >= 0 }

// -------------------------------------------------------------- exporting
// What an exported picture is drawn in. The board wears whatever theme the
// desktop is wearing, which is usually dark, and a dark picture is the wrong
// thing to put in a document, a slide or something meant to be printed. These
// are the answers to "the same board, but light".
//
// Written out rather than computed. A theme's fills and borders are its tint
// colour blended into its background, which is right for a board that has to
// sit on the desktop it belongs to — but an exported picture has no desktop to
// match, and a blend of colours chosen for a dark canvas makes mud on a white
// one. Each of these is picked to read on its own background, with the four
// tint roles still told apart at a glance. What an item says is at least 13:1
// against the fill behind it, and every border and connector clears 3:1
// against its own background — muted sits closest to that line, because being
// recessive is the whole of its job, and tests/suite.js holds it there.
//
// `theme` is not here: it means the board's own colours, and is the absence of
// an override rather than a palette of its own.
var EXPORT_PALETTES = {
  light: {
    label: "on white",
    background: "#ffffff",
    foreground: "#1b1f24",
    connector: "#57606a",
    fills: { foreground: "#f4f5f7", accent: "#e8f1fc", urgent: "#fdecec", muted: "#f1f2f4" },
    borders: { foreground: "#6e7781", accent: "#1f6feb", urgent: "#b42318", muted: "#878e97" }
  },
  dark: {
    label: "on black",
    background: "#0d1117",
    foreground: "#e6edf3",
    connector: "#8b949e",
    fills: { foreground: "#161b22", accent: "#12233c", urgent: "#2d1416", muted: "#15191f" },
    borders: { foreground: "#8b949e", accent: "#58a6ff", urgent: "#f85149", muted: "#6e7681" }
  },
  // For printing, and for anywhere colour is not going to survive the journey.
  // Nothing here carries meaning by hue: the roles differ in weight instead, so
  // the board still reads in one ink.
  mono: {
    label: "in black and white",
    background: "#ffffff",
    foreground: "#000000",
    connector: "#000000",
    fills: { foreground: "#ffffff", accent: "#ebebeb", urgent: "#d6d6d6", muted: "#f7f7f7" },
    borders: { foreground: "#000000", accent: "#000000", urgent: "#000000", muted: "#767676" }
  }
}

// What a picture of part of a board is of. Marking three notes and asking for
// a picture means those three: everything else drawn and then cut off at the
// frame reads as a rendering fault rather than as a choice, whatever a crop
// means to a photograph.
//
// Backgrounds are the exception, because they are scenery rather than content.
// A cluster lifted off a board keeps the panel it was sitting on — so they are
// drawn, and the frame is not put round them: a background is usually most of
// the board, and framing to it would undo the crop.
//
// Connectors need no filtering of their own. fillLinks already drops any whose
// ends are not both on the board it is given, so one leaving the crop leaves
// with it.
function cropRows(rows, indices) {
  if (!indices || indices.length === 0) return { draw: rows, frame: rows }
  var wanted = {}
  for (var i = 0; i < indices.length; i++) wanted[indices[i]] = true
  var draw = [], frame = []
  for (var j = 0; j < rows.length; j++) {
    if (wanted[j] === true) { draw.push(rows[j]); frame.push(rows[j]) }
    else if (rows[j].pinned === true) draw.push(rows[j])
  }
  // Nothing but scenery is nothing worth framing: fall back to the whole board
  // rather than to a picture of an empty panel.
  return frame.length === 0 ? { draw: rows, frame: rows } : { draw: draw, frame: frame }
}

// The same rectangle bounds() finds, over rows as they come out of a board
// file rather than over a model the scene has been filled with.
function boundsOfRows(rows) {
  if (!rows || rows.length === 0) return null
  var b = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity }
  for (var i = 0; i < rows.length; i++) {
    var n = rows[i]
    b.minX = Math.min(b.minX, n.x)
    b.minY = Math.min(b.minY, n.y)
    b.maxX = Math.max(b.maxX, n.x + n.w)
    b.maxY = Math.max(b.maxY, n.y + n.h)
  }
  return b
}

// The board's own colours are named too, so the four read as one choice rather
// than a default and three exceptions. Anything else asked for is the theme.
var EXPORT_PALETTE_NAMES = ["theme", "light", "dark", "mono"]

function exportPalette(name) {
  return EXPORT_PALETTES[name] === undefined ? null : EXPORT_PALETTES[name]
}

// What the board says after a picture is written. The two things that can vary
// are the two worth confirming: what it was of, and what it was drawn in.
function exportNote(name, cropped) {
  var what = cropped ? "what was marked" : "full board"
  var p = exportPalette(name)
  return what + ", without controls" + (p ? ", " + p.label : "")
}

// Which tint role a colour is asked for, with anything unrecognised drawn the
// way an untinted item is. Board files are hand-editable and come from other
// machines, so a tint this version has never heard of must still draw.
function paletteTint(palette, group, tint) {
  var table = palette[group]
  return table[tint] === undefined ? table.foreground : table[tint]
}

// ----------------------------------------------------------- the status line
// One line under the header, and every tier listed below wanting it. Which one gets
// it is decided here, once, because it used to be decided twice — the view drew
// the line and the controller worked out separately whether a failure was on
// screen, so that it could stop timing one that was not. The two disagreed
// about `opened`, and a failure reported while the board was closed spent its
// six seconds where nobody could see it. Two copies of a precedence is one
// copy too many.
//
// The tiers, in order:
//
//   none            the line is not on screen at all
//   saveError       the board is not being saved, and here is why. These are
//   trashIndexError conditions rather than events: none of them fades, and each
//   conflict        names something to be done before edits reach the disk.
//   damaged
//   failure         something asked for did not happen. A subprocess answers on
//                   its own time, and by then the person is elsewhere, so it
//                   outranks whatever they have started since.
//   palette         what the next keystroke means, narrowest claim first.
//   arrange         Typing comes before connecting because both can be true at
//   backgrounds     once — x holds a source, i starts a caret — and while there
//   editing         is a caret in a note, x is the letter x.
//   linking
//   flash           what just happened, and goes away by itself.
//   switching       what it is busy with.
//   saving
//   hints           nothing in particular: the keys.
var STATUS_TIERS = ["none", "saveError", "trashIndexError", "conflict", "damaged", "failure",
                    "palette", "arrange", "backgrounds", "editing", "linking",
                    "flash", "switching", "saving", "hints"]

function statusTier(s) {
  if (!s) return "none"
  // Not on screen: no board, or something covering the line. The find query
  // stands in the same place while it is being typed.
  if (!s.opened || s.helpVisible || s.browserVisible || s.finding) return "none"
  if (s.saveError !== "") return "saveError"
  if (s.trashIndexError !== "") return "trashIndexError"
  if (s.diskChanged) return "conflict"
  if (s.damaged) return "damaged"
  if (s.failureText !== "") return "failure"
  if (s.paletteVisible) return "palette"
  if (s.arranging) return "arrange"
  if (s.showPinned) return "backgrounds"
  if (s.editing) return "editing"
  if (s.linking) return "linking"
  if (s.statusText !== "") return "flash"
  if (s.switching) return "switching"
  if (s.saving) return "saving"
  // The keys are for the pane the keyboard is in. Beside it, a pane that is
  // only being looked at says nothing until it has something to say.
  return s.active === false ? "none" : "hints"
}

// ------------------------------------------------------------ connectors
// Only one connector runs between any pair, so drawing one is three different
// operations depending on what is already there. Which one it will be is
// asked here — once, by the line that promises it while the second end is
// being chosen, and again by the mutation that carries it out. Two decision
// trees is how a hint starts lying.
//
// `at` is the row it lands on, or -1 when there is nothing to land on. An end
// that cannot take a connector at all — nothing chosen, the same item twice —
// is "none", so the hint has something honest to say about it.
function linkAt(links, a, b) {
  if (a === undefined || b === undefined || a === null || b === null
      || a < 0 || b < 0 || a === b) return { at: -1, outcome: "none" }
  for (var i = 0; i < links.count; i++) {
    var l = links.get(i)
    // The same way round again takes it away; the other way round turns it.
    if (l.lfrom === a && l.lto === b) return { at: i, outcome: "remove" }
    if (l.lfrom === b && l.lto === a) return { at: i, outcome: "reverse" }
  }
  return { at: -1, outcome: "create" }
}

// What the board says while the far end is being chosen. Written from the
// outcome rather than beside it, so the words and the mutation move together.
// Every string in it is ours, so there is nothing here to escape.
function linkHint(outcome, color) {
  var line = outcome === "remove" ? keyMarkup("x", color) + " removes this connector"
    : outcome === "reverse" ? keyMarkup("x", color) + " turns this connector round"
    : outcome === "create" ? keyMarkup("x", color) + " connects these two"
    : "pick the other end, then " + keyMarkup("x", color)
  return line + " \u00b7 " + hintMarkup("esc", "cancel", color)
}

// ------------------------------------------------------------ note markup
// What a note may say beyond words. Small on purpose: a note is 220 by 160 and
// most of Markdown has nowhere to go on a canvas.
//
//   # a line          a heading — bigger and heavier
//   *bold*            emphasis
//   _italic_          quieter emphasis
//   `a key`           drawn in the accent, the way every key in this shell is
//   [accent]…[/]      a span in one of the theme's four roles
//
// Roles rather than colours, for the reason items carry roles: a board follows
// whatever theme the desktop is wearing, and there is still no way to put a hex
// colour into a board file.
//
// The safety is the order. Everything arriving from a board file is escaped
// first — a board is a file other people can send you, and the note is the one
// part of it they write — and only then is this syntax turned into tags. No tag
// from outside survives escaping, so nothing anyone else writes can reach the
// renderer as markup. It is the same bargain the status line makes.
var MARKUP_ROLES = ["foreground", "accent", "urgent", "muted"]

// One pass, left to right, so the first alternative to match at a position wins:
// a `*` inside a pair of backticks is consumed as part of the code span and is
// never seen as emphasis.
var MARKUP_SPAN = /`([^`\n]+)`|\[(foreground|accent|urgent|muted)\]([\s\S]*?)\[\/\]|\*([^*\n]+)\*|_([^_\n]+)_/g

function markupSpans(text, colors) {
  return text.replace(MARKUP_SPAN, function (all, code, role, coloured, bold, italic) {
    if (code !== undefined)
      return '<font color="' + colors.accent + '">' + code + "</font>"
    // Recursed, so a coloured span can still carry emphasis inside it. An
    // unclosed one finds no `[/]`, matches nothing, and stays as the text it is.
    if (role !== undefined)
      return '<font color="' + (colors[role] || colors.foreground) + '">'
        + markupSpans(coloured, colors) + "</font>"
    if (bold !== undefined) return "<b>" + bold + "</b>"
    if (italic !== undefined) return "<i>" + italic + "</i>"
    return all
  })
}

// How much of a note is put through the parser. A note is 220 by 160 and shows
// a few dozen words; everything past that is scrolled or clipped, so parsing it
// buys nothing that can be seen. A board file, on the other hand, can carry a
// note of any length and comes from whoever sent it — `fillItems` takes the
// text as it finds it, because truncating somebody's note on load would lose
// what they wrote. So the item keeps every character and the renderer is given
// a bounded piece of it.
var MARKUP_LIMIT = 4000

function noteMarkup(text, colors) {
  var raw = text === undefined || text === null ? "" : String(text)
  if (raw.length > MARKUP_LIMIT) raw = raw.slice(0, MARKUP_LIMIT)
  var lines = escapeMarkup(raw).split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var heading = /^#[ \t]+(.*)$/.exec(lines[i])
    out.push(heading
      ? '<font size="5"><b>' + markupSpans(heading[1], colors) + "</b></font>"
      : markupSpans(lines[i], colors))
  }
  return out.join("<br>")
}

// Putting a mark round the selection, and taking it off again if it is already
// there — pressed twice, a chord undoes itself. Returns where the selection
// should be afterwards, because a chord that leaves the caret somewhere else is
// a chord nobody presses twice.
//
// The marks are recognised from either side: selected inside them, or selected
// including them.
function wrapSelection(text, from, to, open, close) {
  var source = text === undefined || text === null ? "" : String(text)
  var a = Math.max(0, Math.min(source.length, Math.min(from, to)))
  var b = Math.max(0, Math.min(source.length, Math.max(from, to)))
  var inner = source.slice(a, b)

  // Both marks, or neither. Checked separately because a note can hold a lone
  // one — a bare `*` is punctuation, and taking it for half a pair would eat
  // the character next to it.
  var opened = open !== "" && source.slice(a - open.length, a) === open
  var closed = close !== "" && source.slice(b, b + close.length) === close
  if (opened && closed)
    return { text: source.slice(0, a - open.length) + inner + source.slice(b + close.length),
             from: a - open.length, to: b - open.length }

  if (inner.length >= open.length + close.length
      && inner.slice(0, open.length) === open
      && inner.slice(inner.length - close.length) === close) {
    var bare = inner.slice(open.length, inner.length - close.length)
    return { text: source.slice(0, a) + bare + source.slice(b),
             from: a, to: a + bare.length }
  }

  return { text: source.slice(0, a) + open + inner + close + source.slice(b),
           from: a + open.length, to: b + open.length }
}

// ---------------------------------------------------------------- commands
// Every command the board has, as data. The keys were the only way in: a board
// you have not used for a month is a list of letters you have to remember, and
// a board you have never used is worse. This is what `:` searches, so a command
// can be found by what it does rather than by the letter it answers to.
//
// `run` names a function on the controller and `arg` is what it takes, so the
// palette dispatches exactly what a keystroke dispatches rather than a second
// copy of it. `needs` is what has to be true for it to do anything: the
// functions all guard themselves, but a palette that runs something and shows
// nothing is worse than one that says why. `key` is the label shown beside the
// name — tests/contract.js checks the single-character ones against the key
// table in Board.qml, so the two cannot disagree about which letter does what.
// An empty key means there is no keystroke for it: it is reached by name, or
// from the panel that offers it.
//
// `also` is what else someone might type looking for it. The names here say
// what a command does in the board's own words — "Type in it", "Mark
// everything" — and the word most people reach for first is the one every
// other program uses: edit, select all, rename, rectangle. Those go here
// rather than into the name, because the name is what the palette shows and
// what the help teaches, and a list that says "Type in it (edit)" is teaching
// two things at once. Nothing dispatches by an alias: it is only a way in.
var COMMANDS = [
  { name: "New note", key: "n", run: "addRelative", arg: "note", needs: "edit" },
  { name: "New box", key: "r", run: "addRelative", arg: "rect", needs: "edit", also: ["rectangle"] },
  { name: "New ellipse", key: "e", run: "addRelative", arg: "ellipse", needs: "edit" },
  { name: "Type in it", key: "i", run: "editSelected", needs: "target", also: ["edit", "edit text"] },
  // Only while there is a caret in a note. `ctrl+p` opens the list there the
  // way it does on the board, narrowed to these, so the marks are reachable by
  // name before the chords are in the hands.
  { name: "Bold", key: "ctrl+b", run: "markText", arg: "bold", needs: "typing",
    also: ["strong", "emphasis"] },
  { name: "Italic", key: "ctrl+i", run: "markText", arg: "italic", needs: "typing",
    also: ["emphasis"] },
  { name: "Draw it as a key", key: "ctrl+k", run: "markText", arg: "key", needs: "typing",
    also: ["code", "monospace", "shortcut"] },
  { name: "Make it a heading", key: "", run: "headText", needs: "typing",
    also: ["title", "bigger"] },
  { name: "Colour it plain", key: "ctrl+1", run: "markText", arg: "foreground", needs: "typing" },
  { name: "Colour it accent", key: "ctrl+2", run: "markText", arg: "accent", needs: "typing" },
  { name: "Colour it urgent", key: "ctrl+3", run: "markText", arg: "urgent", needs: "typing" },
  { name: "Colour it muted", key: "ctrl+4", run: "markText", arg: "muted", needs: "typing" },
  { name: "Change shape", key: "s", run: "cycleKind", needs: "target" },
  { name: "Change colour", key: "c", run: "recolorItem", needs: "target" },
  { name: "Connect to another", key: "x", run: "toggleLinking", needs: "target", also: ["link"] },
  { name: "Remove its connectors", key: "X", run: "unlinkSelected", needs: "target", also: ["disconnect", "unlink"] },
  { name: "Duplicate", key: "ctrl+d", run: "duplicateTargets", needs: "target" },
  { name: "Delete", key: "del", run: "removeTargets", needs: "target" },
  { name: "Align and spread", key: "g", run: "beginArrange", needs: "edit" },
  // The chord's six answers, each with a name, so the second key is something
  // to learn rather than something to know already.
  { name: "Align left edges", key: "g h", run: "alignTargets", arg: "left", needs: "group" },
  { name: "Align right edges", key: "g l", run: "alignTargets", arg: "right", needs: "group" },
  { name: "Align top edges", key: "g k", run: "alignTargets", arg: "top", needs: "group" },
  { name: "Align bottom edges", key: "g j", run: "alignTargets", arg: "bottom", needs: "group" },
  { name: "Align centres across", key: "g c", run: "alignTargets", arg: "centreX", needs: "group" },
  { name: "Align centres down", key: "g m", run: "alignTargets", arg: "centreY", needs: "group" },
  { name: "Spread evenly across", key: "g H", run: "spreadTargets", arg: "x", needs: "group" },
  { name: "Spread evenly down", key: "g J", run: "spreadTargets", arg: "y", needs: "group" },
  { name: "Bring forward", key: "]", run: "layerTargets", arg: "forward", needs: "item" },
  { name: "Send backward", key: "[", run: "layerTargets", arg: "backward", needs: "item" },
  { name: "Bring to front", key: "}", run: "layerTargets", arg: "front", needs: "item" },
  { name: "Send to back", key: "{", run: "layerTargets", arg: "back", needs: "item" },
  { name: "Pin or unpin as background", key: "p", run: "togglePin", needs: "item" },
  { name: "Select backgrounds", key: "P", run: "togglePinnedSelection", needs: "" },
  { name: "Mark this one as well", key: "space", run: "toggleMark", needs: "", also: ["add to selection"] },
  { name: "Mark everything", key: "a", run: "markAll", needs: "", also: ["select all"] },
  { name: "Undo", key: "u", run: "undo", needs: "edit" },
  { name: "Redo", key: "ctrl+r", run: "redo", needs: "edit" },
  { name: "Copy out", key: "super+c", run: "copySelection", needs: "" },
  { name: "Paste in", key: "super+v", run: "pasteClipboard", needs: "edit" },
  { name: "Find in this board", key: "/", run: "beginFind", needs: "" },
  { name: "Fit the board on screen", key: "f", run: "fitToItems", needs: "" },
  { name: "Reset the view", key: "0", run: "resetView", needs: "" },
  { name: "Canvas background: Dots", key: "", run: "setCanvasBackground", arg: "Dots", needs: "", also: ["texture", "pattern"] },
  { name: "Canvas background: Grid", key: "", run: "setCanvasBackground", arg: "Grid", needs: "", also: ["texture", "pattern", "squares"] },
  { name: "Canvas background: Ruled", key: "", run: "setCanvasBackground", arg: "Ruled", needs: "", also: ["texture", "pattern", "lines"] },
  { name: "Canvas background: Plain", key: "", run: "setCanvasBackground", arg: "Plain", needs: "", also: ["texture", "pattern", "none"] },
  { name: "Zoom in", key: "+", run: "zoomCentre", arg: 1.2, needs: "" },
  { name: "Zoom out", key: "-", run: "zoomCentre", arg: 1 / 1.2, needs: "" },
  { name: "Fullscreen or windowed", key: "w", run: "toggleWindowMode", needs: "" },
  // Two views, of one board or of two. The key that made a layout takes it
  // away again, so there is nothing to learn for closing.
  { name: "Split side by side", key: "v", run: "toggleSplit", arg: "side-by-side", needs: "",
    also: ["two boards", "vertical split", "panes"] },
  { name: "Split stacked", key: "V", run: "toggleSplit", arg: "stacked", needs: "",
    also: ["two boards", "horizontal split", "panes"] },
  { name: "The other pane", key: "o", run: "otherPane", needs: "", also: ["switch pane", "focus"] },
  { name: "Even out the split", key: "", run: "evenSplit", needs: "", also: ["reset split", "half"] },
  { name: "Boards", key: "b", run: "openBrowser", needs: "" },
  { name: "New board", key: "ctrl+n", run: "newBoard", needs: "" },
  { name: "Name this board", key: "F2", run: "renameBoard", needs: "", also: ["rename"] },
  { name: "Import a board", key: "ctrl+o", run: "importBoard", needs: "" },
  { name: "Save a copy to share", key: "ctrl+shift+s", run: "exportBoard", needs: "" },
  { name: "Save a copy without its pictures", key: "", run: "exportBoardPlain", needs: "" },
  // One command per palette rather than a mode to be in: the list is reached
  // by typing, so "white" finds the one that matters without anything new on
  // the board to look at. `ctrl+e` keeps its meaning — the board as it looks.
  { name: "Export a PNG", key: "ctrl+e", run: "choosePng", arg: "theme", needs: "",
    also: ["image", "picture", "screenshot"] },
  { name: "Export a PNG on white", key: "", run: "choosePng", arg: "light", needs: "",
    also: ["png light", "light png", "white background"] },
  { name: "Export a PNG on black", key: "", run: "choosePng", arg: "dark", needs: "",
    also: ["png dark", "dark png", "black background"] },
  { name: "Export a PNG in black and white", key: "", run: "choosePng", arg: "mono", needs: "",
    also: ["png mono", "monochrome", "greyscale", "grayscale", "print"] },
  { name: "Save now", key: "ctrl+s", run: "flushSave", needs: "" },
  // Asked for twice: the first run says what the second will do.
  { name: "Forget this board's history", key: "", run: "forgetHistory", needs: "edit",
    also: ["clear history", "erase history", "privacy", "timeline"] },
  // Only offered while two versions of the open board exist. They have no keys
  // of their own: the panel that appears with the conflict numbers them, and
  // this is how they are found by name.
  { name: "Keep the version from disk", key: "", run: "conflictUseDisk", needs: "conflict" },
  { name: "Save my changes as a copy", key: "", run: "conflictSaveCopy", needs: "conflict" },
  { name: "Replace the version on disk", key: "", run: "conflictReplaceDisk", needs: "conflict" },
  { name: "Menu in the header", key: "m", run: "toggleMenu", needs: "" },
  { name: "Keys", key: "?", run: "toggleHelp", needs: "" },
  // The two ways in do not list themselves.
  { name: "Run a command", key: ":", run: "beginPalette", needs: "", listed: false },
  { name: "Actions for the selection", key: ".", run: "beginSelectionActions", needs: "", listed: false }
]

// What to offer for what has been typed. A name that starts with the query is
// what was meant more often than one that merely contains it, and the order is
// otherwise the table's own, which groups by what the commands are for.
// What a command needs before it can do anything, and which of those are
// about the thing that is selected — the set a menu of actions for a selection
// offers, as opposed to everything the board can do.
var SELECTION_NEEDS = ["target", "item", "group"]

// What a command needs a caret in a note for. Its own scope, because the list
// opened while typing is a different list: everything else on the board acts on
// items, and while there is a caret in a note the thing being worked on is the
// words.
var TYPING_NEEDS = ["typing"]

// The marks each text command puts round the selection. Kept beside the command
// table rather than inside the controller so the chord and the command cannot
// drift: both dispatch through this.
var TEXT_MARKS = {
  bold: ["*", "*"],
  italic: ["_", "_"],
  key: ["`", "`"],
  foreground: ["[foreground]", "[/]"],
  accent: ["[accent]", "[/]"],
  urgent: ["[urgent]", "[/]"],
  muted: ["[muted]", "[/]"]
}

// An alias is a way in, not a name: it is matched from its start, the way a
// name is, so `select all` answers "sel" and `rectangle` does not answer "a".
// A substring rule here would put New box in the list for half the alphabet.
function aliasLeads(command, needle) {
  var also = command.also
  if (!also) return false
  for (var i = 0; i < also.length; i++) if (also[i].indexOf(needle) === 0) return true
  return false
}

function matchCommands(query, scope) {
  var needle = String(query === undefined ? "" : query).toLowerCase().trim()
  var leading = []
  var rest = []
  // What only an alias found. Behind the names, because a command whose own
  // name answers the query is the better guess — and in table order, so the
  // tail of the list is as stable as the rest of it.
  var aliased = []
  for (var i = 0; i < COMMANDS.length; i++) {
    if (COMMANDS[i].listed === false) continue
    if (scope === "selection" && SELECTION_NEEDS.indexOf(COMMANDS[i].needs) < 0) continue
    if (scope === "typing" && TYPING_NEEDS.indexOf(COMMANDS[i].needs) < 0) continue
    // And the other way: what only makes sense with a caret in a note stays out
    // of the list the board opens, where there is nothing for it to act on.
    if (scope !== "typing" && TYPING_NEEDS.indexOf(COMMANDS[i].needs) >= 0) continue
    if (needle === "") { rest.push(COMMANDS[i]); continue }
    var name = COMMANDS[i].name.toLowerCase()
    var at = name.indexOf(needle)
    // The key is worth searching as well as the name: someone who half
    // remembers the letter should be able to type it and see what it does.
    // Tested before the substring, or a command whose name happens to contain
    // that letter — align, chan(g)e — buries the one the letter belongs to.
    //
    // One bucket each, so a command that matches by name and by alias both is
    // still offered once.
    if (at === 0 || COMMANDS[i].key.toLowerCase() === needle) leading.push(COMMANDS[i])
    else if (at > 0) rest.push(COMMANDS[i])
    else if (aliasLeads(COMMANDS[i], needle)) aliased.push(COMMANDS[i])
  }
  return leading.concat(rest, aliased)
}

function commandByName(name) {
  for (var i = 0; i < COMMANDS.length; i++) if (COMMANDS[i].name === name) return COMMANDS[i]
  return null
}

// The glyph a command wears in the list, as the shell's menu gives every row
// one. Font Awesome's codepoints, which Nerd Fonts keep where Font Awesome put
// them; the theme's font need not carry them, and Qt falls back to one that
// does, as it does for the menu. Keyed by what a command runs, then by its
// argument, so a new command in a family already here has one already.
var COMMAND_ICONS = {
  addRelative: { note: "\uf249", rect: "\uf096", ellipse: "\uf10c" },
  editSelected: "\uf040",
  markText: { bold: "\uf032", italic: "\uf033", key: "\uf121",
              foreground: "\uf1fc", accent: "\uf1fc", urgent: "\uf1fc", muted: "\uf1fc" },
  headText: "\uf1dc",
  cycleKind: "\uf1b2",
  recolorItem: "\uf1fc",
  toggleLinking: "\uf0c1",
  unlinkSelected: "\uf127",
  duplicateTargets: "\uf24d",
  removeTargets: "\uf1f8",
  beginArrange: "\uf037",
  alignTargets: { left: "\uf036", right: "\uf038", top: "\uf062", bottom: "\uf063",
                  centreX: "\uf037", centreY: "\uf039" },
  spreadTargets: { x: "\uf07e", y: "\uf07d" },
  layerTargets: { forward: "\uf106", backward: "\uf107", front: "\uf102", back: "\uf103" },
  togglePin: "\uf08d",
  togglePinnedSelection: "\uf08d",
  toggleMark: "\uf046",
  markAll: "\uf14a",
  undo: "\uf0e2",
  redo: "\uf01e",
  copySelection: "\uf0c5",
  pasteClipboard: "\uf0ea",
  beginFind: "\uf002",
  fitToItems: "\uf065",
  resetView: "\uf015",
  setCanvasBackground: "\uf03e",
  toggleWindowMode: "\uf2d0",
  // Columns for side by side, a stack of boxes for stacked.
  toggleSplit: { "side-by-side": "\uf0db", stacked: "\uf233" },
  otherPane: "\uf0ec",
  evenSplit: "\uf0b2",
  openBrowser: "\uf07c",
  newBoard: "\uf016",
  renameBoard: "\uf044",
  importBoard: "\uf019",
  exportBoard: "\uf045",
  exportBoardPlain: "\uf045",
  choosePng: "\uf03e",
  flushSave: "\uf0c7",
  forgetHistory: "\uf12d",
  conflictUseDisk: "\uf0a0",
  conflictSaveCopy: "\uf0c5",
  conflictReplaceDisk: "\uf0c7",
  toggleMenu: "\uf0c9",
  toggleHelp: "\uf11c",
  beginPalette: "\uf120",
  beginSelectionActions: "\uf0ca"
}
function commandIcon(command) {
  if (!command) return ""
  // Zooming is the one family told apart by a number rather than a name.
  if (command.run === "zoomCentre") return command.arg > 1 ? "\uf00e" : "\uf010"
  var icon = COMMAND_ICONS[command.run]
  if (icon && typeof icon === "object") icon = icon[command.arg]
  return typeof icon === "string" ? icon : ""
}

// The shortcut list, in the groups a person looks for a key by. The shell's own
// panels break a long list with small labels and a rule between sections, and
// forty rows with nothing between them read as a wall.
var KEY_HELP_SECTIONS = [
  { title: "Boards and files", rows: [
    ["b", "boards: browse, open, create"],
    ["ctrl+n / F2", "new board / name the current board"],
    ["ctrl+o", "import a native board"],
    ["ctrl+shift+s / ctrl+e", "export editable copy / PNG of the board"],
    ["mark, then ctrl+e", "a PNG of just what is marked, backgrounds included"],
    [": png", "the same picture on white, on black, or in black and white"],
    ["super+v", "paste a picture or text (also ctrl+v)"],
    ["super+c", "copy a picture or text (also ctrl+c)"]
  ] },
  { title: "Make and change", rows: [
    ["n", "new note beside the selected one"],
    ["r / e", "new box / ellipse"],
    ["s", "cycle shape: note, box, ellipse, diamond"],
    ["c", "change its colour"],
    ["p / shift+p", "pin as background / select backgrounds"],
    ["ctrl+d", "duplicate it, connectors between the copies included"],
    ["del / backspace", "delete what is marked, or the one under the cursor"],
    ["u / ctrl+r", "undo / redo"]
  ] },
  { title: "Connect", rows: [
    // Walked to, not clicked at: a pointer selection starts afresh and ends the
    // half-made connector, so the keys are what the line has room to teach.
    ["x", "connect: x on one, tab or hjkl to the other, x again"],
    // Which of the two it will be is said on the line under the header while the
    // far end is being chosen, so this row says that there is a choice rather
    // than asking anyone to work out which side of it they are on.
    ["x on a connected pair", "turn that connector round, or remove it — the line says which"],
    ["X", "remove every connector on this item at once"]
  ] },
  { title: "Write", rows: [
    ["enter / i", "type in the selected item"],
    ["while typing: ctrl+p", "format selected text by name"],
    ["while typing: ctrl+b / ctrl+i", "*bold* / _italic_ round what is selected"],
    ["ctrl+k", "`a key`, drawn in the accent"],
    ["ctrl+1..4", "colour it: foreground, accent, urgent, muted"],
    ["# at the start of a line", "a heading, bigger and heavier"]
  ] },
  { title: "Move and arrange", rows: [
    ["h j k l", "move the selection around"],
    ["tab", "cycle through everything"],
    ["H J K L", "push the selected item"],
    ["ctrl+hjkl", "resize it, from the bottom-right"],
    ["space", "mark this one as well"],
    ["a", "mark everything"],
    ["g then h j k l", "align the marked items on that edge"],
    ["g then c / m", "align their centres on one line"],
    ["g then H J K L", "spread them evenly, outermost two staying put"],
    ["] / [", "bring forward / send backward, where they overlap"],
    ["} / {", "bring right to the front / send right to the back"]
  ] },
  { title: "View", rows: [
    ["f", "fit the whole board on screen"],
    ["0", "reset the view"],
    ["+ / -", "zoom"],
    ["w", "fullscreen or windowed"],
    ["v / V", "split side by side / stacked; the same key again for one pane"],
    ["o", "the other pane; b there opens another board in it"],
    ["/", "find: type to search the notes, enter steps through matches"]
  ] },
  { title: "Find your way", rows: [
    ["? / F1", "this list"],
    [": / ctrl+p", "run any command by name, without knowing its key"],
    [". or right-click", "what can be done with what is selected"],
    ["m", "show or hide the menu in the header"],
    ["m then h l / tab", "walk the menu; enter picks, esc closes"],
    ["esc", "back out, then close the board"]
  ] },
  { title: "Pointer", rows: [
    ["shift+click", "mark items together"],
    ["drag on canvas", "sweep a rectangle to mark everything it touches"],
    ["shift+drag", "sweep, keeping what was already marked"],
    ["drag an item", "move it, and everything marked with it"],
    ["middle/right drag", "pan the canvas"],
    ["drag the line between panes", "resize them; double-click it to even them out"],
    ["wheel", "zoom at the pointer"]
  ] }
]

// Every row, in order, for what wants the whole list at once: the key column is
// measured over all of them, so it lines up from one section to the next.
var KEY_HELP = (function () {
  var rows = []
  for (var i = 0; i < KEY_HELP_SECTIONS.length; i++) rows = rows.concat(KEY_HELP_SECTIONS[i].rows)
  return rows
})()

// ---------------------------------------------------------------- marshalling
// One shape in, one shape out. The file, the undo stack and the models all
// speak this, so there is a single definition of what an item is.

function itemRows(items) {
  var out = []
  for (var i = 0; i < items.count; i++) {
    var n = items.get(i)
    out.push({ id: n.iid, kind: n.kind, x: n.ix, y: n.iy, w: n.iw, h: n.ih, tint: n.itint, text: n.itext, pinned: n.ipinned === true, src: n.isrc })
  }
  return out
}

function linkRows(links) {
  var out = []
  for (var i = 0; i < links.count; i++) out.push({ from: links.get(i).lfrom, to: links.get(i).lto })
  return out
}

// A board file can be hand-edited, copied between machines or half-written by
// something else. Everything coming in is coerced to something the canvas can
// actually draw: a string where a number belongs would otherwise become NaN
// geometry and be written straight back out.
function num(value, fallback) {
  var n = typeof value === "number" ? value : parseFloat(value)
  return isFinite(n) ? n : fallback
}

function fillItems(items, rows) {
  items.clear()
  if (!rows) return
  var used = {}
  var reserved = {}
  for (var r = 0; r < rows.length; r++) {
    var existing = num(rows[r].id, 0)
    if (existing > 0 && existing < 2147483647 && Math.floor(existing) === existing) reserved[existing] = true
  }
  var nextId = 1
  for (var i = 0; i < rows.length; i++) {
    var n = rows[i]
    // Ids have to be unique: connectors reference them, so a duplicate would
    // silently join the wrong things.
    var id = num(n.id, 0)
    id = (id > 0 && id < 2147483647 && Math.floor(id) === id && !used[id]) ? id : 0
    while (id === 0) {
      if (!used[nextId] && !reserved[nextId]) id = nextId
      nextId++
    }
    used[id] = true
    var kind = KINDS.indexOf(n.kind) >= 0 ? n.kind
      : (n.kind === "image" && imageIsValid(n.src) ? "image" : "note")
    items.append({
      iid: id,
      kind: kind,
      ix: num(n.x, 0),
      iy: num(n.y, 0),
      iw: Math.max(MIN_SIZE, num(n.w, 180)),
      ih: Math.max(MIN_SIZE, num(n.h, 140)),
      itint: normalizeTint(n.tint || n.color),
      itext: typeof n.text === "string" ? n.text : "",
      ipinned: n.pinned === true,
      isrc: kind === "image" ? n.src : ""
    })
  }
}

// Connectors reference ids, so one whose ends did not survive is dropped
// rather than left dangling.
function fillLinks(links, items, rows) {
  links.clear()
  if (!rows) return
  var seen = {}
  // One index of the items, rather than a scan of them per endpoint: loading a
  // board was costing time proportional to items times connectors.
  var byId = idIndex(items)
  for (var i = 0; i < rows.length; i++) {
    var l = rows[i]
    // Ends are item ids, which are numbers, so they are read as numbers: the
    // index is a plain object, and a name like "toString" is one every plain
    // object answers to. An id written as "3" still means item 3.
    var from = num(l.from, 0)
    var to = num(l.to, 0)
    // Both ends must exist, an item cannot be joined to itself, and the same
    // pair cannot appear twice; from/to retain its direction.
    if (from === to) continue
    if (byId[from] === undefined || byId[to] === undefined) continue
    var key = Math.min(from, to) + ":" + Math.max(from, to)
    if (seen[key]) continue
    seen[key] = true
    links.append({ lfrom: from, lto: to })
  }
}

function indexOfId(items, id) {
  for (var i = 0; i < items.count; i++) if (items.get(i).iid === id) return i
  return -1
}

// An id -> index map, built once per paint instead of scanning per connector.
function idIndex(items) {
  var map = {}
  for (var i = 0; i < items.count; i++) map[items.get(i).iid] = i
  return map
}

function nextFreeId(items, stored) {
  var id = num(stored, 1)
  if (id < 1 || id >= 2147483647 || Math.floor(id) !== id) id = 1
  for (var i = 0; i < items.count; i++) id = Math.max(id, items.get(i).iid + 1)
  return id
}

// The newest format this reads. Every version from 1 up to it still loads:
// older boards are migrated on the way in rather than refused. The command
// line asks this too, to tell a board from a newer Omarchyform apart from one
// that is broken.
//
// Version 6 is a board that carries its edit history. A board without one is
// still written as version 5, so a copy made to share, and a board nobody has
// edited since, open in every Omarchyform since 0.4 — and a board with history
// opens in one older than this read-only, so it can never be saved over and
// lose it.
var FORMAT_VERSION = 6
var PLAIN_VERSION = 5

// Where a board's history starts in its file. Always the last key and always
// at this indentation, because opening a board reads the board in front of it
// and leaves the history as text: parsing a long history on the shell's own
// thread stood it still for up to 156ms (tests/history-bench.js). A newline
// cannot be inside a JSON string, so this cannot be found in a note.
var HISTORY_MARKER = '\n  "history": '

// A whole number from 1 to FORMAT_VERSION. "5" and 4.5 are not versions.
function knownVersion(version) {
  return version >= 1 && version <= FORMAT_VERSION && Math.floor(version) === version
}

// The longest a note can be. Text is laid out, marked up and written out on
// the shell's own thread, so the bar and everything else in the shell wait
// while it is, for a time that grows with the length: measured on 2026-10-04,
// a 1 MB note held the shell for 47ms when its board loaded and 41ms on every
// edit, and a shared board can carry thirty times that. A board is a file
// anyone can write, so this is checked where text arrives rather than trusted
// to have been checked where it was written. The same as the largest paste
// (cliptext in BoardFiles.sh), so whatever can be pasted fits in a note.
var MAX_NOTE_LENGTH = 1048576

// How long a stretch of text with no space in it can be before a note stops
// looking for a word boundary to break it at. Qt's ordinary wrap searches a
// run for one before breaking it anywhere, and the search grows with the
// square of the run: an unbroken 256 KB line — a pasted base64 blob, a
// minified file — held a note's first frame for 9.5s offscreen, and 64 KB of
// it froze the shell long enough on the desktop for the compositor to offer to
// kill it. Wrapped anywhere it takes 53ms. A run this long already breaks
// mid-word, so only the rest of such a note looks any different for it.
var LONG_RUN = 256
var LONG_RUN_PATTERN = new RegExp("\\S{" + LONG_RUN + "}")
function hasLongRun(text) {
  return typeof text === "string" && text.length >= LONG_RUN && LONG_RUN_PATTERN.test(text)
}

// Where in a board's rows the first item is whose text is longer than a note
// can be, or -1. An index rather than an id: a version 1 board has no ids.
function overlongNote(rows) {
  if (!rows) return -1
  for (var i = 0; i < rows.length; i++) {
    var n = rows[i]
    if (n && typeof n.text === "string" && n.text.length > MAX_NOTE_LENGTH) return i
  }
  return -1
}

// A v1 board stored a flat notes[] with no ids or kinds.
function readFile(raw) {
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return null }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
  if (parsed.version !== undefined && !knownVersion(parsed.version)) return null
  var fields = ["items", "notes", "links"]
  for (var f = 0; f < fields.length; f++) {
    var rows = parsed[fields[f]]
    if (rows === undefined) continue
    if (!Array.isArray(rows)) return null
    for (var i = 0; i < rows.length; i++)
      if (!rows[i] || typeof rows[i] !== "object" || Array.isArray(rows[i])) return null
  }
  return {
    items: parsed.items ? parsed.items : (parsed.notes ? parsed.notes : []),
    links: parsed.links ? parsed.links : [],
    nextId: parsed.nextId ? parsed.nextId : 1,
    // Only when the history was not split off first: a board someone has
    // reformatted by hand still has one, just not where it is looked for.
    history: parsed.history !== undefined ? parsed.history : null
  }
}

// A board file in two: the board in front, as a board of its own, and its
// history after it as text, or "" when it has none or it is not where this
// writer puts it. readFile on the first part reads the board without parsing
// the history; see HISTORY_MARKER.
function splitHistory(raw) {
  var text = typeof raw === "string" ? raw : ""
  var end = text.length
  while (end > 0 && (text.charAt(end - 1) === "\n" || text.charAt(end - 1) === "\r" || text.charAt(end - 1) === " ")) end--
  var at = text.lastIndexOf(HISTORY_MARKER)
  if (at < 1 || text.charAt(at - 1) !== "," || text.charAt(end - 1) !== "}") return { board: text, history: "" }
  var history = text.slice(at + HISTORY_MARKER.length, end - 1)
  var last = history.length
  while (last > 0 && /\s/.test(history.charAt(last - 1))) last--
  return { board: text.slice(0, at - 1) + "\n}\n", history: history.slice(0, last) }
}

function joinHistory(boardText, historyText) {
  return boardText.slice(0, -3) + "," + HISTORY_MARKER + historyText + "\n}\n"
}

// windowMode deliberately absent: which surface the board opens on is a
// property of this machine, not of the board, and lives in state.json. A board
// written before that split still carries the key; it is ignored on the way in.
// The marker goes first so a file manager can tell a board from any other
// JSON without opening it: shared-mime-info matches a string near the front of
// the file, and `{"version": 5` describes half the configuration on the disk.
//
// Deliberately not a format bump. A key an older Omarchyform does not know is
// a key it ignores, so a board written here still opens there; bumping the
// version would make it refuse to save over one, which is the opposite of what
// adding a name to the format should cost. Boards written before this pick the
// marker up the next time they are saved.
var FORMAT_MARKER = "omarchyform.board"

// `historyText`, when there is one, is written after the board as it is held:
// a history is appended to as text rather than written out again, which on a
// long one cost 80-160ms a save.
function writeFile(items, links, nextId, historyText) {
  var board = JSON.stringify({
    kind: FORMAT_MARKER,
    version: historyText ? FORMAT_VERSION : PLAIN_VERSION,
    nextId: nextId,
    items: itemRows(items),
    links: linkRows(links)
  }, null, 2) + "\n"
  return historyText ? joinHistory(board, historyText) : board
}

// --------------------------------------------------------------- layer order
// Which item is drawn over which. The model's order is the paint order, so
// moving an item within it is what "bring forward" means — nothing else about
// the item changes, including whether it is pinned, which is a layer of its
// own and stays one.
//
// Answers in moves rather than a new order, because a ListModel moves rows and
// rebuilding it would tear down every delegate on the board. Applied in the
// order they come back.
//
// Several items keep their order relative to each other: sending three items
// to the back puts them at the back in the order they were already in, which
// is what makes this usable on a group of things that overlap each other.
function layerMoves(count, indices, where) {
  var moves = []
  if (!indices || indices.length === 0 || count <= 1) return moves
  var picked = indices.slice().sort(function (a, b) { return a - b })
  var i
  // Already where it is being asked to go. Worth answering with nothing rather
  // than a set of moves that cancel out: the board would be written again, and
  // the person would be told something happened when it did not.
  var settled = true
  for (i = 0; i < picked.length; i++) {
    var want = where === "front" ? count - picked.length + i : i
    if ((where === "front" || where === "back") && picked[i] !== want) { settled = false; break }
  }
  if ((where === "front" || where === "back") && settled) return moves
  if (where === "front") {
    // Each one to the end, earliest first; every move shifts the ones after it
    // down by one, which is what `moved` counts.
    for (i = 0; i < picked.length; i++) {
      var fromFront = picked[i] - i
      if (fromFront !== count - 1) moves.push({ from: fromFront, to: count - 1 })
    }
  } else if (where === "back") {
    // Each one to the start, latest first, so the earliest ends up first.
    for (i = picked.length - 1; i >= 0; i--) {
      var fromBack = picked[i] + (picked.length - 1 - i)
      if (fromBack !== 0) moves.push({ from: fromBack, to: 0 })
    }
  } else if (where === "forward") {
    // One step each, from the top down, and never past another of the picked
    // ones: a group moving up keeps its shape.
    var ceiling = count
    for (i = picked.length - 1; i >= 0; i--) {
      if (picked[i] + 1 >= ceiling) { ceiling = picked[i]; continue }
      moves.push({ from: picked[i], to: picked[i] + 1 })
      ceiling = picked[i] + 1
    }
  } else if (where === "backward") {
    var floor = -1
    for (i = 0; i < picked.length; i++) {
      if (picked[i] - 1 <= floor) { floor = picked[i]; continue }
      moves.push({ from: picked[i], to: picked[i] - 1 })
      floor = picked[i] - 1
    }
  }
  return moves
}

// ------------------------------------------------------------------- sharing
// A board in the library keeps only the file name of a picture; the bytes live
// once in images/, so the same screenshot on four boards is stored once. That is
// the right shape for one machine with one library and the wrong shape for a
// copy someone is sent, where the name means nothing — a shared board of
// screenshots arrived as a board of holes.
//
// So a copy saved to share carries its pictures inside it, base64 in an `images`
// object beside the items. One file, which is the whole point of being able to
// send someone a board.
//
// Deliberately not a format bump, for the same reason the marker was not: a key
// an older Omarchyform does not know is a key it ignores, so a copy saved here
// still opens there, with its pictures missing exactly as they are missing
// today.
function imageNames(items) {
  var seen = {}
  var names = []
  for (var i = 0; i < items.count; i++) {
    var row = items.get(i)
    if (row.kind !== "image" || !imageIsValid(row.isrc) || seen[row.isrc]) continue
    seen[row.isrc] = true
    names.push(row.isrc)
  }
  return names
}

// Takes the board as text rather than as models, because a copy being saved is
// a picture of one moment and the models move on while its pictures are being
// read out of the library.
function withEmbeddedImages(raw, images) {
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return raw }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return raw
  if (images && Object.keys(images).length > 0) parsed.images = images
  return JSON.stringify(parsed, null, 2) + "\n"
}

// What a shared copy brought with it. Every byte here was written by someone
// else, and a name decides a path on disk, so anything that is not a name this
// would write itself is dropped rather than repaired.
var BASE64_BODY = /^[A-Za-z0-9+/\r\n]+={0,2}$/

// What a board is allowed to carry. The same ceiling a dropped picture has for
// one image, and a total that keeps the encoded copy something a process can
// hand over in one piece. Checked from the length of the base64 rather than by
// decoding it: four characters are three bytes, and a file that is too big to
// accept should be refused before it is turned into bytes.
var MAX_IMAGE_BYTES = 33554432
var MAX_BUNDLE_BYTES = 16777216

function decodedSize(base64) {
  var padding = base64.length > 1 && base64.charAt(base64.length - 1) === "="
    ? (base64.charAt(base64.length - 2) === "=" ? 2 : 1) : 0
  return Math.floor(base64.length * 3 / 4) - padding
}

// How many pictures the file says it carries, whether or not they survive
// being looked at. The difference between this and what sharedImages returns
// is how much of the board did not arrive.
function declaredImageCount(raw) {
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return 0 }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return 0
  var images = parsed.images
  if (!images || typeof images !== "object" || Array.isArray(images)) return 0
  return Object.keys(images).length
}

function sharedImages(raw) {
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return {} }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {}
  var images = parsed.images
  if (!images || typeof images !== "object" || Array.isArray(images)) return {}
  var out = {}
  var total = 0
  var names = Object.keys(images)
  for (var i = 0; i < names.length; i++) {
    var body = images[names[i]]
    if (!imageIsValid(names[i]) || typeof body !== "string" || body === "") continue
    if (!BASE64_BODY.test(body)) continue
    var size = decodedSize(body)
    if (size <= 0 || size > MAX_IMAGE_BYTES) continue
    total += size
    if (total > MAX_BUNDLE_BYTES) break
    out[names[i]] = body
  }
  return out
}

// The pictures landed under names this machine chose, because the ones they
// arrived with may already be taken here. Point the items at where the bytes
// actually are and drop the bytes themselves: they are in images/ now.
//
// A name that did not land is cleared rather than left alone. A shared copy is
// self-contained by construction, so a picture it did not carry is not one this
// machine has — and a name from someone else's board must never end up
// addressing a file in this one's library. Cleared, the item loads as an empty
// note, because "image" is not one of KINDS without a picture to be.
//
// Every import comes through here, including a board that carries no pictures
// at all: leaving the `images` key out must not be a way to keep the names.
function withSharedImages(raw, landed) {
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return raw }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return raw
  delete parsed.images
  var rows = Array.isArray(parsed.items) ? parsed.items
    : (Array.isArray(parsed.notes) ? parsed.notes : [])
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i] || typeof rows[i] !== "object" || Array.isArray(rows[i])) continue
    if (rows[i].src === undefined || rows[i].src === "") continue
    rows[i].src = landed[rows[i].src] === undefined ? "" : landed[rows[i].src]
  }
  return JSON.stringify(parsed, null, 2) + "\n"
}

// ------------------------------------------------------------------- library
// Boards live in a real directory tree under the data dir. Paths here are
// always relative to that root, use "/" and never start or end with one.

function joinPath(a, b) {
  if (!a) return b || ""
  if (!b) return a
  return a + "/" + b
}

function parentOf(path) {
  var i = path.lastIndexOf("/")
  return i < 0 ? "" : path.slice(0, i)
}

function baseName(path) {
  var i = path.lastIndexOf("/")
  return i < 0 ? path : path.slice(i + 1)
}

// What the browser shows: a board without its extension, a folder as it is.
function displayName(entry) {
  var b = baseName(entry.path)
  if (entry.dir) return b
  return b.slice(-5) === ".json" ? b.slice(0, -5) : b
}

// Output of: find <root> -mindepth 1 -printf "%y\t%P\n"
// Anything that is neither a directory nor a .json board is ignored, so a
// stray file in the tree cannot become a broken entry.
function parseListing(out) {
  var rows = []
  if (!out) return rows
  var lines = out.split("\n")
  for (var i = 0; i < lines.length; i++) {
    var tab = lines[i].indexOf("\t")
    if (tab < 0) continue
    var type = lines[i].slice(0, tab)
    var path = lines[i].slice(tab + 1)
    if (!path) continue
    if (type === "d") rows.push({ path: path, dir: true })
    else if (type === "f" && path.slice(-5) === ".json") rows.push({ path: path, dir: false })
  }
  return rows
}

// Directories first, then boards, each alphabetically — the order `ls` would
// give you with --group-directories-first.
function childrenOf(entries, dir) {
  var out = []
  for (var i = 0; i < entries.length; i++)
    if (parentOf(entries[i].path) === dir) out.push(entries[i])
  out.sort(function (a, b) {
    if (a.dir !== b.dir) return a.dir ? -1 : 1
    // Two entries in one directory cannot share a name, so there is no equal
    // case to handle here.
    var an = baseName(a.path).toLowerCase()
    var bn = baseName(b.path).toLowerCase()
    return an < bn ? -1 : 1
  })
  return out
}

// Subsequence match over the whole path, so "wpa" finds work/project-a.
// Lower is better; -1 means no match.
function fuzzyScore(text, query) {
  if (!query) return 0
  var t = text.toLowerCase()
  var q = query.toLowerCase()
  var ti = 0
  var score = 0
  for (var qi = 0; qi < q.length; qi++) {
    var found = -1
    while (ti < t.length) {
      if (t.charAt(ti) === q.charAt(qi)) { found = ti; break }
      ti++
    }
    if (found < 0) return -1
    score += found
    ti++
  }
  return score
}

// With no query this is just the current directory. With one it searches the
// whole tree, which is the point of holding it all in memory.
function filterEntries(entries, dir, query) {
  if (!query) return childrenOf(entries, dir)
  var scored = []
  for (var i = 0; i < entries.length; i++) {
    var s = fuzzyScore(entries[i].path, query)
    if (s >= 0) scored.push({ entry: entries[i], score: s })
  }
  scored.sort(function (a, b) {
    if (a.score !== b.score) return a.score - b.score
    return a.entry.path < b.entry.path ? -1 : 1
  })
  var out = []
  for (var j = 0; j < scored.length; j++) out.push(scored[j].entry)
  return out
}

// A name typed by a person, on its way to becoming a path segment.
function nameIsValid(name) {
  if (!name) return false
  if (name === "." || name === "..") return false
  return !/[\/\\\x00-\x1f\x7f]/.test(name)
}

// The name of the lock for a board, from the board's path.
//
// It lives here because both writers have to arrive at the same string: a lock
// only serialises anything if the plugin and `bin/omarchyform` pick the same
// file for the same board, and two implementations of that rule is one more
// than can be kept in step. The plugin passes a path relative to the library,
// the command line passes the same for a board inside it and the full path for
// one outside; each of those is a different key here, which is the point.
//
// Percent-encoding rather than flattening separators: `work/a.json` and a board
// actually called `work__a.json` used to map to one lock, so two unrelated
// boards waited on each other. Encoding is reversible, so no two paths share a
// key, and a lock file can still be read back to the board it belongs to.
function lockKey(path) {
  return encodeURIComponent(path)
}

// Relative paths in state/trash may have been edited outside the application.
function safeRelative(path) {
  if (typeof path !== "string" || !path) return false
  var parts = path.split("/")
  for (var i = 0; i < parts.length; i++) if (!nameIsValid(parts[i])) return false
  return true
}

// "notes", "notes-2", "notes-3", ...
function uniquePath(entries, dir, base, isDir) {
  var taken = {}
  for (var i = 0; i < entries.length; i++) taken[entries[i].path] = true
  var suffix = isDir ? "" : ".json"
  var candidate = joinPath(dir, base + suffix)
  var n = 2
  while (taken[candidate]) {
    candidate = joinPath(dir, base + "-" + n + suffix)
    n++
  }
  return candidate
}

// ------------------------------------------------------------------- trash
// A deleted board is moved aside rather than destroyed. The index remembers
// where each one came from, so putting it back is exact rather than a guess
// from a flattened filename.

function readTrash(raw) {
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return [] }
  if (!parsed || !Array.isArray(parsed.entries)) return []
  var out = []
  for (var i = 0; i < parsed.entries.length; i++) {
    var e = parsed.entries[i]
    if (!e || typeof e !== "object") continue
    if (typeof e.file !== "string" || !nameIsValid(e.file)) continue
    if (!safeRelative(e.path)) continue
    out.push({ file: e.file, path: e.path, dir: e.dir === true, at: typeof e.at === "string" ? e.at : "" })
  }
  return out
}

function writeTrash(entries) {
  return JSON.stringify({ version: 1, entries: entries }, null, 2) + "\n"
}

// Flattened, stamped, and never colliding with something already in there.
function trashFile(entries, relative, stamp) {
  var base = String(stamp) + "-" + String(relative).replace(/\//g, "__")
  var taken = {}
  for (var i = 0; i < entries.length; i++) taken[entries[i].file] = true
  var candidate = base
  var n = 2
  while (taken[candidate]) { candidate = base + "-" + n; n++ }
  return candidate
}

function withoutTrash(entries, file) {
  var out = []
  for (var i = 0; i < entries.length; i++) if (entries[i].file !== file) out.push(entries[i])
  return out
}

// Newest first: what you just deleted is what you are most likely after.
function sortedTrash(entries) {
  var out = entries.slice()
  out.sort(function (a, b) { return a.at < b.at ? 1 : (a.at > b.at ? -1 : 0) })
  return out
}

// ----------------------------------------------------------------------- theme

// Omarchy themes declare their own mode in colors.toml ("mode = \"light\"").
// Every stock theme does; a third-party one might not, hence the fallback.
function parseThemeMode(toml) {
  if (!toml) return ""
  var m = /^[ \t]*mode[ \t]*=[ \t]*["']?(light|dark)["']?[ \t]*$/m.exec(toml)
  return m ? m[1] : ""
}

// Rec. 709 relative luminance, on 0..1 channels. Used only when a theme does
// not say which it is.
function isLightColor(r, g, b) {
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) > 0.5
}

// The shell draws its summoned surfaces — the menu, its panels, notifications —
// with a border spec: a colour, four side widths, and a gradient at an angle if
// the theme names one. Theme.qml reads the spec off the shell; these turn it
// into something plain QtQuick can paint, so the board's panels wear the same
// edge as the menu beside them without importing anything from the shell.

// The four side widths a spec carries. A spec that is missing or malformed is
// no border, rather than a panel that will not draw.
function borderWidths(spec) {
  function side(v) { var n = Number(v); return isFinite(n) && n > 0 ? n : 0 }
  var w = spec && spec.widths ? spec.widths : {}
  return { top: side(w.top), right: side(w.right), bottom: side(w.bottom), left: side(w.left) }
}

// Whether a Rectangle's own border can draw it: one colour, one width all round.
function flatBorder(spec) {
  var w = borderWidths(spec)
  var graded = !!(spec && spec.gradient && spec.gradient.enabled)
  return !graded && w.top === w.right && w.right === w.bottom && w.bottom === w.left
}

// Where a gradient at `angle` degrees starts and ends on a w-by-h surface.
// The shell's own arithmetic (BorderGeometry.gradientEndpoints), so a panel
// here shades the way the menu does rather than nearly the way.
function gradientEndpoints(w, h, angle) {
  w = Math.max(1, Number(w) || 1)
  h = Math.max(1, Number(h) || 1)
  var rad = (Number(angle) || 0) * Math.PI / 180
  var dx = Math.cos(rad)
  var dy = Math.sin(rad)
  var len = (Math.abs(w * dx) + Math.abs(h * dy)) / 2
  return { x1: w / 2 - dx * len, y1: h / 2 - dy * len, x2: w / 2 + dx * len, y2: h / 2 + dy * len }
}

// A gradient in QML has a fixed number of stops, so a theme's colours are
// spread over them: evenly while there are colours, and the last one held for
// the stops left over. Also the shell's own.
function stopColor(colors, index) {
  if (!colors || colors.length === 0) return "transparent"
  return index < colors.length ? colors[index] : colors[colors.length - 1]
}
function stopPosition(colors, index) {
  var count = colors ? colors.length : 0
  if (count <= 1) return index === 0 ? 0 : 1
  return index >= count ? 1 : index / (count - 1)
}

// The ring a border paints, as SVG path data for an odd-even fill: the outer
// rectangle, and the inner one the side widths cut out of it. Corners follow
// the theme's radius outside and give up the border's width inside.
function ringPath(w, h, radius, widths) {
  var t = widths.top, r = widths.right, b = widths.bottom, l = widths.left
  var inner = Math.max(0, (Number(radius) || 0) - Math.max(t, r, b, l))
  return roundedRectPath(0, 0, w, h, radius) + " " + roundedRectPath(l, t, w - l - r, h - t - b, inner)
}
function roundedRectPath(x, y, w, h, radius) {
  if (!(w > 0) || !(h > 0)) return ""
  var k = Math.max(0, Math.min(Number(radius) || 0, w / 2, h / 2))
  if (k === 0) return "M " + x + " " + y + " H " + (x + w) + " V " + (y + h) + " H " + x + " Z"
  function arc(ex, ey) { return " A " + k + " " + k + " 0 0 1 " + ex + " " + ey }
  return "M " + (x + k) + " " + y + " H " + (x + w - k) + arc(x + w, y + k)
    + " V " + (y + h - k) + arc(x + w - k, y + h)
    + " H " + (x + k) + arc(x, y + h - k)
    + " V " + (y + k) + arc(x + k, y) + " Z"
}

// -------------------------------------------------------------------- geometry

// Nearest item in a direction, scored by distance along the axis plus a
// penalty for drifting off it. This is what makes hjkl feel like moving
// around a board rather than cycling a list.
//
// (dx, dy) is a unit axis vector: one of (1,0) (-1,0) (0,1) (0,-1). Because one
// component is always zero, the sign inside the off-axis term is unobservable
// — mutation testing reports it as an equivalent mutant, which it is.
function nearest(items, fromIndex, dx, dy, pinnedMode) {
  if (fromIndex < 0 || fromIndex >= items.count) return -1
  var from = items.get(fromIndex)
  var fx = from.ix + from.iw / 2
  var fy = from.iy + from.ih / 2
  var best = -1
  var bestScore = Infinity
  for (var i = 0; i < items.count; i++) {
    if (i === fromIndex || (items.get(i).ipinned === true) !== (pinnedMode === true)) continue
    var n = items.get(i)
    var ax = (n.ix + n.iw / 2) - fx
    var ay = (n.iy + n.ih / 2) - fy
    var along = ax * dx + ay * dy
    if (along <= 0) continue
    var score = along + Math.abs(ax * dy + ay * dx) * 2
    if (score < bestScore) { bestScore = score; best = i }
  }
  return best
}

function bounds(items) {
  if (items.count === 0) return null
  var b = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity }
  for (var i = 0; i < items.count; i++) {
    var n = items.get(i)
    b.minX = Math.min(b.minX, n.ix)
    b.minY = Math.min(b.minY, n.iy)
    b.maxX = Math.max(b.maxX, n.ix + n.iw)
    b.maxY = Math.max(b.maxY, n.iy + n.ih)
  }
  return b
}

// ------------------------------------------------------------------ arranging
// Edges a selection can be aligned on. centreX puts every centre on one
// vertical line, centreY on one horizontal line.
var ALIGN_EDGES = ["left", "right", "top", "bottom", "centreX", "centreY"]

function boundsOf(items, indices) {
  if (!indices || indices.length === 0) return null
  var b = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity }
  for (var i = 0; i < indices.length; i++) {
    var n = items.get(indices[i])
    b.minX = Math.min(b.minX, n.ix)
    b.minY = Math.min(b.minY, n.iy)
    b.maxX = Math.max(b.maxX, n.ix + n.iw)
    b.maxY = Math.max(b.maxY, n.iy + n.ih)
  }
  return b
}

// Both of these return only the items that actually move, so the caller can
// tell "already arranged" from "nothing to arrange" and does not write a
// property to the value it already holds.
function alignMoves(items, indices, edge) {
  if (!indices || indices.length < 2 || ALIGN_EDGES.indexOf(edge) < 0) return []
  var b = boundsOf(items, indices)
  var moves = []
  for (var i = 0; i < indices.length; i++) {
    var n = items.get(indices[i])
    var x = n.ix, y = n.iy
    if (edge === "left") x = b.minX
    else if (edge === "right") x = b.maxX - n.iw
    else if (edge === "centreX") x = (b.minX + b.maxX) / 2 - n.iw / 2
    else if (edge === "top") y = b.minY
    else if (edge === "bottom") y = b.maxY - n.ih
    else y = (b.minY + b.maxY) / 2 - n.ih / 2
    if (x !== n.ix || y !== n.iy) moves.push({ index: indices[i], x: x, y: y })
  }
  return moves
}

// Equal gaps rather than equal centre spacing: a wide note beside two narrow
// ones looks evenly placed only when the space between them is what is even.
// The outermost two keep their positions, so the selection does not drift.
function spreadMoves(items, indices, axis) {
  if (!indices || indices.length < 3 || (axis !== "x" && axis !== "y")) return []
  var start = axis === "x" ? "ix" : "iy"
  var size = axis === "x" ? "iw" : "ih"
  var order = indices.slice().sort(function (a, b) {
    return items.get(a)[start] - items.get(b)[start]
  })
  var first = items.get(order[0])
  var last = items.get(order[order.length - 1])
  var span = (last[start] + last[size]) - first[start]
  var total = 0
  for (var i = 0; i < order.length; i++) total += items.get(order[i])[size]
  // Items that together take more room than they sit in cannot have gaps; butt
  // them up rather than dragging the outer two inwards.
  var gap = Math.max(0, (span - total) / (order.length - 1))
  var moves = []
  var at = first[start]
  for (var j = 0; j < order.length; j++) {
    var n = items.get(order[j])
    if (at !== n[start])
      moves.push({
        index: order[j],
        x: axis === "x" ? at : n.ix,
        y: axis === "y" ? at : n.iy
      })
    at = at + n[size] + gap
  }
  return moves
}

// What lands on the clipboard when items are copied out: their text in board
// order, blank ones left out, separated by a blank line so several notes arrive
// as paragraphs rather than one run-on.
function copyText(items, indices) {
  var ordered = indices.slice().sort(function (a, b) { return a - b })
  var parts = []
  for (var i = 0; i < ordered.length; i++) {
    var n = items.get(ordered[i])
    if (typeof n.itext === "string" && n.itext !== "") parts.push(n.itext)
  }
  return parts.join("\n\n")
}

// A dropped URL is untrusted text from another application. Only a plain local
// path comes back; anything with a scheme of its own, a host, or a control
// character in it is not something to go reading off disk.
function localPath(url) {
  if (typeof url !== "string" || url.indexOf("file:///") !== 0) return ""
  var path
  try { path = decodeURIComponent(url.slice(7)) } catch (e) { return "" }
  if (path.charAt(0) !== "/") return ""
  if (/[\x00-\x1f]/.test(path)) return ""
  return path
}

// Items whose text contains the query, in board order. Case-insensitive, and
// backgrounds are skipped the way every other bulk operation skips them.
function findMatches(items, query) {
  var out = []
  if (!query) return out
  var needle = query.toLowerCase()
  for (var i = 0; i < items.count; i++) {
    var n = items.get(i)
    if (n.ipinned === true) continue
    if (typeof n.itext === "string" && n.itext.toLowerCase().indexOf(needle) >= 0) out.push(i)
  }
  return out
}

// Items a marquee touches, in model order. Touching rather than enclosing: at
// low zoom a rectangle that has to swallow an item whole is fiddly, and every
// canvas worth copying picks touching. Backgrounds are skipped, the way every
// other bulk operation skips them.
function idsInRect(items, minX, minY, maxX, maxY) {
  var out = []
  for (var i = 0; i < items.count; i++) {
    var n = items.get(i)
    if (n.ipinned === true) continue
    if (n.ix > maxX || n.ix + n.iw < minX) continue
    if (n.iy > maxY || n.iy + n.ih < minY) continue
    out.push(n.iid)
  }
  return out
}

// Where a connector meets an item: walk from its centre toward the other end
// until we cross its outline.
function edgePoint(it, cx, cy, tx, ty) {
  var dx = tx - cx
  var dy = ty - cy
  if (dx === 0 && dy === 0) return { x: cx, y: cy }
  var scale
  if (it.kind === "ellipse") {
    scale = 1 / Math.sqrt(dx * dx / (it.iw * it.iw / 4) + dy * dy / (it.ih * it.ih / 4))
  } else if (it.kind === "diamond") {
    scale = 1 / (Math.abs(dx) / (it.iw / 2) + Math.abs(dy) / (it.ih / 2))
  } else scale = Math.min(
    dx === 0 ? Infinity : (it.iw / 2) / Math.abs(dx),
    dy === 0 ? Infinity : (it.ih / 2) / Math.abs(dy))
  return { x: cx + dx * scale, y: cy + dy * scale }
}

// How far either side of its line a connector's head opens, in radians.
var ARROW_SPREAD = 0.42

// How far a connector drawn in the theme's foreground is held back: at full
// strength it outweighs the items it joins. The board and a PNG export in the
// theme's own colours both use it, so a picture looks like the board it is of.
// A chosen export palette names a connector colour of its own instead.
var CONNECTOR_ALPHA = 0.55

// Where a connector from item a to item b runs, in board units: from the edge
// of one (fromX, fromY) to the edge of the other (toX, toY), along the line
// between their centres, with a filled head of length `head` whose back
// corners are (leftX, leftY) and (rightX, rightY). The board and an exported
// picture both draw from this, so the two cannot disagree about where a
// connector is — which a label placed against it will depend on. How long the
// head is, how heavy the line, in what colour and through which camera stays
// with each of them.
function connectorGeometry(a, b, head) {
  var acx = a.ix + a.iw / 2, acy = a.iy + a.ih / 2
  var bcx = b.ix + b.iw / 2, bcy = b.iy + b.ih / 2
  var from = edgePoint(a, acx, acy, bcx, bcy)
  var to = edgePoint(b, bcx, bcy, acx, acy)
  var angle = Math.atan2(to.y - from.y, to.x - from.x)
  return {
    fromX: from.x, fromY: from.y, toX: to.x, toY: to.y,
    leftX: to.x - head * Math.cos(angle - ARROW_SPREAD), leftY: to.y - head * Math.sin(angle - ARROW_SPREAD),
    rightX: to.x - head * Math.cos(angle + ARROW_SPREAD), rightY: to.y - head * Math.sin(angle + ARROW_SPREAD)
  }
}

function cycle(list, current) {
  var i = list.indexOf(current)
  return list[(i + 1) % list.length]
}
