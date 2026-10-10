// The history codec: every edit the board can make is recorded so that playing
// it back gives exactly the board it came from, and anything that does not
// describe the board is refused rather than repaired. The oracle is the
// snapshots themselves: each state the edits passed through is kept whole and
// compared with what the history says it was.
const assert = require('assert/strict')
const fs = require('fs')
const path = require('path')
const { loadStore } = require('../bin/store')
const { random, board, edit, clone, MIXES } = require('./history-fixtures')

const H = loadStore(fs.readFileSync(path.join(__dirname, '..', 'BoardHistory.js'), 'utf8'))

// Plays a session of edits and keeps every state it passed through.
function session(seed, items, edits, mix) {
  const rnd = random(seed)
  let state = board(rnd, items)
  const history = H.create(state, 1700000000000, 'lineage-' + seed)
  const states = [H.copyState(state)]
  const kinds = []
  for (let i = 0; i < edits; i++) {
    const made = edit(rnd, state, mix, states)
    const record = H.append(history, state, made.state, made.kind, 1700000000000 + i * 1500)
    if (record) {
      states.push(H.copyState(made.state))
      kinds.push(made.kind)
    }
    state = made.state
  }
  return { history, states, final: state, kinds }
}

{
  const { history, states } = session(71, 8, 30, Object.keys(MIXES)[0])
  const prefix = JSON.parse(JSON.stringify(history))
  prefix.records = prefix.records.slice(0, 10)
  const ix = H.newIndex(prefix)
  while (!ix.done) H.indexSome(ix, prefix, 10)
  assert.equal(H.extendsHistory(prefix, history, ix), true)
  assert.equal(H.extendsHistory(history, prefix), false, 'a rollback is not an extension')
  for (const dropped of [1, 5, 10]) {
    const trimmed = JSON.parse(JSON.stringify(history))
    trimmed.base = clone(states[dropped])
    trimmed.records = trimmed.records.slice(dropped)
    assert.equal(H.extendsHistory(prefix, trimmed, ix), true, 'a verified shared boundary survives trimming')
    assert.equal(H.extendsHistory(trimmed, history), true, 'restoring older retained steps keeps the shared history')
    trimmed.base.items[0].x += 1
    assert.equal(H.extendsHistory(prefix, trimmed, ix), false, 'the shared state must match')
  }
  const unrelated = JSON.parse(JSON.stringify(history))
  unrelated.base = clone(states[11])
  unrelated.records = unrelated.records.slice(11)
  assert.equal(H.extendsHistory(prefix, unrelated, ix), false, 'without an overlap the old cursor cannot be proved')
  for (const key of ['v', 'lineage', 'start']) {
    const changed = JSON.parse(JSON.stringify(history))
    changed[key] += 1
    assert.equal(H.extendsHistory(prefix, changed, ix), false, key + ' identifies a different history')
  }
  const changed = JSON.parse(JSON.stringify(history))
  changed.records[3].a = 'Rewritten'
  assert.equal(H.extendsHistory(prefix, changed, ix), false, 'retained edits must match as well as their states')
  assert.equal(H.sameData({ b: [1, { x: 2 }], a: 3 }, { a: 3, b: [1, { x: 2 }] }), true)
  assert.equal(H.sameData({ a: undefined }, { b: undefined }), false)
  const empty = H.create(history.base, history.start, history.lineage)
  assert.equal(H.extendsHistory(empty, history), true, 'the original baseline can grow its first records')
  console.log('ok — history: extensions prove the shared state and records, including trimmed prefixes')
}

