// Minimal test harness: no dependencies, no framework.
// Loads BoardStore.js (which is QML-flavoured JS) into a plain node context.

const { loadStore, RowModel, STORE_PATH } = require("../bin/store")

// The tests have always called it FakeModel, and in a test that is what it is.
const FakeModel = RowModel

function item(over) {
  return Object.assign(
    { iid: 1, kind: "note", ix: 0, iy: 0, iw: 100, ih: 100, itint: "foreground", itexture: "plain", itext: "", ipinned: false, isrc: "" },
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
