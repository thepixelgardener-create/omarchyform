// Two panes: one board seen twice, or two boards side by side. The workspace,
// its panes and their documents run from the QML sources, as in
// tests/controller.js, with writes that land only when a test says so.
const assert = require('assert/strict')
const { controller } = require('./workspace-harness')

function addNotes(c, pane, n) {
  for (let i = 0; i < n; i++) {
    pane.addItem('note', i * 300, 0)
    c.of(pane.doc).complete()
  }
}

{
  // A split is a second view of the board that is open, looking where the
  // first one was, with the keyboard in it.
  const c = controller()
  const a = c.root, b = c.second
  addNotes(c, a, 1)
  a.camX = 30
  a.zoom = 2
  a.selectOnly(0)
  a.editSelected()
  assert.equal(a.editIndex, 0)
  a.toggleSplit('side-by-side')
  assert.equal(c.workspace.layout, 'side-by-side')
  assert.equal(b.doc, a.doc, 'the same document, not a copy of it')
  assert.equal(c.workspace.documents.length, 1)
  assert.equal(c.workspace.activePane, b, 'the keyboard goes to the new view')
  assert.equal(a.editIndex, -1, 'typing in the pane left behind ends')
  assert.equal(a.selectedIndex, 0, 'and what was selected there stays')
  assert.equal(b.camX, 30)
  assert.equal(b.zoom, 2)
  assert.match(b.statusText, /b opens another board here/)
  const state = JSON.parse(c.states.at(-1))
  assert.equal(state.layout, 'side-by-side')
  assert.equal(state.otherBoard, 'a.json')
  assert.equal(state.lastBoard, 'a.json')

  // The other key turns one split into the other; its own key takes it away.
  b.toggleSplit('stacked')
  assert.equal(c.workspace.layout, 'stacked')
  assert.equal(c.workspace.activePane, b)
  b.toggleSplit('stacked')
  assert.equal(c.workspace.layout, 'single')
  assert.equal(c.workspace.panes[0], b, 'the pane the keyboard was in is the one that stays')
  assert.equal(a.doc, null)
  assert.equal(c.workspace.documents.length, 1, 'its board stays open: the pane kept is showing it')
  assert.equal(JSON.parse(c.states.at(-1)).layout, 'single')
  assert.equal(JSON.parse(c.states.at(-1)).otherBoard, '')
  console.log('ok — split: a second view of one board, turned and taken away')
}

{
  // `o` moves the keyboard, and the pane it leaves ends what it was doing.
  const c = controller()
  const a = c.root, b = c.second
  a.otherPane()
  assert.match(a.statusText, /v or V splits it/, 'one pane has no other')
  a.toggleSplit('side-by-side')
  b.beginPalette()
  assert.equal(b.paletteVisible, true)
  b.otherPane()
  assert.equal(c.workspace.activePane, a)
  assert.equal(b.paletteVisible, false, 'the palette closes in the pane left behind')
  assert.equal(a.active, true)
  assert.equal(b.active, false)

  // Not while the browser is up: it belongs to the pane that opened it.
  c.library.showing = true
  assert.equal(a.browsing, true)
  assert.equal(b.browsing, false, 'it is drawn over one pane, not both')
  a.otherPane()
  assert.equal(c.workspace.activePane, a)
  c.library.showing = false

  // The keys are for the pane the keyboard is in. The other one's line stays
  // quiet until it has something to say.
  a.statusText = ''
  b.statusText = ''
  if (c.persistence.busy) c.complete()
  assert.equal(c.store.statusTier(a.statusState()), 'hints')
  assert.equal(c.store.statusTier(b.statusState()), 'none')
  b.flash('Board changed on disk; reloaded')
  assert.equal(c.store.statusTier(b.statusState()), 'flash')
  console.log('ok — split: moving between panes, and what each line says')
}

