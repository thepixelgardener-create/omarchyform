.pragma library

// The history of a board: the state it started from and every completed edit
// since, in order, so a pane can show the board as it was after any of them.
// Pure, like BoardStore.js: no QML and no side effects, so the plugin, the
// command line and the tests run the same file, and its cost can be measured
// in the engine the board runs in as well as in node.
//
// A state is what a board file holds: items in paint order, connectors, and
// the next id to hand out. A record is the patch from the state before an edit
// to the state after it, keyed by item id, so it stays the size of the edit
// rather than the size of the board:
//
//   d   ids of items removed
//   a   [index, row] of items added, at their place in the paint order after
//   s   [id, {field: value}] for fields that changed
//   x   [id, at, removed, inserted] for a long text that changed in one place
//   o   the paint order after, by id, only when it moved for another reason
//   ld  connectors removed, as [from, to]
//   la  [index, from, to] of connectors added, at their place after
//   lo  the connector order after, only when it moved for another reason
//   n   nextId after, when it changed
//
// Ids are values, never keys. The engine the board runs in stores an object
// whose keys look like numbers as an array, sized to the largest of them, so
// a history keyed by item id took 9s to read on a 3000-item board rather than
// 0.05s — measured by tests/history-bench.js. Rows are looked up in an array
// indexed by id instead, which is what that engine does fast: a Map there made
// playing the same history back four times slower than plain keys had.
//
// Nothing here decides when an edit is complete. That is the transaction's to
// say; this only records what it changed, and plays it back.

var HISTORY_VERSION = 1
// What one board's history may grow to before it is continued in a new board:
// see "History contract and persistence" in docs/splitview-timeline-plan.md.
var MAX_HISTORY_BYTES = 16777216
var MAX_HISTORY_RECORDS = 10000
// Text past this is not read at all: a history this writes is trimmed long
// before it, and parsing one far larger is memory the shell does not have to
// spend to find out it is not one.
var MAX_HISTORY_TEXT = 4 * 16777216
// Edits that continue the record in progress rather than starting one, when
// the next one is the same: typing in one note, a held key moving or resizing.
var MERGING = ["Typing", "Move", "Resize"]
// The longest continuous typing goes without being written and recorded.
var MAX_CHUNK_MS = 5000
// Text at least this long is recorded as the stretch that changed. Typing into
// a long note would otherwise store the whole note again with every pause.
var TEXT_SPLICE_MIN = 64
var ITEM_FIELDS = ["kind", "x", "y", "w", "h", "tint", "text", "pinned", "src"]

// ---------------------------------------------------------------- states
function copyRow(r) {
  return { id: r.id, kind: r.kind, x: r.x, y: r.y, w: r.w, h: r.h, tint: r.tint, text: r.text,
           pinned: r.pinned === true, src: r.src }
}

function copyState(state) {
  var items = []
  for (var i = 0; i < state.items.length; i++) items.push(copyRow(state.items[i]))
  var links = []
  for (var j = 0; j < state.links.length; j++) links.push({ from: state.links[j].from, to: state.links[j].to })
  return { items: items, links: links, nextId: state.nextId }
}

function sameState(a, b) {
  if (!a || !b || a.nextId !== b.nextId) return false
  if (a.items.length !== b.items.length || a.links.length !== b.links.length) return false
  for (var i = 0; i < a.items.length; i++) {
    var p = a.items[i], q = b.items[i]
    if (p.id !== q.id) return false
    for (var f = 0; f < ITEM_FIELDS.length; f++) {
      var name = ITEM_FIELDS[f]
      if (name === "pinned" ? (p.pinned === true) !== (q.pinned === true) : p[name] !== q[name]) return false
    }
  }
  for (var j = 0; j < a.links.length; j++)
    if (a.links[j].from !== b.links[j].from || a.links[j].to !== b.links[j].to) return false
  return true
}

// The form a state is played back in: rows in an array at their id, so a
// patch finds what it changes without a scan. Rows are never changed where
// they are, only replaced, so a copy of this shares every row it did not
// change with the one it was copied from — which is what keeps checkpoints
// cheap.
function working(state) {
  var rows = []
  var order = []
  for (var i = 0; i < state.items.length; i++) {
    var r = copyRow(state.items[i])
    rows[r.id] = r
    order.push(r.id)
  }
  var links = []
  for (var j = 0; j < state.links.length; j++) links.push([state.links[j].from, state.links[j].to])
  return { rows: rows, order: order, links: links, nextId: state.nextId }
}

