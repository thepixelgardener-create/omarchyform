// When an edit reaches the file: a pointer gesture that can still be
// cancelled, a held key, typing that never pauses, a paste; what a board an
// older Omarchyform wrote with its history becomes; and the ids new items get
// on a board that came with the largest one. The workspace, panes and
// documents run from their QML sources, as in tests/controller.js.
const assert = require('assert/strict')
const { controller } = require('./workspace-harness')

// The last file written.
const written = c => JSON.parse(c.writes[c.writes.length - 1].text)

// A board opened from a file, the way the shell opens one, with every write
// completing as soon as it is made.
function opened(text) {
  const c = controller()
  c.session.loadBoard(text, false)
  const land = () => { while (c.persistence.busy) c.complete() }
  return Object.assign(c, { land })
}
const note = (id, x) => ({ id, kind: 'note', x, y: 0, w: 220, h: 160, tint: 'foreground',
  text: 'note ' + id, pinned: false, src: '' })
const plain = (n) => JSON.stringify({ kind: 'omarchyform.board', version: 5, nextId: n + 1, links: [],
  items: Array.from({ length: n }, (_, i) => note(i + 1, i * 300)) }, null, 2) + '\n'

{
  for (const kind of ['Move', 'Resize']) {
    const c = opened(plain(2)), a = c.root
    a.selectOnly(0)
    a.recolorItem(); c.land()
    a.undo(); c.land()
    a.markAll()
    const before = a.snapshot(), undo = c.doc.undoStack, redo = c.doc.redoStack
    const writes = c.writes.length
    a.beginPointerEdit()
    if (kind === 'Move') a.moveTargets(15, 25)
    else a.resizeTargets(15, 25)
    c.doc.save(true)
    assert.equal(c.writes.length, writes, 'a save during a gesture must wait for its outcome')
    a.finishPointerEdit(true); c.land()
    assert.deepEqual(a.snapshot(), before, kind + ': cancellation restores all marked items')
    assert.equal(c.doc.undoStack, undo)
    assert.equal(c.doc.redoStack, redo, 'cancellation preserves the redo branch')
    assert.equal(c.writes.length, writes, 'cancellation writes no intermediate board')

    a.beginPointerEdit()
    if (kind === 'Move') a.moveTargets(30, 40)
    else a.resizeTargets(30, 40)
    a.finishPointerEdit(false); c.land()
    assert.equal(c.writes.length, writes + 1, kind + ': release writes the whole gesture, once')
    assert.deepEqual(written(c).items, a.snapshot().items)
    assert.equal(c.doc.undoStack.length, undo.length + 1, 'and it is one step to undo')
  }

  // A held key moves a note a step at a time and is written when the autosave
  // settles, or when anything else writes: whole either way.
  const c = opened(plain(1)), a = c.root
  a.selectOnly(0)
  for (let i = 0; i < 5; i++) a.nudgeSelected(1, 0)
  assert.equal(c.writes.length, 0, 'a held key writes nothing while it is held')
  c.session.flushSave(); c.land()
  assert.equal(written(c).items[0].x, 5 * 40, 'and the move is written whole')

  // Completing a preceding save while a drag is held cannot publish its
  // intermediate position; a reload discards the gesture without saving over it.
  a.recolorItem()
  const before = a.snapshot(), pendingWrites = c.writes.length
  a.beginPointerEdit(); a.moveTargets(50, 60)
  c.land()
  assert.equal(c.writes.length, pendingWrites)
  a.finishPointerEdit(true)
  assert.deepEqual(a.snapshot(), before)
  a.beginPointerEdit(); a.moveTargets(70, 80)
  c.session.loadBoard(plain(2), false)
  a.finishPointerEdit(false)
  assert.equal(c.items.count, 2, 'a late pointer release cannot restore the previous board')
  assert.equal(c.writes.length, pendingWrites, 'reload cancellation writes nothing')

  // Opening another board in the pane ends a gesture the same way.
  a.selectOnly(0)
  a.beginPointerEdit(); a.moveTargets(10, 10)
  const switching = c.doc.loadSerial
  a.openBoard('b.json')
  assert.equal(c.doc.currentBoard, 'b.json')
  assert.notEqual(c.doc.loadSerial, switching, 'leaving the board is a new reading')
  a.finishPointerEdit(false)
  assert.equal(c.writes.length, pendingWrites, 'so the gesture from the board before writes nothing to it')

  const pending = opened(plain(1)), p = pending.root
  p.selectOnly(0)
  p.recolorItem() // first write starts
  p.recolorItem() // second accepted change waits behind it
  const accepted = p.snapshot()
  p.beginPointerEdit(); p.moveTargets(90, 100)
  pending.land() // completion cannot save while the pointer gesture is active
  assert.equal(pending.writes.length, 1)
  p.finishPointerEdit(true); pending.land()
  assert.deepEqual(p.snapshot(), accepted)
  assert.equal(pending.writes.length, 2, 'cancellation resumes the earlier accepted change')
  assert.equal(written(pending).items[0].tint, accepted.items[0].tint)
  console.log('ok — editing: canceled pointer gestures restore state; released ones and held keys write once')
}

