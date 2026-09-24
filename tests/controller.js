// Exercise the real controller functions with delayed I/O completions.
const fs = require('fs')
const vm = require('vm')
const assert = require('assert/strict')
const { loadStore, FakeModel } = require('./harness')
const source = fs.readFileSync(require('path').join(__dirname, '../Omarchyform.qml'), 'utf8')
function controller() {
  const items = new FakeModel(), links = new FakeModel()
  const root = { currentBoard: 'a.json', items, links, nextId: 1, nextColor: 0, windowMode: false,
    undoStack: [], redoStack: [], selectedIndex: -1, editIndex: -1,
    camX: 0, camY: 0, zoom: 1, activeBoard: null }
  const session = { ctl: root, boardLoaded: true, damaged: false, pendingBoard: null,
    lastSavedCount: 0, lastSavedText: '', saveError: '' }
  Object.defineProperty(session, 'canEdit', {
    get: () => session.boardLoaded && !session.damaged && session.pendingBoard === null
  })
  for (const key of ['boardLoaded', 'damaged', 'pendingBoard', 'saveError', 'canEdit'])
    Object.defineProperty(root, key, { get: () => session[key] })
  Object.defineProperty(root, 'boardPath', { get: () => '/boards/' + root.currentBoard })
  const writes = []
  const persistence = { busy: false, save(path, text) { this.busy = true; writes.push({path,text}) } }
  const context = vm.createContext({ root, session, Store: loadStore(), itemModel: items, linkModel: links,
    persistence, saveTimer: { running: false, stop() {}, restart() {} }, stateFile: {setText() {}} })
  function loadFunctions(target, qml) {
    for (const match of qml.matchAll(/^  function (\w+)\((.*?)\) \{\n([\s\S]*?)^  }/gm))
      target[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
    for (const match of qml.matchAll(/^  function (\w+)\((.*?)\) \{ (.*?) }$/gm))
      target[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
  }
  loadFunctions(root, source)
  loadFunctions(session, fs.readFileSync(require('path').join(__dirname, '../BoardSession.qml'), 'utf8'))
  return { root, session, items, links, writes, persistence, complete() {
    const write = writes[writes.length - 1]
    persistence.busy = false
    session.savedBoard(write.path, write.text)
  } }
}
{
  const c = controller()
  c.session.loadBoard('{broken', false)
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
  c.session.failedSave('disk full')
  assert.equal(c.root.currentBoard, 'a.json')
  assert.equal(c.root.pendingBoard, null)
  assert.equal(c.session.lastSavedCount, 0)
  assert.match(c.root.saveError, /disk full/)
  c.root.save()
  c.complete()
  assert.equal(c.session.lastSavedCount, 1)
  assert.equal(c.root.saveError, '')
}
{
  const c = controller()
  c.session.loadBoard('{"items":[null]}', false)
  assert.equal(c.root.damaged, true)
  c.session.loadBoard('', true)
  assert.equal(c.root.canEdit, true)
  assert.equal(c.root.nextId, 1)
}

{
  // A completion carries the board it belongs to. Adopting it as the baseline
  // for a different board suppresses that board's first write whenever the two
  // serialise the same — and two empty boards always do.
  const c = controller()
  c.session.loadBoard('{"version":3,"items":[],"links":[]}', false)
  c.root.addItem('note', 0, 0)
  assert.equal(c.writes.length, 1, 'the first board is written')
  const stale = c.writes[c.writes.length - 1]

  // Switch away before that write reports back, the way openBoard does.
  c.session.boardLoaded = false
  c.root.currentBoard = 'b.json'
  c.session.loadBoard('', true)          // a board that does not exist yet
  const beforeBaseline = c.session.lastSavedText

  // The late completion names the board it was for, not the one now open.
  c.persistence.busy = false
  c.session.savedBoard(stale.path, stale.text)
  assert.equal(c.session.lastSavedText, beforeBaseline,
    'a completion for another board must not become this board\'s baseline')

  // With the baseline intact, the new board can still write itself.
  c.root.addItem('note', 0, 0)
  const last = c.writes[c.writes.length - 1]
  assert.equal(last.path, '/boards/b.json', 'the new board is written')
}
{
  // Saves, board switches and completions interleave, and the bug that
  // reached main was an ordering one: a completion landing after a switch.
  // Rather than hope a hand-written sequence finds the next one, drive random
  // orders and assert what must hold however they land.
  let seed = 20260924
  const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
  const boards = ['a.json', 'b.json', 'c.json']

  let totalWrites = 0, totalSwitches = 0
  for (let run = 0; run < 200; run++) {
    const c = controller()
    const disk = {}
    // Remember the board each write was serialised for, to catch a write
    // landing on a path it was not meant for.
    c.persistence.save = function (path, text) {
      this.busy = true
      c.writes.push({ path, text, forBoard: c.root.currentBoard })
    }
    c.session.loadBoard('{"version":3,"items":[],"links":[]}', false)

    for (let step = 0; step < 24; step++) {
      const pick = rnd()
      if (pick < 0.45) {
        c.root.addItem('note', rnd() * 100, rnd() * 100)
      } else if (pick < 0.7) {
        const next = boards[Math.floor(rnd() * boards.length)]
        totalSwitches++
        c.session.openBoard(next, disk[next] === undefined)
        if (!c.session.pendingBoard && !c.session.boardLoaded)
          c.session.loadBoard(disk[c.root.currentBoard] === undefined
            ? '' : disk[c.root.currentBoard],
            disk[c.root.currentBoard] === undefined)
      } else if (c.persistence.busy) {
        const w = c.writes[c.writes.length - 1]
        assert.equal(w.path, '/boards/' + w.forBoard,
          'a write must land on the board it was serialised for')
        disk[w.forBoard] = w.text
        c.persistence.busy = false
        c.session.savedBoard(w.path, w.text)
        if (!c.session.boardLoaded)
          c.session.loadBoard(disk[c.root.currentBoard] === undefined
            ? '' : disk[c.root.currentBoard],
            disk[c.root.currentBoard] === undefined)
      }
    }

    // Drain: deliver every outstanding completion.
    for (let guard = 0; guard < 50 && c.persistence.busy; guard++) {
      const w = c.writes[c.writes.length - 1]
      disk[w.forBoard] = w.text
      c.persistence.busy = false
      c.session.savedBoard(w.path, w.text)
      if (!c.session.boardLoaded)
        c.session.loadBoard(disk[c.root.currentBoard] === undefined
          ? '' : disk[c.root.currentBoard],
          disk[c.root.currentBoard] === undefined)
    }
    totalWrites += c.writes.length
    assert.equal(c.persistence.busy, false, `run ${run}: the writer must not stay busy`)

    // Whatever the model holds now must be what a final save puts on disk.
    c.session.save(true)
    if (c.persistence.busy) {
      const w = c.writes[c.writes.length - 1]
      disk[w.forBoard] = w.text
      c.persistence.busy = false
      c.session.savedBoard(w.path, w.text)
    }
    assert.equal(disk[c.root.currentBoard] !== undefined || c.items.count === 0, true,
      `run ${run}: the open board must have reached disk`)
  }
  console.log('   stress: ' + totalWrites + ' writes, ' + totalSwitches + ' board switches across 200 runs')
}
console.log('ok — controller: damaged boards, delayed saves, switching, failure and retry')