function copyWorking(w) {
  return { rows: w.rows.slice(), order: w.order.slice(), links: w.links.slice(), nextId: w.nextId }
}

function stateOf(w) {
  var items = []
  for (var i = 0; i < w.order.length; i++) items.push(w.rows[w.order[i]])
  var links = []
  for (var j = 0; j < w.links.length; j++) links.push({ from: w.links[j][0], to: w.links[j][1] })
  return { items: items, links: links, nextId: w.nextId }
}

// ------------------------------------------------------------------ text
function isHigh(code) { return code >= 0xD800 && code <= 0xDBFF }
function isLow(code) { return code >= 0xDC00 && code <= 0xDFFF }

// The one stretch that differs, as [where it starts, how long it was, what it
// is now]. Never cuts a character in two: a lone half of a surrogate pair is
// not something every JSON writer will put in a file.
function textSplice(before, after) {
  var start = 0
  var max = Math.min(before.length, after.length)
  while (start < max && before.charCodeAt(start) === after.charCodeAt(start)) start++
  if (start > 0 && isHigh(before.charCodeAt(start - 1))) start--
  var endA = before.length, endB = after.length
  while (endA > start && endB > start && before.charCodeAt(endA - 1) === after.charCodeAt(endB - 1)) {
    endA--
    endB--
  }
  if (endA < before.length && isLow(before.charCodeAt(endA))) { endA++; endB++ }
  return [start, endA - start, after.slice(start, endB)]
}

function applySplice(text, splice) {
  return text.slice(0, splice[0]) + splice[2] + text.slice(splice[0] + splice[1])
}

// ---------------------------------------------------------------- patches
function linkKey(from, to) { return from + ">" + to }

// What an id can be: a whole number the board could have handed out. Anything
// else is not looked up at all — an array indexed by "length" or by a
// thousand million is not a lookup.
function isId(value) {
  return typeof value === "number" && value >= 1 && value < 2147483647 && Math.floor(value) === value
}

// What turns `before` into `after`, or null when they are the same board.
function diff(before, after) {
  var p = {}
  var was = [], now = []
  for (var i = 0; i < before.items.length; i++) was[before.items[i].id] = before.items[i]
  for (var j = 0; j < after.items.length; j++) now[after.items[j].id] = after.items[j]

  var removed = [], kept = []
  for (var b = 0; b < before.items.length; b++) {
    if (now[before.items[b].id] === undefined) removed.push(before.items[b].id)
    else kept.push(before.items[b].id)
  }
  var added = [], sets = [], splices = []
  for (var a = 0; a < after.items.length; a++) {
    var row = after.items[a]
    var old = was[row.id]
    if (old === undefined) { added.push([a, copyRow(row)]); continue }
    var change = null
    for (var f = 0; f < ITEM_FIELDS.length; f++) {
      var name = ITEM_FIELDS[f]
      var then = name === "pinned" ? old.pinned === true : old[name]
      var value = name === "pinned" ? row.pinned === true : row[name]
      if (then === value) continue
      if (name === "text" && typeof then === "string" && typeof value === "string" && then.length >= TEXT_SPLICE_MIN) {
        var cut = textSplice(then, value)
        splices.push([row.id, cut[0], cut[1], cut[2]])
        continue
      }
      if (!change) change = {}
      change[name] = value
    }
    if (change) sets.push([row.id, change])
  }
  if (removed.length > 0) p.d = removed
  if (added.length > 0) p.a = added
  if (sets.length > 0) p.s = sets
  if (splices.length > 0) p.x = splices
  // The order is written out only when the items that stayed changed places:
  // removing and adding already put everything else where it goes.
  var expected = kept.slice()
  for (var e = 0; e < added.length; e++) expected.splice(added[e][0], 0, added[e][1].id)
  for (var o = 0; o < after.items.length; o++) {
    if (expected[o] === after.items[o].id) continue
    p.o = after.items.map(function (r) { return r.id })
    break
  }

  var wasLink = {}, nowLink = {}
  for (var l = 0; l < before.links.length; l++) wasLink[linkKey(before.links[l].from, before.links[l].to)] = true
  for (var m = 0; m < after.links.length; m++) nowLink[linkKey(after.links[m].from, after.links[m].to)] = true
  var linksGone = [], linksKept = []
  for (var g = 0; g < before.links.length; g++) {
    var bl = before.links[g]
    if (nowLink[linkKey(bl.from, bl.to)] === true) linksKept.push(linkKey(bl.from, bl.to))
    else linksGone.push([bl.from, bl.to])
  }
  var linksNew = []
  for (var k = 0; k < after.links.length; k++) {
    var al = after.links[k]
    if (wasLink[linkKey(al.from, al.to)] !== true) linksNew.push([k, al.from, al.to])
  }
  if (linksGone.length > 0) p.ld = linksGone
  if (linksNew.length > 0) p.la = linksNew
  var linkOrder = linksKept.slice()
  for (var q = 0; q < linksNew.length; q++) linkOrder.splice(linksNew[q][0], 0, linkKey(linksNew[q][1], linksNew[q][2]))
  for (var z = 0; z < after.links.length; z++) {
    if (linkOrder[z] === linkKey(after.links[z].from, after.links[z].to)) continue
    p.lo = after.links.map(function (x) { return [x.from, x.to] })
    break
  }
  if (before.nextId !== after.nextId) p.n = after.nextId

  for (var any in p) return p
  return null
}