{
  // One board in two panes. A cursor is a row, and rows move when the other
  // pane deletes one, so a pane finds the item it was on again after every
  // edit made there — or lets go of it.
  const c = controller()
  const a = c.root, b = c.second
  addNotes(c, a, 4)
  a.toggleSplit('side-by-side')
  a.selectOnly(2)
  a.markedIds = [3, 4]
  assert.equal(a.cursorId, 3)

  b.selectOnly(0)
  b.removeTargets()
  c.complete()
  assert.equal(c.items.count, 3)
  assert.equal(a.selectedIndex, 1, 'the row moved, and the cursor went with its item')
  assert.equal(c.items.get(a.selectedIndex).iid, 3)

  b.selectOnly(1)
  b.removeTargets()
  c.complete()
  assert.equal(a.selectedIndex, -1, 'the item it was on is gone, so it lets go')
  assert.deepEqual(a.markedIds, [4], 'and the mark on it is dropped, so the count stays true')
  assert.equal(b.selectedIndex, 1, 'the pane that deleted keeps its place as it always has')

  // Undo belongs to the board, whichever pane made the edit.
  a.selectOnly(0)
  b.undo()
  c.complete()
  assert.equal(c.items.count, 3, 'the delete made in one pane is undone from the other')
  assert.equal(c.items.get(a.selectedIndex).iid, 2, 'and the cursor over there is still on its item')
  console.log('ok — split: two views of one board follow each other\'s edits')
}

{
  // A board nobody else is showing switches in place, through the session's
  // own switch: it saves first and waits for a write in flight.
  const c = controller()
  const a = c.root
  const doc = a.doc
  a.addItem('note', 0, 0)
  a.openBoard('b.json')
  assert.equal(doc.pendingBoard.path, 'b.json', 'the session waits for the write, as it always has')
  c.complete()
  assert.equal(a.doc, doc, 'the same document, now holding the other board')
  assert.equal(doc.currentBoard, 'b.json')
  assert.equal(c.workspace.documents.length, 1)
  console.log('ok — split: one pane switches boards the way it always has')
}

{
  // A pane sharing its board opens another one: a document of its own, and
  // the other pane's left alone. Back onto the first board, its own is saved,
  // closed, and the two share again.
  const c = controller()
  const a = c.root, b = c.second
  a.toggleSplit('side-by-side')
  b.openBoard('b.json')
  assert.notEqual(b.doc, a.doc)
  assert.equal(b.doc.currentBoard, 'b.json')
  assert.equal(a.doc.currentBoard, 'a.json')
  assert.equal(c.workspace.documents.length, 2)
  assert.equal(JSON.parse(c.states.at(-1)).otherBoard, 'b.json')

  const own = b.doc
  b.addItem('note', 0, 0)
  assert.equal(c.of(own).persistence.busy, true)
  b.openBoard('a.json')
  assert.equal(b.doc, own, 'not before its write has landed')
  assert.equal(b.leaving, true)
  assert.equal(b.canEdit, false, 'and nothing more goes into it meanwhile')
  b.statusText = ''
  assert.equal(c.store.statusTier(b.statusState()), 'switching', 'and its line says what it is waiting for')
  c.workspace.retryLeave()
  assert.equal(b.doc, own, 'still waiting')
  c.of(own).complete()
  c.workspace.retryLeave()
  assert.equal(b.doc, a.doc)
  assert.equal(b.leaving, false)
  assert.equal(own.destroyed, true, 'a board nobody shows is closed')
  assert.deepEqual(c.workspace.documents, [a.doc])

  // A board made in the browser from a pane that is sharing goes into a
  // document of its own, which makes the file once it is found missing.
  c.library.openRequested('new.json', true)
  assert.equal(b.doc.currentBoard, 'new.json')
  assert.equal(c.of(b.doc).session.createWhenLoaded, true)
  assert.equal(a.doc.currentBoard, 'a.json', 'the first pane keeps its board')
  console.log('ok — split: a pane opens a board of its own, and comes back to share')
}

{
  // Two versions of a board, or a failed save, are not walked away from — not
  // by switching the pane, and not by closing it.
  const c = controller()
  const a = c.root, b = c.second
  a.toggleSplit('side-by-side')
  b.openBoard('b.json')
  const own = b.doc
  c.of(own).session.conflict = true
  b.openBoard('a.json')
  assert.equal(b.doc, own, 'the pane stays on the board with two versions')
  assert.equal(b.conflictVisible, true, 'and the choice is put on screen')

  b.conflictVisible = false
  c.workspace.activate(a)
  a.toggleSplit('side-by-side')
  assert.equal(c.workspace.layout, 'side-by-side', 'closing the split would hide it, so it stays')
  assert.equal(c.workspace.activePane, b, 'the keyboard goes to the pane with the question')
  assert.equal(b.conflictVisible, true)

  c.of(own).session.conflict = false
  c.of(own).session.saveError = 'Could not save — ctrl+s to retry'
  b.openBoard('a.json')
  assert.equal(b.doc, own, 'a failed save keeps the pane on its board too')

  // A write that fails while the pane waits cancels the leaving.
  c.of(own).session.saveError = ''
  b.addItem('note', 0, 0)
  b.openBoard('a.json')
  assert.equal(b.leaving, true)
  c.of(own).persistence.busy = false
  c.of(own).session.failedSave('disk full')
  c.workspace.retryLeave()
  assert.equal(b.doc, own)
  assert.equal(b.leaving, false)
  assert.equal(own.destroyed, false)
  assert.match(b.saveError, /disk full/)
  console.log('ok — split: two versions and failed saves keep their pane')
}