{
  for (const kind of ['text', 'image', 'drop']) {
    const c = opened(plain(0))
    if (kind === 'text') c.root.pasteText('A complete pasted note')
    else {
      if (kind === 'drop') c.root.imageQueue = [{ name: 'test.png', x: 100, y: 200,
        atPoint: true, board: c.root.currentBoard, shown: c.root.docSerial }]
      c.root.pasteImage('test.png', 1200, 600)
    }
    c.land()
    const w = written(c)
    const item = w.items[0]
    assert.equal(item.text, kind === 'text' ? 'A complete pasted note' : '')
    assert.equal(item.src, kind === 'text' ? '' : 'test.png')
    assert.deepEqual([item.w, item.h], kind === 'text' ? [300, 200] : [360, 180])
    if (kind === 'drop') assert.deepEqual([item.x, item.y], [-80, 110])
    else assert.deepEqual([item.x + item.w / 2, item.y + item.h / 2],
      [c.root.toWorldX(c.root.viewW / 2), c.root.toWorldY(c.root.viewH / 2)], 'paste centers the final size')
    for (const write of c.writes)
      assert.deepEqual(JSON.parse(write.text).items, w.items, kind + ': no empty placeholder reaches disk')
    c.root.undo(); c.land()
    assert.equal(c.items.count, 0, kind + ': one undo removes the paste')
    c.root.redo(); c.land()
    assert.deepEqual(written(c).items, w.items, kind + ': redo restores the complete item')
  }
  console.log('ok — editing: text, image and dropped image each save one complete item')
}

{
  // Typing waits for a pause before it is written, but never more than five
  // seconds: the delay restarts with every key.
  const c = opened(plain(2))
  c.root.selectOnly(0)
  c.root.editSelected()
  c.root.items.setProperty(0, 'itext', 'and on')
  c.root.scheduleSave()
  assert.equal(c.writes.length, 0, 'typing waits for a pause')
  c.session.waitingSince -= 6000             // the first of these keys was six seconds ago
  c.root.items.setProperty(0, 'itext', 'and on and on')
  c.root.scheduleSave()
  assert.equal(c.writes.length, 1, 'written without waiting for a pause')
  assert.equal(written(c).items[0].text, 'and on and on')
  c.land()
  c.root.items.setProperty(0, 'itext', 'and on and on and on')
  c.root.scheduleSave()
  assert.equal(c.writes.length, 1, 'and the five seconds start again from that write')
  c.root.stopEditing(); c.land()
  assert.equal(written(c).items[0].text, 'and on and on and on')
  console.log('ok — editing: never more than five seconds of typing unwritten')
}