// Plays a patch onto a working state, checking each thing it claims as it
// goes: a record that names an item that is not there, or adds one that is, is
// a history that does not describe this board. Answers "" or what was wrong;
// on a wrong answer the working state is part-way and must be thrown away.
function apply(w, p) {
  if (!p || typeof p !== "object") return "a record with no change in it"
  if (p.d !== undefined) {
    if (!Array.isArray(p.d)) return "removals are not a list"
    for (var i = 0; i < p.d.length; i++) {
      if (!isId(p.d[i]) || w.rows[p.d[i]] === undefined) return "removes item " + p.d[i] + ", which is not there"
      w.rows[p.d[i]] = undefined
    }
    w.order = w.order.filter(function (id) { return w.rows[id] !== undefined })
  }
  if (p.a !== undefined) {
    if (!Array.isArray(p.a)) return "additions are not a list"
    for (var a = 0; a < p.a.length; a++) {
      var at = p.a[a][0], row = p.a[a][1]
      if (!row || typeof row !== "object" || !isId(row.id)) return "adds an item with no id"
      if (w.rows[row.id] !== undefined) return "adds item " + row.id + ", which is already there"
      if (typeof at !== "number" || at < 0 || at > w.order.length) return "adds item " + row.id + " out of range"
      w.rows[row.id] = copyRow(row)
      w.order.splice(at, 0, row.id)
    }
  }
  if (p.s !== undefined) {
    if (!Array.isArray(p.s)) return "changes are not a list"
    for (var c = 0; c < p.s.length; c++) {
      var id = p.s[c][0], change = p.s[c][1]
      var old = isId(id) ? w.rows[id] : undefined
      if (old === undefined) return "changes item " + id + ", which is not there"
      if (!change || typeof change !== "object") return "changes item " + id + " to nothing"
      var next = copyRow(old)
      for (var f = 0; f < ITEM_FIELDS.length; f++)
        if (change[ITEM_FIELDS[f]] !== undefined) next[ITEM_FIELDS[f]] = change[ITEM_FIELDS[f]]
      w.rows[id] = next
    }
  }
  if (p.x !== undefined) {
    if (!Array.isArray(p.x)) return "text edits are not a list"
    for (var t = 0; t < p.x.length; t++) {
      var s = p.x[t]
      var was = Array.isArray(s) && isId(s[0]) ? w.rows[s[0]] : undefined
      if (was === undefined) return "edits the text of item " + (Array.isArray(s) ? s[0] : "?") + ", which is not there"
      if (typeof was.text !== "string" || s[1] < 0 || s[2] < 0 || s[1] + s[2] > was.text.length || typeof s[3] !== "string")
        return "edits the text of item " + s[0] + " outside it"
      var edited = copyRow(was)
      edited.text = applySplice(was.text, [s[1], s[2], s[3]])
      w.rows[s[0]] = edited
    }
  }
  if (p.o !== undefined) {
    if (!Array.isArray(p.o) || p.o.length !== w.order.length) return "an order that is not every item"
    var seen = []
    for (var o = 0; o < p.o.length; o++) {
      if (!isId(p.o[o]) || w.rows[p.o[o]] === undefined || seen[p.o[o]] === true) return "an order that is not every item once"
      seen[p.o[o]] = true
    }
    w.order = p.o.slice()
  }
  if (p.ld !== undefined || p.la !== undefined || p.lo !== undefined) {
    var links = w.links
    if (p.ld !== undefined) {
      var drop = {}
      for (var d = 0; d < p.ld.length; d++) drop[linkKey(p.ld[d][0], p.ld[d][1])] = true
      var before = links.length
      links = links.filter(function (l) { return drop[linkKey(l[0], l[1])] !== true })
      if (links.length !== before - p.ld.length) return "removes a connector that is not there"
    } else links = links.slice()
    if (p.la !== undefined) {
      for (var n = 0; n < p.la.length; n++) {
        if (p.la[n][0] < 0 || p.la[n][0] > links.length) return "adds a connector out of range"
        links.splice(p.la[n][0], 0, [p.la[n][1], p.la[n][2]])
      }
    }
    if (p.lo !== undefined) {
      if (!Array.isArray(p.lo) || p.lo.length !== links.length) return "a connector order that is not every connector"
      links = p.lo.map(function (l) { return [l[0], l[1]] })
    }
    for (var k = 0; k < links.length; k++)
      if (!isId(links[k][0]) || !isId(links[k][1]) || w.rows[links[k][0]] === undefined || w.rows[links[k][1]] === undefined)
        return "a connector to an item that is not there"
    w.links = links
  }
  if (p.n !== undefined) {
    if (typeof p.n !== "number" || p.n < 1) return "a next id that cannot be one"
    w.nextId = p.n
  }
  return ""
}

