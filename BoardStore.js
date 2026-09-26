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
var MENU_COMMANDS = ["New", "Boards", "Import", "Save copy", "Export PNG", "Help"]

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
var BOARD_HINTS = [["n", "note"], ["r", "rect"], ["e", "ellipse"], ["x", "connect"],
                   ["/", "find"], ["?", "keys"], ["esc", "close"]]
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
var PROMPT_HINTS = [["enter", "confirm"], ["esc", "cancel"]]
var EMPTY_HINTS = [["a", "add a board"], ["A", "Add a folder"]]
var START_HINTS = [["n", "New note"], ["Ctrl+V", "Paste text"]]

var KEY_HELP = [
  ["ctrl+n / F2", "new board / name the current board"],
  ["ctrl+v", "paste a picture, or clipboard text as a note"],
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
  ["ctrl+c", "copy it out: a picture as a picture, anything else as its text"],
  ["/", "find: type to search the notes, enter steps through matches"],
  ["g then h j k l", "align the marked items on that edge"],
  ["g then c / m", "align their centres on one line"],
  ["g then H J K L", "spread them evenly, outermost two staying put"],
  ["c", "change its colour"],
  ["w", "fullscreen or windowed"],
  ["f", "fit the whole board on screen"],
  ["0", "reset the view"],
  ["+ / -", "zoom"],
  ["? / F1", "this list"],
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
function writeFile(items, links, nextId) {
  return JSON.stringify({
    version: 5,
    nextId: nextId,
    items: itemRows(items),
    links: linkRows(links)
  }, null, 2) + "\n"
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