{
  // A board Omarchyform 0.4.7 to 0.4.10 wrote, its history last: it opens
  // ready to edit, opening and leaving it writes nothing, and its first save
  // leaves the history out. A board with textures stays the format for them.
  const records = Array.from({ length: 50 }, (_, i) => `{"i":${i + 1},"t":0,"a":"Move","p":{}}`).join(',')
  const history = '{"v":1,"lineage":"x","start":0,"base":{"items":[],"links":[],"nextId":1},"records":[' + records + ']}'
  for (const textured of [false, true]) {
    const board = JSON.parse(plain(2))
    board.version = textured ? 7 : 6
    if (textured) board.items[1].texture = 'grid'
    const text = JSON.stringify(board, null, 2).slice(0, -2) + ',\n  "history": ' + history + '\n}\n'
    const c = opened(text)
    assert.equal(c.root.canEdit, true, 'editable at once')
    assert.equal(c.root.boardState, 'Saved locally')
    assert.equal(c.items.count, 2)
    c.session.flushSave(); c.land()
    assert.equal(c.writes.length, 0, 'opening it writes nothing')
    c.root.selectOnly(0)
    c.root.recolorItem(); c.land()
    const w = written(c)
    assert.equal(w.history, undefined, 'the first save leaves the history out')
    assert.equal(w.version, textured ? 7 : 5)
    assert.equal(w.items[0].tint, c.items.get(0).itint)
    assert.equal(w.items[1].texture, textured ? 'grid' : undefined)
    assert.equal(c.writes[0].text.indexOf('"history"'), -1)
  }
  console.log('ok — editing: a board with an old history opens editable and is saved without it')

  // A key after the history is the file's, even on the history's own line. A
  // newer version there keeps the board read-only, with or without a version
  // in front, and nothing asked of it writes over it; the canvas after it is
  // what opens.
  for (const front of ['versioned', 'unversioned']) {
    const board = JSON.parse(plain(2))
    if (front === 'unversioned') delete board.version
    const c = opened(JSON.stringify(board, null, 2).slice(0, -2) + ',\n  "history": ' + history + ', "version": 8\n}\n')
    assert.equal(c.root.canEdit, false, front + ': a newer version after the history is read-only')
    assert.equal(c.root.boardState, 'Read only')
    c.root.addItem('note', 0, 0)
    c.root.selectOnly(0)
    c.root.recolorItem()
    c.doc.save(true)
    c.session.flushSave(); c.land()
    assert.equal(c.writes.length, 0, front + ': and nothing writes over it')
  }
  const later = opened(plain(2).slice(0, -3) + ',\n  "history": ' + history
    + ', "items": [{"id": 9, "kind": "note", "text": "after"}], "nextId": 12\n}\n')
  assert.deepEqual([later.items.count, later.items.get(0).itext, later.doc.nextId], [1, 'after', 12],
    'the items after the history are the ones that open')
  console.log('ok — editing: a key after an old history counts, on any line')
}

{
  // A file whose bytes are what this session read but not what it would write
  // (an old history, a layout by hand), touched or written again unchanged, is
  // still this session's: a refused save is taken again, a notification is
  // nothing. Other bytes are someone else's, and so are the old ones once this
  // session has written the board.
  const history = '{"v":1,"lineage":"x","start":0,"base":{"items":[],"links":[],"nextId":1},"records":[]}'
  const other = plain(3)
  for (const [what, raw] of [['an old history', plain(2).slice(0, -3) + ',\n  "history": ' + history + '\n}\n'],
                             ['a layout by hand', JSON.stringify(JSON.parse(plain(2)))]]) {
    const c = opened(raw)
    c.root.selectOnly(0); c.root.recolorItem()
    c.refuse(raw)
    assert.equal(c.session.conflict, false, what + ': the same bytes are not someone else\'s')
    c.land()
    assert.equal(written(c).items[0].tint, c.items.get(0).itint, what + ': and the edit is written')

    const d = opened(raw)
    d.session.diskText = raw; d.session.externalWrite()
    assert.equal(d.session.conflict, false)
    assert.doesNotMatch(d.root.statusText, /reloaded/, what + ': not read again for a touch')

    const e = opened(raw)
    e.root.selectOnly(0); e.root.recolorItem()
    e.refuse(other)
    assert.equal(e.session.conflict, true, what + ': other bytes with an edit on screen are two versions')
    const f = opened(raw)
    f.session.diskText = other; f.session.externalWrite()
    assert.equal(f.items.count, 3, what + ': and with nothing unsaved, the other board is read')

    const g = opened(raw)
    g.root.selectOnly(0); g.root.recolorItem(); g.land()
    g.session.diskText = raw; g.session.externalWrite()
    assert.match(g.root.statusText, /reloaded/, what + ': once written, the old bytes are someone else\'s')
  }
  console.log('ok — editing: the same bytes on disk are still this session\'s until it writes')
}