// --------------------------------------------------------------- history
// A new history starts at the state the board is in, and says when.
// `lineage` names this line of edits, so a copy of a board is told apart from
// the board it was copied from even while their records still agree.
function create(state, now, lineage) {
  return { v: HISTORY_VERSION, lineage: String(lineage), start: Math.round(now),
           base: copyState(state), records: [] }
}

// Records the edit from `before` to `after`, or nothing when nothing changed.
// Times are whole seconds after the start: they are for reading, and the order
// comes from the sequence rather than the clock, which can go backwards.
function append(history, before, after, action, now) {
  var p = diff(before, after)
  if (!p) return null
  var last = history.records.length > 0 ? history.records[history.records.length - 1].i : 0
  var record = { i: last + 1, t: Math.max(0, Math.round((now - history.start) / 1000)),
                 a: String(action || "edit"), p: p }
  history.records.push(record)
  return record
}

// The bytes a string takes in a UTF-8 file.
function utf8Length(text) {
  var n = 0
  for (var i = 0; i < text.length; i++) {
    var c = text.charCodeAt(i)
    if (c < 0x80) n += 1
    else if (c < 0x800) n += 2
    else if (isHigh(c) && i + 1 < text.length && isLow(text.charCodeAt(i + 1))) { n += 4; i++ }
    else n += 3
  }
  return n
}

// Whether one more record fits, before it is accepted. The base, every record
// and the punctuation between them are counted, because the limit is on what
// is written to the file, not on what is held.
function room(history, bytesSoFar, record) {
  var size = utf8Length(JSON.stringify(record)) + 1
  if (history.records.length + 1 > MAX_HISTORY_RECORDS) return { fits: false, why: "records", bytes: bytesSoFar }
  if (bytesSoFar + size > MAX_HISTORY_BYTES) return { fits: false, why: "bytes", bytes: bytesSoFar }
  return { fits: true, why: "", bytes: bytesSoFar + size }
}

