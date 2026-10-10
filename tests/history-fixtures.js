// Boards and sequences of edits made the way the board makes them, from a
// seed, so a correctness test and a benchmark describe the same thing and a
// failure can be run again exactly. Shared by tests/history.js and
// tests/history-bench.js.

// A small, fast, seeded generator: the same seed gives the same board.
function random(seed) {
  let a = seed >>> 0
  return function () {
    a = (a + 0x6D2B79F5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const KINDS = ['note', 'rect', 'ellipse', 'diamond']
const TINTS = ['foreground', 'accent', 'urgent', 'muted']
const WORDS = ['plan', 'ship', 'labels', 'connector', 'review', 'notes', 'idea', 'later', 'why', 'because',
  'the', 'board', 'shows', 'what', 'changed', 'and', 'when', 'größe', 'naïve', '🙂', '漢字']

function sentence(rnd, words) {
  const out = []
  for (let i = 0; i < words; i++) out.push(WORDS[Math.floor(rnd() * WORDS.length)])
  return out.join(' ')
}

// `words` is how much each note says to begin with: a dozen or so for a board
// of sticky notes, hundreds for one that is mostly writing.
function board(rnd, count, words) {
  const items = []
  const say = words || 12
  for (let i = 0; i < count; i++) {
    items.push({ id: i + 1, kind: KINDS[i % 4], x: (i % 60) * 260, y: Math.floor(i / 60) * 220,
      w: 220, h: 160, tint: TINTS[i % 4], text: sentence(rnd, 3 + Math.floor(rnd() * say)), pinned: false, src: '' })
  }
  const links = []
  const seen = new Set()
  for (let i = 0; i < Math.floor(count / 2); i++) {
    const from = 1 + Math.floor(rnd() * count), to = 1 + Math.floor(rnd() * count)
    if (from === to || seen.has(from + '>' + to) || seen.has(to + '>' + from)) continue
    seen.add(from + '>' + to)
    links.push({ from, to })
  }
  return { items, links, nextId: count + 1 }
}

function clone(state) {
  return { items: state.items.map(r => Object.assign({}, r)), links: state.links.map(l => Object.assign({}, l)),
           nextId: state.nextId }
}

const pick = (rnd, list) => list[Math.floor(rnd() * list.length)]

// One edit, as the board would make it, applied to a copy. Which edits are
// likely is the mix's to say: `mixed` is a working session, `moves` is mostly
// dragging things about, `text` is mostly writing.
const MIXES = {
  mixed: { move: 30, group: 6, resize: 6, colour: 6, kind: 3, text: 25, long: 4, add: 8, remove: 4,
           layer: 2, duplicate: 2, link: 5, pin: 1, undo: 2 },
  moves: { move: 80, group: 10, resize: 4, text: 3, add: 1, remove: 1, link: 1 },
  text: { text: 50, long: 40, move: 5, add: 3, remove: 2 }
}

function edit(rnd, state, mix, history) {
  const weights = MIXES[mix]
  let roll = rnd() * Object.values(weights).reduce((a, b) => a + b, 0)
  let kind = 'move'
  for (const [name, w] of Object.entries(weights)) { roll -= w; if (roll < 0) { kind = name; break } }
  const next = clone(state)
  const items = next.items
  if (items.length === 0) kind = 'add'
  const one = () => items[Math.floor(rnd() * items.length)]
  switch (kind) {
    case 'move': { const r = one(); r.x += Math.round((rnd() - 0.5) * 400); r.y += Math.round((rnd() - 0.5) * 400); break }
    case 'group': {
      const dx = Math.round((rnd() - 0.5) * 300), dy = Math.round((rnd() - 0.5) * 300)
      const n = 2 + Math.floor(rnd() * Math.min(40, items.length))
      for (let i = 0; i < n; i++) { const r = one(); r.x += dx; r.y += dy }
      break
    }
    case 'resize': { const r = one(); r.w = Math.max(60, r.w + Math.round((rnd() - 0.5) * 100)); r.h = Math.max(60, r.h + 40); break }
    case 'colour': { const r = one(); r.tint = pick(rnd, TINTS.filter(t => t !== r.tint)); break }
    case 'kind': { const r = one(); r.kind = pick(rnd, KINDS.filter(k => k !== r.kind)); break }
    case 'text': { const r = one(); r.text = r.text + ' ' + sentence(rnd, 1 + Math.floor(rnd() * 4)); break }
    case 'long': {
      // A long note being written into somewhere in the middle: the record
      // should be the words, not the note.
      const r = one()
      if (r.text.length < 2000) r.text = r.text + '\n' + sentence(rnd, 300)
      const at = Math.floor(rnd() * r.text.length)
      r.text = r.text.slice(0, at) + sentence(rnd, 2) + r.text.slice(at + Math.floor(rnd() * 20))
      break
    }
    case 'add': {
      items.push({ id: next.nextId, kind: 'note', x: Math.round(rnd() * 8000), y: Math.round(rnd() * 4000), w: 180, h: 140,
        tint: pick(rnd, TINTS), text: '', pinned: false, src: '' })
      next.nextId += 1
      break
    }
    case 'remove': {
      const at = Math.floor(rnd() * items.length)
      const id = items[at].id
      items.splice(at, 1)
      next.links = next.links.filter(l => l.from !== id && l.to !== id)
      break
    }
    case 'layer': {
      const from = Math.floor(rnd() * items.length)
      const [r] = items.splice(from, 1)
      items.splice(rnd() < 0.5 ? 0 : items.length, 0, r)
      break
    }
    case 'duplicate': {
      const r = one()
      items.push(Object.assign({}, r, { id: next.nextId, x: r.x + 24, y: r.y + 24, pinned: false }))
      next.nextId += 1
      break
    }
    case 'link': {
      const a = one(), b = one()
      if (a.id === b.id) break
      const at = next.links.findIndex(l => (l.from === a.id && l.to === b.id) || (l.from === b.id && l.to === a.id))
      if (at < 0) next.links.push({ from: a.id, to: b.id })
      else if (next.links[at].from === a.id) next.links.splice(at, 1)
      else next.links[at] = { from: a.id, to: b.id }
      break
    }
    case 'pin': { const r = one(); r.pinned = !r.pinned; break }
    case 'undo': {
      // Undo restores a whole earlier board: whatever it puts back is the
      // next state in the history, recorded like any other edit.
      if (history.length > 2) return { state: clone(history[Math.max(0, history.length - 1 - Math.floor(rnd() * 3))]), kind }
      break
    }
  }
  return { state: next, kind }
}

module.exports = { random, board, edit, clone, MIXES }
