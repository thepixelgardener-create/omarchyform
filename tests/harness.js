// Minimal test harness: no dependencies, no framework.
// Loads BoardStore.js (which is QML-flavoured JS) into a plain node context.

const fs = require("fs")
const path = require("path")

const STORE_PATH = path.join(__dirname, "..", "BoardStore.js")

// `.pragma library` is a QML directive, not JavaScript. Strip it and evaluate
// the rest as a module body so the same file the plugin loads is the file
// under test — no copy to drift out of sync.
function loadStore(source) {
  const src = source !== undefined ? source : fs.readFileSync(STORE_PATH, "utf8")
  const body = src.replace(/^\s*\.pragma\s+library\s*$/m, "")
  const exported = [
    "MIN_SIZE", "TINTS", "LEGACY_SWATCHES", "KINDS", "KEY_HELP", "normalizeTint",
    "itemRows", "linkRows", "fillItems", "fillLinks", "indexOfId", "idIndex",
    "nextFreeId", "num", "readFile", "writeFile", "parseThemeMode", "isLightColor",
    "readTrash", "writeTrash", "trashFile", "trashEntry", "withoutTrash", "sortedTrash",
    "safeRelative", "joinPath", "parentOf", "baseName", "displayName", "parseListing",
    "childrenOf", "fuzzyScore", "filterEntries", "nameIsValid", "uniquePath", "nearest", "bounds", "edgePoint", "cycle"
  ]
  const factory = new Function(`${body}\nreturn {${exported.join(",")}}`)
  return factory()
}

// Stands in for a QML ListModel: the handful of methods BoardStore actually
// uses, with the same semantics.
class FakeModel {
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

function item(over) {
  return Object.assign(
    { iid: 1, kind: "note", ix: 0, iy: 0, iw: 100, ih: 100, itint: "foreground", itext: "", ipinned: false },
    over)
}

class AssertionError extends Error {}

function fail(message) { throw new AssertionError(message) }

function eq(actual, expected, what) {
  const a = JSON.stringify(actual)
  const b = JSON.stringify(expected)
  if (a !== b) fail(`${what || "value"}: expected ${b}, got ${a}`)
}

function ok(cond, what) {
  if (!cond) fail(what || "expected truthy")
}

function near(actual, expected, what, tolerance) {
  const t = tolerance === undefined ? 1e-9 : tolerance
  if (!(Math.abs(actual - expected) <= t))
    fail(`${what || "value"}: expected ~${expected}, got ${actual}`)
}

module.exports = { loadStore, FakeModel, item, eq, ok, near, fail, AssertionError, STORE_PATH }
