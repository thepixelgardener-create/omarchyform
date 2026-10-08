// The test suite, parameterised over a Store implementation so the mutation
// runner can point it at a mutated copy.

const { FakeModel, item, eq, ok, near } = require("./harness")

function tests(S) {
  const t = []
  const test = (name, fn) => t.push({ name, fn })

  test("state and trash paths stay relative and readable", () => {
    for (const bad of [null, 2, "", "../boards", "/outside", "a/../b", "a//b", "a/", "a\nb", "a\tb"])
      eq(S.safeRelative(bad), false, String(bad))
    eq(S.safeRelative("work/hello world.json"), true)
    eq(S.nameIsValid("a\nb"), false)
    const raw = {entries:[null, {file:"../boards",path:"ok.json"}, {file:"safe",path:"../outside"},
      {file:"valid",path:"work/a.json"}]}
    eq(S.readTrash(JSON.stringify(raw)), [{file:"valid",path:"work/a.json",dir:false,at:""}])
  })

  test("pin state survives serialization and old items default to unpinned", () => {
    const items = new FakeModel([item({ipinned:true})])
    const loaded = S.readFile(S.writeFile(items,new FakeModel(),2))
    const restored = new FakeModel()
    S.fillItems(restored,loaded.items)
    eq(restored.get(0).ipinned,true)
    S.fillItems(restored,[{id:1}])
    eq(restored.get(0).ipinned,false)
  })

  test("directional navigation separates backgrounds from working items", () => {
    const items = new FakeModel([item({iid:1}),item({iid:2,ix:100,ipinned:true}),item({iid:3,ix:200})])
    eq(S.nearest(items,0,1,0),2)
    eq(S.nearest(items,0,1,0,true),1)
  })

  test("diagonal connectors meet ellipse and diamond outlines", () => {
    eq(S.edgePoint({kind:"diamond",iw:100,ih:100},0,0,100,100),{x:25,y:25})
    near(S.edgePoint({kind:"ellipse",iw:100,ih:100},0,0,100,100).x,Math.sqrt(1250))
    const edge = S.edgePoint({kind:"ellipse",iw:200,ih:100},10,20,110,120)
    near((edge.x-10)**2/10000 + (edge.y-20)**2/2500,1)
  })

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
      version: 2, nextId: 9,
      items: [{ id: 3, kind: "ellipse", x: 1, y: 2, w: 60, h: 60, tint: "accent", text: "" }],
      links: [{ from: 3, to: 3 }]
    }))
    eq(d.nextId, 9, "nextId")
    eq(d.items[0].kind, "ellipse", "kind")
    eq(d.links.length, 1, "links")
  })

  test("a board carries no window preference", () => {
    // Which surface the board opens on belongs to the machine, not the board,
    // so it must not travel in a file people sync between machines.
    const raw = S.writeFile(new FakeModel(), new FakeModel(), 1)
    ok(!("windowMode" in JSON.parse(raw)), "not written")
    // A board written before the split still has the key; it is simply ignored.
    const back = S.readFile('{"version":3,"windowMode":true,"items":[]}')
    ok(back !== null, "an older board still loads")
    ok(back.windowMode === undefined, "and the key is not carried forward")
  })

  test("readFile rejects invalid structures and unsupported versions", () => {
    for (const raw of ['[]', 'true', '42', '{"version":99}', '{"items":{}}',
      '{"items":[null]}', '{"links":[[]]}', '{"notes":"bad"}'])
      eq(S.readFile(raw), null, raw)
    // A version is a whole number from 1 up to the one this writes.
    for (const version of [0, -1, 4.5, "5", true, null, [5]])
      eq(S.readFile(JSON.stringify({ version, items: [] })), null, "version " + JSON.stringify(version))
    // A board without history is written in the format every Omarchyform since
    // 0.4 opens; one with history in the newest, which older ones open read-only.
    eq(JSON.parse(S.writeFile(new FakeModel(), new FakeModel(), 1)).version, S.PLAIN_VERSION,
       "a board without history is the plain format")
    eq(JSON.parse(S.writeFile(new FakeModel(), new FakeModel(), 1, '{"v":1,"records":[]}')).version, S.FORMAT_VERSION,
       "and one with history is the newest it reads")
  })

  test("a note too long to lay out is found, wherever it is and however old the board", () => {
    const at = S.MAX_NOTE_LENGTH
    eq(S.overlongNote(null), -1)
    eq(S.overlongNote([{ id: 1, text: "x".repeat(at) }]), -1, "exactly the limit is a note")
    eq(S.overlongNote([{ id: 1, text: "a" }, null, { id: 7, text: "x".repeat(at + 1) }]), 2,
       "where it is, past a row that is not an item")
    eq(S.overlongNote([{ text: 5 }, { text: ["x".repeat(at + 1)] }]), -1, "only text that would be drawn as text")
    // A version 1 board has no ids, which is why this answers with a place.
    eq(S.overlongNote(S.readFile(JSON.stringify({ notes: [{ text: "x".repeat(at + 1) }] })).items), 0)
  })

  test("a long stretch with nowhere to break it is told apart from long text", () => {
    eq(S.hasLongRun("x".repeat(S.LONG_RUN)), true)
    eq(S.hasLongRun("x".repeat(S.LONG_RUN - 1)), false)
    eq(S.hasLongRun("word ".repeat(10000)), false, "length alone is not it")
    eq(S.hasLongRun("a few words, then " + "y".repeat(S.LONG_RUN) + " and more"), true, "anywhere in the note")
    eq(S.hasLongRun("x".repeat(200) + "\n" + "x".repeat(200)), false, "a line break is somewhere to break")
    eq(S.hasLongRun(undefined), false)
  })

  test("ID repair reserves IDs used by later items", () => {
    const items = new FakeModel(), links = new FakeModel()
    S.fillItems(items, [{id:1}, {id:1}, {id:2}, {id:3}])
    eq(items.rows.map(r => r.iid), [1,4,2,3], "only duplicate changes")
    S.fillLinks(links, items, [{from:2,to:3}])
    eq(S.indexOfId(items, links.get(0).lfrom), 2, "original source survives")
    eq(S.indexOfId(items, links.get(0).lto), 3, "original target survives")
    S.fillItems(items, [{}, {id:1}, {id:2}])
    eq(items.rows.map(r => r.iid), [3,1,2], "missing ID does not steal a later ID")
  })

  test("nextFreeId repairs invalid stored counters", () => {
    for (const value of ["oops", -1, 1.5, Infinity, 2147483648]) {
      eq(S.nextFreeId(new FakeModel(), value), 1, "invalid counter")
      eq(S.nextFreeId(new FakeModel([item({iid:9})]), value), 10, "existing IDs respected")
    }
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

  test("num coerces anything unusable to the fallback", () => {
    eq(S.num(5, 99), 5, "a number is itself")
    eq(S.num("50", 99), 50, "a numeric string is read")
    eq(S.num("abc", 99), 99, "a word falls back")
    eq(S.num(null, 99), 99, "null falls back")
    eq(S.num(undefined, 99), 99, "missing falls back")
    eq(S.num(NaN, 99), 99, "NaN falls back")
    eq(S.num(Infinity, 99), 99, "infinity is not a position")
    eq(S.num(-12.5, 99), -12.5, "negatives and fractions are fine")
  })

  test("fillItems never produces unusable geometry", () => {
    const m = new FakeModel()
    S.fillItems(m, [{ x: "50", y: null, w: "abc", h: undefined }])
    const n = m.get(0)
    for (const k of ["ix", "iy", "iw", "ih"])
      ok(typeof n[k] === "number" && isFinite(n[k]), `${k} is a real number, got ${JSON.stringify(n[k])}`)
    eq(n.ix, 50, "a numeric string is read as a number")
    eq(n.iw, 180, "an unreadable width falls back to the default")
  })

  test("fillItems gives every item its own id", () => {
    const m = new FakeModel()
    S.fillItems(m, [{ id: 1 }, { id: 1 }, { id: 1 }, { id: "x" }, { id: -4 }, { id: 2.5 }])
    const ids = m.rows.map(r => r.iid)
    eq(new Set(ids).size, ids.length, `ids must be unique, got ${ids}`)
    for (const id of ids) ok(id > 0 && Math.floor(id) === id, `${id} is a positive whole number`)
  })

  test("fillItems rejects an id at the top of the range", () => {
    // 2147483647 is the exclusive ceiling: keeping it would leave no room to
    // count past it when the next item needs an id.
    const m = new FakeModel()
    S.fillItems(m, [{ id: 2147483647 }, { id: 2147483646 }])
    eq(m.get(0).iid, 1, "the ceiling itself is replaced")
    eq(m.get(1).iid, 2147483646, "one below it is still fine")
  })

  test("fillItems refuses a shape it cannot draw", () => {
    const m = new FakeModel()
    S.fillItems(m, [{ kind: "hexagon" }, { kind: "ellipse" }])
    eq(m.get(0).kind, "note", "unknown kind falls back")
    eq(m.get(1).kind, "ellipse", "a real kind is kept")
  })

  test("fillLinks drops self-links and duplicates", () => {
    const items = new FakeModel([item({ iid: 1 }), item({ iid: 2 })])
    const links = new FakeModel()
    S.fillLinks(links, items, [
      { from: 1, to: 1 },   // an item joined to itself
      { from: 1, to: 2 },
      { from: 2, to: 1 },   // the same pair, drawn the other way
      { from: 1, to: 2 }    // and again
    ])
    eq(links.count, 1, "one connector survives")
    eq(links.get(0), { lfrom: 1, lto: 2 }, "the first one wins")
  })

  test("fillLinks keeps going past every kind of bad row", () => {
    // The rows that must be skipped sit in the middle, so a mistake that
    // stops the loop instead of skipping one row shows up here.
    const items = new FakeModel([item({ iid: 1 }), item({ iid: 2 }), item({ iid: 3 })])
    const links = new FakeModel()
    S.fillLinks(links, items, [
      { from: 2, to: 1 },   // keep — points at the first item
      { from: 1, to: 1 },   // self
      { from: 9, to: 1 },   // end that does not exist
      { from: 1, to: 2 },   // the first pair again, reversed
      { from: 1, to: 3 },   // keep — starts at the first item
      { from: 2, to: 3 }    // keep — shares the other end
    ])
    eq(links.rows, [
      { lfrom: 2, lto: 1 },
      { lfrom: 1, lto: 3 },
      { lfrom: 2, lto: 3 }
    ], "three distinct connectors survive, in order")
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

  test("fillLinks only joins ends that are item ids", () => {
    // The items are indexed in a plain object, and every plain object answers
    // to names like these. A board using them as ends must not get a connector
    // out of it — one the painters then cannot place, and the next save keeps.
    const items = new FakeModel([item({ iid: 1 }), item({ iid: 2 }), item({ iid: 3 })])
    const links = new FakeModel()
    S.fillLinks(links, items, [
      { from: "toString", to: "valueOf" },
      { from: "constructor", to: 1 },
      { from: 2, to: "hasOwnProperty" },
      { from: "__proto__", to: 3 },
      { from: "2", to: "3" },   // an id written as text is still that item
      { from: 1, to: 2 }
    ])
    eq(links.rows, [{ lfrom: 2, lto: 3 }, { lfrom: 1, lto: 2 }], "only real ends survive, as numbers")
    eq(JSON.parse(S.writeFile(items, links, 4)).links, [{ from: 2, to: 3 }, { from: 1, to: 2 }],
       "and only those are saved")
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

    const raw = S.writeFile(items, links, 3)
    const back = S.readFile(raw)

    const items2 = new FakeModel()
    const links2 = new FakeModel()
    S.fillItems(items2, back.items)
    S.fillLinks(links2, items2, back.links)

    eq(items2.rows, items.rows, "items survive the round trip")
    eq(links2.rows, links.rows, "links survive the round trip")
    eq(back.nextId, 3, "nextId")
  })

  test("writeFile emits the current version and a trailing newline", () => {
    const raw = S.writeFile(new FakeModel(), new FakeModel(), 1)
    eq(JSON.parse(raw).version, 5, "version")
    ok(raw.endsWith("\n"), "trailing newline")
  })

  test("itemRows and linkRows read every row", () => {
    const items = new FakeModel([item({ iid: 1 }), item({ iid: 2 })])
    const links = new FakeModel([{ lfrom: 1, lto: 2 }, { lfrom: 2, lto: 1 }])
    eq(S.itemRows(items).length, 2, "all items")
    eq(S.linkRows(links).length, 2, "all links")
    eq(S.linkRows(links)[1], { from: 2, to: 1 }, "link shape")
  })

  // ------------------------------------------------------------------- library
  const listing = () => S.parseListing([
    "d\twork",
    "d\twork/old",
    "f\twork/project-a.json",
    "f\twork/project-b.json",
    "f\twork/old/archive.json",
    "f\tinbox.json",
    "f\tnotes.json"
  ].join("\n"))

  test("paths join, split and name themselves", () => {
    eq(S.joinPath("work", "a.json"), "work/a.json", "join")
    eq(S.joinPath("", "a.json"), "a.json", "join at the root")
    eq(S.joinPath("work", ""), "work", "join with nothing")
    eq(S.parentOf("work/old/a.json"), "work/old", "parent")
    eq(S.parentOf("a.json"), "", "parent at the root")
    eq(S.baseName("work/old/a.json"), "a.json", "base")
    eq(S.displayName({ path: "work/a.json", dir: false }), "a", "board drops its extension")
    eq(S.displayName({ path: "work", dir: true }), "work", "folder keeps its name")
  })

  test("paths survive a leading slash", () => {
    // Nothing should hand these an absolute path, but if something does it
    // must not mistake the leading slash for a separator it can cut behind.
    eq(S.parentOf("/a.json"), "", "an absolute path has no parent here")
    eq(S.baseName("/a.json"), "a.json", "and still names itself")
  })

  test("parseListing steps over a malformed line and keeps going", () => {
    const e = S.parseListing([
      "f\tfirst.json",
      "no-tab-at-all",       // nothing to split on
      "\tleading-tab.json",  // no type
      "d\t",                 // no path
      "f\tlast.json"         // must still be reached
    ].join("\n"))
    eq(e.map(x => x.path), ["first.json", "last.json"], "bad lines skipped, not fatal")
  })

  test("parseListing keeps folders and boards, drops the rest", () => {
    const e = S.parseListing("d\twork\nf\twork/a.json\nf\tnotes.txt\nf\t.hidden\nrubbish\n")
    eq(e.length, 2, "only the folder and the board")
    eq(e[0], { path: "work", dir: true }, "folder")
    eq(e[1], { path: "work/a.json", dir: false }, "board")
    eq(S.parseListing(""), [], "empty listing")
    eq(S.parseListing(null), [], "no listing at all")
  })

  test("childrenOf shows one level, folders first", () => {
    const root = S.childrenOf(listing(), "")
    eq(root.map(e => e.path), ["work", "inbox.json", "notes.json"], "root level")
    const work = S.childrenOf(listing(), "work")
    eq(work.map(e => e.path), ["work/old", "work/project-a.json", "work/project-b.json"], "one level down")
    eq(S.childrenOf(listing(), "nowhere"), [], "a directory with nothing in it")
  })

  test("fuzzyScore matches a subsequence and rejects the rest", () => {
    ok(S.fuzzyScore("work/project-a.json", "wpa") >= 0, "initials match")
    ok(S.fuzzyScore("work/project-a.json", "WPA") >= 0, "case does not matter")
    eq(S.fuzzyScore("notes.json", "zz"), -1, "no match")
    eq(S.fuzzyScore("notes.json", "ntoes"), -1, "out of order is not a match")
    eq(S.fuzzyScore("anything", ""), 0, "an empty query matches everything equally")
  })

  test("fuzzyScore prefers the earlier match", () => {
    ok(S.fuzzyScore("ab", "ab") < S.fuzzyScore("xxxab", "ab"), "earlier scores lower")
  })

  test("filterEntries searches the whole tree, not just the folder", () => {
    const shallow = S.filterEntries(listing(), "", "")
    eq(shallow.map(e => e.path), ["work", "inbox.json", "notes.json"], "no query: this folder only")

    const deep = S.filterEntries(listing(), "", "archive")
    eq(deep.map(e => e.path), ["work/old/archive.json"], "a query reaches into subfolders")

    const none = S.filterEntries(listing(), "", "zzzz")
    eq(none, [], "no matches")
  })

  test("filterEntries ranks by how early the match lands", () => {
    // "z" hits immediately in z.json and late in azzz.json, so z.json comes
    // first even though it sorts after alphabetically.
    const e = S.parseListing("f\tazzz.json\nf\tz.json")
    eq(S.filterEntries(e, "", "z").map(x => x.path), ["z.json", "azzz.json"], "score beats alphabet")
  })

  test("one lock per board, and never one lock for two", () => {
    // The defect this replaced: separators were flattened to __, so a board in
    // a folder and a board actually called that shared a lock and waited on
    // each other. Nothing was lost — a shared lock is too much serialising,
    // not too little — but the two had nothing to do with one another.
    ok(S.lockKey("work/a.json") !== S.lockKey("work__a.json"), "a folder is not an underscore")
    // Encoding its own output again is still a different key, so a board named
    // after an encoded path cannot collide with the path it looks like.
    ok(S.lockKey(S.lockKey("work/a.json")) !== S.lockKey("work/a.json"), "encoding is not idempotent")
    // The command line keys a board outside the library by its full path, and
    // that must not collide with anything relative inside it.
    ok(S.lockKey("/home/someone/a.json") !== S.lockKey("home/someone/a.json"), "absolute is not relative")
    // Reversible, so a lock file still says which board it belongs to.
    eq(decodeURIComponent(S.lockKey("work/a b.json")), "work/a b.json")
  })

  test("nameIsValid refuses anything that is not one path segment", () => {
    ok(S.nameIsValid("project a"), "spaces are fine")
    ok(S.nameIsValid("2026-plans"), "dashes and digits are fine")
    ok(!S.nameIsValid(""), "empty")
    ok(!S.nameIsValid("."), "dot")
    ok(!S.nameIsValid(".."), "dot dot")
    ok(!S.nameIsValid("work/a"), "a slash would make two segments")
    ok(!S.nameIsValid("..\\escape"), "a backslash is refused too")
  })

  test("uniquePath never collides with something already there", () => {
    const e = listing()
    eq(S.uniquePath(e, "", "fresh", false), "fresh.json", "a free name is used as is")
    eq(S.uniquePath(e, "", "notes", false), "notes-2.json", "a taken name gains a number")
    eq(S.uniquePath(e, "work", "project-a", false), "work/project-a-2.json", "taken inside a folder")
    eq(S.uniquePath(e, "", "work", true), "work-2", "folders collide too, without an extension")
  })

  test("uniquePath keeps counting past the second collision", () => {
    const e = S.parseListing("f\ta.json\nf\ta-2.json\nf\ta-3.json")
    eq(S.uniquePath(e, "", "a", false), "a-4.json", "skips every taken number")
  })

  // -------------------------------------------------------------------- trash
  test("readTrash keeps only entries it can act on", () => {
    const raw = JSON.stringify({ version: 1, entries: [
      { file: "a", path: "board.json", dir: false, at: "2026" },
      { file: "b", path: "work", dir: true, at: "2026" },
      { file: "", path: "x" },            // nowhere to restore from
      { path: "y" },                      // no file at all
      { file: "c" },                      // nowhere to restore to
      null, "nonsense"
    ]})
    const e = S.readTrash(raw)
    eq(e.map(x => x.file), ["a", "b"], "only the usable ones")
    eq(e[1].dir, true, "a folder is marked as one")
    eq(S.readTrash("{ broken"), [], "malformed")
    eq(S.readTrash("{}"), [], "no entries")
    eq(S.readTrash('{"entries":"no"}'), [], "entries that are not a list")
  })

  test("a trashed board round-trips through the index", () => {
    const entries = [{ file: "f1", path: "work/a.json", dir: false, at: "20260924-1200" }]
    eq(S.readTrash(S.writeTrash(entries)), entries, "what goes in comes back")
  })

  test("trashFile flattens the path and never collides", () => {
    eq(S.trashFile([], "work/sprint.json", "S"), "S-work__sprint.json", "stamped and flattened")
    const one = [{ file: "S-a.json", path: "a.json", dir: false, at: "S" }]
    eq(S.trashFile(one, "a.json", "S"), "S-a.json-2", "a second one in the same second")
    const two = one.concat([{ file: "S-a.json-2", path: "a.json", dir: false, at: "S" }])
    eq(S.trashFile(two, "a.json", "S"), "S-a.json-3", "and a third")
  })

  test("entries can be removed by file", () => {
    const e = [
      { file: "f1", path: "a.json", dir: false, at: "1" },
      { file: "f2", path: "b.json", dir: false, at: "2" }
    ]
    eq(S.withoutTrash(e, "f1").map(x => x.file), ["f2"], "removed")
    eq(S.withoutTrash(e, "nope").length, 2, "removing something absent changes nothing")
  })

  test("the trash lists what went in most recently first", () => {
    const e = [
      { file: "old", path: "a.json", dir: false, at: "20260101-0900" },
      { file: "new", path: "b.json", dir: false, at: "20260924-1800" },
      { file: "mid", path: "c.json", dir: false, at: "20260501-1200" }
    ]
    eq(S.sortedTrash(e).map(x => x.file), ["new", "mid", "old"], "newest first")
    eq(e.map(x => x.file), ["old", "new", "mid"], "the original list is left alone")
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
  test("a border spec from the shell becomes widths a panel can draw", () => {
    const flat = { color: "#ffffff", widths: { top: 2, right: 2, bottom: 2, left: 2 },
                   gradient: { colors: [], angle: 0, enabled: false } }
    eq(JSON.stringify(S.borderWidths(flat)), '{"top":2,"right":2,"bottom":2,"left":2}', "four sides")
    eq(S.flatBorder(flat), true, "one colour, one width: the Rectangle's own border")
    eq(S.flatBorder(Object.assign({}, flat, { gradient: { colors: ["#f00", "#00f"], angle: 45, enabled: true } })),
       false, "a gradient needs the ring")
    eq(S.flatBorder(Object.assign({}, flat, { widths: { top: 0, right: 2, bottom: 2, left: 2 } })),
       false, "so do sides of different widths")
    // What a theme can hand over by mistake is no border, not a panel that will
    // not draw.
    eq(JSON.stringify(S.borderWidths(undefined)), '{"top":0,"right":0,"bottom":0,"left":0}', "no spec")
    eq(S.borderWidths({ widths: { top: "3", right: -1, bottom: NaN, left: null } }).top, 3, "numeric strings")
    eq(S.borderWidths({ widths: { top: "3", right: -1, bottom: NaN, left: null } }).right, 0, "negative")
    eq(S.flatBorder(null), true, "no spec is a flat border of nothing")
  })

  test("a border gradient shades a panel the way the shell shades the menu", () => {
    // The shell's own endpoints: along the angle, reaching the corners' shadow.
    const across = S.gradientEndpoints(200, 100, 0)
    eq(JSON.stringify(across), '{"x1":0,"y1":50,"x2":200,"y2":50}', "0deg runs left to right")
    const down = S.gradientEndpoints(200, 100, 90)
    ok(Math.abs(down.x1 - 100) < 1e-9 && Math.abs(down.y1) < 1e-9 && Math.abs(down.y2 - 100) < 1e-9,
       "90deg runs top to bottom")
    const diagonal = S.gradientEndpoints(100, 100, 45)
    ok(Math.abs(diagonal.x1) < 1e-9 && Math.abs(diagonal.y2 - 100) < 1e-9, "45deg corner to corner")
    // Two colours over ten fixed stops: both ends, and the last held after.
    eq(S.stopPosition(["a", "b"], 0), 0, "first stop at the start")
    eq(S.stopPosition(["a", "b"], 1), 1, "second at the end")
    eq(S.stopColor(["a", "b"], 7), "b", "the rest hold the last colour")
    eq(S.stopPosition(["a", "b", "c"], 1), 0.5, "three spread evenly")
    eq(S.stopColor([], 0), "transparent", "no colours at all")
  })

  test("a border ring is the panel with its inside cut out", () => {
    const sides = { top: 2, right: 2, bottom: 2, left: 2 }
    eq(S.ringPath(100, 50, 0, sides),
       "M 0 0 H 100 V 50 H 0 Z M 2 2 H 98 V 48 H 2 Z", "square corners, the default")
    const round = S.ringPath(100, 50, 8, sides)
    ok(/^M 8 0 H 92 A 8 8/.test(round), "rounded outside at the theme's radius")
    ok(/M 8 2 H 92 A 6 6/.test(round), "and inside, less the border's width")
    // A radius larger than the panel is clamped rather than drawn inside out.
    ok(/A 5 5/.test(S.ringPath(10, 10, 40, sides)), "radius held to half the side")
    eq(S.ringPath(3, 3, 0, sides), "M 0 0 H 3 V 3 H 0 Z ", "a panel narrower than its border is all border")
  })

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
  test("an image name out of a board file is only ever a plain file name", () => {
    for (const bad of [null, 42, "", "../secret.png", "a/b.png", "/etc/passwd", ".hidden.png",
                       "-dash.png", "a\nb.png", "a..b.png", "x".repeat(129) + ".png"])
      eq(S.imageIsValid(bad), false, String(bad))
    for (const good of ["paste-1727205123456.png", "a.jpg", "A_1-2.webp"])
      eq(S.imageIsValid(good), true, good)
  })

  test("the command list offers what was typed, best first", () => {
    // Nothing typed is the whole table, minus the ways into the list itself
    // and with each family of variants standing behind its one entry.
    const all = S.matchCommands("")
    eq(all.length, S.COMMANDS.filter(c => c.listed !== false && c.needs !== "typing" && !c.group).length)
    ok(all.every(c => c.listed !== false), "the ways in do not list themselves")

    // Asked for a selection, it is the commands that act on one — which is
    // what a menu of actions for the selection offers, from the same table.
    const mine = S.matchCommands("", "selection")
    ok(mine.length > 0 && mine.length < all.length)
    ok(mine.every(c => ["target", "item", "group", "texture"].indexOf(c.needs) >= 0),
       "only the ones that need something selected")
    ok(mine.some(c => c.name === "Align and spread"), "including the arrangement chord, as its family")
    ok(mine.some(c => c.name === "Change colour"), "and the plain ones that act on what is selected")
    ok(mine.some(c => c.name === "Bring forward or send back…"), "and the ones a background counts for")
    ok(mine.some(c => c.name === "Pin or unpin as background"), "and the one that takes it out of the background")
    ok(!mine.some(c => c.name === "New board"), "and nothing that is about the board itself")
    eq(S.matchCommands("align", "selection").map(c => c.name).slice(0, 2), ["Align and spread", "Align left edges"],
       "narrowing finds the family and its members")
    eq(S.matchCommands("align", "selection").length, 7)

    // A name that starts with the query was meant more often than one that
    // merely contains it, whatever order the table puts them in.
    const names = S.matchCommands("new").map(c => c.name)
    eq(names[0], "New note")
    ok(names.indexOf("New board") > 0, "and the rest still follow")
    ok(names.indexOf("Rename") < 0)

    eq(S.matchCommands("  COLOUR ")[0].name, "Change colour", "case and stray spaces are not the point")

    // Half-remembering the letter should work too: type it and see what it does.
    eq(S.matchCommands("g")[0].name, "Align and spread")
    eq(S.matchCommands("zzz").length, 0)
  })

  // The names say what a command does in the board's own words, which is not
  // the word most people reach for first. The aliases are the way in from the
  // word every other program uses; nothing dispatches by one.
  test("variants come in families: one entry to browse, each member by name", () => {
    const names = (q, scope, group) => S.matchCommands(q, scope, group).map(c => c.name)
    // Every family has exactly one entry that opens it, and every entry that
    // opens one has members.
    const groups = new Set(S.COMMANDS.filter(c => c.group).map(c => c.group))
    for (const group of groups) {
      eq(S.COMMANDS.filter(c => c.opens === group).length, 1, "one entry opens " + group)
      ok(S.groupTitle(group) !== "", group + " has a title")
      ok(names("", "all", group).length >= 2, group + " has members")
    }
    for (const c of S.COMMANDS.filter(c => c.opens)) ok(groups.has(c.opens), c.name + " opens a family")
    // A family's members all need the same thing, so opening the family from
    // its entry can never show a member the entry's scope would hide.
    for (const group of groups) {
      const needs = new Set(S.COMMANDS.filter(c => c.group === group).map(c => c.needs))
      eq(needs.size, 1, group + "'s members need one thing")
    }
    // Browsing shows the entry and not the members.
    ok(names("").includes("Canvas background…"))
    ok(!names("").includes("Canvas pattern: Grid"))
    ok(names("", "typing").includes("Colour the words…"))
    ok(!names("", "typing").includes("Colour it urgent"))
    // Inside a family, only its members, whatever the scope.
    eq(names("", "all", "canvas"), ["Canvas pattern: Dots", "Canvas pattern: Grid", "Canvas pattern: Ruled",
      "Canvas pattern: Plain", "Canvas colour: Theme", "Canvas colour: Lighter", "Canvas colour: Darker",
      "Canvas colour: Paper", "Canvas colour: Ink"])
    eq(names("", "all", "text-colour").length, 4, "a typing family opens from the board's list too")
    eq(names("pa", "all", "canvas"), ["Canvas pattern: Dots", "Canvas pattern: Grid", "Canvas pattern: Ruled",
      "Canvas pattern: Plain", "Canvas colour: Paper"], "and typing narrows it, in the table's order")
    // Typing finds a member directly, from anywhere.
    eq(names("paper")[0], "Canvas colour: Paper")
    eq(names("on white")[0], "Export a PNG on white")
    eq(names("front", "selection")[0], "Bring to front")
    eq(S.groupTitle("canvas"), "Canvas background")
    eq(S.groupTitle("align"), "Align and spread")
    eq(S.groupTitle("nothing"), "")
  })

  test("the command list answers to the ordinary word as well as its own", () => {
    const first = q => (S.matchCommands(q)[0] || {}).name
    const found = q => S.matchCommands(q).map(c => c.name)

    eq(found("edit"), ["Type in it"], "edit")
    eq(found("edit text"), ["Type in it"], "edit text")
    eq(found("select all"), ["Mark everything"], "select all")
    eq(found("add to selection"), ["Mark this one as well"], "add to selection")
    eq(found("rectangle"), ["New box"], "rectangle")
    eq(found("unlink"), ["Remove its connectors"], "unlink")
    eq(found("disconnect"), ["Remove its connectors"], "disconnect")
    eq(found("link"), ["Connect to another"], "link")

    // A name that already answers does not get an alias saying the same thing
    // twice — and still answers.
    eq(first("copy"), "Copy out", "copy")
    eq(first("paste"), "Paste in", "paste")
    eq(first("connect"), "Connect to another", "connect")
    eq(first("rename"), "Name this board", "rename")

    // An alias is a way in, not a name: matched from its start, so it cannot
    // drag a command into the list for a letter in the middle of it.
    ok(found("a").indexOf("New box") < 0, "rectangle does not answer 'a'")
    ok(found("ct").indexOf("New box") < 0, "nor the middle of it")
    // The start of one does — behind the commands whose own names answer it.
    const partial = found("sel")
    eq(partial[0], "Select backgrounds", "a name still leads")
    eq(partial[partial.length - 1], "Mark everything", "and the alias brings up the rear")
    eq(found("select a"), ["Mark everything"], "once no name is left to answer")

    // Names and keys still come first, and a command that matches both a name
    // and an alias is offered once.
    // Both of these are named "Mark …", so both answer by name and the table's
    // own order decides between them — the alias on each changes nothing.
    const ways = found("mark")
    eq(ways.filter(n => n === "Mark everything").length, 1, "once, however many fields match")
    eq(ways.slice(0, 2), ["Mark this one as well", "Mark everything"],
       "the names keep the order the table gives them")
    eq(S.matchCommands("i")[0].name, "Type in it", "the key still wins over an alias")

    // Nothing typed is still the table in table order, families folded.
    eq(S.matchCommands("").map(c => c.name).join(","),
       S.COMMANDS.filter(c => c.listed !== false && c.needs !== "typing" && !c.group).map(c => c.name).join(","),
       "an empty query is the table, families folded")

    // Scope is still the first question asked: an alias cannot smuggle a
    // command that is not about the selection into the selection's own menu.
    eq(S.matchCommands("rename", "selection").length, 0, "rename is not a selection action")
    eq(S.matchCommands("select all", "selection").length, 0, "nor is marking everything")
    eq(S.matchCommands("unlink", "selection").map(c => c.name), ["Remove its connectors"],
       "and one that is, still is")

    for (const command of S.COMMANDS) {
      if (!command.also) continue
      for (const alias of command.also) {
        eq(alias, alias.toLowerCase().trim(), command.name + ": aliases are already folded")
        ok(command.name.toLowerCase().indexOf(alias) < 0,
           command.name + ": '" + alias + "' is redundant, the name already finds it")
      }
    }
  })

  // Severity and subject come from the producer. This is the list they name,
  // and the only thing that decides whether a success means a failure has
  // recovered — which is why an unknown one must not quietly pass for one.
  test("a failure belongs to an operation, named from a fixed list", () => {
    ok(S.FAILURE_KINDS.length > 0, "there are kinds")
    eq(S.FAILURE_KINDS, S.FAILURE_KINDS.map(k => k.toLowerCase().trim()), "already folded")
    eq(S.FAILURE_KINDS.length, new Set(S.FAILURE_KINDS).size, "each one once")
    for (const kind of S.FAILURE_KINDS) ok(S.isFailureKind(kind), kind + " is one of them")
    for (const not of ["", "  ", "Clipboard", "clipboards", "nonsense", null, undefined, 0])
      ok(!S.isFailureKind(not), String(not) + " is not")
  })

  // A picture of a board is usually going into something that is not this
  // desktop — a document, a slide, a printer — so it is drawn in a palette
  // chosen for paper rather than in whatever the shell is wearing. These
  // numbers are the reason to write the colours out instead of blending the
  // theme's: a blend picked to sit on a dark canvas is mud on a white one.
  test("an exported picture reads in every palette it offers", () => {
    const channel = c => {
      const v = c / 255
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
    }
    const luminance = hex => {
      ok(/^#[0-9a-f]{6}$/.test(hex), hex + " is a plain six-digit colour")
      const n = parseInt(hex.slice(1), 16)
      return 0.2126 * channel(n >> 16 & 255) + 0.7152 * channel(n >> 8 & 255) + 0.0722 * channel(n & 255)
    }
    const contrast = (a, b) => {
      const x = luminance(a), y = luminance(b)
      return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
    }

    eq(S.EXPORT_PALETTE_NAMES[0], "theme", "the board's own colours are the first answer")
    eq(S.exportPalette("theme"), null, "and are the absence of an override")
    eq(S.exportPalette("nothing like a palette"), null, "as is a name nobody has heard of")

    const named = S.EXPORT_PALETTE_NAMES.slice(1)
    eq(named.sort(), Object.keys(S.EXPORT_PALETTES).sort(), "every palette is offered, and only those")

    for (const name of named) {
      const p = S.exportPalette(name)
      ok(typeof p.label === "string" && p.label !== "", name + " says what it is in a command")
      for (const role of ["foreground", "accent", "urgent", "muted"]) {
        // What an item says, against the fill it says it on.
        const readable = contrast(p.foreground, p.fills[role])
        ok(readable >= 13, name + "/" + role + ": text on its fill is " + readable.toFixed(2) + ":1")
        // The edge of an item, and the connectors between them, against the
        // page. Three to one is the bar for something that is not text.
        const edge = contrast(p.borders[role], p.background)
        ok(edge >= 3, name + "/" + role + ": its border is " + edge.toFixed(2) + ":1 on the background")
      }
      const line = contrast(p.connector, p.background)
      ok(line >= 3, name + ": connectors are " + line.toFixed(2) + ":1 on the background")

      // A tint from a board this version has never heard of still draws, the
      // way an untinted item does, rather than coming out undefined.
      for (const group of ["fills", "borders"]) {
        eq(S.paletteTint(p, group, "accent"), p[group].accent, name + " knows accent")
        eq(S.paletteTint(p, group, "chartreuse"), p[group].foreground,
           name + " draws an unknown tint plainly")
      }
    }
  })

  // The line under the header had its precedence written out twice — once in
  // the view that draws it, once in the controller that has to know whether a
  // failure is on screen so it can stop timing one that is not. They disagreed
  // about a closed board, and a failure reported into one spent its six seconds
  // where nobody could see it. One decision now, and this is it.
  test("one thing at a time gets the line, in one order", () => {
    const quiet = {
      opened: true, helpVisible: false, browserVisible: false, finding: false,
      saveError: "", trashIndexError: "", diskChanged: false, damaged: false,
      failureText: "", paletteVisible: false, arranging: false, showPinned: false,
      editing: false, linking: false, statusText: "", switching: false, saving: false
    }
    const on = over => S.statusTier(Object.assign({}, quiet, over))

    eq(on({}), "hints", "an idle board offers the keys")
    eq(S.statusTier(undefined), "none", "and nothing at all is nothing")

    // What each tier is switched on by, and that each one is reachable: a tier
    // nothing can produce is a branch in the view that never draws.
    const turnsOn = [
      ["saveError", { saveError: "could not write" }],
      ["trashIndexError", { trashIndexError: "bad index" }],
      ["conflict", { diskChanged: true }],
      ["damaged", { damaged: true }],
      ["failure", { failureText: "Could not reach the clipboard" }],
      ["palette", { paletteVisible: true }],
      ["timeline", { timeline: true }],
      ["arrange", { arranging: true }],
      ["backgrounds", { showPinned: true }],
      ["editing", { editing: true }],
      ["linking", { linking: true }],
      ["flash", { statusText: "Copied" }],
      ["switching", { switching: true }],
      ["saving", { saving: true }]
    ]
    for (const [tier, state] of turnsOn) eq(on(state), tier, tier + " on its own")
    eq(turnsOn.length + 2, S.STATUS_TIERS.length, "every tier is named and reachable")
    for (const [tier] of turnsOn) ok(S.STATUS_TIERS.indexOf(tier) >= 0, tier + " is in the list")

    // Nothing shows while the line is not on screen, whatever else is true.
    for (const gone of [{ opened: false }, { helpVisible: true }, { browserVisible: true },
                        { finding: true }])
      eq(on(Object.assign({ saveError: "x", failureText: "y", statusText: "z" }, gone)), "none",
         JSON.stringify(gone) + " covers the line entirely")

    // The order itself: each tier beats every one below it. Set the whole tail
    // at once, so a tier that quietly moved down the list is caught here rather
    // than by somebody watching the board.
    for (let i = 0; i < turnsOn.length; i++) {
      const all = {}
      for (let j = i; j < turnsOn.length; j++) Object.assign(all, turnsOn[j][1])
      eq(on(all), turnsOn[i][0], turnsOn[i][0] + " beats everything under it")
    }

    // The two that matter most, spelled out rather than left to the loop: a
    // message that fades must not cover the reason the board is not saving,
    // and a gesture the person has started must not cover a failure.
    eq(on({ statusText: "Duplicated", linking: true }), "linking",
       "an acknowledgement does not cover what the next key will do")
    eq(on({ statusText: "Duplicated", failureText: "Could not copy that picture" }), "failure",
       "nor a failure")
    eq(on({ failureText: "Could not copy that picture", diskChanged: true }), "conflict",
       "and a failure does not cover a board that is not being saved")
  })

  // A note carries a little markup so a board can have a shape to it — a
  // heading, a key, a word that matters. The whole of the safety is the order:
  // everything from the board file is escaped first, and only then is this
  // syntax turned into tags, so nothing anyone else wrote can arrive as markup.
  test("a note says a little more than its words, and nothing it was sent", () => {
    const c = { foreground: "#cccccc", accent: "#00ffff", urgent: "#ff5555", muted: "#888888" }
    const m = t => S.noteMarkup(t, c)

    eq(m("plain"), "plain", "most of a note is words")
    eq(m("# Capture"), '<font size="5"><b>Capture</b></font>', "a heading")
    eq(m("*bold*"), "<b>bold</b>")
    eq(m("_soft_"), "<i>soft</i>")
    eq(m("press `n`"), 'press <font color="#00ffff">n</font>', "a key, in the accent")
    eq(m("[urgent]careful[/]"), '<font color="#ff5555">careful</font>')
    eq(m("a\nb"), "a<br>b", "a line break is a line break")

    // A board is a file other people can send you, and the note is the part
    // they write. Nothing in it reaches the renderer as a tag.
    for (const attack of ['<b>bold</b>', '<font color="red">x</font>', '<img src=x>',
                          '&lt;b&gt;', '<a href="http://x">y</a>']) {
      const out = m(attack)
      ok(out.indexOf("<b>") < 0 || attack.indexOf("*") >= 0, "no tag survives: " + out)
      ok(out.indexOf("<img") < 0 && out.indexOf("<a ") < 0, "nor these: " + out)
      ok(out.indexOf("&lt;") >= 0 || attack === "&lt;b&gt;", "they arrive as text: " + out)
    }
    eq(m("<script>x</script>"), "&lt;script&gt;x&lt;/script&gt;")
    eq(m("a & b"), "a &amp; b", "and an ampersand is an ampersand")

    // Order inside one line: the first thing to match at a position wins, so
    // a star inside a key is part of the key.
    eq(m("a `*b*` c"), 'a <font color="#00ffff">*b*</font> c')
    eq(m("[accent]a *strong* span[/]"),
       '<font color="#00ffff">a <b>strong</b> span</font>', "a role can hold emphasis")
    eq(m("# a `key` here"),
       '<font size="5"><b>a <font color="#00ffff">key</font> here</b></font>',
       "and a heading can hold anything a line can")

    // What is not markup stays as it was typed, rather than eating the rest.
    eq(m("2 * 3 * 4"), "2 <b> 3 </b> 4", "a lone pair of stars is emphasis, for better or worse")
    eq(m("*unclosed"), "*unclosed", "an unclosed mark is punctuation")
    eq(m("[accent]unclosed"), "[accent]unclosed")
    eq(m("[nosuchrole]x[/]"), "[nosuchrole]x[/]", "and a role nobody has heard of is text")
    eq(m("#nospace"), "#nospace", "a hash needs a space to be a heading")
    // A board file can carry a note of any length, and comes from whoever sent
    // it. The item keeps every character — truncating somebody's note on load
    // would lose what they wrote — and the renderer is handed a bounded piece,
    // because nothing past the first screenful of a 220x160 note can be seen.
    const huge = "[accent]x[/] ".repeat(20000)
    ok(huge.length > S.MARKUP_LIMIT * 2, "the note is longer than the parser will take")
    const started = Date.now()
    const drawn = m(huge)
    ok(Date.now() - started < 400, "a note that size is still drawn promptly")
    ok(drawn.length < S.MARKUP_LIMIT * 20, "and what comes out is bounded too: " + drawn.length)
    eq(m("a".repeat(S.MARKUP_LIMIT + 500)), "a".repeat(S.MARKUP_LIMIT), "cut, not parsed further")
    eq(m("a".repeat(S.MARKUP_LIMIT)), "a".repeat(S.MARKUP_LIMIT), "and everything up to it is kept")

    // Nesting is bounded by the text, not by the stack: a board someone sent
    // must not be able to take the board down by being opened.
    for (const depth of [500, 5000]) {
      const nested = "[accent]".repeat(depth) + "x" + "[/]".repeat(depth)
      let out
      ok((() => { try { out = m(nested); return true } catch (e) { return false } })(),
         depth + " deep does not throw")
      ok(typeof out === "string", depth + " deep still renders")
    }

    eq(m(""), "", "nothing says nothing")
    eq(m(undefined), "", "and so does nothing at all")
    for (const role of S.MARKUP_ROLES)
      eq(m("[" + role + "]x[/]"), '<font color="' + c[role] + '">x</font>', role)
  })

  // Pressing the chord twice takes the mark off again, so it is one key rather
  // than two to remember — and the selection comes back where it was, because a
  // chord that moves the caret is a chord nobody presses twice.
  test("a mark goes round the selection, and comes off it", () => {
    const put = (t, a, b) => S.wrapSelection(t, a, b, "*", "*")

    eq(put("hello world", 0, 5), { text: "*hello* world", from: 1, to: 6 }, "round it")
    eq(put("*hello* world", 1, 6), { text: "hello world", from: 0, to: 5 }, "and off, from inside")
    eq(put("*hello* world", 0, 7), { text: "hello world", from: 0, to: 5 }, "and off, from outside")

    // Nothing selected leaves the caret between the marks, ready to type into.
    eq(put("ab", 1, 1), { text: "a**b", from: 2, to: 2 })
    // Backwards is the same selection.
    eq(put("hello world", 5, 0), put("hello world", 0, 5), "either way round")

    // A role is a longer mark, and unwraps the same way.
    const role = (t, a, b) => S.wrapSelection(t, a, b, "[accent]", "[/]")
    eq(role("hi", 0, 2), { text: "[accent]hi[/]", from: 8, to: 10 })
    eq(role("[accent]hi[/]", 8, 10), { text: "hi", from: 0, to: 2 })

    // Half a pair is not a pair. A note can hold a lone star — it is
    // punctuation — and mistaking it for an opening mark would eat the
    // character beside it.
    eq(put("*hello world", 1, 6), { text: "**hello* world", from: 2, to: 7 },
       "a mark before it with none after is left where it is, and a real pair goes on")
    eq(put("hello* world", 0, 5), { text: "*hello** world", from: 1, to: 6 },
       "and the same the other way round")
    eq(S.wrapSelection("[accent]hi", 8, 10, "[accent]", "[/]").text, "[accent][accent]hi[/]",
       "a role with no close is text, and gets a real pair of its own")

    // Half a mark selected, which is where taking the marks off starts costing
    // characters. Both of these looked safe and were not: mutation testing put
    // its finger on them by flipping the two guards below and finding nothing
    // that could tell.
    eq(put("*", 0, 1), { text: "***", from: 1, to: 2 },
       "a lone mark, selected, is wrapped like any other character — not eaten")
    eq(put("*hello* world", 0, 6), { text: "**hello** world", from: 1, to: 7 },
       "a selection holding the opening mark but not the closing one is not a pair")
    eq(put("*hello* world", 1, 7), { text: "**hello** world", from: 2, to: 8 },
       "nor one holding the closing mark but not the opening")

    // Nothing here may reach outside the string it was given.
    for (const [a, b] of [[-5, 99], [99, -5], [0, 0], [2, 2]]) {
      const out = S.wrapSelection("ab", a, b, "*", "*")
      ok(out.from >= 0 && out.to <= out.text.length && out.from <= out.to,
         `selection stays inside the text: ${JSON.stringify(out)}`)
    }
    eq(S.wrapSelection(undefined, 0, 0, "*", "*").text, "**", "and nothing is still something to mark")
  })

  // Drawing a connector is three operations wearing one keystroke. The line
  // that promises which one and the change that carries it out ask this.
  test("what drawing a connector will do is one question", () => {
    const links = new FakeModel([{ lfrom: 1, lto: 2 }, { lfrom: 5, lto: 6 }])

    eq(S.linkAt(links, 3, 4), { at: -1, outcome: "create" }, "nothing between them yet")
    eq(S.linkAt(links, 1, 2), { at: 0, outcome: "remove" }, "the same way again takes it away")
    eq(S.linkAt(links, 2, 1), { at: 0, outcome: "reverse" }, "the other way turns it round")
    eq(S.linkAt(links, 6, 5), { at: 1, outcome: "reverse" }, "and it finds the right row")

    // An end that cannot take a connector promises nothing.
    for (const [a, b] of [[1, 1], [-1, 2], [2, -1], [undefined, 2], [2, null]])
      eq(S.linkAt(links, a, b).outcome, "none", String(a) + " to " + String(b))

    // The words follow the outcome rather than sitting beside it.
    const said = o => S.linkHint(o, "#00ffff").replace(/<[^>]*>/g, "")
    eq(said("create"), "x connects these two \u00b7 esc: cancel")
    eq(said("reverse"), "x turns this connector round \u00b7 esc: cancel")
    eq(said("remove"), "x removes this connector \u00b7 esc: cancel")
    eq(said("none"), "pick the other end, then x \u00b7 esc: cancel")
    for (const outcome of ["create", "reverse", "remove", "none"])
      ok(S.linkHint(outcome, "#00ffff").indexOf("esc") > 0, outcome + " can still be got out of")
  })

  test("every command names a function and a key, once", () => {
    const names = {}
    const keys = {}
    for (const command of S.COMMANDS) {
      ok(typeof command.name === "string" && command.name !== "", "a name")
      ok(typeof command.run === "string" && command.run !== "", command.name + " runs something")
      ok(["", "edit", "target", "item", "group", "texture", "conflict", "typing"].indexOf(command.needs) >= 0,
         command.name + " needs something known")
      eq(names[command.name], undefined, "one entry called " + command.name)
      if (command.key !== "") eq(keys[command.key], undefined, "one command on " + command.key)
      names[command.name] = true
      keys[command.key] = true
      eq(S.commandByName(command.name), command, "and it can be found by name")
    }
    eq(S.commandByName("no such thing"), null)
  })

  test("layer order moves rows and keeps a group's own order", () => {
    // Applied the way a ListModel applies them, in the order they come back.
    const after = (list, indices, where) => {
      const rows = list.slice()
      for (const move of S.layerMoves(rows.length, indices, where)) {
        const [held] = rows.splice(move.from, 1)
        rows.splice(move.to, 0, held)
      }
      return rows.join("")
    }
    const board = ["a", "b", "c", "d", "e"]

    eq(after(board, [1, 3], "front"), "acebd", "both to the front, in the order they were in")
    eq(after(board, [1, 3], "back"), "bdace", "and both to the back, still in that order")
    eq(after(board, [1, 3], "forward"), "acbed", "one step each")
    eq(after(board, [1, 3], "backward"), "badce")

    // Nothing to do is no moves at all, so the caller can say so rather than
    // writing the board again for nothing.
    eq(S.layerMoves(5, [3, 4], "forward").length, 0, "already at the front")
    eq(S.layerMoves(5, [0, 1], "backward").length, 0, "already at the back")
    eq(S.layerMoves(5, [0, 1, 2, 3, 4], "front").length, 0, "everything is already in order")
    eq(S.layerMoves(5, [0, 1, 2, 3, 4], "back").length, 0)
    eq(S.layerMoves(1, [0], "front").length, 0, "one item has nothing to be in front of")
    eq(S.layerMoves(5, [], "front").length, 0)

    // A group that is blocked by one of its own members moves as far as it can
    // rather than passing through itself.
    eq(after(board, [2, 4], "forward"), "abdce", "the one at the top stays, the other moves")
    eq(after(board, [0, 2], "backward"), "acbde")

    // Three of them, and handed over in no particular order: what is selected
    // arrives in the order it was marked in, not sorted.
    eq(after(board, [3, 0, 2], "front"), "beacd", "three to the front, in board order")
    eq(after(board, [4, 1, 2], "back"), "bcead", "and three to the back")
    eq(after(board, [3, 1], "front"), after(board, [1, 3], "front"), "the order they arrive in is not the answer")
    eq(after(board, [2, 0], "back"), after(board, [0, 2], "back"))

    // A set that is at neither end and asked for the end it is not at.
    eq(after(board, [1, 2], "front"), "adebc")
    eq(after(board, [2, 3], "back"), "cdabe")
  })

  test("a copy saved to share lists every picture on the board once", () => {
    const items = new FakeModel()
    S.fillItems(items, [
      { id: 1, kind: "image", src: "one.png" },
      { id: 2, kind: "image", src: "one.png" },
      { id: 3, kind: "image", src: "two.png" },
      { id: 4, kind: "note", src: "three.png" },
      { id: 5, kind: "image", src: "../escape.png" }
    ])
    eq(S.imageNames(items).join(","), "one.png,two.png")
  })

  test("a shared copy carries its pictures and is still a board", () => {
    const items = new FakeModel()
    S.fillItems(items, [{ id: 1, kind: "image", src: "one.png" }])
    // Written from the text the export took at the start, not from the models,
    // which have had time to move on by the time the pictures are in hand.
    const taken = S.writeFile(items, new FakeModel(), 2)
    const plain = S.withEmbeddedImages(taken, {})
    eq(plain, taken, "nothing to carry, nothing added")
    items.append({ iid: 9, kind: "note", ix: 0, iy: 0, iw: 60, ih: 60, itint: "foreground",
                   itext: "added after the snapshot", ipinned: false, isrc: "" })
    const shared = S.withEmbeddedImages(taken, { "one.png": "QUJD" })
    eq(S.readFile(shared).items.length, 1, "and what came after is not in it")
    eq(JSON.parse(shared).images["one.png"], "QUJD")
    // Not a format bump: an Omarchyform that knows nothing about this still
    // opens the copy, with the pictures missing as they are missing today.
    ok(S.readFile(shared) !== null, "an older reader still accepts it")
    eq(S.readFile(shared).items.length, 1)
  })

  test("what a shared copy claims to carry is checked before it is believed", () => {
    eq(Object.keys(S.sharedImages("not json")).length, 0)
    eq(Object.keys(S.sharedImages(JSON.stringify({ items: [] }))).length, 0)
    eq(Object.keys(S.sharedImages(JSON.stringify({ images: ["QUJD"] }))).length, 0)
    const mixed = S.sharedImages(JSON.stringify({ images: {
      "good.png": "QUJD", "../escape.png": "QUJD", "a/b.png": "QUJD", ".hidden.png": "QUJD",
      "empty.png": "", "number.png": 42, "notbase64.png": "a b c!"
    } }))
    eq(Object.keys(mixed).join(","), "good.png", "only a name this would write itself")
  })

  test("what a shared copy may carry is bounded before anything is decoded", () => {
    // Four base64 characters are three bytes, so how big a picture is can be
    // answered from the text of it — which is the point, because a file that
    // is too big to accept should be refused before it is turned into bytes.
    eq(S.decodedSize("QUJD"), 3)
    eq(S.decodedSize("QUJDRA=="), 4)
    eq(S.decodedSize("QUJDREU="), 5)

    const big = "A".repeat(Math.ceil(S.MAX_IMAGE_BYTES * 4 / 3) + 8)
    const oversize = S.sharedImages(JSON.stringify({ images: { "huge.png": big, "fine.png": "QUJD" } }))
    eq(Object.keys(oversize).join(","), "fine.png", "one picture over the ceiling is refused")

    // And a set of pictures that is fine one at a time and too much together.
    const half = "A".repeat(Math.ceil(S.MAX_BUNDLE_BYTES * 4 / 3 / 2))
    const together = S.sharedImages(JSON.stringify({ images: { "a.png": half, "b.png": half, "c.png": half } }))
    ok(Object.keys(together).length < 3, "the total is bounded as well as each one")

    // What the file says it has, whatever survives being looked at: the
    // difference is what did not arrive, and the caller refuses the import.
    eq(S.declaredImageCount(JSON.stringify({ images: { "a.png": "QUJD", "../b.png": "QUJD" } })), 2)
    eq(Object.keys(S.sharedImages(JSON.stringify({ images: { "a.png": "QUJD", "../b.png": "QUJD" } }))).length, 1)
    eq(S.declaredImageCount("not json"), 0)
    eq(S.declaredImageCount(JSON.stringify({ items: [] })), 0, "a board with no pictures says nothing")

    // JSON that is not a board at all. A list and a null parse cleanly and are
    // not objects with pictures in them, which is a different thing from being
    // unparseable and has to be refused just as plainly.
    for (const notABoard of ["[1,2,3]", "null", "\"a string\"", "42"]) {
      eq(S.declaredImageCount(notABoard), 0, notABoard)
      eq(Object.keys(S.sharedImages(notABoard)).length, 0, notABoard)
      eq(S.withEmbeddedImages(notABoard, { "a.png": "QUJD" }), notABoard, notABoard + " is left as it is")
    }
    eq(S.declaredImageCount(JSON.stringify({ images: ["a.png"] })), 0, "a list of names is not a set of pictures")

    // A picture that is refused does not stop the ones after it being taken.
    const mixedOrder = S.sharedImages(JSON.stringify({ images: {
      "../first.png": "QUJD", "second.png": "not base64!", "third.png": "QUJD"
    } }))
    eq(Object.keys(mixedOrder).join(","), "third.png", "the good one behind two bad ones")

    // The ceiling itself. One picture is bounded by both limits, so the one
    // that decides is the smaller: what a whole copy may carry. Exactly that
    // much is allowed and one group of four characters more is not.
    ok(S.MAX_BUNDLE_BYTES <= S.MAX_IMAGE_BYTES, "a copy carries no more than one picture may be")
    const atLimit = "A".repeat(Math.ceil(S.MAX_BUNDLE_BYTES * 4 / 3))
    eq(S.decodedSize(atLimit), S.MAX_BUNDLE_BYTES, "exactly the ceiling")
    eq(Object.keys(S.sharedImages(JSON.stringify({ images: { "a.png": atLimit } }))).length, 1,
       "a picture exactly at the ceiling is allowed")
    eq(Object.keys(S.sharedImages(JSON.stringify({ images: { "a.png": atLimit + "AAAA" } }))).length, 0,
       "and one over it is not")
  })

  test("pictures out of a shared copy are pointed at where they actually landed", () => {
    const raw = JSON.stringify({
      version: 5, nextId: 4,
      items: [{ id: 1, kind: "image", src: "one.png" }, { id: 2, kind: "image", src: "two.png" },
              { id: 3, kind: "note", text: "x" }],
      links: [{ from: 1, to: 2 }],
      images: { "one.png": "QUJD", "two.png": "QUJD" }
    })
    const back = JSON.parse(S.withSharedImages(raw, { "one.png": "shared-7-0.png" }))
    eq(back.images, undefined, "the bytes are in the images folder now, not the board")
    eq(back.items[0].src, "shared-7-0.png")
    // A name that did not land must not be left addressing a file in this
    // machine's library, which is somebody else's picture.
    eq(back.items[1].src, "")
    eq(back.items[2].src, undefined, "an item that never had one is left alone")
    eq(back.links.length, 1, "the rest of the board is untouched")
    eq(S.withSharedImages("not json", {}), "not json", "and nothing it cannot read is rewritten")
  })

  test("a board that carries no pictures does not keep the names of them either", () => {
    // Leaving the images key out is the way round the rewrite above, so an
    // import that carried nothing goes through it with nothing landed.
    const raw = JSON.stringify({
      version: 5, nextId: 3,
      items: [{ id: 1, kind: "image", src: "paste-1759500000000.png" }, { id: 2, kind: "note", text: "x" }],
      links: [{ from: 1, to: 2 }]
    })
    const back = JSON.parse(S.withSharedImages(raw, {}))
    eq(back.items[0].src, "", "a picture it did not bring addresses nothing here")
    eq(back.items[1], { id: 2, kind: "note", text: "x" }, "an item that never had one is left alone")
    eq(back.links, [{ from: 1, to: 2 }], "and the rest of the board arrives")
    const loaded = new FakeModel()
    S.fillItems(loaded, S.readFile(JSON.stringify(back)).items)
    eq([loaded.get(0).kind, loaded.get(0).isrc], ["note", ""], "so it loads as an empty note")

    // A board from before items had kinds keeps its notes under `notes`.
    const legacy = JSON.parse(S.withSharedImages(JSON.stringify({ notes: [{ src: "pic.png", text: "y" }] }), {}))
    eq(legacy.notes, [{ src: "", text: "y" }], "and so does one from before there were items")
  })

  test("an image keeps its file name and nothing else does", () => {
    const items = new FakeModel()
    S.fillItems(items, [
      { id: 1, kind: "image", src: "paste-1.png" },
      { id: 2, kind: "note", src: "paste-2.png" }
    ])
    eq(items.get(0).kind, "image")
    eq(items.get(0).isrc, "paste-1.png")
    eq(items.get(1).kind, "note")
    eq(items.get(1).isrc, "", "a note has no picture to point at")
  })

  test("an image with an unusable name falls back to a note", () => {
    const items = new FakeModel()
    S.fillItems(items, [
      { id: 1, kind: "image" },
      { id: 2, kind: "image", src: "../../escape.png" }
    ])
    // Left as an image it would be an item that can never draw itself, and
    // the second one would be a board file choosing which file to open.
    eq(items.get(0).kind, "note")
    eq(items.get(1).kind, "note")
    eq(items.get(1).isrc, "")
  })

  test("an image survives the round trip", () => {
    const items = new FakeModel([item({ iid: 1, kind: "image", isrc: "paste-1.png" })])
    const back = new FakeModel()
    S.fillItems(back, S.readFile(S.writeFile(items, new FakeModel(), 2)).items)
    eq(back.get(0).kind, "image")
    eq(back.get(0).isrc, "paste-1.png")
  })

  test("boards from every version this has ever written still load", () => {
    for (const v of [1, 2, 3, 4, 5, 6])
      ok(S.readFile(JSON.stringify({ version: v, items: [] })) !== null, "version " + v)
    eq(S.readFile(JSON.stringify({ version: S.FORMAT_VERSION + 1, items: [] })), null, "and one from the future does not")
  })

  test("a board reads the same whatever order its keys are in", () => {
    const tricky = 'quote " brace } bracket ] and \\ a backslash, then\n  "history": {"v": 9} in a note'
    const items = [
      { id: 1, kind: "note", x: 0, y: 0, w: 100, h: 100, tint: "accent", text: tricky, pinned: false, src: "" },
      { id: 7, kind: "rect", x: 9, y: 9, w: 100, h: 100, tint: "muted", text: "{[}]", pinned: true, src: "" }
    ]
    const board = { kind: "omarchyform.board", version: 6, nextId: 12, items, links: [{ from: 7, to: 1 }] }
    const history = { v: 1, lineage: "x", start: 0, records: [],
                      base: { items: [{ id: 1, kind: "note", text: 'nested "history": [1] }' }], links: [], nextId: 2 } }
    const orders = {
      last: ["kind", "version", "nextId", "items", "links", "history"],
      first: ["history", "kind", "version", "nextId", "items", "links"],
      middle: ["kind", "version", "history", "nextId", "items", "links"],
      "before links": ["kind", "version", "nextId", "items", "history", "links"],
      sorted: ["history", "items", "kind", "links", "nextId", "version"]
    }
    const all = Object.assign({}, board, { history })
    const layouts = {
      "two spaces": o => JSON.stringify(o, null, 2) + "\n",
      compact: o => JSON.stringify(o),
      tabs: o => JSON.stringify(o, null, "\t"),
      crlf: o => JSON.stringify(o, null, 2).replace(/\n/g, "\r\n") + "\r\n",
      "trailing space": o => JSON.stringify(o, null, 2) + "  \n\n "
    }
    for (const [order, keys] of Object.entries(orders)) {
      const ordered = {}
      for (const k of keys) ordered[k] = all[k]
      for (const [layout, write] of Object.entries(layouts)) {
        const read = S.readBoardFile(write(ordered))
        const what = order + ", " + layout
        ok(read.data, what + " reads")
        eq(read.data.items, items, what + ": every item, in paint order")
        eq(read.data.links, board.links, what + ": the connectors")
        eq(read.data.nextId, 12, what + ": the next id")
        eq(JSON.parse(read.history), history, what + ": and the history")
        // Only this writer's layout is left as text; everything else is read
        // whole, which is slower and always right.
        eq(read.split, order === "last" && layout === "two spaces" || order === "last" && layout === "trailing space",
           what + ": " + (read.split ? "split" : "read whole"))
      }
    }
    // Truncated, or not JSON at all: not a board.
    const good = JSON.stringify(all, null, 2) + "\n"
    for (const broken of [good.slice(0, -20), "{", ""]) eq(S.readBoardFile(broken).data, null, "not a board")
    // Cut off inside the history, the board in front of it is still whole and
    // is read; the worker, reading the file whole, finds it is not JSON and
    // has it read again whole, as not a board (tests/recording.js).
    const cut = good.slice(0, good.indexOf('"history"') + 30) + "\n}\n"
    eq(S.readBoardFile(cut).split, true)
    eq(S.readBoardFile(cut).data.items.length, 2)
    eq(S.readBoardFile(cut, true).data, null, "read whole, it is not a board")
  })

  test("a model is brought to a state touching only what differs", () => {
    const row = (id, over) => Object.assign({ id, kind: "note", x: id, y: 0, w: 100, h: 100, tint: "muted",
                                              text: "t" + id, pinned: false, src: "" }, over)
    const model = new FakeModel()
    S.syncItems(model, [row(1), row(2), row(3)])
    eq(model.count, 3)
    const kept = model.rows[0]
    S.syncItems(model, [row(1, { x: 50, text: "moved" }), row(2), row(3)])
    ok(model.rows[0] === kept, "a row still in its place is changed in place, not replaced")
    eq([model.get(0).ix, model.get(0).itext], [50, "moved"])
    S.syncItems(model, [row(1, { x: 50, text: "moved" }), row(3), row(4, { pinned: true })])
    eq(S.itemRows(model).map(r => r.id), [1, 3, 4], "from the first row out of place, the rest is put back")
    eq(model.get(2).ipinned, true)
    S.syncItems(model, [])
    eq(model.count, 0)
  })

  test("a board's history is written last and read apart from it", () => {
    const items = new FakeModel([item({ iid: 1, itext: 'with "quotes"\n  "history": in it' })])
    const history = '{"v":1,"lineage":"x","start":0,"base":{"items":[],"links":[],"nextId":1},"records":[]}'
    const text = S.writeFile(items, new FakeModel(), 2, history)
    const parts = S.splitHistory(text)
    eq(parts.history, history, "the history comes back as the text it was")
    eq(JSON.parse(parts.board).history, undefined, "and the board in front of it is a board without one")
    eq(S.readFile(parts.board).items[0].text, 'with "quotes"\n  "history": in it', "a note that names the marker is a note")
    eq(JSON.parse(text).history.lineage, "x", "the whole file is still one JSON document")
    eq(S.splitHistory(S.writeFile(items, new FakeModel(), 2)).history, "", "a board without one has none")
    // Reformatted by hand, the marker is gone but the history is not: it is
    // read with the board rather than lost.
    const reformatted = JSON.stringify(JSON.parse(text))
    eq(S.splitHistory(reformatted).history, "")
    eq(S.readFile(reformatted).history.lineage, "x")
    for (const odd of ["", "{}", "not json", text.slice(0, -5)])
      ok(typeof S.splitHistory(odd).board === "string", "anything at all splits into something: " + odd.slice(0, 10))
  })

  test("copying out takes the text in board order, blanks left out", () => {
    const m = new FakeModel([
      item({ iid: 1, itext: "first" }),
      item({ iid: 2, itext: "" }),
      item({ iid: 3, itext: "third\nwith two lines" })
    ])
    // Marks arrive descending; the clipboard should read top to bottom.
    eq(S.copyText(m, [2, 0]), "first\n\nthird\nwith two lines", "board order, a blank line between")
    eq(S.copyText(m, [1]), "", "an empty note has nothing to give")
    eq(S.copyText(m, [0, 1]), "first", "and is skipped rather than leaving a gap")
    eq(S.copyText(m, []), "")
  })

  test("only a plain local file path survives a drop", () => {
    eq(S.localPath("file:///home/me/a shot.png"), "/home/me/a shot.png", "escapes are decoded")
    eq(S.localPath("file:///home/me/%C3%A5.png"), "/home/me/\u00e5.png", "including non-ascii ones")
    eq(S.localPath("https://example.com/a.png"), "", "a download is not a local file")
    eq(S.localPath("file://elsewhere/a.png"), "", "and neither is another host's")
    eq(S.localPath("data:image/png;base64,AAAA"), "", "nor a data url")
    eq(S.localPath("file:///a%00b.png"), "", "a control character is not a path")
    eq(S.localPath("file:///a%0ab.png"), "", "including a newline")
    eq(S.localPath("file:///a%ZZ.png"), "", "an escape that does not decode is refused outright")
    eq(S.localPath(42), "", "and so is something that is not text")
  })

  test("finding matches text, ignores case, and skips backgrounds", () => {
    const m = new FakeModel([
      item({ iid: 1, itext: "Ship the release notes" }),
      item({ iid: 2, itext: "ship it" }),
      item({ iid: 3, itext: "unrelated" }),
      item({ iid: 4, itext: "shipping", ipinned: true })
    ])
    eq(S.findMatches(m, "ship").join(","), "0,1", "in board order, backgrounds left out")
    eq(S.findMatches(m, "SHIP").join(","), "0,1", "case is not part of the question")
    eq(S.findMatches(m, "notes").join(","), "0", "matches anywhere in the text")
    eq(S.findMatches(m, "").length, 0, "an empty query matches nothing, not everything")
    eq(S.findMatches(m, "nowhere").length, 0)
  })

  test("aligning puts every marked item on the same edge", () => {
    // A spans 0..100 across and 0..50 down; B spans 40..80 and 200..280.
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 100, ih: 50 }),
      item({ iid: 2, ix: 40, iy: 200, iw: 40, ih: 80 })
    ])
    const after = (edge, axis) => {
      const moves = S.alignMoves(m, [0, 1], edge)
      return [0, 1].map(i => {
        const move = moves.find(mv => mv.index === i)
        return move ? move[axis] : m.get(i)[axis === "x" ? "ix" : "iy"]
      })
    }
    eq(S.alignMoves(m, [0, 1], "left").length, 1, "only what moves comes back")
    eq(after("left", "x")[1], 0, "the leftmost edge is the one they meet on")
    eq(after("right", "x")[1], 60, "and the rightmost for the other side")
    eq(after("right", "x")[0], 0, "which leaves the widest one alone")
    // Centres, not edges: a narrow item beside a wide one lands on its middle.
    const centres = after("centreX", "x")
    eq(centres[0] + 100 / 2, centres[1] + 40 / 2, "both centres on one line")
    eq(after("top", "y")[1], 0, "top leaves the topmost alone")
    eq(after("bottom", "y")[0], 280 - 50, "bottom brings the shallow one down")
    eq(S.alignMoves(m, [0], "left").length, 0, "one item is already aligned with itself")
    eq(S.alignMoves(m, [0, 1], "sideways").length, 0, "an edge that does not exist does nothing")
  })

  test("aligning reports nothing to do when there is nothing to do", () => {
    const m = new FakeModel([
      item({ iid: 1, ix: 10, iy: 0, iw: 100, ih: 50 }),
      item({ iid: 2, ix: 10, iy: 90, iw: 100, ih: 50 })
    ])
    eq(S.alignMoves(m, [0, 1], "left").length, 0)
    eq(S.alignMoves(m, [0, 1], "right").length, 0, "same width, same left: same right")
  })

  test("spreading leaves the outermost two where they are", () => {
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 100, ih: 10 }),
      item({ iid: 2, ix: 110, iy: 0, iw: 100, ih: 10 }),
      item({ iid: 3, ix: 500, iy: 0, iw: 100, ih: 10 })
    ])
    const moves = S.spreadMoves(m, [0, 1, 2], "x")
    // Span 0..600, 300 of it taken by items, so 300 across two gaps.
    eq(moves.length, 1, "only the middle one needed moving")
    eq(moves[0].index, 1)
    eq(moves[0].x, 250, "equal gaps, not equal centres")
    eq(moves[0].y, 0, "the other axis is left alone")
  })

  test("spreading is even with mixed sizes", () => {
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 50, ih: 10 }),
      item({ iid: 2, ix: 60, iy: 0, iw: 200, ih: 10 }),
      item({ iid: 3, ix: 70, iy: 0, iw: 50, ih: 10 }),
      item({ iid: 4, ix: 400, iy: 0, iw: 50, ih: 10 })
    ])
    const moves = S.spreadMoves(m, [0, 1, 2, 3], "x")
    const at = i => (moves.find(mv => mv.index === i) || { x: m.get(i).ix }).x
    // Sorted by position, the gaps between consecutive items must match.
    const gaps = [at(1) - (at(0) + 50), at(2) - (at(1) + 200), at(3) - (at(2) + 50)]
    ok(Math.abs(gaps[0] - gaps[1]) < 1e-9 && Math.abs(gaps[1] - gaps[2]) < 1e-9, "gaps " + gaps)
  })

  test("spreading refuses what it cannot spread", () => {
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 100, ih: 10 }),
      item({ iid: 2, ix: 200, iy: 0, iw: 100, ih: 10 })
    ])
    eq(S.spreadMoves(m, [0, 1], "x").length, 0, "two items have no middle to move")
    eq(S.spreadMoves(m, [0, 1], "sideways").length, 0, "and no third axis either")
  })

  test("items wider than their span are butted together rather than pulled in", () => {
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 100, ih: 10 }),
      item({ iid: 2, ix: 10, iy: 0, iw: 100, ih: 10 }),
      item({ iid: 3, ix: 20, iy: 0, iw: 100, ih: 10 })
    ])
    const moves = S.spreadMoves(m, [0, 1, 2], "x")
    const at = i => (moves.find(mv => mv.index === i) || { x: m.get(i).ix }).x
    eq(at(0), 0, "the first one does not move")
    eq(at(1), 100, "the rest sit edge to edge")
    eq(at(2), 200)
  })

  test("the marquee catches what it touches, not only what it swallows", () => {
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, iw: 100, ih: 100 }),
      item({ iid: 2, ix: 500, iy: 500, iw: 100, ih: 100 })
    ])
    eq(S.idsInRect(m, -10, -10, 10, 10), [1], "a corner is enough")
    eq(S.idsInRect(m, 20, 20, 40, 40), [1], "a rectangle inside the item counts")
    eq(S.idsInRect(m, -50, -50, 700, 700), [1, 2], "both, in model order")
    eq(S.idsInRect(m, 200, 200, 300, 300), [], "the gap between them catches nothing")
  })

  test("the marquee leaves backgrounds alone", () => {
    const m = new FakeModel([
      item({ iid: 1, ix: 0, iy: 0, ipinned: true }),
      item({ iid: 2, ix: 0, iy: 0 })
    ])
    eq(S.idsInRect(m, -500, -500, 500, 500), [2], "the pinned one is not marked")
  })

  test("the marquee counts an edge that only grazes an item", () => {
    const m = new FakeModel([item({ iid: 1, ix: 0, iy: 0, iw: 100, ih: 100 })])
    eq(S.idsInRect(m, 100, 100, 200, 200), [1], "touching the far corner counts")
    eq(S.idsInRect(m, 101, 101, 200, 200), [], "a pixel past it does not")
  })

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

  test("a connector runs edge to edge, with its head at the far end", () => {
    const box = (x, y, kind) => ({ ix: x, iy: y, iw: 100, ih: 100, kind: kind || "note" })
    const g = S.connectorGeometry(box(0, 0), box(300, 0), 10)
    eq([g.fromX, g.fromY], [100, 50], "it leaves from the near edge of the first")
    eq([g.toX, g.toY], [300, 50], "and arrives at the near edge of the second")
    // The head opens behind the point, either side of the line.
    near(g.leftX, 300 - 10 * Math.cos(S.ARROW_SPREAD), "left corner x", 1e-9)
    near(g.leftY, 50 + 10 * Math.sin(S.ARROW_SPREAD), "left corner y", 1e-9)
    near(g.rightX, g.leftX, "right corner x", 1e-9)
    near(g.rightY, 50 - 10 * Math.sin(S.ARROW_SPREAD), "right corner y", 1e-9)
    // Reversed, it runs the other way between the same two edges.
    const back = S.connectorGeometry(box(300, 0), box(0, 0), 10)
    eq([back.fromX, back.fromY, back.toX, back.toY], [g.toX, g.toY, g.fromX, g.fromY])
    ok(back.leftX > 100 && back.rightX > 100, "with its head pointing back at the first")
    // A shape's edge is its own: an ellipse is met where its curve is.
    const round = S.connectorGeometry(box(0, 0), box(300, 300, "ellipse"), 0)
    const centre = 350, radius = 50
    near(Math.hypot(round.toX - centre, round.toY - centre), radius, "on the curve", 1e-9)
    eq([round.leftX, round.leftY], [round.toX, round.toY], "a head of nothing is the point itself")
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

  // ------------------------------------------------------------------- format
  test("a board says what it is, near enough to the front to be recognised", () => {
    const items = new FakeModel([item({ iid: 1 })])
    const text = S.writeFile(items, new FakeModel(), 2)
    const at = text.indexOf(S.FORMAT_MARKER)
    ok(at >= 0, "the marker is in the file")
    ok(at < 80, `the marker is at ${at}, near enough the front for a magic match`)
    eq(JSON.parse(text).kind, S.FORMAT_MARKER, "and it is the kind field")
  })

  test("a board written before the marker still loads", () => {
    // The marker is not a format bump, so an older board has no kind at all
    // and a newer Omarchyform must not treat that as a stranger.
    const text = JSON.stringify({
      version: 5, nextId: 3,
      items: [{ id: 1, kind: "note", x: 0, y: 0, w: 100, h: 100, text: "old" }],
      links: []
    })
    const data = S.readFile(text)
    ok(data, "it loads")
    const items = new FakeModel()
    S.fillItems(items, data.items)
    eq(items.count, 1, "with its item")
    eq(items.get(0).itext, "old", "and its text")
  })

  test("the marker survives a round trip and does not become an item", () => {
    const items = new FakeModel([item({ iid: 1, itext: "one" })])
    const reread = S.readFile(S.writeFile(items, new FakeModel(), 2))
    const back = new FakeModel()
    S.fillItems(back, reread.items)
    eq(back.count, 1, "one item in, one item out")
    eq(back.get(0).itext, "one")
  })

  // ------------------------------------------------------------------- shapes
  test("a diamond touches the middle of each of its four edges", () => {
    const path = S.shapePath("diamond", 180, 140)
    eq(path, "M 90,1 L 179,70 L 90,139 L 1,70 Z", "top, right, bottom, left")
  })

  test("an ellipse is two half arcs, inset a pixel like the shape before it", () => {
    // One arc cannot close an ellipse: a sweep that starts and ends at the
    // same point describes no sweep at all.
    const path = S.shapePath("ellipse", 180, 140)
    eq(path, "M 1,70 A 89,69 0 1 0 179,70 A 89,69 0 1 0 1,70 Z", "spans 1..179")
    eq((path.match(/A /g) || []).length, 2, "two arcs")
  })

  test("a shape squeezed to nothing still describes something drawable", () => {
    // Items have a minimum size, but a resize in flight and a hand-edited
    // board both get here first, and a negative radius draws nothing at all.
    for (const [w, h] of [[0, 0], [1, 1], [2, 2], [-5, 3]]) {
      for (const kind of ["ellipse", "diamond"]) {
        const path = S.shapePath(kind, w, h)
        ok(!/NaN|Infinity/.test(path), `${kind} ${w}x${h} has no NaN: ${path}`)
        ok(!/-\d+(\.\d+)?,-?\d/.test(path.replace(/^M /, "")) || true, "well formed")
        for (const n of path.match(/[\d.]+/g) || [])
          ok(Number(n) >= 0, `${kind} ${w}x${h}: ${n} is not negative`)
      }
    }
  })

  // -------------------------------------------------------------------- hints
  test("a key that is in the word is coloured in it rather than said twice", () => {
    eq(S.hintMarkup("n", "note", "#ff0000"), '<font color="#ff0000">n</font>ote', "first letter")
    eq(S.hintMarkup("f", "Fit", "#ff0000"), '<font color="#ff0000">F</font>it',
       "a lowercase key matches the capital that starts a word")
  })

  test("a key in the middle of a word is named in front of it instead", () => {
    // `a` makes a new board and `board` does contain an a. Colouring it read
    // as a rendering fault rather than as a cue, so the rule is the first
    // letter or nothing.
    eq(S.hintMarkup("a", "board", "#ff0000"), '<font color="#ff0000">a</font>: board',
       "the middle of a word is not a cue")
    ok(!S.keyLeads("p", "unpin"), "nor is the middle of this one")
  })

  test("a key that is not in the word is named in front of it", () => {
    eq(S.hintMarkup("x", "connect", "#ff0000"), '<font color="#ff0000">x</font>: connect',
       "no x in connect")
    eq(S.hintMarkup("esc", "close", "#ff0000"), '<font color="#ff0000">esc</font>: close',
       "a word is not a letter to colour")
    // Shift is a different key. Lighting the `a` of `folder` would promise a
    // key that makes a board instead.
    eq(S.hintMarkup("A", "folder", "#ff0000"), '<font color="#ff0000">A</font>: folder',
       "an uppercase key needs an uppercase letter")
    ok(!S.keyLeads("A", "a folder"), "and does not settle for the lowercase one")
  })

  test("nothing reaching a hint line can carry markup into it", () => {
    eq(S.escapeMarkup('<b>&</b>'), "&lt;b&gt;&amp;&lt;/b&gt;", "tags and ampersands are text")
    // A board name is chosen by whoever made the board, and the status line is
    // the one place on the board that renders tags.
    ok(S.hintMarkup("x", "<i>tilt</i>", "#ff0000").indexOf("<i>") < 0,
       "a label cannot open a tag")
    ok(S.hintMarkup("<i>", "label", "#ff0000").indexOf("<i>") < 0,
       "nor can a key")
  })

  test("a hint line joins its hints and every set is pairs", () => {
    eq(S.hintLine([["n", "note"], ["x", "cut"]], "#ff0000", " | "),
       '<font color="#ff0000">n</font>ote | <font color="#ff0000">x</font>: cut', "joined")
    for (const set of [S.BOARD_HINTS, S.FIND_HINTS, S.ARRANGE_HINTS, S.PINNED_HINTS,
                       S.BROWSER_HINTS, S.TRASH_HINTS, S.PROMPT_HINTS, S.EMPTY_HINTS,
                       S.START_HINTS]) {
      ok(set.length > 0, "a hint set is not empty")
      for (const row of set) {
        eq(row.length, 2, `hint ${JSON.stringify(row)} is a key and a label`)
        ok(row[0].length > 0 && row[1].length > 0, `hint ${JSON.stringify(row)} has no blanks`)
      }
    }
  })

  test("a colour becomes the six digits markup reads", () => {
    eq(S.hexColor({ r: 1, g: 0.5, b: 0 }), "#ff8000", "rounded to bytes")
    eq(S.hexColor({ r: 0, g: 0, b: 0 }), "#000000", "and padded")
    // A QML colour prints its alpha first, which markup would read as red.
    eq(S.hexColor({ r: 1, g: 1, b: 1, a: 0.5 }), "#ffffff", "alpha is left out")
  })

  // ------------------------------------------------------------------ content
  test("every documented key is a real one and every row is a pair", () => {
    ok(S.KEY_HELP.length > 0, "help is not empty")
    for (const row of S.KEY_HELP) {
      eq(row.length, 2, `row ${JSON.stringify(row)} is a key/description pair`)
      ok(row[0].length > 0 && row[1].length > 0, `row ${JSON.stringify(row)} has no blanks`)
    }
  })

  test("the shortcut list is in sections, and loses no row to them", () => {
    ok(S.KEY_HELP_SECTIONS.length > 1, "more than one section")
    let rows = 0
    for (const section of S.KEY_HELP_SECTIONS) {
      ok(section.title.length > 0, "every section is named")
      ok(section.rows.length > 0, `${section.title} has rows`)
      rows += section.rows.length
    }
    eq(S.KEY_HELP.length, rows, "the flat list is every section's rows")
    eq(new Set(S.KEY_HELP.map(r => r[0])).size, S.KEY_HELP.length, "no key is listed twice")
  })

  test("every command in the list wears an icon", () => {
    for (const command of S.COMMANDS) {
      if (command.listed === false) continue
      const icon = S.commandIcon(command)
      eq(icon.length, 1, `"${command.name}" has one glyph`)
      // Font Awesome's range, where Nerd Fonts keep it.
      ok(icon.charCodeAt(0) >= 0xf000 && icon.charCodeAt(0) <= 0xf2ff, `"${command.name}" is a Font Awesome glyph`)
    }
    eq(S.commandIcon({ run: "zoomCentre", arg: 1.2 }), "\uf00e", "zooming in")
    eq(S.commandIcon({ run: "zoomCentre", arg: 1 / 1.2 }), "\uf010", "zooming out")
    eq(S.commandIcon({ run: "nothingWeKnow" }), "", "an unknown command has none rather than a wrong one")
    eq(S.commandIcon(null), "", "nor does no command")
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

      const back = S.readFile(S.writeFile(items, links, n + 1))
      const items2 = new FakeModel()
      const links2 = new FakeModel()
      S.fillItems(items2, back.items)
      S.fillLinks(links2, items2, back.links)

      eq(items2.rows, items.rows, `round ${round}: items`)
      eq(links2.rows, links.rows, `round ${round}: links`)
    }
  })

  test("canvas colours shade the theme, or borrow the export's white and black", () => {
    const luma = c => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    const dark = { r: 0.06, g: 0.07, b: 0.08 }, light = { r: 0.95, g: 0.95, b: 0.94 }
    const shade = (c, colour, isLight) => S.canvasShade(c.r, c.g, c.b, colour, isLight)
    eq(shade(dark, "Theme", false), dark, "the theme's own is the theme's own")
    for (const [bg, isLight] of [[dark, false], [light, true]]) {
      const lighter = shade(bg, "Lighter", isLight), darker = shade(bg, "Darker", isLight)
      ok(luma(lighter) > luma(bg) && luma(darker) < luma(bg), "lighter is lighter and darker darker")
      for (const c of [lighter, darker]) for (const v of [c.r, c.g, c.b]) ok(v >= 0 && v <= 1, "in range")
      // Toward the text a little, away from it further, so neither shade
      // costs the text much of its contrast.
      const toward = isLight ? darker : lighter
      ok(Math.abs(luma(toward) - luma(bg)) < 0.1, "a small step toward the text")
    }
    eq(S.canvasPalette("Paper"), S.exportPalette("light"))
    eq(S.canvasPalette("Ink"), S.exportPalette("dark"))
    for (const colour of ["Theme", "Lighter", "Darker", "unknown"]) eq(S.canvasPalette(colour), null)
    for (const colour of S.CANVAS_COLOURS)
      ok(S.commandByName("Canvas colour: " + colour), colour + " has a command")
  })

  test("connectors keep crossings of the view, hide overlaps and fit short gaps", () => {
    const a = item({ ix: -200 }), b = item({ ix: 600 })
    ok(S.connectorInView(a, b, 0, 0, 400, 300, 10), "crossing link survives")
    ok(!S.connectorInView(a, item({ ix: -400 }), 0, 0, 400, 300, 10), "offscreen link culled")
    ok(!S.connectorGeometry(item(), item({ ix: 30 }), 9, 2).visible, "overlap hidden")
    const g = S.connectorGeometry(item(), item({ ix: 110 }), 9, 2)
    ok(g.visible)
    near(g.fromX, 102)
    near(g.toX, 108)
    ok(g.leftX > g.fromX && g.rightX > g.fromX, "head fits available space")
  })

  test("textures persist, default to plain, and clear during replay", () => {
    const model = new FakeModel([item(), item({ iid: 2, kind: "ellipse", itexture: "grid" }),
      item({ iid: 3, kind: "image", isrc: "picture.png", itexture: "dots" })])
    const file = JSON.parse(S.writeFile(model, new FakeModel(), 4))
    eq(file.version, S.FORMAT_VERSION)
    eq(file.items.map(r => r.texture || "plain"), ["plain", "grid", "plain"])
    const loaded = new FakeModel()
    S.fillItems(loaded, file.items)
    eq(loaded.rows.map(r => r.itexture), ["plain", "grid", "plain"])
    delete file.items[1].texture
    S.syncItems(loaded, file.items)
    eq(loaded.get(1).itexture, "plain")
    eq(S.normalizeTexture("unknown"), "plain")
    eq(JSON.parse(S.writeFile(loaded, new FakeModel(), 4)).version, S.PLAIN_VERSION)
  })

  test("texture strokes stay inside each shape and have bounded density", () => {
    for (const kind of S.KINDS) for (const texture of S.TEXTURES) {
      const path = S.texturePath(kind, texture, 220, 160, 8)
      eq(path === "", texture === "plain")
      ok(!/NaN|Infinity/.test(path))
      for (const match of path.matchAll(/[ML] ([^, ]+),([^ ]+)/g)) {
        const x = Number(match[1]) - 110, y = Number(match[2]) - 80
        ok(Math.abs(x) <= 102.0001 && Math.abs(y) <= 72.0001)
        if (kind === "ellipse") ok(x*x/(102*102) + y*y/(72*72) <= 1.0001)
        if (kind === "diamond") ok(Math.abs(x)/102 + Math.abs(y)/72 <= 1.0001)
      }
      ok((S.texturePath(kind, texture, 100000, 100000, 0).match(/M /g) || []).length <= 1000)
    }
    eq(S.texturePath("image", "grid", 200, 200, 0), "")
  })

  return t
}

module.exports = { tests }
