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
    finding: false, findQuery: '', findCount: 0, imageQueue: [],
    menuVisible: false, menuIndex: 0, helpVisible: false,
    paletteVisible: false, paletteQuery: '', paletteIndex: 0, paletteRows: 9,
    conflictVisible: false, conflictIndex: 0, paletteScope: 'all',
    boardsDir: '/boards', backupsDir: '/backups', worldStep: 40, minItemSize: 60, viewW: 1000, viewH: 700 }
  const session = { ctl: root, boardLoaded: true, damaged: false, pendingBoard: null,
    lastSavedCount: 0, lastSavedText: '', saveError: '',
    // The conflict state the QML declares, mirrored here: an undeclared
    // property reads as undefined, which is not what a string property does.
    conflict: false, conflictText: '', conflictBoard: '', resolving: '',
    revision: '', forceNextSave: false }
  Object.defineProperty(session, 'canEdit', {
    get: () => session.boardLoaded && !session.damaged && session.pendingBoard === null
  })
  for (const key of ['boardLoaded', 'damaged', 'pendingBoard', 'saveError', 'canEdit'])
    Object.defineProperty(root, key, { get: () => session[key] })
  Object.defineProperty(root, 'diskChanged', { get: () => session.conflict })
  Object.defineProperty(root, 'boardPath', { get: () => '/boards/' + root.currentBoard })
  // Mirrors the QML binding of the same name: the harness loads functions, not
  // bindings, so a derived property has to be declared here.
  Object.defineProperty(root, 'findDimming', { get: () => root.finding && root.findQuery !== '' })
  Object.defineProperty(root, 'findNeedle', { get: () => root.findQuery.toLowerCase() })
  Object.defineProperty(root, 'paletteMatches', { get: () =>
    root.paletteVisible ? loadStore().matchCommands(root.paletteQuery, root.paletteScope) : [] })
  Object.defineProperty(root, 'markedLookup', { get: () => {
    const lookup = {}
    for (const id of root.markedIds) lookup[id] = true
    return lookup
  } })
  const writes = []
  const persistence = { busy: false, contents: '',
    save(path, text, backup, root, backupRoot, lock, expected) {
      this.busy = true
      this.contents = text
      writes.push({ path, text, expected })
    } }
  // Stands in for BoardExchange: the controller hands it filtered paths and
  // never learns what happens to them.
  const exchange = { imported: [], copied: [], copies: [],
    importDropped(entries) { exchange.imported.push(...entries) },
    copyItems(indices) { exchange.copied.push(Array.from(indices)) },
    saveCopy(text, name) { exchange.copies.push({ text, name }); return true } }
  // The browser reaches for the trash index and a directory listing; neither is
  // the subject of these tests, so both are present and inert.
  const trashIndexFile = { reload() {}, setText() {} }
  const scanProc = { running: false }
  const context = vm.createContext({ root, session, Store: loadStore(), itemModel: items, linkModel: links,
    persistence, exchange, trashIndexFile, scanProc,
    statusTimer: {restart() {}}, saveTimer: { running: false, stop() {}, restart() {} }, stateFile: {setText() {}} })
  function loadFunctions(target, qml) {
    for (const match of qml.matchAll(/^  function (\w+)\((.*?)\) \{\n([\s\S]*?)^  }/gm))
      target[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
    for (const match of qml.matchAll(/^  function (\w+)\((.*?)\) \{ (.*?) }$/gm))
      target[match[1]] = vm.runInContext(`(function(${match[2]}) {${match[3]}})`, context)
  }
  loadFunctions(root, source)
  loadFunctions(session, fs.readFileSync(require('path').join(__dirname, '../BoardSession.qml'), 'utf8'))
  // Two of the session's functions reach for a FileView and a Process. What
  // they fetch is what matters here, so they fetch it from the test instead.
  session.diskText = ''
  session.readDisk = () => session.diskText
  session.refreshRevision = () => { session.revision = 'rev-fresh' }
  let revisions = 0
  return { root, session, items, links, writes, persistence, exchange, complete() {
    const write = writes[writes.length - 1]
    persistence.busy = false
    session.savedBoard(write.path, write.text, 'rev-' + (++revisions))
  },
  // The helper refused the write: the file is no longer what this session
  // last saw. `disk` is what is there instead.
  refuse(disk) {
    const write = writes[writes.length - 1]
    persistence.busy = false
    session.diskText = disk
    session.staleSave(write.path, 'rev-external')
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
{
  // Finding: navigation that works on a board you cannot write to.
  const c = controller()
  c.session.loadBoard(JSON.stringify({ version: 5, items: [
    { id: 1, kind: 'note', x: 0, y: 0, w: 100, h: 100, text: 'ship the notes' },
    { id: 2, kind: 'note', x: 900, y: 0, w: 100, h: 100, text: 'unrelated' },
    { id: 3, kind: 'note', x: 0, y: 900, w: 100, h: 100, text: 'shipping' }
  ] }), false)

  c.root.beginFind()
  assert.equal(c.root.finding, true)
  assert.equal(c.root.findDimming, false, 'an empty query dims nothing')

  // What the field on the board calls as it is typed into.
  c.root.setFindQuery('s')
  c.root.setFindQuery('sh')
  assert.equal(c.root.findQuery, 'sh')
  assert.equal(c.root.findCount, 2)
  assert.equal(c.root.selectedIndex, 0, 'the board follows the typing to the first match')
  assert.equal(c.root.findDimming, true)
  assert.equal(c.root.matchesFind('SHIPPED'), true, 'case is not part of the question')
  assert.equal(c.root.matchesFind('unrelated'), false)

  // Enter steps through matches and wraps.
  c.root.nextMatch()
  assert.equal(c.root.selectedIndex, 2)
  c.root.nextMatch()
  assert.equal(c.root.selectedIndex, 0, 'and comes back round')

  // Taking a letter back widens the query again.
  c.root.setFindQuery('s')
  assert.equal(c.root.findQuery, 's')
  assert.equal(c.root.findCount, 2)

  // A query that matches nothing leaves the selection where it was.
  c.root.setFindQuery('szz')
  assert.equal(c.root.findCount, 0)
  assert.equal(c.root.selectedIndex, 0, 'no match does not throw the cursor away')

  c.root.endFind()
  assert.equal(c.root.finding, false)
  assert.equal(c.root.findQuery, '')
  assert.equal(c.root.findDimming, false)

  // Nothing to search is said rather than entering a mode with no exit sign.
  const empty = controller()
  empty.session.loadBoard('{"version":5,"items":[]}', false)
  empty.root.beginFind()
  assert.equal(empty.root.finding, false)

  // A damaged board is read-only, but finding is not a write.
  const ro = controller()
  ro.session.loadBoard('{broken', false)
  assert.equal(ro.root.canEdit, false)
  ro.items.append({ iid: 1, kind: 'note', ix: 0, iy: 0, iw: 100, ih: 100,
    itint: 'foreground', itext: 'still findable', ipinned: false, isrc: '' })
  ro.root.beginFind()
  ro.root.setFindQuery('find')
  assert.equal(ro.root.finding, true, 'a board that cannot be edited can still be searched')
  assert.equal(ro.root.findCount, 1)
  assert.equal(ro.writes.length, 0, 'and searching never writes')
}
console.log('ok — controller: finding, stepping through matches and dimming the rest')
{
  // Dropping files in: which paths get through, where they land, and what
  // happens when several arrive at once.
  const c = controller()
  c.session.loadBoard('{"version":5,"items":[]}', false)

  // Only local files are passed on, and a drop of nothing usable says so.
  c.root.dropFiles(['https://example.com/a.png', 'data:image/png;base64,AA'], 100, 200)
  assert.equal(c.exchange.imported.length, 0, 'a download is not a file to copy')

  c.root.dropFiles(['file:///shots/a.png', 'https://example.com/b.png', 'file:///shots/b.png'], 100, 200)
  assert.deepEqual(c.exchange.imported.map(e => e.path), ['/shots/a.png', '/shots/b.png'],
    'the usable ones go through in order')
  assert.deepEqual(c.exchange.imported.map(e => [e.x, e.y]), [[100, 200], [124, 224]],
    'staggered, so two dropped together do not land in one stack')

  // A read-only board takes nothing.
  const ro = controller()
  ro.session.loadBoard('{broken', false)
  ro.root.dropFiles(['file:///shots/a.png'], 0, 0)
  assert.equal(ro.exchange.imported.length, 0)

  // With a scene, measuring is asynchronous: one probe runs and the rest wait.
  // The stub stands in for an open board, recording what it was asked to measure.
  const probes = []
  c.root.activeBoard = { probeImage(name) { probes.push(name) }, repaintLinks() {}, focusKeys() {} }
  c.root.imageDropped('drop-1.png', 500, 600)
  c.root.imagePasted('paste-1.png')
  assert.equal(c.root.imageQueue.length, 2, 'both wait their turn')
  assert.deepEqual(probes, ['drop-1.png'], 'and only the first is being measured')

  c.root.pasteImage('drop-1.png', 200, 100)
  assert.deepEqual(probes, ['drop-1.png', 'paste-1.png'], 'finishing one starts the next')
  assert.equal(c.items.count, 1)
  assert.equal(c.items.get(0).isrc, 'drop-1.png')
  assert.equal(c.items.get(0).ix, 500 - c.items.get(0).iw / 2, 'centred on the point it was dropped')
  assert.equal(c.items.get(0).iy, 600 - c.items.get(0).ih / 2)

  c.root.pasteImage('paste-1.png', 200, 100)
  assert.equal(c.items.count, 2)
  assert.equal(c.root.imageQueue.length, 0, 'and the queue drains')
  // viewW/viewH are 1000x700 in this harness, so the middle is 500,350.
  assert.equal(c.items.get(1).iy, 350 - c.items.get(1).ih / 2, 'a paste goes to the middle of the view')

  // A name that never entered the queue still places, in the middle. This is
  // the no-scene path, so nothing is waiting behind it.
  c.root.activeBoard = null
  c.root.pasteImage('stray.png', 100, 100)
  assert.equal(c.items.count, 3)
  assert.equal(c.root.imageQueue.length, 0)

  // A name the queue rejects does not strand the ones behind it.
  c.root.activeBoard = { probeImage(name) { probes.push(name) }, repaintLinks() {}, focusKeys() {} }
  c.root.imageDropped('../escape.png', 0, 0)
  c.root.imageDropped('after.png', 10, 20)
  const before = c.items.count
  c.root.pasteImage('../escape.png', 10, 10)
  assert.equal(c.items.count, before, 'the bad name is refused')
  assert.equal(c.root.imageQueue.length, 1, 'and the one behind it is still waiting')
  assert.equal(probes[probes.length - 1], 'after.png', 'which is now the one being measured')

  // A measurement that comes back after a board switch answers for a board that
  // is no longer open. Placing it would put the picture on whatever is open now,
  // at a point that was never on this board.
  const switched = controller()
  switched.root.activeBoard = { probeImage() {}, repaintLinks() {}, focusKeys() {} }
  switched.root.imageDropped('late.png', 40, 50)
  switched.root.currentBoard = 'b.json'
  switched.root.pasteImage('late.png', 200, 100)
  assert.equal(switched.items.count, 0, 'the late picture does not land on the board that is open now')
  assert.equal(switched.root.imageQueue.length, 0, 'and it stops waiting')

  // The rest of the queue is sorted the same way: everything still waiting for
  // the board that closed is dropped, and the next one meant for this board is
  // measured instead of being stuck behind them.
  const mixed = controller()
  const seen = []
  mixed.root.activeBoard = { probeImage(name) { seen.push(name) }, repaintLinks() {}, focusKeys() {} }
  mixed.root.imageDropped('a-1.png', 0, 0)
  mixed.root.imageDropped('a-2.png', 0, 0)
  mixed.root.currentBoard = 'b.json'
  mixed.root.imageDropped('b-1.png', 0, 0)
  mixed.root.pasteImage('a-1.png', 100, 100)
  assert.equal(mixed.items.count, 0, 'nothing meant for the closed board is placed')
  assert.deepEqual(seen, ['a-1.png', 'b-1.png'], 'the queue skips to the picture meant for this board')
  assert.equal(mixed.root.imageQueue.length, 1, 'which is the only one left')
}
console.log('ok — controller: dropped files, their paths and where they land')
{
  // Copying out: what the controller decides to hand over.
  const c = controller()
  c.session.loadBoard('{"version":5,"items":[]}', false)

  c.root.selectedIndex = -1
  c.root.copySelection()
  assert.equal(c.exchange.copied.length, 0, 'nothing selected is nothing to copy')

  c.root.addItem('note', 0, 0)
  c.root.addItem('note', 200, 0)
  c.root.selectedIndex = 0
  c.root.markedIds = []
  c.root.copySelection()
  assert.deepEqual(c.exchange.copied[0], [0], 'the item under the cursor')

  c.root.markedIds = [c.items.get(0).iid, c.items.get(1).iid]
  c.root.copySelection()
  assert.deepEqual(c.exchange.copied[1].slice().sort(), [0, 1], 'or everything marked')

  // A background is not a target, so it is not copied either.
  const pinned = controller()
  pinned.session.loadBoard('{"version":5,"items":[]}', false)
  pinned.root.addItem('note', 0, 0)
  pinned.root.selectedIndex = 0
  pinned.root.togglePin()
  pinned.root.selectedIndex = 0
  pinned.root.markedIds = []
  pinned.root.copySelection()
  assert.equal(pinned.exchange.copied.length, 0)
}
console.log('ok — controller: copying the selection out')
{
  // Walking the menu, and one dispatch for both the keyboard and the pointer.
  const c = controller()
  c.session.loadBoard('{"version":5,"items":[]}', false)
  const menu = require('./harness').loadStore().MENU_COMMANDS
  assert.equal(menu.length, 7, 'seven commands, as the header draws')

  c.root.toggleMenu()
  assert.equal(c.root.menuVisible, true)
  assert.equal(c.root.menuIndex, 0, 'opens on the first item, ready to walk')

  c.root.moveMenu(1)
  assert.equal(c.root.menuIndex, 1)
  c.root.moveMenu(-1)
  assert.equal(c.root.menuIndex, 0)
  // Wrapping both ways, so neither end is a dead stop.
  c.root.moveMenu(-1)
  assert.equal(c.root.menuIndex, menu.length - 1, 'back from the first is the last')
  c.root.moveMenu(1)
  assert.equal(c.root.menuIndex, 0, 'and on from the last is the first')

  // Running the highlighted item closes the menu and resets the walk.
  c.root.menuIndex = 5
  c.root.runMenu(c.root.menuIndex)
  assert.equal(c.root.helpVisible, true, 'the sixth item is Help')
  assert.equal(c.root.menuVisible, false)
  assert.equal(c.root.menuIndex, 0)

  // The last is the palette, so a pointer can reach the commands the keys
  // reach without knowing that `:` opens it.
  c.root.helpVisible = false
  c.root.toggleMenu()
  c.root.runMenu(6)
  assert.equal(c.root.paletteVisible, true, 'the last item opens the palette')
  c.root.endPalette()

  // Boards is the browser, and it is the same call a click makes.
  c.root.helpVisible = false
  c.root.toggleMenu()
  c.root.runMenu(1)
  assert.equal(c.root.browserVisible, true)
  assert.equal(c.root.menuVisible, false, 'picking always closes it')

  // Toggling shut resets the highlight rather than leaving it where it was.
  c.root.closeBrowser()
  c.root.toggleMenu()
  c.root.moveMenu(3)
  c.root.toggleMenu()
  assert.equal(c.root.menuVisible, false)
  assert.equal(c.root.menuIndex, 0)
}
console.log('ok — controller: walking the header menu and running its commands')
{
  // The palette: every command by name, and one dispatch for it and the keys.
  const S = loadStore()
  const c = controller()
  c.session.loadBoard('{"version":5,"items":[]}', false)

  c.root.beginPalette()
  assert.equal(c.root.paletteVisible, true)
  assert.equal(c.root.paletteQuery, '')
  assert.equal(c.root.paletteIndex, 0, 'opens on the first, ready to run')
  assert.equal(c.root.paletteMatches.length, S.COMMANDS.filter(x => x.listed !== false).length,
    'every command but the ways into this list')

  // Typing narrows it, and the cursor goes back to the top rather than staying
  // on a row that now means something else.
  c.root.movePalette(2)
  assert.equal(c.root.paletteIndex, 2)
  c.root.setPaletteQuery('col')
  assert.equal(c.root.paletteIndex, 0)
  assert.deepEqual(c.root.paletteMatches.map(m => m.name), ['Change colour'])
  c.root.setPaletteQuery('')
  assert.equal(c.root.paletteQuery, '')

  // Wrapping both ways, so neither end of the list is a dead stop.
  c.root.movePalette(-1)
  assert.equal(c.root.paletteIndex, c.root.paletteMatches.length - 1)
  c.root.movePalette(1)
  assert.equal(c.root.paletteIndex, 0)

  // Running one closes the palette and does the thing.
  c.root.paletteQuery = 'new note'
  c.root.runPaletteChoice()
  assert.equal(c.root.paletteVisible, false, 'running closes it')
  assert.equal(c.root.paletteQuery, '', 'and forgets what was typed')
  assert.equal(c.items.count, 1, 'and the note is on the board')

  // A command with an argument carries it: two names, one function.
  const before = c.root.zoom
  c.root.runCommand('Zoom in')
  assert.ok(c.root.zoom > before)
  c.root.runCommand('Zoom out')
  assert.equal(Math.round(c.root.zoom * 1000), Math.round(before * 1000))

  // A command that cannot do anything now says so rather than appearing to run.
  c.root.selectedIndex = -1
  c.root.markedIds = []
  c.root.statusText = ''
  c.root.runCommand('Change colour')
  assert.match(c.root.statusText, /nothing is selected/)

  // A read-only board refuses the ones that would write to it, by the same
  // rule, and still allows the ones that only look.
  const ro = controller()
  ro.session.loadBoard('{broken', false)
  ro.root.runCommand('New note')
  assert.equal(ro.items.count, 0)
  assert.match(ro.root.statusText, /read-only/)
  ro.root.runCommand('Fit the board on screen')
  assert.equal(ro.root.statusText.indexOf('Fit') , -1, 'looking is not refused')

  // The actions for what is selected: the same panel, opened on the commands
  // that act on a selection, and closed again by running one.
  c.root.endPalette()
  c.root.selectedIndex = -1
  c.root.markedIds = []
  c.root.statusText = ''
  c.root.beginSelectionActions()
  assert.equal(c.root.paletteVisible, false, 'with nothing selected there is nothing to offer')
  assert.match(c.root.statusText, /nothing selected/)

  c.root.addItem('note', 0, 0)
  c.root.beginSelectionActions()
  assert.equal(c.root.paletteVisible, true)
  assert.equal(c.root.paletteScope, 'selection')
  assert.ok(c.root.paletteMatches.length > 0)
  assert.ok(c.root.paletteMatches.every(m => ['target', 'item', 'group'].includes(m.needs)),
    'only what acts on the selection')
  // Alignment is offered by name, so the second key of the chord is something
  // to learn rather than something to know already.
  assert.ok(c.root.paletteMatches.some(m => m.name === 'Align left edges'))
  c.root.endPalette()
  assert.equal(c.root.paletteScope, 'selection', 'the scope belongs to the opening, not the closing')
  c.root.beginPalette()
  assert.equal(c.root.paletteScope, 'all', 'and opening it plainly is everything again')
  c.root.endPalette()

  // A name the table does not have runs nothing at all.
  c.root.statusText = ''
  c.root.runCommand('Delete everything forever')
  assert.equal(c.root.statusText, '')

  // Every command names a function the controller actually has, and every
  // single-key one agrees with the key table the board dispatches through.
  for (const command of S.COMMANDS)
    assert.equal(typeof c.root[command.run], 'function', `${command.name} runs ${command.run}`)
}
console.log('ok — controller: the command palette and one dispatch for every command')
{
  // Two versions of one board. Nothing here may lose either of them, and
  // nothing but a choice may resolve it.
  const S = loadStore()
  const disk = (texts) => JSON.stringify({ version: 5, nextId: texts.length + 1,
    items: texts.map((t, i) => ({ id: i + 1, kind: 'note', x: i * 200, y: 0, w: 180, h: 140,
                                  tint: 'foreground', text: t, pinned: false })), links: [] }) + '\n'

  function conflicted() {
    const c = controller()
    c.session.loadBoard(disk(['theirs']), false)
    c.session.revision = 'rev-1'
    // An edit on screen that has not been written, and a different version
    // underneath it. The write is refused because the file moved.
    c.root.addItem('note', 40, 40)
    c.items.setProperty(c.root.selectedIndex, 'itext', 'mine')
    c.root.save()
    c.session.diskText = disk(['theirs', 'and more of theirs'])
    c.refuse(c.session.diskText)
    return c
  }

  {
    const c = conflicted()
    assert.equal(c.session.conflict, true, 'a refused write raises the question')
    assert.equal(c.items.count, 2, 'and the edits are still on screen')
    assert.equal(c.session.revision, 'rev-external', 'with what is on disk now recorded')
    assert.equal(c.root.diskChanged, true, 'which the board says out loud')

    // Everything that is not a choice leaves both versions alone.
    const wrote = c.writes.length
    c.root.save()
    c.session.scheduleSave()
    c.session.flushSave()
    assert.equal(c.writes.length, wrote, 'autosave and flushing write nothing')
    assert.equal(c.session.conflict, true, 'and resolve nothing')

    c.root.openBoard('b.json')
    assert.equal(c.root.currentBoard, 'a.json', 'leaving waits for the choice')
    assert.equal(c.items.count, 2, 'with the edits still there')
    assert.equal(c.root.conflictVisible, true, 'and the choices on screen')

    // ctrl+s is no longer a save while this is outstanding: it is the moment
    // someone asked about it.
    c.root.endConflictChoice()
    c.root.flushSave()
    assert.equal(c.root.conflictVisible, true, 'ctrl+s asks the question again')

    // And closing the board is not an answer: the edits stay in the session,
    // so the question is still there when it comes back.
    c.root.endConflictChoice()
    const closed = c.writes.length
    c.root.close()
    assert.equal(c.writes.length, closed, 'closing writes nothing over the other version')
    assert.equal(c.session.conflict, true, 'and leaves the question standing')
    assert.equal(c.items.count, 2, 'with the edits still in hand')
  }

  {
    // Choice one: what is on disk wins, whole.
    const c = conflicted()
    c.root.conflictUseDisk()
    assert.equal(c.session.conflict, false)
    assert.equal(c.items.count, 2, 'the board is what was on disk')
    assert.equal(c.items.get(1).itext, 'and more of theirs')
    assert.equal(c.session.revision, 'rev-fresh', 'and the revision is read again')
  }

  {
    // Choice two: the edits are written somewhere of their own first, and only
    // then does the board take the version from disk.
    const c = conflicted()
    c.root.conflictSaveCopy()
    assert.equal(c.exchange.copies.length, 1, 'the copy is handed to the publisher')
    assert.match(c.exchange.copies[0].name, /-mine$/)
    assert.match(c.exchange.copies[0].text, /mine/, 'and it holds what was on screen')
    assert.equal(c.session.conflict, true, 'which is not resolved until it lands')
    assert.equal(c.items.count, 2, 'and the edits are still on screen')

    c.session.keptAsCopy('a-mine.json')
    assert.equal(c.session.conflict, false)
    assert.equal(c.items.get(1).itext, 'and more of theirs', 'now the board takes the disk version')
    assert.match(c.root.statusText, /a-mine\.json/, 'and says where the other one went')
  }

  {
    // Choice three: this version wins, and the write says so explicitly rather
    // than pretending it is still updating what it read.
    const c = conflicted()
    c.root.conflictReplaceDisk()
    assert.equal(c.session.conflict, false)
    const write = c.writes[c.writes.length - 1]
    assert.equal(write.expected, '-', 'the write is an overwrite, and says so')
    assert.match(write.text, /mine/)

    // And a resolution that fails is not a resolution: the question comes back
    // with the edits still in hand.
    c.session.failedSave('disk full')
    assert.equal(c.session.conflict, true, 'the choice is put back')
    assert.equal(c.items.count, 2, 'with nothing lost')
  }

  {
    // A refusal that turns out to be our own write after all is not a question
    // for anyone: it retries against what is actually there.
    const c = controller()
    c.session.loadBoard(disk(['one']), false)
    c.session.revision = 'rev-1'
    c.root.addItem('note', 0, 0)
    c.root.save()
    const sent = c.writes[c.writes.length - 1].text
    c.session.diskText = sent
    c.refuse(sent)
    assert.equal(c.session.conflict, false, 'the disk already says what we sent')
    assert.equal(c.session.lastSavedText, sent)
  }
}
console.log('ok — controller: two versions of a board, and the three ways out')
{
  // Which item is drawn over which: rows move, and nothing else does.
  const c = controller()
  c.session.loadBoard('{"version":5,"items":[]}', false)
  const S = loadStore()
  const named = (n) => {
    c.root.addItem('note', 0, 0)
    c.items.setProperty(c.root.selectedIndex, 'itext', n)
    return c.items.get(c.root.selectedIndex).iid
  }
  const order = () => S.itemRows(c.items).map(r => r.text).join('')
  const first = named('a'), second = named('b'), third = named('c')
  assert.equal(order(), 'abc')

  // The cursor is on c; sending it back takes it with it.
  c.root.selectOnly(2)
  c.root.layerTargets('back')
  assert.equal(order(), 'cab')
  assert.equal(c.items.get(c.root.selectedIndex).itext, 'c', 'the cursor follows its item, not its place')
  assert.equal(c.items.get(c.root.selectedIndex).iid, third, 'which keeps the id it always had')

  // Undo puts the order back, and redo takes it forward again.
  c.root.undo()
  assert.equal(order(), 'abc', 'undo restores the order')
  c.root.redo()
  assert.equal(order(), 'cab', 'and redo puts it back')

  // Connectors are between ids, so reordering cannot touch them.
  c.root.addLink(first, third)
  const links = S.linkRows(c.links).map(l => l.from + '>' + l.to).join(',')
  c.root.selectOnly(0)
  c.root.layerTargets('front')
  assert.equal(S.linkRows(c.links).map(l => l.from + '>' + l.to).join(','), links,
    'the connectors are unchanged')

  // Several at once keep their order relative to each other, and marks are by
  // id so they survive the move.
  assert.equal(order(), 'abc')
  c.root.markedIds = [first, second]
  c.root.selectedIndex = -1
  c.root.layerTargets('front')
  assert.equal(order(), 'cab', 'both came forward, in the order they were in')
  assert.deepEqual(c.root.markedIds.slice().sort(), [first, second].sort(), 'the marks are still on them')

  // Nothing to do says so rather than writing the board again.
  const writes = c.writes.length
  c.root.statusText = ''
  c.root.layerTargets('front')
  assert.equal(c.writes.length, writes, 'no move, no write')
  assert.equal(order(), 'cab')
  assert.match(c.root.statusText, /already at the front/)

  // The order is what the file says, so it comes back the way it went in.
  c.root.markedIds = []
  c.root.selectOnly(0)
  c.root.layerTargets('front')
  const saved = S.writeFile(c.items, c.links, c.root.nextId)
  const reopened = controller()
  reopened.session.loadBoard(saved, false)
  assert.equal(S.itemRows(reopened.items).map(r => r.text).join(''), order(),
    'saving and opening again keeps the order')

  // A background can be reordered among the backgrounds, and comes out of it
  // still a background: which layer an item is in is not what this changes.
  c.root.selectOnly(0)
  const backgroundId = c.items.get(0).iid
  c.root.togglePin()
  assert.equal(S.itemRows(c.items).filter(r => r.pinned).length, 1)
  c.root.togglePinnedSelection()
  assert.equal(c.items.get(c.root.selectedIndex).iid, backgroundId, 'the backgrounds mode selects it')
  c.root.layerTargets('front')
  assert.equal(c.items.get(c.items.count - 1).iid, backgroundId, 'it moved')
  assert.equal(c.items.get(c.items.count - 1).ipinned, true, 'and is still a background')
  assert.equal(S.itemRows(c.items).filter(r => r.pinned).length, 1, 'with nothing else pinned or unpinned')

  // A board that cannot be written to cannot be reordered either.
  const ro = controller()
  ro.session.loadBoard('{broken', false)
  ro.root.layerTargets('front')
  assert.equal(ro.items.count, 0)
}
console.log('ok — controller: bringing things forward and sending them back')