{
  // Each record turns the state before it into the state after it, exactly,
  // for every kind of edit in every mix.
  for (const mix of Object.keys(MIXES)) {
    for (let seed = 1; seed <= 20; seed++) {
      const rnd = random(seed * 7 + mix.length)
      let state = board(rnd, 40)
      const seen = [clone(state)]
      for (let i = 0; i < 200; i++) {
        const made = edit(rnd, state, mix, seen)
        const patch = H.diff(state, made.state)
        if (patch === null) assert.ok(H.sameState(state, made.state), `${mix}/${seed}/${i}: no patch means no change`)
        else {
          const w = H.working(state)
          assert.equal(H.apply(w, patch), '', `${mix}/${seed}/${i}: ${made.kind} applies cleanly`)
          assert.ok(H.sameState(H.stateOf(w), made.state), `${mix}/${seed}/${i}: ${made.kind} plays back exactly`)
          // Through the file and back: the patch is JSON, and numbers that
          // were keys come back as strings.
          const w2 = H.working(state)
          assert.equal(H.apply(w2, JSON.parse(JSON.stringify(patch))), '')
          assert.ok(H.sameState(H.stateOf(w2), made.state), `${mix}/${seed}/${i}: and through JSON`)
        }
        seen.push(clone(made.state))
        state = made.state
      }
    }
  }
  console.log('ok — history: every edit plays back exactly, through JSON too')
}

{
  // The whole history ends at the board as it is, and any point in it is the
  // board as it was then — however the index was built.
  const s = session(42, 300, 2500, 'mixed')
  assert.equal(H.verify(s.history, s.final), '')
  assert.equal(H.verify(JSON.parse(JSON.stringify(s.history)), s.final), '', 'and after the file')
  for (const every of [1, 7, 100, 1000]) {
    const ix = H.newIndex(s.history, every)
    let calls = 0
    while (!H.indexSome(ix, s.history, 37)) calls++
    assert.equal(ix.error, '')
    for (const at of [0, 1, 2, 99, 100, 101, s.states.length - 2, s.states.length - 1, 1234 % s.states.length])
      assert.ok(H.sameState(H.stateAt(ix, s.history, at), s.states[at]), `every ${every}: the board after ${at} records`)
    // Seeking must not disturb what it seeks from: the same point twice, and
    // a point before it, are still right afterwards.
    assert.ok(H.sameState(H.stateAt(ix, s.history, 500), s.states[500]))
    assert.ok(H.sameState(H.stateAt(ix, s.history, 499), s.states[499]))
    assert.ok(H.sameState(H.stateAt(ix, s.history, 500), s.states[500]))
  }
  console.log('ok — history: any point in a long history is the board as it was')
}

{
  // A history that does not describe the board is refused, with why — never
  // played into something it was not.
  const rnd = random(5)
  const start = board(rnd, 5)
  const h = H.create(start, 0, 'x')
  const changed = clone(start)
  changed.items[0].x += 10
  H.append(h, start, changed, 'move', 1000)
  assert.equal(H.verify(h, changed), '')
  assert.match(H.verify(h, start), /does not end at the board/, 'a board changed without its history')

  const broken = patch => {
    const bad = JSON.parse(JSON.stringify(h))
    bad.records[0].p = patch
    return H.verify(bad, changed)
  }
  assert.match(broken({ d: [99] }), /removes item 99/)
  assert.match(broken({ a: [[0, { id: 1, kind: 'note' }]] }), /already there/)
  assert.match(broken({ a: [[9, { id: 50, kind: 'note' }]] }), /out of range/)
  assert.match(broken({ s: [[77, { x: 1 }]] }), /changes item 77/)
  assert.match(broken({ s: { 1: { x: 1 } } }), /not a list/, 'ids as keys are not the format')
  assert.match(broken({ x: [[1, 500, 3, 'zz']] }), /outside it/)
  assert.match(broken({ o: [1, 2, 3] }), /not every item/)
  assert.match(broken({ o: [1, 1, 2, 3, 4] }), /every item once/)
  assert.match(broken({ ld: [[40, 41]] }), /connector that is not there/)
  assert.match(broken({ d: [start.links.length ? start.links[0].from : 1] }), /connector to an item that is not there|does not end/)
  assert.match(broken({ n: 0 }), /next id/)
  assert.match(broken(null), /nothing in it/, 'caught by its shape before anything is played')

  const shape = change => { const bad = JSON.parse(JSON.stringify(h)); change(bad); return H.checkShape(bad) }
  assert.equal(H.checkShape(h), '')
  assert.match(shape(b => { b.v = 2 }), /newer/)
  assert.match(shape(b => { b.lineage = '' }), /lineage/)
  assert.match(shape(b => { delete b.base }), /state to start from/)
  assert.match(shape(b => { b.records.push(Object.assign({}, b.records[0])) }), /out of order/)
  assert.match(shape(b => { b.records = {} }), /no records/)
  console.log('ok — history: anything that does not describe the board is refused')
}