// ----------------------------------------------------------------- reading
// Everything about a history's shape that can be checked without playing it.
// Cheap enough to do when a board is opened.
function checkShape(h) {
  if (!h || typeof h !== "object" || Array.isArray(h)) return "not a history"
  if (h.v !== HISTORY_VERSION) return h.v > HISTORY_VERSION ? "from a newer Omarchyform" : "not a version this reads"
  if (typeof h.lineage !== "string" || h.lineage === "") return "no lineage"
  if (typeof h.start !== "number") return "no start time"
  if (!h.base || !Array.isArray(h.base.items) || !Array.isArray(h.base.links) || typeof h.base.nextId !== "number")
    return "no state to start from"
  if (!Array.isArray(h.records)) return "no records"
  // Twice the limit: a history is over it from the record that crosses it
  // until the worker has trimmed it, and is written meanwhile. Far beyond it
  // is not a history this wrote, and not worth playing to find out.
  if (h.records.length > 2 * MAX_HISTORY_RECORDS) return "more records than a history keeps"
  var last = 0
  for (var i = 0; i < h.records.length; i++) {
    var r = h.records[i]
    if (!r || typeof r !== "object" || typeof r.i !== "number" || r.i <= last) return "records out of order at " + i
    if (typeof r.a !== "string" || !r.p || typeof r.p !== "object") return "a record with nothing in it at " + i
    last = r.i
  }
  return ""
}

// Plays the whole history and checks that it ends at the board as it is. A
// history that does not is not shown and is not written onto: some other
// writer changed the board without it, or it is damaged.
function verify(h, live) {
  var shape = checkShape(h)
  if (shape !== "") return shape
  var w = working(h.base)
  for (var i = 0; i < h.records.length; i++) {
    var wrong = apply(w, h.records[i].p)
    if (wrong !== "") return "record " + h.records[i].i + " " + wrong
  }
  return sameState(stateOf(w), live) ? "" : "it does not end at the board as it is"
}

// --------------------------------------------------------------- seeking
// Checkpoints for getting to any record without playing from the start: the
// working state every `every` records, sharing the rows it did not change.
// Built a slice at a time, so a long history is indexed between frames rather
// than in one stop: call until it answers true.
// The spacing grows with the board: a checkpoint of a 3000-item board holds
// arrays of that length, and a hundred of them were 31 MiB (gate 3). Seeking
// replays at most `every` records, a few milliseconds either way.
function spacing(h) {
  return Math.max(100, Math.ceil(h.base.items.length / 15))
}

function newIndex(h, every) {
  return { every: Math.max(1, every || spacing(h)), checkpoints: [{ at: 0, w: working(h.base) }],
           w: null, at: 0, done: h.records.length === 0, error: "" }
}

function indexSome(ix, h, budget) {
  if (ix.done) return true
  if (ix.w === null) ix.w = copyWorking(ix.checkpoints[0].w)
  var end = Math.min(h.records.length, ix.at + Math.max(1, budget))
  while (ix.at < end) {
    var wrong = apply(ix.w, h.records[ix.at].p)
    if (wrong !== "") { ix.error = "record " + h.records[ix.at].i + " " + wrong; ix.done = true; return true }
    ix.at++
    if (ix.at % ix.every === 0) ix.checkpoints.push({ at: ix.at, w: copyWorking(ix.w) })
  }
  if (ix.at >= h.records.length) { ix.done = true; ix.w = null }
  return ix.done
}

// The board after `count` records: 0 is where the history starts, and the
// number of records is the board as it is now.
function stateAt(ix, h, count) {
  var k = Math.max(0, Math.min(h.records.length, count))
  var c = ix.checkpoints[Math.min(ix.checkpoints.length - 1, Math.floor(k / ix.every))]
  var w = copyWorking(c.w)
  for (var r = c.at; r < k; r++) apply(w, h.records[r].p)
  return stateOf(w)
}

// ------------------------------------------------------------ as text
// The board holds its history as text and appends to it, rather than holding
// it parsed and writing it out again: see HISTORY_MARKER in BoardStore.js. The
// text is the history's JSON with its records last, so it splits in two at
// where they begin — everything up to "records":[ and the records themselves,
// joined by commas — and a new record is a comma and its own JSON.
var RECORDS_KEY = '"records":['

// A name for a new line of edits: when it began, and enough chance in it that
// two boards started in the same millisecond are still told apart.
function newLineage(now) {
  return Math.round(now).toString(36) + "-" + Math.floor(Math.random() * 2176782336).toString(36)
}

// The text of a new, empty history, up to and including where its records go.
function startText(state, now, lineage) {
  var text = JSON.stringify(create(state, now, lineage))
  return text.slice(0, -2)
}

function joinText(header, records) { return header + records + "]}" }

