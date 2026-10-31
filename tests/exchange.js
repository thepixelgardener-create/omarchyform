// Exercise production import stages and completion handlers with immediate QML-
// style idle notifications. A focus change must not steal an operation's result.
const assert = require('assert/strict')
const fs = require('fs')
const vm = require('vm')
const path = require('path')
const { loadStore } = require('../bin/store')
const read = name => fs.readFileSync(path.join(__dirname, '..', name), 'utf8')
const source = read('BoardExchange.qml')
const workspace = read('Omarchyform.qml')

function fixture() {
  const a = { name: 'a', dataDir: '/a', imagesDir: '/a/images', fileCommand: (op, args) => [op, ...args] }, b = { name: 'b', dataDir: '/b' }
  const root = { activePane: a, exchangePane: a }
  let busy = false
  const signals = [], staged = []
  const exchange = { root, dialogOpen: false, error: '', operation: '', firstNote: false,
    exportNote: '', sharing: null, imageBudget: {},
    Store: loadStore(), Date, Qt: { callLater(f) { f() } },
    output: { path: '', setText(text) { staged.push({ path: this.path, text }) } },
    // What the helper's bounded read handed back, and the file it was asked for.
    importBytes: { text: '' }, reading: { source: '/outside.json' }, published: { text: 'new.json' } }
  exchange.exchange = exchange
  Object.defineProperty(exchange, 'ctl', { get: () => root.exchangePane })
  Object.defineProperty(root, 'exchangeIdle', { get: () => !busy && !exchange.dialogOpen })
  const context = vm.createContext(exchange)
  const handler = name => vm.runInContext(`(function() {${workspace.match(new RegExp('  ' + name + ': ([^\\n]+)'))[1]}})`, context)
  const idleChanged = handler('onExchangeIdleChanged'), focusChanged = handler('onActivePaneChanged')
  Object.defineProperty(exchange, 'busy', { get: () => busy, set(value) { busy = value; idleChanged() } })
  for (const match of source.matchAll(/^  function (\w+)\((.*?)\) \{\n([\s\S]*?)^  }/gm))
    exchange[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
  for (const name of ['created', 'copied', 'finished', 'failed'])
    exchange[name] = (...args) => signals.push({ name, pane: exchange.ctl, args })
  function exited(id, code) {
    const match = source.match(new RegExp('id: ' + id + '\\n[\\s\\S]*?onExited: function\\s*\\(code\\) \\{\\n([\\s\\S]*?)^    }$', 'm'))
    assert.ok(match, id)
    vm.runInContext(`(function(code) {${match[1]}})`, context)(code)
  }
  exchange.busy = true
  root.activePane = b; focusChanged()
  assert.equal(exchange.ctl, a)
  return { exchange, a, b, signals, staged, exited }
}

for (const operation of ['publish', 'copy', 'export']) {
  for (const code of [0, 1]) {
    const c = fixture()
    c.exchange.operation = operation
    c.exited('publish', code)
    assert.equal(c.signals.length, 1)
    assert.equal(c.signals[0].pane, c.a, operation + ': completion belongs to its original pane')
    assert.equal(c.exchange.busy, false)
    assert.equal(c.exchange.ctl, c.b, 'idle follows focus only after delivery')
  }
}
{
  const c = fixture()
  c.exchange.importBytes.text = JSON.stringify({ version: 5, nextId: 1, items: [], links: [] })
  c.exited('reading', 0)
  assert.equal(c.exchange.busy, true)
  assert.equal(c.exchange.ctl, c.a, 'measuring and reading do not release the import owner')
  assert.match(c.staged[0].path, /^\/a\//)
  c.exited('publish', 0)
  assert.equal(c.signals[0].pane, c.a)
}
{
  // The helper read it and stopped at the bound (5), or could not read it, or
  // read nothing: each is refused, says why, and lets go of the exchange.
  for (const [code, text, says] of [
    [5, '', 'That file is larger than 32 MB — too large for a board'],
    [1, '', 'Could not read that board'],
    [0, '', 'Could not read that board']]) {
    const c = fixture()
    c.exchange.importBytes.text = text
    c.exited('reading', code)
    assert.deepEqual(c.signals[0].args, [says, 'board'])
    assert.equal(c.staged.length, 0)
    assert.equal(c.exchange.busy, false)
  }
  // Asked of the helper as one bounded read, not a size and then a read.
  const c = fixture()
  c.exchange.busy = false
  c.b.fileCommand = c.a.fileCommand
  const asked = {}
  c.exchange.reading = asked
  c.exchange.importPath('/outside.json')
  assert.deepEqual(asked.command, ['read', '/outside.json'])
}
{
  // A board with more in it than a board holds is refused with the reason,
  // not imported to open read-only; one exactly full arrives.
  const rows = n => Array.from({ length: n }, (_, i) => ({ id: i + 1, kind: 'rect', x: i, y: 0, w: 60, h: 60 }))
  for (const [items, links, says] of [
    [rows(5001), [], 'That board has more than 5,000 items'],
    [rows(2), Array.from({ length: 20001 }, () => ({ from: 1, to: 2 })), 'That board has more than 20,000 connectors']]) {
    const c = fixture()
    c.exchange.importBytes.text = JSON.stringify({ version: 5, nextId: items.length + 1, items, links })
    c.exited('reading', 0)
    assert.equal(c.signals.length, 1)
    assert.equal(c.signals[0].name, 'failed')
    assert.deepEqual(c.signals[0].args, [says, 'board'])
    assert.equal(c.staged.length, 0, 'nothing of it is staged')
  }
  for (const [raw, says] of [
    ['{"version":5,"items":[],"links":[' + '0,'.repeat(100000) + '0]}', 'That board has a list too long to read'],
    ['not a board', 'That file is not a supported board']]) {
    const c = fixture()
    c.exchange.importBytes.text = raw
    c.exited('reading', 0)
    assert.deepEqual(c.signals[0].args, [says, 'board'])
  }
  const c = fixture()
  c.exchange.importBytes.text = JSON.stringify({ version: 5, nextId: 5001, items: rows(5000), links: [] })
  c.exited('reading', 0)
  assert.equal(c.staged.length, 1, 'a board exactly full is imported')
}
{
  const c = fixture()
  c.exchange.sharing = { at: 1, names: ['old.png'], base: 'board', landed: { 'old.png': 'new.png' },
    raw: JSON.stringify({ version: 5, items: [{ id: 1, kind: 'image', src: 'old.png' }], links: [] }) }
  c.exchange.nextSharedImage()
  assert.equal(c.exchange.busy, true)
  assert.equal(c.exchange.ctl, c.a, 'unbundling and publication retain the import owner')
  assert.equal(c.staged.length, 0, 'no board is staged before the aggregate check')
  assert.equal(c.exchange.imageBudget.input, 'new.png\n')
  c.exited('imageBudget', 0)
  assert.equal(JSON.parse(c.staged[0].text).items[0].src, 'new.png')
  c.exited('publish', 0)
  assert.equal(c.signals[0].pane, c.a)
}

for (const code of [7, 10, 12, 1]) {
  const c = fixture()
  c.exchange.sharing = { at: 1, names: ['old.png'], base: 'board', landed: { 'old.png': 'new.png' },
    raw: JSON.stringify({ version: 5, items: [1, 2, 3].map(id => ({ id, kind: 'image', src: 'old.png' })), links: [] }) }
  c.exchange.nextSharedImage()
  assert.equal(c.exchange.imageBudget.input, 'new.png\nnew.png\nnew.png\n', 'every retained decode is counted')
  c.exited('imageBudget', code)
  assert.equal(c.staged.length, 0, 'over-budget or unmeasurable imports are never published')
  assert.equal(c.exchange.sharing, null)
  assert.equal(c.signals[0].name, 'failed')
  assert.equal(c.signals[0].pane, c.a, 'a late refusal still belongs to the asking pane')
  assert.match(c.signals[0].args[0], /nothing was imported/)
  assert.equal(c.exchange.busy, false, 'another import is possible after refusal')
}

{
  const c = fixture()
  c.exchange.importBytes.text = JSON.stringify({ version: 5, items: [{ kind: 'image', src: { toString: null, valueOf: null } }], links: [] })
  c.exited('reading', 0)
  assert.equal(c.staged.length, 0)
  assert.equal(c.signals[0].name, 'failed')
  assert.equal(c.signals[0].pane, c.a, 'schema refusal belongs to the asking pane')
  assert.equal(c.exchange.busy, false, 'malformed imports do not strand exchange operations')
  assert.equal(c.exchange.sharing, null)
  c.exchange.busy = true
  c.exchange.importBytes.text = JSON.stringify({ version: 5, items: [{ text: 'recovered' }], links: [] })
  c.exited('reading', 0)
  assert.equal(JSON.parse(c.staged[0].text).items[0].text, 'recovered', 'a valid import still works')
}

// A picture BoardFiles.sh refuses for the compressed text inside it (exit 9)
// says so, on each way a picture comes in, rather than reading as unreadable.
{
  const c = fixture()
  c.exchange.pasteBoard = 'x.json'
  c.exchange.pasteShown = 0
  // BoardPane's own test of whether an answer still belongs to this view.
  c.exchange.pastePane = { currentBoard: 'x.json', docSerial: 0,
    stillShows(board, shown) { return board === this.currentBoard && shown === this.docSerial } }
  c.exchange.grabbed = { text: '' }
  c.exchange.clipboard = { running: false }
  c.exited('imageGrab', 9)
  const said = c.signals[c.signals.length - 1]
  assert.equal(said.name, 'failed')
  assert.match(said.args[0], /compressed text/, 'a paste says why')
  assert.equal(said.args[1], 'paste')
  assert.equal(c.exchange.clipboard.running, false, 'and does not fall back to pasting text')
}
{
  const c = fixture()
  const reports = []
  const pane = { doc: {}, report: (message, kind) => reports.push({ message, kind }) }
  c.exchange.dropQueue = [{ pane, board: 'x.json', x: 0, y: 0 }]
  c.exchange.importedName = { text: '' }
  c.exchange.nextDrop = () => {}
  c.exited('imageImport', 9)
  assert.match(reports[0].message, /compressed text/, 'an imported picture says why')
  assert.equal(reports[0].kind, 'picture')
}
for (const [code, says] of [[9, /carries compressed text.*nothing was imported/], [4, /^A picture in that board could not be read/]]) {
  const c = fixture()
  c.exchange.sharing = { at: 0, names: ['old.png'], base: 'board', landed: {}, raw: '{}' }
  c.exchange.unbundled = { text: '' }
  c.exited('unbundle', code)
  const said = c.signals[c.signals.length - 1]
  assert.equal(said.name, 'failed')
  assert.match(said.args[0], says, 'a board carrying the picture, exit ' + code)
  assert.equal(c.exchange.sharing, null, 'and nothing more of it is imported')
}
console.log('ok — exchange: every import stage and completion retains its originating pane')
