// Boards someone else wrote, each pushing one thing a board can carry to the
// bound the plugin holds it to, or just past it. tests/hostile.js opens every
// one the way the shell and the command line do and times it.
//
// Each stall the marketplace review or a user found was one of these: a note
// of one unbroken line (2026-10-04), an item at the largest id (2026-10-14),
// note text a parser read as markup (2026-10-16). Every new field a board can
// carry, and every new way of reading one, adds its fixture here at its bound.
//
// `opens` says what the plugin does with it: true for a board that opens,
// false for one shown empty and read-only (refused or not a board).
// The CLI normally succeeds without warnings. `cliWarning` names an expected
// canvas-limit warning (validate can still inspect that board); `cliError`
// names a refusal from its loader, with exit status 1. `ordinary` marks the
// two boards at no limit at all, there to be held to the targets for a board
// in ordinary use (docs/performance.md#targets--2026-10-26).
const S = require('../bin/store').loadStore()

const MAX = S.MAX_BOARD_BYTES
const note = (id, x, y, text, extra) => Object.assign({ id, kind: 'note', x, y, w: 220, h: 160,
  tint: 'foreground', text, pinned: false, src: '' }, extra)
const board = (items, links, extra) => JSON.stringify(Object.assign({ kind: 'omarchyform.board',
  version: 5, nextId: items.length + 1, items, links: links || [] }, extra))
// Fills a field with `unit` until the board is just under the byte limit.
const filled = (items, unit, field) => {
  const empty = board(items.map(n => Object.assign({}, n, { [field]: '' })))
  const per = Math.floor((MAX - empty.length - 1024) / items.length / Buffer.byteLength(unit))
  return items.map(n => Object.assign({}, n, { [field]: unit.repeat(per) }))
}
// As many notes of `text` as fit, each at the note limit, stacked on one spot.
const fullNotes = unit => {
  const text = unit.repeat(Math.floor(S.MAX_NOTE_LENGTH / unit.length))
  const count = Math.floor((MAX - 1024) / (Buffer.byteLength(JSON.stringify(text)) + 160))
  return board(Array.from({ length: count }, (_, i) => note(i + 1, i * 8, i * 8, text)))
}
const grid = (count, gap, make) => Array.from({ length: count }, (_, i) =>
  make(i + 1, (i % 71) * gap, Math.floor(i / 71) * gap))
// A board as people make them: notes of a few words to a few sentences, a
// shape every fifth item, each item joined to the one before it and every
// tenth to the one ten back. The showcase board is 11 items, its notes 12 to
// 137 characters.
const ordinary = count => {
  const words = 'ship the first draft before review, then ask what is missing and why it matters'.split(' ')
  const items = Array.from({ length: count }, (_, i) => {
    const text = Array.from({ length: 2 + (i * 7) % 30 }, (_, w) => words[(i + w) % words.length]).join(' ')
    return note(i + 1, (i % 20) * 280, Math.floor(i / 20) * 220, text,
      i % 5 === 4 ? { kind: S.KINDS[1 + ((i + 1) / 5) % 3], text: text.slice(0, 24) } : { tint: S.TINTS[i % 4] })
  })
  const links = []
  for (let i = 2; i <= count; i++) links.push({ from: i - 1, to: i })
  for (let i = 11; i <= count; i += 10) links.push({ from: i - 10, to: i })
  return board(items, links)
}

