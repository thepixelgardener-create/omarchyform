// The test suite, parameterised over a Store implementation so the mutation
// runner can point it at a mutated copy.

const { FakeModel, item, eq, ok, near } = require("./harness")

function tests(S) {
  const t = []
  const test = (name, fn) => t.push({ name, fn })

  // ------------------------------------------------------------------ reading
  test("readFile rejects malformed json", () => {
    eq(S.readFile("{ not json"), null, "malformed")
    eq(S.readFile(""), null, "empty")
    eq(S.readFile("null"), null, "literal null")
  })

  test("readFile migrates a v1 board (notes, no ids, no kinds)", () => {
    const d = S.readFile(JSON.stringify({
      version: 1,
      notes: [{ x: 5, y: 6, w: 180, h: 140, color: "#F7D794", text: "hi" }]
    }))
    eq(d.items.length, 1, "item count")
    eq(d.items[0].text, "hi", "text carried over")
    eq(d.links, [], "v1 has no links")
    eq(d.nextId, 1, "nextId defaults")
  })

  test("readFile passes a v2 board through", () => {
    const d = S.readFile(JSON.stringify({
      version: 2, nextId: 9, windowMode: true,
      items: [{ id: 3, kind: "ellipse", x: 1, y: 2, w: 60, h: 60, tint: "accent", text: "" }],
      links: [{ from: 3, to: 3 }]
    }))
    eq(d.nextId, 9, "nextId")
    eq(d.windowMode, true, "windowMode")
    eq(d.items[0].kind, "ellipse", "kind")
    eq(d.links.length, 1, "links")
  })

  test("windowMode is only true for a real true", () => {
    eq(S.readFile('{"windowMode":true}').windowMode, true, "true")
    eq(S.readFile('{"windowMode":false}').windowMode, false, "false")
    eq(S.readFile('{"windowMode":"yes"}').windowMode, false, "truthy string is not true")
    eq(S.readFile("{}").windowMode, false, "absent")
  })

  // ------------------------------------------------------------------ filling
  test("fillItems assigns ids to rows that lack them", () => {
    const m = new FakeModel()
    S.fillItems(m, [{ x: 0 }, { x: 1 }, { x: 2 }])
    eq(m.rows.map(r => r.iid), [1, 2, 3], "generated ids are unique and ascending")
  })

  test("fillItems keeps ids that are present", () => {
    const m = new FakeModel()
    S.fillItems(m, [{ id: 7, x: 0 }, { id: 9, x: 1 }])
    eq(m.rows.map(r => r.iid), [7, 9], "ids preserved")
  })

  test("fillItems clamps sizes to the minimum", () => {
    const m = new FakeModel()
    S.fillItems(m, [{ w: 1, h: 1 }, { w: 500, h: 400 }])
    eq(m.get(0).iw, S.MIN_SIZE, "tiny width clamped")
    eq(m.get(0).ih, S.MIN_SIZE, "tiny height clamped")
    eq(m.get(1).iw, 500, "large width untouched")
    eq(m.get(1).ih, 400, "large height untouched")
  })

  test("fillItems defaults kind and colour", () => {
    const m = new FakeModel()
    S.fillItems(m, [{}])
    eq(m.get(0).kind, "note", "default kind")
    eq(m.get(0).itint, S.TINTS[0], "default tint")
    eq(m.get(0).itext, "", "default text")
  })

  test("fillItems replaces rather than appends", () => {
    const m = new FakeModel([item({ iid: 99 })])
    S.fillItems(m, [{ id: 1 }])
    eq(m.count, 1, "old rows cleared")
    eq(m.get(0).iid, 1, "new row present")
  })

  test("fillItems on empty input clears the model", () => {
    const m = new FakeModel([item()])
    S.fillItems(m, [])
    eq(m.count, 0, "cleared")
  })

  // ------------------------------------------------------------------- links
  test("fillLinks drops connectors whose ends are gone", () => {
    const items = new FakeModel([item({ iid: 1 }), item({ iid: 2 })])
    const links = new FakeModel()
    S.fillLinks(links, items, [
      { from: 1, to: 2 },   // both present
      { from: 1, to: 42 },  // far end missing
      { from: 42, to: 2 },  // near end missing
      { from: 8, to: 9 }    // both missing
    ])
    eq(links.count, 1, "only the intact connector survives")
    eq(links.get(0), { lfrom: 1, lto: 2 }, "roles mapped")
  })

  test("fillLinks tolerates a board with no links", () => {
    const items = new FakeModel([item({ iid: 1 })])
    const links = new FakeModel([{ lfrom: 1, lto: 1 }])
    S.fillLinks(links, items, undefined)
    eq(links.count, 0, "cleared when absent")
  })

  // ---------------------------------------------------------------- id lookup
  test("indexOfId finds and misses correctly", () => {
    const m = new FakeModel([item({ iid: 4 }), item({ iid: 7 })])
    eq(S.indexOfId(m, 4), 0, "first")
    eq(S.indexOfId(m, 7), 1, "second")
    eq(S.indexOfId(m, 5), -1, "absent")
    eq(S.indexOfId(new FakeModel(), 1), -1, "empty model")
  })

  test("idIndex agrees with indexOfId for every item", () => {
    const m = new FakeModel([item({ iid: 4 }), item({ iid: 7 }), item({ iid: 11 })])
    const map = S.idIndex(m)
    for (const row of m.rows) eq(map[row.iid], S.indexOfId(m, row.iid), `id ${row.iid}`)
    eq(map[999], undefined, "absent id is undefined, not 0")
  })

  test("nextFreeId clears every id in use", () => {
    const m = new FakeModel([item({ iid: 3 }), item({ iid: 11 }), item({ iid: 7 })])
    const id = S.nextFreeId(m, 1)
    ok(id > 11, `expected greater than the highest id, got ${id}`)
    eq(S.nextFreeId(new FakeModel(), 5), 5, "empty model keeps the stored value")
  })

  // ------------------------------------------------------------------ writing
  test("writeFile round-trips a board unchanged", () => {
    const items = new FakeModel([
      item({ iid: 1, kind: "note", ix: 10, iy: 20, iw: 180, ih: 140, itint: "foreground", itext: "a" }),
      item({ iid: 2, kind: "diamond", ix: -5, iy: 7, iw: 160, ih: 110, itint: "accent", itext: "b" })
    ])
    const links = new FakeModel([{ lfrom: 1, lto: 2 }])

    const raw = S.writeFile(items, links, 3, true)
    const back = S.readFile(raw)

    const items2 = new FakeModel()
    const links2 = new FakeModel()
    S.fillItems(items2, back.items)
    S.fillLinks(links2, items2, back.links)

    eq(items2.rows, items.rows, "items survive the round trip")
    eq(links2.rows, links.rows, "links survive the round trip")
    eq(back.nextId, 3, "nextId")
    eq(back.windowMode, true, "windowMode")
  })

  test("writeFile emits version 2 and a trailing newline", () => {
    const raw = S.writeFile(new FakeModel(), new FakeModel(), 1, false)
    eq(JSON.parse(raw).version, 3, "version")
    ok(raw.endsWith("\n"), "trailing newline")
  })

  test("itemRows and linkRows read every row", () => {
    const items = new FakeModel([item({ iid: 1 }), item({ iid: 2 })])
    const links = new FakeModel([{ lfrom: 1, lto: 2 }, { lfrom: 2, lto: 1 }])
    eq(S.itemRows(items).length, 2, "all items")
    eq(S.linkRows(links).length, 2, "all links")
    eq(S.linkRows(links)[1], { from: 2, to: 1 }, "link shape")
  })

  // --------------------------------------------------------------------- tints
  test("normalizeTint passes a real tint straight through", () => {
    for (const t of S.TINTS) eq(S.normalizeTint(t), t, t)
  })

  test("normalizeTint maps a legacy pastel onto a theme role", () => {
    // v2 boards stored hexes. Each must land on a tint, and the palette must
    // still spread across the roles rather than collapsing to one.
    const mapped = S.LEGACY_SWATCHES.map(hex => S.normalizeTint(hex))
    for (let i = 0; i < S.LEGACY_SWATCHES.length; i++)
      ok(S.TINTS.indexOf(mapped[i]) >= 0, `${S.LEGACY_SWATCHES[i]} -> ${mapped[i]} is a real tint`)
    eq(mapped[0], S.TINTS[0], "first pastel takes the first role")
    eq(mapped[1], S.TINTS[1], "second pastel takes the second role")
    ok(new Set(mapped).size > 1, "an old board keeps more than one role")
  })

  test("normalizeTint falls back for anything else", () => {
    eq(S.normalizeTint(""), S.TINTS[0], "empty")
    eq(S.normalizeTint(undefined), S.TINTS[0], "missing")
    eq(S.normalizeTint("#123456"), S.TINTS[0], "an unknown hex")
    eq(S.normalizeTint("chartreuse"), S.TINTS[0], "a name we do not know")
  })

  test("fillItems migrates a legacy colour field", () => {
    const m = new FakeModel()
    S.fillItems(m, [{ color: S.LEGACY_SWATCHES[1] }, { tint: "urgent" }])
    eq(m.get(0).itint, S.normalizeTint(S.LEGACY_SWATCHES[1]), "legacy hex migrated")
    eq(m.get(1).itint, "urgent", "explicit tint preferred")
  })

  // -------------------------------------------------------------------- theme
  test("parseThemeMode reads the mode a theme declares", () => {
    eq(S.parseThemeMode('mode = "light"\naccent = "#205EA6"'), "light", "light")
    eq(S.parseThemeMode('mode = "dark"'), "dark", "dark")
    eq(S.parseThemeMode("mode = dark"), "dark", "unquoted")
    eq(S.parseThemeMode("  mode   =   'light'  "), "light", "loose spacing, single quotes")
  })

  test("parseThemeMode says nothing when the theme does not", () => {
    eq(S.parseThemeMode(""), "", "empty")
    eq(S.parseThemeMode(null), "", "missing file")
    eq(S.parseThemeMode('accent = "#205EA6"'), "", "no mode key")
    eq(S.parseThemeMode('mode = "sepia"'), "", "unrecognised value")
    // A comment mentioning the word must not be mistaken for the key.
    eq(S.parseThemeMode('# mode = "light"'), "", "commented out")
    eq(S.parseThemeMode('lighter_background = "#E6E4D9"'), "", "similar key")
  })

  test("isLightColor separates light backgrounds from dark ones", () => {
    ok(S.isLightColor(1, 1, 1), "white is light")
    ok(!S.isLightColor(0, 0, 0), "black is dark")
    // Real theme backgrounds: flexoki-light #FFFCF0 and tokyo-night #1a1b26.
    ok(S.isLightColor(1.0, 0.988, 0.941), "flexoki-light background")
    ok(!S.isLightColor(0.102, 0.106, 0.149), "tokyo-night background")
    // Green dominates the luminance formula, blue barely registers.
    ok(S.isLightColor(0, 0.8, 0), "saturated green reads light")
    ok(!S.isLightColor(0, 0, 1), "saturated blue reads dark")
  })

  test("isLightColor still counts the channels it weighs least", () => {
    // Green alone leaves this just under the line; blue is what tips it over,
    // so blue has to be added, not ignored or subtracted.
    ok(!S.isLightColor(0, 0.66, 0), "green alone stays dark")
    ok(S.isLightColor(0, 0.66, 1), "the same green plus blue reads light")
    // Likewise red has to count toward the total, not against it.
    ok(!S.isLightColor(0, 0.42, 0), "green alone under the line")
    ok(S.isLightColor(1, 0.42, 0), "red pushes it over")
  })

  test("isLightColor treats mid grey as dark", () => {
    // The weights sum to 1, so 50% grey sits exactly on the threshold. It must
    // fall on the dark side rather than flickering between the two.
    ok(!S.isLightColor(0.5, 0.5, 0.5), "exactly on the threshold is not light")
    ok(S.isLightColor(0.51, 0.51, 0.51), "just above is light")
  })

  // ----------------------------------------------------------------- geometry
  test("nearest picks the item in the direction asked for", () => {
    // left(0) at x=0, right(1) at x=200, above(2) at y=-200
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0 }),
      item({ iid: 2, ix: 200, iy: 0 }),
      item({ iid: 3, ix: 0, iy: -200 })
    ])
    eq(S.nearest(m, 0, 1, 0), 1, "right of the first is the second")
    eq(S.nearest(m, 0, 0, -1), 2, "above the first is the third")
    eq(S.nearest(m, 1, -1, 0), 0, "left of the second is the first")
  })

  test("nearest ignores everything behind you", () => {
    const m = new FakeModel([item({ iid: 1, ix: 0 }), item({ iid: 2, ix: -200 })])
    eq(S.nearest(m, 0, 1, 0), -1, "nothing to the right")
    eq(S.nearest(m, 0, -1, 0), 1, "but there is something to the left")
  })

  test("nearest prefers the aligned item over a closer but offset one", () => {
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0 }),
      item({ iid: 2, ix: 300, iy: 0 }),    // further along, dead ahead
      item({ iid: 3, ix: 260, iy: 400 })   // nearer along, far off-axis
    ])
    eq(S.nearest(m, 0, 1, 0), 1, "off-axis drift is penalised")
  })

  test("nearest never returns the item you started on", () => {
    const m = new FakeModel([item({ iid: 1 })])
    eq(S.nearest(m, 0, 1, 0), -1, "alone on the board")
  })

  test("nearest handles a bad starting index", () => {
    const m = new FakeModel([item()])
    eq(S.nearest(m, -1, 1, 0), -1, "no selection")
    eq(S.nearest(m, 5, 1, 0), -1, "out of range")
  })

  // These pin the arithmetic inside nearest(): without them the centre
  // offsets and the off-axis weight can be changed without any test noticing.
  test("nearest measures from the centre of the item you are on", () => {
    // from spans x 0..200, so its centre is x=100. A candidate centred at
    // x=0 is behind that centre, even though its left edge is not.
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 200, ih: 100 }),
      item({ iid: 2, ix: -50, iy: 0, iw: 100, ih: 100 })
    ])
    eq(S.nearest(m, 0, 1, 0), -1, "candidate behind the centre is not ahead")
  })

  test("nearest measures to the centre of the candidate", () => {
    // from centre x=100; candidate spans 60..160 so its centre x=110 is ahead
    // of it, though its left edge is behind.
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 200, ih: 100 }),
      item({ iid: 2, ix: 60, iy: 0, iw: 100, ih: 100 })
    ])
    eq(S.nearest(m, 0, 1, 0), 1, "candidate just past the centre counts")
  })

  test("nearest measures vertically from the centre too", () => {
    // from centre y=200; candidate centre y=150 is above it.
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 150, iw: 100, ih: 100 }),
      item({ iid: 2, ix: 0, iy: 100, iw: 100, ih: 100 })
    ])
    eq(S.nearest(m, 0, 0, -1), 1, "found going up")
  })

  test("nearest measures vertically to the candidate centre", () => {
    // from centre y=200; candidate centre y=230 is below it.
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 150, iw: 100, ih: 100 }),
      item({ iid: 2, ix: 0, iy: 180, iw: 100, ih: 100 })
    ])
    eq(S.nearest(m, 0, 0, 1), 1, "found going down")
  })

  test("nearest treats an item on the far side as behind you", () => {
    // Going down from centre y=200: the item at centre y=230 is ahead, the
    // one at y=100 is behind and must stay out of the running.
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 150, iw: 100, ih: 100 }),
      item({ iid: 2, ix: 0, iy: 180, iw: 100, ih: 100 }),
      item({ iid: 3, ix: 0, iy: 50, iw: 100, ih: 100 })
    ])
    eq(S.nearest(m, 0, 0, 1), 1, "the one below wins, the one above is excluded")
  })

  test("nearest weighs drift off the axis against distance along it", () => {
    // Dead ahead at 100 beats nearer-but-skewed at 50 with 40 of drift,
    // because drift counts double: 100 < 50 + 80.
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 100, ih: 100 }),
      item({ iid: 2, ix: 100, iy: 0, iw: 100, ih: 100 }),
      item({ iid: 3, ix: 50, iy: 40, iw: 100, ih: 100 })
    ])
    eq(S.nearest(m, 0, 1, 0), 1, "straight ahead wins over near but skewed")
  })

  test("nearest keeps the first of two equally good candidates", () => {
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 100, ih: 100 }),
      item({ iid: 2, ix: 100, iy: 0, iw: 100, ih: 100 }),
      item({ iid: 3, ix: 100, iy: 0, iw: 100, ih: 100 })
    ])
    eq(S.nearest(m, 0, 1, 0), 1, "ties resolve to the earlier item")
  })

  test("bounds covers every corner", () => {
    const m = new FakeModel([
      item({ ix: 10, iy: 20, iw: 100, ih: 100 }),
      item({ ix: -50, iy: 5, iw: 30, ih: 30 })
    ])
    eq(S.bounds(m), { minX: -50, minY: 5, maxX: 110, maxY: 120 }, "bounds")
    eq(S.bounds(new FakeModel()), null, "empty board has no bounds")
  })

  test("edgePoint lands on the box edge, not the centre", () => {
    const it = item({ iw: 100, ih: 100 })
    // straight right from (0,0): should exit at x = +50
    const p = S.edgePoint(it, 0, 0, 500, 0)
    near(p.x, 50, "x on the right edge")
    near(p.y, 0, "y unchanged")

    // straight down
    const q = S.edgePoint(it, 0, 0, 0, 500)
    near(q.x, 0, "x unchanged")
    near(q.y, 50, "y on the bottom edge")

    // straight up is the mirror of straight down
    const r = S.edgePoint(it, 0, 0, 0, -500)
    near(r.y, -50, "y on the top edge")
  })

  test("edgePoint on a diagonal stays inside the box", () => {
    const it = item({ iw: 100, ih: 200 })
    const p = S.edgePoint(it, 0, 0, 1000, 1000)
    ok(Math.abs(p.x) <= 50 + 1e-9, `x within half-width, got ${p.x}`)
    ok(Math.abs(p.y) <= 100 + 1e-9, `y within half-height, got ${p.y}`)
    // the shorter axis is the one that clips
    near(Math.max(Math.abs(p.x) / 50, Math.abs(p.y) / 100), 1, "touches exactly one edge")
  })

  test("edgePoint degenerates safely when both ends coincide", () => {
    const p = S.edgePoint(item(), 7, 9, 7, 9)
    eq(p, { x: 7, y: 9 }, "returns the point itself rather than dividing by zero")
  })

  // -------------------------------------------------------------------- cycle
  test("cycle advances and wraps", () => {
    eq(S.cycle(S.KINDS, "note"), "rect", "advance")
    eq(S.cycle(S.KINDS, S.KINDS[S.KINDS.length - 1]), S.KINDS[0], "wrap")
    eq(S.cycle(S.TINTS, S.TINTS[0]), S.TINTS[1], "tints advance")
  })

  test("cycle recovers from a value that is not in the list", () => {
    eq(S.cycle(S.KINDS, "hexagon"), S.KINDS[0], "unknown falls to the first")
  })

  // ------------------------------------------------------------------ content
  test("every documented key is a real one and every row is a pair", () => {
    ok(S.KEY_HELP.length > 0, "help is not empty")
    for (const row of S.KEY_HELP) {
      eq(row.length, 2, `row ${JSON.stringify(row)} is a key/description pair`)
      ok(row[0].length > 0 && row[1].length > 0, `row ${JSON.stringify(row)} has no blanks`)
    }
  })

  test("kinds and swatches are unique", () => {
    eq(new Set(S.KINDS).size, S.KINDS.length, "kinds unique")
    eq(new Set(S.TINTS).size, S.TINTS.length, "tints unique")
  })

  // ------------------------------------------------------------------ property
  test("property: any random board survives save and load", () => {
    // Deterministic PRNG so a failure is reproducible.
    let seed = 20260923
    const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
    const pick = list => list[Math.floor(rnd() * list.length)]

    for (let round = 0; round < 200; round++) {
      const n = 1 + Math.floor(rnd() * 6)
      const items = new FakeModel()
      for (let i = 0; i < n; i++) {
        items.append(item({
          iid: i + 1,
          kind: pick(S.KINDS),
          ix: Math.floor(rnd() * 2000 - 1000),
          iy: Math.floor(rnd() * 2000 - 1000),
          iw: S.MIN_SIZE + Math.floor(rnd() * 300),
          ih: S.MIN_SIZE + Math.floor(rnd() * 300),
          itint: pick(S.TINTS),
          itext: rnd() < 0.5 ? "" : "text " + round
        }))
      }
      const links = new FakeModel()
      for (let i = 0; i < n - 1; i++)
        if (rnd() < 0.5) links.append({ lfrom: i + 1, lto: i + 2 })

      const back = S.readFile(S.writeFile(items, links, n + 1, false))
      const items2 = new FakeModel()
      const links2 = new FakeModel()
      S.fillItems(items2, back.items)
      S.fillLinks(links2, items2, back.links)

      eq(items2.rows, items.rows, `round ${round}: items`)
      eq(links2.rows, links.rows, `round ${round}: links`)
    }
  })

  return t
}

module.exports = { tests }
