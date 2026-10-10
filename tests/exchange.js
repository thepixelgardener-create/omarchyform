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
  const a = { name: 'a', dataDir: '/a' }, b = { name: 'b', dataDir: '/b' }
  const root = { activePane: a, exchangePane: a }
  let busy = false
  const signals = [], staged = []
  const exchange = { root, dialogOpen: false, error: '', operation: '', firstNote: false,
    maxImportBytes: 33554432, exportNote: '', sharing: null,
    Store: loadStore(), Date, Qt: { callLater(f) { f() } },
    output: { path: '', setText(text) { staged.push({ path: this.path, text }) } },
    input: { path: '', reload() {}, waitForJob() {}, text() { return this.raw } },
    measured: { text: '100' }, measure: { source: '/outside.json' }, published: { text: 'new.json' } }
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
  c.exchange.input.raw = JSON.stringify({ version: 5, nextId: 1, items: [], links: [] })
  c.exited('measure', 0)
  assert.equal(c.exchange.busy, true)
  assert.equal(c.exchange.ctl, c.a, 'measuring and reading do not release the import owner')
  assert.match(c.staged[0].path, /^\/a\//)
  c.exited('publish', 0)
  assert.equal(c.signals[0].pane, c.a)
}
{
  const c = fixture()
  c.exchange.sharing = { at: 1, names: ['old.png'], base: 'board', landed: { 'old.png': 'new.png' },
    raw: JSON.stringify({ version: 5, items: [{ id: 1, kind: 'image', src: 'old.png' }], links: [] }) }
  c.exchange.nextSharedImage()
  assert.equal(c.exchange.busy, true)
  assert.equal(c.exchange.ctl, c.a, 'unbundling and publication retain the import owner')
  assert.equal(JSON.parse(c.staged[0].text).items[0].src, 'new.png')
  c.exited('publish', 0)
  assert.equal(c.signals[0].pane, c.a)
}
console.log('ok — exchange: every import stage and completion retains its originating pane')
