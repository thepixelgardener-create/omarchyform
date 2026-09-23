.pragma library

// Pure board logic: no QML, no side effects beyond the models handed in.
// Everything here is testable by reading it, which is the point of the split.

var MIN_SIZE = 60
var KINDS = ["note", "rect", "ellipse", "diamond"]

// Items carry a theme role, not a hex colour, so a board follows the desktop
// theme instead of fighting it. The shell exposes these four.
var TINTS = ["foreground", "accent", "urgent", "muted"]

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

var KEY_HELP = [
  ["n", "new note beside the selected one"],
  ["r / e", "new box / ellipse"],
  ["s", "cycle shape: note, box, ellipse, diamond"],
  ["x", "connect: press on one, then on another"],
  ["X", "remove every connector on this item"],
  ["u / ctrl+r", "undo / redo"],
  ["enter / i", "type in the selected item"],
  ["esc", "back out, then close the board"],
  ["h j k l", "move the selection around"],
  ["H J K L", "push the selected item"],
  ["tab", "cycle through everything"],
  ["d", "delete the selected item"],
  ["c", "change its colour"],
  ["w", "fullscreen or windowed"],
  ["f", "fit the whole board on screen"],
  ["0", "reset the view"],
  ["+ / -", "zoom"],
  ["? / F1", "this list"],
  ["drag", "move an item, or the canvas"],
  ["wheel", "zoom at the pointer"]
]

// ---------------------------------------------------------------- marshalling
// One shape in, one shape out. The file, the undo stack and the models all
// speak this, so there is a single definition of what an item is.

function itemRows(items) {
  var out = []
  for (var i = 0; i < items.count; i++) {
    var n = items.get(i)
    out.push({ id: n.iid, kind: n.kind, x: n.ix, y: n.iy, w: n.iw, h: n.ih, tint: n.itint, text: n.itext })
  }
  return out
}

function linkRows(links) {
  var out = []
  for (var i = 0; i < links.count; i++) out.push({ from: links.get(i).lfrom, to: links.get(i).lto })
  return out
}

function fillItems(items, rows) {
  items.clear()
  if (!rows) return
  var nextId = 1
  for (var i = 0; i < rows.length; i++) {
    var n = rows[i]
    items.append({
      iid: n.id ? n.id : nextId++,
      kind: n.kind ? n.kind : "note",
      ix: n.x || 0,
      iy: n.y || 0,
      iw: Math.max(MIN_SIZE, n.w || 180),
      ih: Math.max(MIN_SIZE, n.h || 140),
      itint: normalizeTint(n.tint || n.color),
      itext: n.text || ""
    })
  }
}

// Connectors reference ids, so one whose ends did not survive is dropped
// rather than left dangling.
function fillLinks(links, items, rows) {
  links.clear()
  if (!rows) return
  for (var i = 0; i < rows.length; i++) {
    var l = rows[i]
    if (indexOfId(items, l.from) >= 0 && indexOfId(items, l.to) >= 0)
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
  var id = stored ? stored : 1
  for (var i = 0; i < items.count; i++) id = Math.max(id, items.get(i).iid + 1)
  return id
}

// A v1 board stored a flat notes[] with no ids or kinds.
function readFile(raw) {
  var parsed
  try { parsed = JSON.parse(raw) } catch (e) { return null }
  if (!parsed) return null
  return {
    windowMode: parsed.windowMode === true,
    items: parsed.items ? parsed.items : (parsed.notes ? parsed.notes : []),
    links: parsed.links ? parsed.links : [],
    nextId: parsed.nextId ? parsed.nextId : 1
  }
}

function writeFile(items, links, nextId, windowMode) {
  return JSON.stringify({
    version: 3,
    windowMode: windowMode,
    nextId: nextId,
    items: itemRows(items),
    links: linkRows(links)
  }, null, 2) + "\n"
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
function nearest(items, fromIndex, dx, dy) {
  if (fromIndex < 0 || fromIndex >= items.count) return -1
  var from = items.get(fromIndex)
  var fx = from.ix + from.iw / 2
  var fy = from.iy + from.ih / 2
  var best = -1
  var bestScore = Infinity
  for (var i = 0; i < items.count; i++) {
    if (i === fromIndex) continue
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

// Where a connector meets an item: walk from its centre toward the other end
// until we cross the bounding box.
function edgePoint(it, cx, cy, tx, ty) {
  var dx = tx - cx
  var dy = ty - cy
  if (dx === 0 && dy === 0) return { x: cx, y: cy }
  var scale = Math.min(
    dx === 0 ? Infinity : (it.iw / 2) / Math.abs(dx),
    dy === 0 ? Infinity : (it.ih / 2) / Math.abs(dy))
  return { x: cx + dx * scale, y: cy + dy * scale }
}

function cycle(list, current) {
  var i = list.indexOf(current)
  return list[(i + 1) % list.length]
}
