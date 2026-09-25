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
    camX: 0, camY: 0, zoom: 1, activeBoard: null, markedIds: [], showPinned: false, arranging: false,
    boardsDir: '/boards', backupsDir: '/backups', worldStep: 40, minItemSize: 60, viewW: 1000, viewH: 700 }
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
    persistence, statusTimer: {restart() {}}, saveTimer: { running: false, stop() {}, restart() {} }, stateFile: {setText() {}} })
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
  // A slow write is only a delay: the switch waits for it instead of vanishing.
  const c = controller()
  c.root.addItem('note', 0, 0)
  assert.equal(c.persistence.busy, true)
  c.session.saveError = 'Saving is taking longer than expected; waiting for disk'
  c.root.openBoard('b.json')
  assert.equal(c.root.pendingBoard.path, 'b.json')
  c.complete()
  assert.equal(c.root.currentBoard, 'b.json')
  assert.equal(c.root.saveError, '')
}
{
  // A broken trash index must not stop the browser opening folders or boards.
  const c = controller()
  Object.assign(c.root, { browserBusy: false, browserTrash: false, browserIndex: 0, browserMessage: '',
    trashIndexError: 'trash index is invalid', closeBrowser() {},
    browserRows: [{ path: 'b.json', dir: false }] })
  const opened = []
  c.root.openBoard = path => opened.push(path)
  c.root.browserEnter()
  assert.deepEqual(opened, ['b.json'])
  c.root.browserRows = [{ path: 'work', dir: true }]
  c.root.browserEnter()
  assert.equal(c.root.browserDir, 'work')
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

{
  const c = controller()
  c.root.markedIds = [1]
  c.root.showPinned = true
  c.session.loadBoard('{"version":3,"items":[{"id":1,"text":"other board"}]}', false)
  assert.deepEqual(Array.from(c.root.markedIds), [])
  assert.equal(c.root.showPinned, false)
  assert.deepEqual(Array.from(c.root.targets()), [])
  assert.notEqual(c.root.backupPathFor('work/a.json'), c.root.backupPathFor('work__a.json'))
  c.root.applyState('{"lastBoard":"../outside.json"}')
  assert.equal(c.root.currentBoard, 'a.json')
}
{
  const c = controller()
  c.session.loadBoard('{"version":3,"items":[{"id":1},{"id":2}]}', false)
  c.root.selectedIndex = 0
  c.root.togglePin()
  assert.equal(c.items.get(0).ipinned, true)
  assert.equal(c.root.selectedIndex, -1)
  c.root.markAll()
  assert.deepEqual(Array.from(c.root.markedIds), [2])
  c.root.selectedIndex = 0
  c.root.markedIds = []
  c.root.nudgeSelected(1,0)
  c.root.resizeSelected(1,0)
  c.root.removeItem(0)
  c.root.editSelected()
  assert.equal(c.items.count, 2)
  assert.equal(c.items.get(0).ix, 0)
  assert.equal(c.items.get(0).iw, 180)
  assert.equal(c.root.editIndex, -1)
  c.root.selectNext(1)
  assert.equal(c.root.selectedIndex, 1)
  c.root.togglePinnedSelection()
  assert.equal(c.root.selectedIndex, 0)
  c.root.togglePin()
  assert.equal(c.items.get(0).ipinned, false)
  c.root.undo()
  assert.equal(c.items.get(0).ipinned, true)
  c.root.redo()
  assert.equal(c.items.get(0).ipinned, false)
  for (let i=0;i<130;i++) c.root.pushUndo()
  assert.equal(c.root.undoStack.length, 100)
}
console.log('ok — controller: board-local marks, pinning, backup names and history cap')

{
  const c = controller()
  c.session.loadBoard('{"items":[{"id":1},{"id":2},{"id":3,"pinned":true}]}', false)
  c.root.pointerSelect(0, false)
  c.root.pointerSelect(1, true)
  assert.deepEqual(Array.from(c.root.markedIds), [1,2])
  c.root.pointerSelect(0, false)
  c.root.moveTargets(20,30)
  c.root.resizeTargets(10,20)
  assert.equal(c.items.get(0).ix,20)
  assert.equal(c.items.get(1).ix,20)
  assert.equal(c.items.get(2).ix,0)
  assert.equal(c.items.get(0).iw,190)
  assert.equal(c.items.get(1).iw,190)
  assert.equal(c.items.get(2).iw,180)
}

{
  const c = controller()
  c.root.trashIndexSaving = false
  c.root.trashIndexError = ''
  c.root.trashIndexNeedsRead = true
  c.root.acceptTrashIndex('{"version":1,"entries":[{"file":"saved","path":"work/a.json"}]}')
  assert.equal(c.root.trashEntries.length,1)
  c.root.acceptTrashIndex('{broken')
  assert.equal(c.root.trashEntries.length,1,'invalid metadata must not replace remembered entries')
  assert.match(c.root.trashIndexError,/invalid/)
  c.root.acceptTrashIndex('{"entries":[{"file":"../boards","path":"a.json"}]}')
  assert.match(c.root.trashIndexError,/invalid/)
  c.root.acceptTrashIndex('{"version":1,"entries":[]}')
  assert.equal(c.root.trashIndexError,'')
}
{
  // The marquee: what it catches, what it leaves, and the cursor it hands to
  // the keyboard afterwards.
  const c = controller()
  c.session.loadBoard('{"items":[{"id":1,"x":0,"y":0},{"id":2,"x":400,"y":0},{"id":3,"x":0,"y":400,"pinned":true}]}', false)
  c.root.markInRect(-10, -10, 10, 10, false)
  assert.deepEqual(Array.from(c.root.markedIds), [1])
  assert.equal(c.root.selectedIndex, 0, 'a sweep leaves a cursor inside what it marked')
  c.root.markInRect(410, 10, 390, -10, true)
  assert.deepEqual(Array.from(c.root.markedIds), [1, 2], 'dragging up and left marks the same items')
  assert.equal(c.root.selectedIndex, 0, 'an additive sweep keeps a cursor that is still marked')
  c.root.markInRect(390, -10, 410, 10, false)
  assert.deepEqual(Array.from(c.root.markedIds), [2], 'without shift the previous marks go')
  assert.equal(c.root.selectedIndex, 1, 'the cursor follows into the new set')
  c.root.markInRect(2000, 2000, 2100, 2100, false)
  assert.deepEqual(Array.from(c.root.markedIds), [])
  assert.equal(c.root.selectedIndex, -1, 'an empty sweep is a deselect')
  c.root.markInRect(-2000, -2000, 2000, 2000, false)
  assert.deepEqual(Array.from(c.root.markedIds), [1, 2], 'the background is never swept up')
  assert.deepEqual(Array.from(c.root.targets()), [1, 0], 'and the marks drive the next operation')
}
console.log('ok — controller: marquee selection, order and cursor handover')
{
  // Pasted pictures: what lands, how big, and what the shape cycle does to it.
  const c = controller()
  c.session.loadBoard('{"version":5,"items":[]}', false)
  c.root.pasteImage('../escape.png', 100, 100)
  assert.equal(c.items.count, 0, 'a name that is not a plain file name never becomes an item')
  c.root.pasteImage('paste-1.png', 1600, 900)
  assert.equal(c.items.count, 1)
  assert.equal(c.items.get(0).kind, 'image')
  assert.equal(c.items.get(0).isrc, 'paste-1.png')
  assert.equal(c.items.get(0).iw, 360, 'the long side sets the size')
  assert.equal(c.items.get(0).ih, 203, 'and the short side keeps the proportions')
  c.root.pasteImage('paste-2.png', 0, 0)
  assert.equal(c.items.get(1).iw, 320, 'an image that could not be measured still lands')
  assert.equal(c.items.get(1).ih, 240)
  c.root.selectedIndex = 0
  c.root.markedIds = []
  c.root.cycleKind()
  assert.equal(c.items.get(0).kind, 'image', 'there is nowhere for an image to cycle to')
  c.root.addItem('note', 0, 0)
  const note = c.items.count - 1
  c.root.selectedIndex = note
  c.root.markedIds = [c.items.get(0).iid, c.items.get(note).iid]
  c.root.cycleKind()
  assert.equal(c.items.get(note).kind, 'rect', 'a shape marked beside an image still cycles')
  assert.equal(c.items.get(0).kind, 'image', 'and the image is left out of it')
}
console.log('ok — controller: pasted images, sizing and the shape cycle')
{
  // Duplicating: what comes along, what does not, and what is selected after.
  const c = controller()
  c.session.loadBoard('{"version":5,"items":[]}', false)
  c.root.addItem('note', 0, 0)
  c.root.addItem('rect', 300, 0)
  c.root.addItem('note', 600, 0)
  const [a, b, outside] = [c.items.get(0).iid, c.items.get(1).iid, c.items.get(2).iid]
  c.root.addLink(a, b)
  c.root.addLink(b, outside)

  c.root.selectedIndex = 0
  c.root.markedIds = [a, b]
  c.root.duplicateTargets()
  assert.equal(c.items.count, 5, 'two copies landed')
  const copies = [c.items.get(3), c.items.get(4)]
  assert.deepEqual(copies.map(n => n.kind), ['note', 'rect'], 'copied in board order, not mark order')
  assert.equal(copies[0].ix, c.items.get(0).ix + 24, 'offset from the original rather than on top of it')
  assert.equal(copies[0].iy, c.items.get(0).iy + 24)
  assert.equal(copies[1].iw, c.items.get(1).iw, 'size comes along')
  assert.equal(copies[1].itint, c.items.get(1).itint, 'so does the colour')
  assert.equal(new Set([a, b, outside, ...copies.map(n => n.iid)]).size, 5, 'every id is distinct')

  assert.equal(c.links.count, 3, 'the connector between the two copies came along')
  const added = c.links.get(2)
  assert.deepEqual([added.lfrom, added.lto], copies.map(n => n.iid),
    'and it joins the copies, not the originals')

  assert.deepEqual(Array.from(c.root.markedIds), copies.map(n => n.iid),
    'the copies are what the next command acts on')
  assert.equal(c.root.selectedIndex, 4, 'with the cursor on the last of them')

  // One item: no marks to inherit, just the cursor on the copy.
  c.root.markedIds = []
  c.root.selectedIndex = 0
  c.root.duplicateTargets()
  assert.equal(c.items.count, 6)
  assert.deepEqual(Array.from(c.root.markedIds), [], 'a single copy does not leave a mark behind')
  assert.equal(c.root.selectedIndex, 5)

  // An image copy shares the file rather than duplicating it.
  c.root.pasteImage('paste-1.png', 100, 100)
  c.root.markedIds = []
  c.root.duplicateTargets()
  assert.equal(c.items.get(c.items.count - 1).isrc, 'paste-1.png')

  // Undo puts the board back, including the connector.
  const before = c.items.count
  c.root.undo()
  assert.equal(c.items.count, before - 1)

  // A pinned item is not a target, so it is not duplicated.
  c.root.selectedIndex = 0
  c.root.markedIds = []
  c.root.togglePin()
  const pinnedCount = c.items.count
  c.root.selectedIndex = 0
  c.root.duplicateTargets()
  assert.equal(c.items.count, pinnedCount, 'a background is left out of it')
}
console.log('ok — controller: duplicating items, their connectors and their pictures')
{
  // The arrange mode: what it refuses, what it does, and what it says.
  const c = controller()
  c.session.loadBoard('{"version":5,"items":[]}', false)
  // Staggered, so there is something to line up and something to even out.
  c.root.addItem('note', 0, 0)
  c.root.addItem('note', 300, 120)
  c.root.addItem('note', 700, 260)
  const ids = [0, 1, 2].map(i => c.items.get(i).iid)

  // One item is not an arrangement.
  c.root.markedIds = []
  c.root.selectedIndex = 0
  c.root.beginArrange()
  assert.equal(c.root.arranging, false, 'one item has nothing to line up with')

  c.root.markedIds = ids.slice(0, 2)
  c.root.beginArrange()
  assert.equal(c.root.arranging, true)

  // Aligning leaves the mode, moves only what needs moving, and is undoable.
  const before = [0, 1].map(i => c.items.get(i).iy)
  c.root.alignTargets('top')
  assert.equal(c.root.arranging, false, 'the mode ends with the command')
  assert.equal(c.items.get(0).iy, c.items.get(1).iy, 'the two share a top edge')
  c.root.undo()
  assert.deepEqual([0, 1].map(i => c.items.get(i).iy), before, 'and undo puts them back')

  // Aligning twice: the second time there is nothing to do and no undo entry.
  c.root.markedIds = ids.slice(0, 2)
  c.root.alignTargets('top')
  const depth = c.root.undoStack.length
  c.root.alignTargets('top')
  assert.equal(c.root.undoStack.length, depth, 'an alignment that changes nothing is not history')

  // Spreading needs three.
  c.root.markedIds = ids.slice(0, 2)
  c.root.spreadTargets('x')
  assert.equal(c.root.arranging, false)
  c.root.markedIds = ids
  c.root.spreadTargets('x')
  const gaps = [
    c.items.get(1).ix - (c.items.get(0).ix + c.items.get(0).iw),
    c.items.get(2).ix - (c.items.get(1).ix + c.items.get(1).iw)
  ]
  assert.ok(Math.abs(gaps[0] - gaps[1]) < 1e-9, 'evenly spaced: ' + gaps)

  // A read-only board arranges nothing.
  const ro = controller()
  ro.session.loadBoard('{broken', false)
  ro.root.beginArrange()
  assert.equal(ro.root.arranging, false, 'a board that cannot be edited cannot be arranged')
}
console.log('ok — controller: the arrange mode, aligning and spreading')
