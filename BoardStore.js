.pragma library

// Pure board logic: no QML, no side effects beyond the models handed in.
// Everything here is testable by reading it, which is the point of the split.

var MIN_SIZE = 60
var KINDS = ["note", "rect", "ellipse", "diamond"]

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

// The header menu. One list, so the view draws what the controller dispatches
// and a keyboard walk cannot drift out of step with what is on screen.
var MENU_COMMANDS = ["New", "Boards", "Import", "Save copy", "Export PNG", "Help", "Commands"]

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
var COMMANDS = [
  { name: "New note", key: "n", run: "addRelative", arg: "note", needs: "edit" },
  { name: "New box", key: "r", run: "addRelative", arg: "rect", needs: "edit" },
  { name: "New ellipse", key: "e", run: "addRelative", arg: "ellipse", needs: "edit" },
  { name: "Type in it", key: "i", run: "editSelected", needs: "target" },
  { name: "Change shape", key: "s", run: "cycleKind", needs: "target" },
  { name: "Change colour", key: "c", run: "recolorItem", needs: "target" },
  { name: "Connect to another", key: "x", run: "toggleLinking", needs: "target" },
  { name: "Remove its connectors", key: "X", run: "unlinkSelected", needs: "target" },
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
  { name: "Mark this one as well", key: "space", run: "toggleMark", needs: "" },
  { name: "Mark everything", key: "a", run: "markAll", needs: "" },
  { name: "Undo", key: "u", run: "undo", needs: "edit" },
  { name: "Redo", key: "ctrl+r", run: "redo", needs: "edit" },
  { name: "Copy out", key: "super+c", run: "copySelection", needs: "" },
  { name: "Paste in", key: "super+v", run: "pasteClipboard", needs: "edit" },
  { name: "Find in this board", key: "/", run: "beginFind", needs: "" },
  { name: "Fit the board on screen", key: "f", run: "fitToItems", needs: "" },
  { name: "Reset the view", key: "0", run: "resetView", needs: "" },
  { name: "Zoom in", key: "+", run: "zoomCentre", arg: 1.2, needs: "" },
  { name: "Zoom out", key: "-", run: "zoomCentre", arg: 1 / 1.2, needs: "" },
  { name: "Fullscreen or windowed", key: "w", run: "toggleWindowMode", needs: "" },
  { name: "Boards", key: "b", run: "openBrowser", needs: "" },
  { name: "New board", key: "ctrl+n", run: "newBoard", needs: "" },
  { name: "Name this board", key: "F2", run: "renameBoard", needs: "" },
  { name: "Import a board", key: "ctrl+o", run: "importBoard", needs: "" },
  { name: "Save a copy to share", key: "ctrl+shift+s", run: "exportBoard", needs: "" },
  { name: "Save a copy without its pictures", key: "", run: "exportBoardPlain", needs: "" },
  { name: "Export a PNG", key: "ctrl+e", run: "choosePng", needs: "" },
  { name: "Save now", key: "ctrl+s", run: "flushSave", needs: "" },
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

function matchCommands(query, scope) {
  var needle = String(query === undefined ? "" : query).toLowerCase().trim()
  var leading = []
  var rest = []
  for (var i = 0; i < COMMANDS.length; i++) {
    if (COMMANDS[i].listed === false) continue
    if (scope === "selection" && SELECTION_NEEDS.indexOf(COMMANDS[i].needs) < 0) continue
    if (needle === "") { rest.push(COMMANDS[i]); continue }
    var name = COMMANDS[i].name.toLowerCase()
    var at = name.indexOf(needle)
    // The key is worth searching as well as the name: someone who half
    // remembers the letter should be able to type it and see what it does.
    // Tested before the substring, or a command whose name happens to contain
    // that letter — align, chan(g)e — buries the one the letter belongs to.
    if (at === 0 || COMMANDS[i].key.toLowerCase() === needle) leading.push(COMMANDS[i])
    else if (at > 0) rest.push(COMMANDS[i])
  }
  return leading.concat(rest)
}

function commandByName(name) {
  for (var i = 0; i < COMMANDS.length; i++) if (COMMANDS[i].name === name) return COMMANDS[i]
  return null
}

var KEY_HELP = [
  ["ctrl+n / F2", "new board / name the current board"],
  ["super+v", "paste a picture or text (also ctrl+v)"],
  ["ctrl+o", "import a native board"],
  ["ctrl+shift+s / ctrl+e", "export editable copy / PNG"],
  ["n", "new note beside the selected one"],
  ["r / e", "new box / ellipse"],
  ["p / shift+p", "pin as background / select backgrounds"],
  ["s", "cycle shape: note, box, ellipse, diamond"],
  ["x", "connect: press on one, then on another; again to turn it round"],
  ["X", "remove every connector on this item"],
  ["u / ctrl+r", "undo / redo"],
  ["b", "boards: browse, open, create"],
  ["enter / i", "type in the selected item"],
  ["esc", "back out, then close the board"],
  ["h j k l", "move the selection around"],
  ["H J K L", "push the selected item"],
  ["ctrl+hjkl", "resize it, from the bottom-right"],
  ["tab", "cycle through everything"],
  ["space", "mark this one as well"],
  ["a", "mark everything"],
  ["del / backspace", "delete what is marked, or the one under the cursor"],
  ["ctrl+d", "duplicate it, connectors between the copies included"],
  ["m", "show or hide the menu in the header"],
  ["m then h l / tab", "walk the menu; enter picks, esc closes"],
  ["super+c", "copy a picture or text (also ctrl+c)"],
  ["/", "find: type to search the notes, enter steps through matches"],
  ["g then h j k l", "align the marked items on that edge"],
  ["g then c / m", "align their centres on one line"],
  ["g then H J K L", "spread them evenly, outermost two staying put"],
  [". or right-click", "what can be done with what is selected"],
  ["] / [", "bring forward / send backward, where they overlap"],
  ["} / {", "bring right to the front / send right to the back"],
  ["c", "change its colour"],
  ["w", "fullscreen or windowed"],
  ["f", "fit the whole board on screen"],
  ["0", "reset the view"],
  ["+ / -", "zoom"],
  ["? / F1", "this list"],
  [": / ctrl+p", "run any command by name, without knowing its key"],
  ["shift+click", "mark items together"],
  ["drag on canvas", "sweep a rectangle to mark everything it touches"],
  ["shift+drag", "sweep, keeping what was already marked"],
  ["drag an item", "move it, and everything marked with it"],
  ["middle/right drag", "pan the canvas"],
  ["wheel", "zoom at the pointer"]
]

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
    // Both ends must exist, an item cannot be joined to itself, and the same
    // pair cannot appear twice; from/to retain its direction.
    if (l.from === l.to) continue
    if (byId[l.from] === undefined || byId[l.to] === undefined) continue
    var key = Math.min(l.from, l.to) + ":" + Math.max(l.from, l.to)
    if (seen[key]) continue
    seen[key] = true
    links.append({ lfrom: l.from, lto: l.to })
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

// A v1 board stored a flat notes[] with no ids or kinds.
function readFile(raw) {
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return null }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
  if (parsed.version !== undefined && [1, 2, 3, 4, 5].indexOf(parsed.version) < 0) return null
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
    nextId: parsed.nextId ? parsed.nextId : 1
  }
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

function writeFile(items, links, nextId) {
  return JSON.stringify({
    kind: FORMAT_MARKER,
    version: 5,
    nextId: nextId,
    items: itemRows(items),
    links: linkRows(links)
  }, null, 2) + "\n"
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

function trashEntry(entries, file) {
  for (var i = 0; i < entries.length; i++) if (entries[i].file === file) return entries[i]
  return null
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

function cycle(list, current) {
  var i = list.indexOf(current)
  return list[(i + 1) % list.length]
}