{
  // Long text is recorded as the stretch that changed, and never cut through
  // a character: what goes into the file is text any JSON writer can write.
  const long = 'Ein ganz langer Satz über größe und 🙂 Gesichter, '.repeat(40)
  const pairs = [
    [long, long.slice(0, 300) + 'X' + long.slice(300)],
    [long, long.replace('🙂', '🙃')],
    [long + '🙂', long + '🙃'],
    ['🙂' + long, '🙃' + long],
    [long, long.slice(0, 120) + long.slice(160)],
    [long, '']
  ]
  for (const [a, b] of pairs) {
    const s = H.textSplice(a, b)
    assert.equal(H.applySplice(a, s), b)
    const cut = (text, at) => at > 0 && at < text.length
      && text.charCodeAt(at - 1) >= 0xD800 && text.charCodeAt(at - 1) <= 0xDBFF
    assert.ok(!cut(a, s[0]) && !cut(a, s[0] + s[1]), 'no surrogate pair is cut')
    assert.ok(s[2].length < b.length || b.length < 64, 'only the stretch that changed is kept')
  }
  const before = { items: [{ id: 1, kind: 'note', x: 0, y: 0, w: 1, h: 1, tint: 'muted', text: long, pinned: false, src: '' }],
                   links: [], nextId: 2 }
  const after = clone(before)
  after.items[0].text = long.slice(0, 500) + 'typed' + long.slice(500)
  const p = H.diff(before, after)
  assert.deepEqual(p.x, [[1, 500, 0, 'typed']], 'typing into a long note records the typing')
  assert.ok(JSON.stringify(p).length < 60)
  console.log('ok — history: long text is recorded as what changed in it')
}

{
  // Nothing grows without being asked whether it fits.
  const h = H.create({ items: [], links: [], nextId: 1 }, 0, 'cap')
  const record = { i: 1, t: 0, a: 'move', p: { s: [[1, { x: 1 }]] } }
  assert.equal(H.room(h, 0, record).fits, true)
  assert.equal(H.room(h, H.MAX_HISTORY_BYTES - 10, record).why, 'bytes')
  h.records.length = H.MAX_HISTORY_RECORDS
  assert.equal(H.room(h, 0, record).why, 'records')
  assert.equal(H.utf8Length('aé🙂漢'), 1 + 2 + 4 + 3)
  console.log('ok — history: limits are checked before a record is taken')
}

{
  const start = board(random(29), 3)
  const explicit = H.copyState(start)
  explicit.items[0].texture = 'plain'
  assert.equal(H.diff(start, explicit), null, 'older rows mean plain')
  const textured = H.copyState(start)
  textured.items[0].texture = 'grid'
  const h = H.create(start, 0, 'textures')
  H.append(h, start, textured, 'Texture', 1)
  H.append(h, textured, start, 'Texture', 2)
  const stored = JSON.parse(JSON.stringify(h))
  assert.equal(H.verify(stored, start), '', 'set and clear texture survive JSON')
  const ix = H.newIndex(stored, 1)
  while (!H.indexSome(ix, stored, 10)) {}
  assert.equal(H.stateAt(ix, stored, 1).items[0].texture, 'grid')
  assert.equal(H.stateAt(ix, stored, 2).items[0].texture, undefined)
  console.log('ok — history: textures and return to plain survive playback')
}