const fixtures = [
  // At no limit: what the targets for a board in ordinary use are held to.
  { name: 'ordinary-50', opens: true, ordinary: true, text: () => ordinary(50) },
  { name: 'ordinary-500', opens: true, ordinary: true, text: () => ordinary(500) },

  // How many: every item on screen at once, then the most connectors.
  { name: 'max-items-stacked', opens: true,
    text: () => board(Array.from({ length: S.MAX_ITEMS }, (_, i) => note(i + 1, i % 50, i % 37, 'n' + i))) },
  { name: 'max-items-grid', opens: true,
    text: () => board(grid(S.MAX_ITEMS, 240, (id, x, y) => note(id, x, y, 'note ' + id))) },
  { name: 'max-items-shapes', opens: true,
    text: () => board(grid(S.MAX_ITEMS, 240, (id, x, y) => note(id, x, y, '',
      { kind: S.KINDS[id % 4], texture: S.TEXTURES[id % 5] })), [], { version: 7 }) },
  { name: 'max-links', opens: true,
    text: () => {
      // 201 items have 20,100 pairs; the first 20,000 of them, all on screen.
      const items = Array.from({ length: 201 }, (_, i) => note(i + 1, (i % 15) * 60, Math.floor(i / 15) * 60, ''))
      const links = []
      for (let a = 1; a <= 201 && links.length < S.MAX_LINKS; a++)
        for (let b = a + 1; b <= 201 && links.length < S.MAX_LINKS; b++) links.push({ from: a, to: b })
      return board(items, links)
    } },
  { name: 'one-past-items', opens: false, cliWarning: 'has more than 5,000 items',
    text: () => board(Array.from({ length: S.MAX_ITEMS + 1 }, (_, i) => note(i + 1, 0, 0, ''))) },
  { name: 'one-past-links', opens: false, cliWarning: 'has more than 20,000 connectors',
    text: () => board([note(1, 0, 0, ''), note(2, 300, 0, '')],
      Array.from({ length: S.MAX_LINKS + 1 }, () => ({ from: 1, to: 2 }))) },
  { name: 'dangling-links', opens: true,
    text: () => board([note(1, 0, 0, 'a')], Array.from({ length: S.MAX_LINKS }, (_, i) => ({ from: i + 2, to: 'toString' }))) },

  // What a note says: the longest, in the text that costs most to lay out.
  { name: 'notes-words', opens: true, text: () => fullNotes('lorem ipsum ') },
  { name: 'notes-unbroken', opens: true, text: () => fullNotes('A') },
  { name: 'notes-markup', opens: true, text: () => fullNotes('<b>**#[x](y)</b>&amp;<font size=99>') },
  { name: 'notes-one-cluster', opens: true, text: () => fullNotes('e' + '\u0301'.repeat(63)) },
  { name: 'notes-bidi', opens: true, text: () => fullNotes('\u05d0a\u202e\u0628\u200d') },
  { name: 'notes-emoji-zwj', opens: true, text: () => fullNotes('\ud83d\udc69\u200d') },
  { name: 'notes-newlines', opens: true, text: () => fullNotes('\n') },
  { name: 'notes-tabs', opens: true, text: () => fullNotes('\t') },
  { name: 'max-items-previews', opens: true,
    text: () => board(filled(grid(S.MAX_ITEMS, 240, (id, x, y) => note(id, x, y, '')), 'w ', 'text')) },
  { name: 'one-past-note', opens: false, cliWarning: 'is longer than 1048576 characters',
    text: () => board([note(1, 0, 0, 'a'.repeat(S.MAX_NOTE_LENGTH + 1))]) },

  // Ids and numbers.
  { name: 'max-id', opens: true,
    text: () => board(Array.from({ length: S.MAX_ITEMS }, (_, i) => note(S.MAX_ID - i, (i % 71) * 240, Math.floor(i / 71) * 240, '')),
      Array.from({ length: S.MAX_ITEMS - 1 }, (_, i) => ({ from: S.MAX_ID - i, to: S.MAX_ID - i - 1 })), { nextId: S.MAX_ID }) },
  { name: 'duplicate-ids', opens: true,
    text: () => board(Array.from({ length: S.MAX_ITEMS }, (_, i) => note(1, (i % 71) * 240, Math.floor(i / 71) * 240, ''))) },
  { name: 'extreme-geometry', opens: true,
    text: () => {
      const odd = [1e308, -1e308, 'NaN', 'Infinity', -0, 0, -1, 2 ** 53, 1e-308, '1e400', null, true, [], {}]
      return board(Array.from({ length: S.MAX_ITEMS }, (_, i) => note(i + 1, odd[i % 14], odd[(i + 3) % 14], 'x',
        { w: odd[(i + 5) % 14], h: odd[(i + 7) % 14] })), [], { nextId: 'Infinity' })
    } },
  { name: 'odd-values', opens: true,
    text: () => board(Array.from({ length: S.MAX_ITEMS }, (_, i) => ({ id: String(i + 1), kind: ['image', 'toString',
      '__proto__', 'constructor'][i % 4], tint: '#'.repeat(4096), texture: { valueOf: 1 }, color: [], src: '../'.repeat(500),
      text: i % 2 ? 5 : { length: 1e9 }, pinned: 'yes' }))) },

  // How it is written: the parser's limits, and bytes that cost reading.
  { name: 'open-list-under', opens: true,
    text: () => board([note(1, 0, 0, 'x')], [], { extra: Array(S.MAX_JSON_OPEN - 100).fill(0) }) },
  { name: 'open-list-over', opens: false, cliError: 'is not a board this understands',
    text: () => board([note(1, 0, 0, 'x')], [], { extra: Array(S.MAX_JSON_OPEN + 1).fill(0) }) },
  { name: 'deep-nesting', opens: false, cliError: 'is not a board this understands',
    text: () => '{"items":[' + '['.repeat(100000) + ']'.repeat(100000) + ']}' },
  { name: 'nesting-at-limit', opens: true,
    text: () => board([note(1, 0, 0, 'x')]).slice(0, -1) + ',"extra":' + '{"a":'.repeat(1000) + '0' + '}'.repeat(1000) + '}' },
  { name: 'escaped-quotes', opens: true,
    text: () => board([note(1, 0, 0, 'x')]).slice(0, -1) + ',"extra":"' + '\\\\\\",['.repeat(Math.floor((MAX - 1024) / 6)) + '"}' },
  { name: 'whitespace', opens: true, text: () => ' '.repeat(MAX - 1024) + board([note(1, 0, 0, 'x')]) },
  { name: 'unknown-field', opens: true, text: () => board([note(1, 0, 0, 'x', { extra: 'z'.repeat(MAX - 1024) })]) },
  { name: 'old-history', opens: true,
    text: () => board([note(1, 0, 0, 'x')], [], { version: 6, history: { v: 1, records:
      Array.from({ length: 68000 }, (_, i) => ({ op: 'add', id: S.MAX_ID - i, items: [note(S.MAX_ID - i, 0, 0, 'h'.repeat(300))] })) } }) },
  { name: 'pictures-missing', opens: true,
    text: () => board(grid(S.MAX_ITEMS, 240, (id, x, y) => ({ id, kind: 'image', x, y, w: 200, h: 200, src: 'p' + id + '.png' }))) },
  { name: 'future-version', opens: false, cliError: 'is format 8, newer than this understands',
    text: () => board([note(1, 0, 0, 'x')], [], { version: 8 }) },
  { name: 'not-a-board', opens: false, cliError: 'is not a board this understands',
    text: () => '['.repeat(1024) + ']'.repeat(1024) }
]

for (const f of fixtures) f.bytes = () => Buffer.from(f.text(), 'utf8')
module.exports = { fixtures }
