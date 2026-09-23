// Exercise the real controller functions with delayed I/O completions.
const fs = require('fs')
const vm = require('vm')
const assert = require('assert/strict')
const { loadStore, FakeModel } = require('./harness')
const source = fs.readFileSync(require('path').join(__dirname, '../Omarchyform.qml'), 'utf8')
function controller() {
  const items = new FakeModel(), links = new FakeModel()
  const root = { boardLoaded: true, damaged: false, pendingBoard: null, currentBoard: 'a.json',
    lastSavedCount: 0, lastSavedText: '', nextId: 1, nextColor: 0, windowMode: false,
    undoStack: [], redoStack: [], selectedIndex: -1, editIndex: -1, saveError: '',
    camX: 0, camY: 0, zoom: 1, activeBoard: null }
  Object.defineProperties(root, {
    canEdit: { get: () => root.boardLoaded && !root.damaged && root.pendingBoard === null },
    boardPath: { get: () => '/boards/' + root.currentBoard }
  })
  const writes = []
  const persistence = { busy: false, save(path, text) { this.busy = true; writes.push({path,text}) } }
  const context = vm.createContext({ root, Store: loadStore(), itemModel: items, linkModel: links,
    persistence, saveTimer: { running: false, stop() {}, restart() {} }, stateFile: {setText() {}} })
  for (const match of source.matchAll(/^  function (\w+)\((.*?)\) \{\n([\s\S]*?)^  }/gm))
    root[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
  for (const match of source.matchAll(/^  function (\w+)\((.*?)\) \{ (.*?) }$/gm))
    root[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
  return { root, items, links, writes, persistence, complete() {
    const write = writes[writes.length - 1]
    persistence.busy = false
    root.savedBoard(write.path, write.text)
  } }
}
{
  const c = controller()
  c.root.loadBoard('{broken', false)
  c.root.addItem('note', 0, 0)
  c.root.addLink(1, 2)
  c.root.save(true)
  assert.equal(c.items.count, 0)
  assert.equal(c.links.count, 0)
  assert.equal(c.writes.length, 0)
  assert.equal(c.root.canEdit, false)
}
{
  const c = controller()
  c.root.addItem('note', 0, 0)
  c.root.addItem('note', 100, 100)
  c.root.openBoard('b.json')
  assert.equal(c.root.currentBoard, 'a.json')
  assert.equal(c.root.canEdit, false)
  assert.equal(c.writes.length, 1)
  c.complete()
  assert.equal(c.writes.length, 2)
  assert.equal(JSON.parse(c.writes[1].text).items.length, 2)
  assert.equal(c.writes[1].path, '/boards/a.json')
  assert.equal(c.root.currentBoard, 'a.json')
  c.complete()
  assert.equal(c.root.currentBoard, 'b.json')
  assert.equal(c.root.boardLoaded, false)
}
{
  const c = controller()
  c.root.addItem('note', 0, 0)
  c.root.openBoard('b.json')
  c.persistence.busy = false
  c.root.failedSave('disk full')
  assert.equal(c.root.currentBoard, 'a.json')
  assert.equal(c.root.pendingBoard, null)
  assert.equal(c.root.lastSavedCount, 0)
  assert.match(c.root.saveError, /disk full/)
  c.root.save()
  c.complete()
  assert.equal(c.root.lastSavedCount, 1)
  assert.equal(c.root.saveError, '')
}
{
  const c = controller()
  c.root.loadBoard('{"items":[null]}', false)
  assert.equal(c.root.damaged, true)
  c.root.loadBoard('', true)
  assert.equal(c.root.canEdit, true)
  assert.equal(c.root.nextId, 1)
}
console.log('ok — controller: damaged boards, delayed saves, switching, failure and retry')