{
  // Closing the split leaves the other pane's board the way switching does:
  // its last write lands first, then it is closed.
  const c = controller()
  const a = c.root, b = c.second
  a.toggleSplit('side-by-side')
  b.openBoard('b.json')
  a.addItem('note', 0, 0)
  b.toggleSplit('side-by-side')
  assert.equal(c.workspace.layout, 'side-by-side', 'waiting for the first pane\'s write')
  assert.equal(a.leaving, true)
  c.complete()
  c.workspace.retryLeave()
  assert.equal(c.workspace.layout, 'single')
  assert.equal(c.workspace.panes[0], b)
  assert.equal(a.doc, null)
  assert.deepEqual(c.workspace.documents.map(d => d.currentBoard), ['b.json'])
  assert.equal(JSON.parse(c.states.at(-1)).lastBoard, 'b.json', 'the board left open is the one remembered')
  console.log('ok — split: closing saves and closes the other pane\'s board')
}

{
  // The trash will not take a board open in either pane, nor a folder
  // holding one.
  const c = controller()
  const a = c.root, b = c.second
  a.toggleSplit('side-by-side')
  b.openBoard('work/b.json')
  c.workspace.activate(a)
  assert.equal(c.library.holdsOpenBoard({ path: 'work/b.json', dir: false }), true, 'the other pane\'s board')
  assert.equal(c.library.holdsOpenBoard({ path: 'work', dir: true }), true, 'and the folder it is in')
  assert.equal(c.library.holdsOpenBoard({ path: 'a.json', dir: false }), true)
  assert.equal(c.library.holdsOpenBoard({ path: 'c.json', dir: false }), false)
  assert.equal(c.library.holdsOpenBoard({ path: 'wor', dir: true }), false)
  // A rename that moves one follows it into the pane showing it.
  c.library.openBoardMoved('work/b.json', 'done/b.json')
  assert.equal(b.currentBoard, 'done/b.json')
  assert.equal(JSON.parse(c.states.at(-1)).otherBoard, 'done/b.json')
  console.log('ok — split: the library guards every open board')
}

{
  // The layout comes back after a restart, with the boards each pane had.
  const c = controller()
  c.workspace.applyState(JSON.stringify({ lastBoard: 'a.json', layout: 'stacked', otherBoard: 'b.json',
    splitRatio: 0.7 }))
  assert.equal(c.workspace.layout, 'stacked')
  assert.equal(c.second.doc.currentBoard, 'b.json')
  assert.equal(c.workspace.documents.length, 2)
  assert.equal(c.workspace.splitRatio, 0.7)

  const twice = controller()
  twice.workspace.applyState(JSON.stringify({ lastBoard: 'a.json', layout: 'side-by-side', otherBoard: 'a.json' }))
  assert.equal(twice.second.doc, twice.root.doc, 'the same board twice is one document')

  const outside = controller()
  outside.workspace.applyState(JSON.stringify({ layout: 'stacked', otherBoard: '../away.json', splitRatio: 5 }))
  assert.equal(outside.workspace.layout, 'single', 'a board outside the library is not opened')
  assert.equal(outside.workspace.splitRatio, 0.8, 'and a ratio that leaves no room is held to one that does')

  const old = controller()
  old.workspace.applyState(JSON.stringify({ lastBoard: 'a.json', windowMode: true }))
  assert.equal(old.workspace.layout, 'single', 'state from before split view opens one pane')
  console.log('ok — split: the layout and both boards survive a restart')
}

{
  // Both panes render pictures through the same file, so one waits.
  const c = controller()
  const a = c.root, b = c.second
  a.toggleSplit('side-by-side')
  a.imageBusy = true
  b.choosePng('theme')
  assert.deepEqual(c.exchange.chosen, [], 'no second dialog')
  assert.match(b.statusText, /Finishing image export/)
  a.imageBusy = false
  b.choosePng('theme')
  assert.deepEqual(c.exchange.chosen, ['png'])
  console.log('ok — split: one picture at a time')
}