{
  // A board's numbers are held to the board's size and extent, from its file
  // and from every edit: a move stops at the edge, keeping the selection's
  // shape; a resize stops at the largest size; neither records a step that
  // changes nothing; copies and new items beside one at the edge stay on.
  const S = controller().store
  const huge = JSON.stringify({ kind: 'omarchyform.board', version: 5, nextId: 3, links: [],
    items: [Object.assign(note(1, 0), { x: 1.7e308, y: -1e300, w: 1e300, h: 1e9 }), note(2, 0)] }, null, 2) + '\n'
  const c = opened(huge), a = c.root
  const at = i => { const n = c.items.get(i); return [n.ix, n.iy, n.iw, n.ih] }
  assert.deepEqual(at(0), [S.MAX_COORD, -S.MAX_COORD, S.MAX_SIZE, S.MAX_SIZE], 'opened within the board')
  a.selectOnly(0); a.recolorItem(); c.land()
  const w = written(c).items[0]
  assert.deepEqual([w.x, w.y, w.w, w.h], [S.MAX_COORD, -S.MAX_COORD, S.MAX_SIZE, S.MAX_SIZE], 'and written so')

  const steps = c.doc.undoStack.length
  a.selectOnly(0)
  a.nudgeSelected(1, -1)
  a.resizeSelected(1, 1)
  assert.deepEqual(at(0), [S.MAX_COORD, -S.MAX_COORD, S.MAX_SIZE, S.MAX_SIZE])
  assert.equal(c.doc.undoStack.length, steps, 'no step for a move or a resize that cannot happen')
  a.duplicateTargets(); c.land()
  assert.deepEqual(at(2).slice(0, 2), [S.MAX_COORD, 24 - S.MAX_COORD], 'a copy of one at the edge stays on the board')

  a.markAll()
  a.beginPointerEdit(); a.moveTargets(500, 0); a.finishPointerEdit(false); c.land()
  assert.deepEqual([at(0)[0], at(1)[0]], [S.MAX_COORD, 0], 'a selection at the edge does not come apart')
  a.beginPointerEdit(); a.moveTargets(-500, 40); a.finishPointerEdit(false); c.land()
  assert.deepEqual([at(0)[0], at(0)[1], at(1)[0], at(1)[1]], [S.MAX_COORD - 500, 40 - S.MAX_COORD, -500, 40])

  a.selectOnly(1)
  for (let i = 0; i < 3; i++) a.resizeTargets(S.MAX_SIZE, S.MAX_SIZE)
  assert.deepEqual(at(1).slice(2), [S.MAX_SIZE, S.MAX_SIZE], 'a resize stops at the largest size')

  a.selectOnly(0); a.addRelative('note'); c.land()
  for (let i = 0; i < c.items.count; i++)
    for (const v of at(i).slice(0, 2)) assert.ok(Math.abs(v) <= S.MAX_COORD, 'item ' + i + ' stays on the board')
  console.log('ok — editing: positions and sizes stay within the board, from the file and every edit')
}

{
  // Arranging works from the selection's bounds, which reach MAX_SIZE past
  // the last position. Aligning to that edge, or butting up items that take
  // more room than they sit in, stops at the board, and what is saved is what
  // opening the board again shows.
  const S = controller().store
  const wide = (id, x) => Object.assign(note(id, x), { w: S.MAX_SIZE })
  const board = items => JSON.stringify({ kind: 'omarchyform.board', version: 5,
    nextId: items.length + 1, links: [], items }, null, 2) + '\n'
  const cases = [
    ['right', [wide(1, S.MAX_COORD), note(2, 0)], a => a.alignTargets('right')],
    ['centreX', [wide(1, S.MAX_COORD), note(2, S.MAX_COORD - 500)], a => a.alignTargets('centreX')],
    ['spread', [wide(1, S.MAX_COORD - 1000), wide(2, S.MAX_COORD - 500), note(3, S.MAX_COORD)],
      a => a.spreadTargets('x')]
  ]
  for (const [what, items, arrange] of cases) {
    const c = opened(board(items))
    c.root.markAll(); arrange(c.root); c.land()
    const saved = written(c).items
    for (const n of saved) assert.ok(Math.abs(n.x) <= S.MAX_COORD, what + ': item ' + n.id + ' stays on the board')
    const again = opened(c.writes[c.writes.length - 1].text)
    assert.deepEqual(saved.map(n => n.x), Array.from({ length: again.items.count }, (_, i) => again.items.get(i).ix),
      what + ': opens again where it was saved')
  }
  console.log('ok — editing: arranging stays within the board and reopens as saved')
}

