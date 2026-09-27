const fs = require("fs")
const path = require("path")

// Loading BoardStore.js outside QML, and the model it expects to write into.
//
// The board's logic is a `.pragma library` QML script: valid JavaScript with
// one line of QML on the front. Strip that line and it runs anywhere, which is
// how the test suite exercises the very file the plugin loads, and how
// `bin/omarchyform` edits a board with no Qt, no compositor and no display.
//
// Shared by the tests and the command line so there is one loader rather than
// two that drift.

const STORE_PATH = path.join(__dirname, "..", "BoardStore.js")

// `.pragma library` is a QML directive, not JavaScript. Strip it and evaluate
// the rest as a module body so the same file the plugin loads is the file
// under test — no copy to drift out of sync.
function loadStore(source) {
  const src = source !== undefined ? source : fs.readFileSync(STORE_PATH, "utf8")
  const body = src.replace(/^\s*\.pragma\s+library\s*$/m, "")
  // Read off the source rather than listed by hand: a hand-written list means
  // a new Store function is quietly missing from every test until someone
  // remembers this file, which is how idsInRect first arrived unreachable.
  const exported = [
    ...body.matchAll(/^function\s+(\w+)\s*\(/gm),
    ...body.matchAll(/^var\s+(\w+)\s*=/gm)
  ].map(m => m[1])
  const factory = new Function(`${body}\nreturn {${exported.join(",")}}`)
  return factory()
}

// What BoardStore writes into. A QML ListModel where the plugin runs, and
// this where it does not: the same handful of methods, the same semantics.
class RowModel {
  constructor(rows) {
    this.rows = rows ? rows.map(r => Object.assign({}, r)) : []
  }
  get count() { return this.rows.length }
  get(i) { return this.rows[i] }
  append(row) { this.rows.push(Object.assign({}, row)) }
  clear() { this.rows = [] }
  remove(i) { this.rows.splice(i, 1) }
  setProperty(i, role, value) { this.rows[i][role] = value }
}


module.exports = { loadStore, RowModel, STORE_PATH }