// A history's text in its two parts, or null when it is not shaped the way
// this writes one. Its records are the last thing in it, and a key cannot
// appear inside a string, so the first match is the key.
function splitText(text) {
  if (typeof text !== "string" || text.slice(-2) !== "]}") return null
  var at = text.indexOf(RECORDS_KEY)
  if (at < 0) return null
  return { header: text.slice(0, at + RECORDS_KEY.length), records: text.slice(at + RECORDS_KEY.length, -2) }
}

// What can be read off the front of a history without parsing its baseline:
// its version, its lineage and when it began. Null when that is not there.
function headerFacts(header) {
  var at = header.indexOf(',"base":')
  if (at < 0) return null
  try {
    var facts = JSON.parse(header.slice(0, at) + "}")
    return facts && typeof facts === "object" ? facts : null
  } catch (e) { return null }
}

// The number of the last record, read off the end of the records. Every
// record is written starting {"i":, and nothing inside one can be: its keys
// are the patch's and an item's, and text is escaped.
function lastNumber(records) {
  var at = records.lastIndexOf('{"i":')
  if (at < 0) return 0
  var n = parseInt(records.slice(at + 5, at + 25), 10)
  return isFinite(n) && n > 0 ? n : 0
}

// --------------------------------------------------------- keeping it small
// Past either limit, the oldest tenth goes at once and the baseline moves to
// where it ended: trimming then happens once in a thousand edits rather than
// on every one. Answers how many records went.
function trim(h) {
  var keepRecords = Math.floor(MAX_HISTORY_RECORDS * 0.9)
  var keepBytes = Math.floor(MAX_HISTORY_BYTES * 0.9)
  var sizes = []
  var total = 0
  for (var i = 0; i < h.records.length; i++) {
    sizes.push(utf8Length(JSON.stringify(h.records[i])) + 1)
    total += sizes[i]
  }
  var drop = 0
  while (drop < h.records.length && (h.records.length - drop > keepRecords || total > keepBytes)) {
    total -= sizes[drop]
    drop++
  }
  if (drop === 0) return 0
  var w = working(h.base)
  for (var r = 0; r < drop; r++) apply(w, h.records[r].p)
  h.base = copyState(stateOf(w))
  h.records = h.records.slice(drop)
  return drop
}

// The size of a history's records as they are written, and how many.
function measure(h) {
  var bytes = 0
  for (var i = 0; i < h.records.length; i++) bytes += utf8Length(JSON.stringify(h.records[i])) + 1
  return { count: h.records.length, bytes: bytes,
           last: h.records.length > 0 ? h.records[h.records.length - 1].i : 0 }
}

// When a history ends somewhere other than the board as it is — the file was
// edited by something that does not keep one — the difference becomes one
// record, labelled for what it is. The steps in between are not invented.
var OUTSIDE = "Changed outside Omarchyform"
function bridge(h, live, now) {
  var w = working(h.base)
  for (var i = 0; i < h.records.length; i++)
    if (apply(w, h.records[i].p) !== "") return null
  return append(h, stateOf(w), live, OUTSIDE, now)
}

// More records arrived after the index was built: carry it on from where it
// stopped rather than build it again. The caller goes on calling indexSome.
function extendIndex(ix, h) {
  if (ix.error !== "" || ix.at >= h.records.length) return
  if (ix.w === null) {
    var last = ix.checkpoints[ix.checkpoints.length - 1]
    ix.w = copyWorking(last.w)
    for (var r = last.at; r < ix.at; r++) apply(ix.w, h.records[r].p)
  }
  ix.done = false
}

// What a step on the timeline is called on the strip: its name, and when it
// was made — the time alone today, the date as well before that.
function stepLabel(record, start, now) {
  if (!record) return "where the history starts"
  var when = new Date(start + record.t * 1000)
  var today = new Date(now)
  var pad = function (n) { return n < 10 ? "0" + n : String(n) }
  var time = pad(when.getHours()) + ":" + pad(when.getMinutes())
  var sameDay = when.getFullYear() === today.getFullYear() && when.getMonth() === today.getMonth()
    && when.getDate() === today.getDate()
  return record.a + " · " + (sameDay ? time
    : when.getFullYear() + "-" + pad(when.getMonth() + 1) + "-" + pad(when.getDate()) + " " + time)
}
