#!/usr/bin/env node
// Board marshalling cost at size. A diagnostic, not a pass/fail gate: run it
// before and after a change to persistence and compare the columns.
//
// Loading used to be superlinear because every connector scanned the whole
// item list to resolve its two ends. Watch the load column against the item
// count: it should roughly double when the board doubles, not quadruple.

const { loadStore, FakeModel } = require("./harness")

const S = loadStore()

function board(n) {
  const items = []
  const links = []
  for (let i = 1; i <= n; i++)
    items.push({ id: i, kind: "note", x: i * 10, y: i * 7, w: 180, h: 140, tint: "foreground", text: "note " + i })
  // One connector per item, which is the shape that made the old load quadratic.
  for (let i = 1; i < n; i++) links.push({ from: i, to: i + 1 })
  return { items, links }
}

function time(rounds, fn) {
  fn()                                   // warm
  const start = process.hrtime.bigint()
  for (let i = 0; i < rounds; i++) fn()
  return Number(process.hrtime.bigint() - start) / rounds / 1e6
}

const sizes = process.argv.slice(2).map(Number).filter(n => n > 0)
const plan = sizes.length ? sizes : [10, 100, 500, 1000, 3000]

console.log("items      serialise        load      file")
for (const n of plan) {
  const raw = board(n)
  const items = new FakeModel()
  const links = new FakeModel()
  S.fillItems(items, raw.items)
  S.fillLinks(links, items, raw.links)

  const write = time(20, () => S.writeFile(items, links, n + 1, false))
  const text = S.writeFile(items, links, n + 1, false)
  const read = time(20, () => {
    const data = S.readFile(text)
    const i2 = new FakeModel()
    S.fillItems(i2, data.items)
    const l2 = new FakeModel()
    S.fillLinks(l2, i2, data.links)
  })

  console.log(`${String(n).padStart(5)}  ${write.toFixed(2).padStart(9)} ms  ${read.toFixed(2).padStart(8)} ms  ${(text.length / 1024).toFixed(0).padStart(5)} KB`)
}