{
  // A board that came with an item at the largest id there is. New notes and
  // copies get ids it keeps, so they, and the connectors drawn to them,
  // survive the board being opened again.
  const S = controller().store
  const text = JSON.stringify({ kind: 'omarchyform.board', version: 5, nextId: 7,
    items: [note(2, 0), note(S.MAX_ID, 300)], links: [{ from: 2, to: S.MAX_ID }] }, null, 2) + '\n'
  const c = opened(text), a = c.root
  assert.equal(c.doc.nextId, S.MAX_ID + 1, 'it has run out of new ids')
  a.selectOnly(1)
  a.addRelative('note'); c.land()
  a.addRelative('note'); c.land()
  const added = [c.items.get(2).iid, c.items.get(3).iid]
  assert.deepEqual(added, [1, 3], 'so new notes get the smallest ids no item has')
  a.addLink(2, added[0]); c.land()
  a.addLink(added[1], S.MAX_ID); c.land()
  a.markAll(); a.duplicateTargets(); c.land()
  const w = written(c)
  const ids = w.items.map(r => r.id)
  assert.equal(ids.length, 8)
  assert.equal(new Set(ids).size, 8, 'every id once')
  for (const id of ids) assert.ok(S.isItemId(id), id + ' is an id a board keeps')
  assert.ok(c.doc.nextId <= 2147483647, 'and the next one fits the int it is kept in')

  const again = opened(c.writes[c.writes.length - 1].text)
  assert.deepEqual(S.itemRows(again.items).map(r => r.id), ids, 'opened again, every item keeps its id')
  assert.deepEqual(S.linkRows(again.links), w.links, 'and every connector is still there')
  assert.equal(w.links.length, 6, 'the three drawn and their copies')
  console.log('ok — editing: a board at the largest id still gets ids it keeps')
}

{
  // A board filled in a slice at a time (BoardSession.fillMore): part of it in
  // is not a board to save, a newer load drops the older one's rows, and a
  // board that is not one finishes at once.
  const c = controller()
  c.doc.fillSliceMs = 0
  const big = JSON.stringify({ kind: 'omarchyform.board', version: 5, nextId: 6,
    items: [1, 2, 3, 4, 5].map(id => note(id, id * 300)), links: [{ from: 1, to: 2 }] }) + '\n'
  c.session.loadBoard(big, false)
  assert.ok(c.doc.opening && !c.doc.boardLoaded && !c.doc.canEdit, 'a board still filling is read-only')
  assert.equal(c.items.count, 1, 'one row a slice')
  c.doc.save(true)
  assert.equal(c.writes.length, 0, 'and is never written')

  c.session.loadBoard(plain(2), false)
  while (c.doc.opening) c.session.fillMore()
  assert.equal(c.items.count, 2, 'a newer load leaves none of the older one: ' + c.items.count)
  assert.ok(c.doc.boardLoaded && c.doc.openedShare === 1)

  c.session.loadBoard(big, false)
  c.session.loadBoard('{broken', false)
  assert.ok(!c.doc.opening && c.doc.damaged && c.items.count === 0, 'one that is not a board finishes at once')
  c.session.fillMore()
  assert.equal(c.items.count, 0, 'and a slice left over from before does nothing')

  c.session.loadBoard(big, false)
  while (c.doc.opening) c.session.fillMore()
  assert.equal(c.items.count, 5)
  assert.equal(c.links.count, 1, 'connectors once every item is in')
  assert.equal(c.doc.nextId, 6)
  console.log('ok — editing: a board opened a slice at a time')
}
