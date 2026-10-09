// Recording a board's history as it is edited: where one edit ends and the
// next begins, that what is written can always be played back to the board it
// was written with, and what happens when a history is opened that ends
// elsewhere, cannot be read, comes from a newer version, or has grown past its
// limits. The workspace, panes and documents run from their QML sources, as in
// tests/controller.js; the history worker runs from its own file.
const assert = require('assert/strict')
const { controller } = require('./workspace-harness')
const { History: H, historyWorker } = require('./history-worker')

const W = historyWorker()

// The last file written, as a board and the history that came with it.
function written(c) {
  const text = c.writes[c.writes.length - 1].text
  const file = JSON.parse(text)
  return { text, file, history: file.history, records: file.history ? file.history.records : [] }
}
const live = file => ({ items: file.items, links: file.links, nextId: file.nextId })
const labels = c => written(c).records.map(r => r.a)

// A board opened from a file, the way the shell opens one, with every write
// completing as soon as it is made.
function opened(text) {
  const c = controller()
  c.session.loadBoard(text, false)
  const land = () => { while (c.persistence.busy) c.complete() }
  return Object.assign(c, { land })
}
const plain = (n) => JSON.stringify({ kind: 'omarchyform.board', version: 5, nextId: n + 1, links: [],
  items: Array.from({ length: n }, (_, i) => ({ id: i + 1, kind: 'note', x: i * 300, y: 0, w: 220, h: 160,
    tint: 'foreground', text: 'note ' + (i + 1), pinned: false, src: '' })) }, null, 2) + '\n'

{
  for (const label of ['Move', 'Resize']) {
    const c = opened(plain(2)), a = c.root
    a.selectOnly(0)
    a.recolorItem(); c.land()
    a.undo(); c.land()
    a.markAll()
    const before = a.snapshot(), undo = c.doc.undoStack, redo = c.doc.redoStack
    const count = c.doc.historyCount, writes = c.writes.length
    a.beginPointerEdit(label)
    if (label === 'Move') a.moveTargets(15, 25)
    else a.resizeTargets(15, 25)
    c.doc.save(true)
    assert.equal(c.writes.length, writes, 'a save during a gesture must wait for its outcome')
    a.finishPointerEdit(true); c.land()
    assert.deepEqual(a.snapshot(), before, label + ': cancellation restores all marked items')
    assert.equal(c.doc.undoStack, undo)
    assert.equal(c.doc.redoStack, redo, 'cancellation preserves the redo branch')
    assert.equal(c.doc.historyCount, count)
    assert.equal(c.writes.length, writes, 'cancellation writes no intermediate board')

    a.beginPointerEdit(label)
    if (label === 'Move') a.moveTargets(30, 40)
    else a.resizeTargets(30, 40)
    a.finishPointerEdit(false); c.land()
    assert.equal(c.doc.historyCount, count + 1, 'release records the whole gesture once')
    assert.equal(labels(c).at(-1), label)
    assert.equal(H.verify(written(c).history, live(written(c).file)), '')
  }
  const c = opened(plain(1)), a = c.root
  a.selectOnly(0)
  a.nudgeSelected(1, 0); a.nudgeSelected(1, 0)
  a.finishKeyEdit(); c.land()
  assert.deepEqual(labels(c), ['Move'], 'release commits the held movement')
  a.nudgeSelected(1, 0); a.finishKeyEdit(); c.land()
  assert.deepEqual(labels(c), ['Move', 'Move'], 'another press is its own step')
  a.resizeSelected(1, 0); a.deactivate(); c.land()
  assert.deepEqual(labels(c), ['Move', 'Move', 'Resize'], 'focus loss finishes resizing')

  // Completing a preceding save while a drag is held cannot publish its
  // intermediate position; a reload discards the gesture without saving over it.
  a.recolorItem()
  const before = a.snapshot(), pendingWrites = c.writes.length
  a.beginPointerEdit('Move'); a.moveTargets(50, 60)
  c.land()
  assert.equal(c.writes.length, pendingWrites)
  a.finishPointerEdit(true)
  assert.deepEqual(a.snapshot(), before)
  a.beginPointerEdit('Move'); a.moveTargets(70, 80)
  c.session.loadBoard(plain(2), false)
  a.finishPointerEdit(false)
  assert.equal(c.items.count, 2, 'a late pointer release cannot restore the previous board')
  assert.equal(c.writes.length, pendingWrites, 'reload cancellation writes nothing')

  const pending = opened(plain(1)), p = pending.root
  p.selectOnly(0)
  p.recolorItem() // first write starts
  p.recolorItem() // second accepted change waits behind it
  const accepted = p.snapshot()
  p.beginPointerEdit('Move'); p.moveTargets(90, 100)
  pending.land() // completion cannot save while the pointer gesture is active
  assert.equal(pending.writes.length, 1)
  p.finishPointerEdit(true); pending.land()
  assert.deepEqual(p.snapshot(), accepted)
  assert.equal(pending.writes.length, 2, 'cancellation resumes the earlier accepted change')
  assert.equal(written(pending).file.items[0].tint, 'urgent')
  assert.deepEqual(labels(pending), ['Colour', 'Colour'])
  assert.equal(H.verify(written(pending).history, live(written(pending).file)), '')
  console.log('ok — recording: canceled pointer gestures restore state; release and focus loss finish key gestures')
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
    assert.deepEqual(labels(c), [kind === 'text' ? 'Paste' : 'Picture'], kind + ': one history step')
    const item = w.file.items[0]
    assert.equal(item.text, kind === 'text' ? 'A complete pasted note' : '')
    assert.equal(item.src, kind === 'text' ? '' : 'test.png')
    assert.deepEqual([item.w, item.h], kind === 'text' ? [300, 200] : [360, 180])
    if (kind === 'drop') assert.deepEqual([item.x, item.y], [-80, 110])
    else assert.deepEqual([item.x + item.w / 2, item.y + item.h / 2],
      [c.root.toWorldX(c.root.viewW / 2), c.root.toWorldY(c.root.viewH / 2)], 'paste centers the final size')
    for (const write of c.writes) {
      const file = JSON.parse(write.text)
      assert.deepEqual(file.items, w.file.items, kind + ': no empty placeholder reaches disk')
      assert.equal(H.verify(file.history, live(file)), '')
    }
    c.root.undo(); c.land()
    assert.equal(c.items.count, 0, kind + ': one undo removes the paste')
    c.root.redo(); c.land()
    assert.deepEqual(written(c).file.items, w.file.items, kind + ': redo restores the complete item')
  }
  console.log('ok — recording: text, image and dropped image each save one complete history step')
}

{
  // The version after history is just as authoritative as one before it,
  // including a duplicate key whose last value wins under JSON parsing.
  const file = JSON.parse(plain(2))
  const history = H.create(live(file), 1, 'version-after-history')
  for (const version of [8, '6', null, 6]) {
    for (const duplicate of [false, true]) {
      const fields = { kind: file.kind }
      if (duplicate) fields.version = 6
      Object.assign(fields, { nextId: file.nextId, items: file.items, links: file.links, history })
      const text = JSON.stringify(fields, null, 2).slice(0, -2)
        + ',\n  "version": ' + JSON.stringify(version) + '\n}\n'
      const c = opened(text)
      assert.equal(c.root.canEdit, false, 'validation holds editing')
      for (let attempts = 0; c.doc.historyChecking; attempts++) {
        assert.ok(attempts < 3, 'whole-file reload finishes validation')
        c.answer(W.dispatch(c.worker.asked[c.worker.asked.length - 1]))
      }
      c.land()
      assert.equal(c.writes.length, 0, 'opening never rewrites the file')
      assert.equal(c.aside.written.length, 0, 'version refusal is not history recovery')
      assert.equal(c.root.canEdit, version === 6, 'only the supported version is editable')
      c.root.selectOnly(0)
      c.root.recolorItem()
      c.session.flushSave()
      c.land()
      if (version === 6) assert.equal(written(c).file.items.length, 2)
      else assert.equal(c.writes.length, 0, 'an unsupported version cannot be overwritten')
    }
  }
  console.log('ok — recording: a board version after history still protects the file')
}

{
  // Malformed nested values must produce an answer, not an uncaught worker
  // exception that leaves the document waiting forever.
  const file = JSON.parse(plain(2))
  for (const damage of [
    h => { h.base.items = [null] },
    h => { h.base.links = [null] },
    h => { h.records = [{ i: 1, a: 'Broken', p: { s: [null] } }] }
  ]) {
    const history = H.create(live(file), 1, 'malformed-nested-history')
    damage(history)
    const c = opened(JSON.stringify(Object.assign({}, file, { version: 6, history }), null, 2) + '\n')
    const answer = W.dispatch(c.worker.asked[c.worker.asked.length - 1])
    assert.equal(answer.unreadable, true, 'the worker reports malformed history')
    assert.ok(answer.error, 'the failure explains why')
    c.answer(answer)
    c.land()
    assert.equal(c.doc.historyChecking, false, 'validation completes')
    assert.equal(c.root.canEdit, true, 'recovery unlocks the intact canvas')
    assert.deepEqual(JSON.parse(c.aside.written[0].text), history, 'original history is kept aside')
    assert.deepEqual(written(c).file.items, file.items, 'recovery preserves the live items')
    assert.equal(H.verify(written(c).history, live(written(c).file)), '')
    c.root.selectOnly(0)
    c.root.recolorItem()
    c.land()
    assert.deepEqual(labels(c), ['Colour'], 'editing resumes after recovery')
  }
  console.log('ok — recording: malformed nested history replies and recovery completes')

  // Trimming also replays history on the worker. Its failure must release
  // the document's trimming state without replacing the original history.
  const history = H.create(live(file), 1, 'malformed-trim')
  history.base.items = [null]
  history.records = Array.from({ length: H.MAX_HISTORY_RECORDS + 1 }, (_, i) =>
    ({ i: i + 1, a: 'Move', p: {} }))
  const trimmed = W.dispatch({ trim: true, token: 91, history: JSON.stringify(history) })
  assert.equal(trimmed.kind, 'trimmed')
  assert.ok(trimmed.error, 'trim failures receive an error reply too')
  assert.equal(trimmed.text, '', 'no partial replacement history is returned')
  const c = opened(plain(2))
  c.doc.historyTrimming = true
  const before = c.doc.historyRecords
  c.doc.trimmedHistory(trimmed)
  assert.equal(c.doc.historyTrimming, false)
  assert.equal(c.doc.historyRecords, before)
  assert.equal(c.writes.length, 0)
}

{
  // A board without a history gets one at its first edit, starting from the
  // board as it was just before it, and is written in the newest format.
  const c = opened(plain(2))
  assert.equal(c.doc.historyChecking, false, 'nothing to read')
  c.root.selectOnly(0)
  c.root.recolorItem()
  c.land()
  const w = written(c)
  assert.equal(w.file.version, 7)
  assert.equal(w.records.length, 1)
  assert.equal(w.records[0].a, 'Colour')
  assert.equal(w.history.base.items[0].tint, 'foreground', 'the baseline is the board before the edit')
  assert.equal(H.verify(w.history, live(w.file)), '', 'and the history plays back to the board written')
  console.log('ok — recording: a first edit starts the history, from the board before it')
}

{
  // One command, one record, named for what it was. Typing is one record per
  // pause, held keys are one record, a drag is one, and undo is an edit too.
  const c = opened(plain(3))
  c.root.selectOnly(0)
  c.root.addRelative('note')                 // a new note, then typing in it
  c.land()
  c.root.items.setProperty(c.root.editIndex, 'itext', 'h')
  c.root.scheduleSave()
  c.root.items.setProperty(c.root.editIndex, 'itext', 'hi')
  c.root.scheduleSave()
  c.root.stopEditing()
  c.land()
  assert.deepEqual(labels(c), ['New note', 'Typing'])

  c.root.selectOnly(1)
  for (let i = 0; i < 5; i++) c.root.nudgeSelected(1, 0)
  assert.equal(labels(c).length, 2, 'a held key writes nothing while it is held')
  c.session.flushSave()
  c.land()
  assert.deepEqual(labels(c).slice(-1), ['Move'], 'and is one record when it is written')
  assert.equal(written(c).records.slice(-1)[0].p.s[0][1].x, 300 + 5 * 40, 'of the whole move')

  // A drag: the first frame begins it, the frames move it, release writes.
  c.root.selectOnly(2)
  c.root.pushUndo('Move')
  c.root.moveTargets(10, 0)
  c.root.moveTargets(10, 0)
  c.root.save()
  c.land()
  assert.deepEqual(labels(c).slice(-2), ['Move', 'Move'], 'a drag after a held key is a record of its own')

  c.root.undo()
  c.land()
  c.root.redo()
  c.land()
  assert.deepEqual(labels(c).slice(-2), ['Undo', 'Redo'])

  // Writing again with nothing changed records nothing.
  const count = labels(c).length
  c.root.save(true)
  c.session.flushSave()
  c.land()
  assert.equal(labels(c).length, count)
  const w = written(c)
  assert.equal(H.verify(w.history, live(w.file)), '', 'every write plays back to the board it was written with')
  console.log('ok — recording: one record per command, pause, held key, drag and undo')
}

{
  // Typing in one note, then straight into another, is two records; and
  // typing that never pauses is written and recorded every five seconds.
  const c = opened(plain(2))
  c.root.selectOnly(0)
  c.root.editSelected()
  c.root.items.setProperty(0, 'itext', 'first, changed')
  c.root.scheduleSave()
  c.root.selectOnly(1)
  c.root.editSelected()
  c.root.items.setProperty(1, 'itext', 'second, changed')
  c.root.scheduleSave()
  c.root.stopEditing()
  c.land()
  assert.deepEqual(labels(c), ['Typing', 'Typing'])

  c.root.selectOnly(0)
  c.root.editSelected()
  c.root.items.setProperty(0, 'itext', 'and on')
  c.root.scheduleSave()
  const before = c.writes.length
  c.doc.changedSince -= 6000               // the first of these keys was six seconds ago
  c.root.items.setProperty(0, 'itext', 'and on and on')
  c.root.scheduleSave()
  assert.equal(c.writes.length, before + 1, 'written without waiting for a pause')
  c.land()
  assert.equal(labels(c).length, 3)
  console.log('ok — recording: a note at a time, and never more than five seconds of typing')
}

{
  // A board opened with a history: until the worker has read it, nothing is
  // edited and nothing is written; then edits go on, numbered after it.
  const first = opened(plain(2))
  first.root.selectOnly(0)
  first.root.recolorItem()
  first.land()
  const saved = written(first).text

  const c = opened(saved)
  assert.equal(c.doc.historyChecking, true)
  const asked = c.worker.asked[c.worker.asked.length - 1]
  c.root.selectOnly(1)
  c.root.cycleKind()
  c.land()
  assert.equal(c.items.get(1).kind, 'note', 'no edit while it is read')
  assert.equal(c.writes.length, 0, 'and nothing written')

  const reply = W.check(asked)
  assert.equal(reply.error, '')
  assert.equal(reply.bridge, '', 'it ends at the board it was opened with')
  c.answer(reply)
  c.root.cycleKind()
  c.land()
  const w = written(c)
  assert.deepEqual(w.records.map(r => [r.i, r.a]), [[1, 'Colour'], [2, 'Shape']],
    'the first edit after it was read follows, numbered after it')
  assert.equal(H.verify(w.history, live(w.file)), '')
  // The same answer twice is not news, and one about a history that has since
  // been replaced is not about this one.
  c.answer(Object.assign({}, reply, { count: 999 }))
  assert.notEqual(c.doc.historyCount, 999, 'a second answer changes nothing')
  const again = opened(saved)
  const stale = W.check(again.worker.asked[again.worker.asked.length - 1])
  again.session.loadBoard(saved, false)
  again.answer(Object.assign({}, stale, { count: 999 }))
  assert.notEqual(again.doc.historyCount, 999, 'an answer about a history read since is dropped')
  assert.equal(again.doc.historyChecking, true, 'and the reading it is waiting for still is')
  console.log('ok — recording: a history opened is read aside, and only then added to')
}

{
  // Ends somewhere else: the file was edited by something without history.
  // The difference is one record, before anything made here.
  const first = opened(plain(2))
  first.root.selectOnly(0)
  first.root.recolorItem()
  first.land()
  const file = JSON.parse(written(first).text)
  file.items[1].text = 'changed in a text editor'
  const handEdited = JSON.stringify(file, null, 2) + '\n'

  const c = opened(handEdited)
  c.answer(W.check(c.worker.asked[c.worker.asked.length - 1]))
  c.root.selectOnly(0)
  c.root.recolorItem()
  c.land()
  const w = written(c)
  assert.deepEqual(w.records.map(r => r.a), ['Colour', H.OUTSIDE, 'Colour'])
  assert.equal(H.verify(w.history, live(w.file)), '')
  console.log('ok — recording: a change made outside is one record, not invented steps')
}

{
  // A history that cannot be played is kept beside the backups, and a new
  // one starts from the board as it was opened. One from a newer Omarchyform
  // makes the board read-only.
  const first = opened(plain(2))
  first.root.selectOnly(0)
  first.root.recolorItem()
  first.land()
  const file = JSON.parse(written(first).text)
  file.history.records[0].p = { d: [42] }
  const broken = JSON.stringify(file, null, 2).replace(/,\n {2}"history": [\s\S]*$/, '')
    + ',\n  "history": ' + JSON.stringify(file.history) + '\n}\n'

  const c = opened(broken)
  c.answer(W.check(c.worker.asked[c.worker.asked.length - 1]))
  c.land()
  assert.equal(c.aside.written.length, 1, 'the old history is kept')
  assert.match(c.aside.written[0].path, /^\/backups\/.*\.history-\d+\.json$/)
  assert.equal(JSON.parse(c.aside.written[0].text).records[0].p.d[0], 42, 'as it was')
  assert.match(c.root.statusText, /could not be read/)
  c.root.selectOnly(0)
  c.root.recolorItem()
  c.land()
  const w = written(c)
  assert.notEqual(w.history.lineage, file.history.lineage, 'a new line of edits')
  assert.equal(H.verify(w.history, live(w.file)), '')

  // Text far past the limit is not parsed to find out.
  const huge = W.check({ token: 1, history: ' '.repeat(H.MAX_HISTORY_TEXT + 1), board: '{}', now: 0 })
  assert.equal(huge.unreadable, true)
  assert.match(huge.error, /larger than a history can be/)

  file.history.v = 2
  const newer = opened(JSON.stringify(Object.assign({}, file, { history: undefined }), null, 2).slice(0, -2)
    + ',\n  "history": ' + JSON.stringify(file.history) + '\n}\n')
  assert.equal(newer.root.canEdit, false)
  assert.match(newer.session.damageReason, /newer Omarchyform/)
  console.log('ok — recording: an unreadable history is kept aside; a newer one is left alone')
}

{
  // A board whose history is not where this writer puts it — after some keys
  // and before the items, as an editor or a script can leave it — reads whole:
  // every item is there, nothing is written while it is read and checked, and
  // nothing is taken for an unreadable history. The next edit writes it back
  // in order. (History first, as sorting keys leaves it, was always read whole:
  // the marker has to follow a comma.)
  const first = opened(plain(3))
  first.root.selectOnly(0)
  first.root.recolorItem()
  first.land()
  const saved = JSON.parse(written(first).text)
  const moved = {}
  for (const key of ['kind', 'version', 'history', 'nextId', 'items', 'links']) moved[key] = saved[key]
  const text = JSON.stringify(moved, null, 2) + '\n'
  assert.ok(text.indexOf('"history"') < text.indexOf('"items"'), 'the history comes before the items')

  const c = opened(text)
  assert.equal(c.items.count, 3, 'every item is read')
  c.answer(W.check(c.worker.asked[c.worker.asked.length - 1]))
  c.land()
  assert.equal(c.writes.length, 0, 'nothing is written while it is read')
  assert.equal(c.aside.written.length, 0, 'and nothing is taken for unreadable')
  assert.equal(c.items.count, 3)
  c.root.selectOnly(2)
  c.root.cycleKind()
  c.land()
  const w = written(c)
  assert.deepEqual(w.file.items.map(r => [r.id, r.kind, r.tint]),
    saved.items.map(r => [r.id, r.id === 3 ? 'rect' : r.kind, r.tint]), 'the edit is the only change to the board')
  assert.deepEqual(w.records.map(r => r.a), ['Colour', 'Shape'], 'and the history goes on')
  assert.equal(H.verify(w.history, live(w.file)), '')
  assert.ok(w.text.indexOf('"history"') > w.text.indexOf('"links"'), 'written back in this writer\'s order')

  // Cut off inside the history: the board in front reads, but the file is not
  // JSON. The worker has it read again whole, which makes it unreadable — and
  // nothing is recovered from it or written over it.
  const good = written(first).text
  const cut = good.slice(0, good.indexOf('"history"') + 40) + '\n}\n'
  const d = opened(cut)
  d.answer(W.check(d.worker.asked[d.worker.asked.length - 1]))
  d.land()
  assert.equal(d.root.canEdit, false, 'read-only, as any unreadable board')
  assert.equal(d.items.count, 0)
  assert.equal(d.writes.length, 0, 'nothing written over it')
  assert.equal(d.aside.written.length, 0, 'and no history recovered from it')

  // Something after the history: the history is the file's, not unreadable.
  const after = good.replace(/\n\}\n$/, ',\n  "later": 1\n}\n')
  const e = opened(after)
  e.answer(W.check(e.worker.asked[e.worker.asked.length - 1]))
  e.land()
  assert.equal(e.aside.written.length, 0)
  e.root.selectOnly(0)
  e.root.cycleKind()
  e.land()
  assert.deepEqual(labels(e), ['Colour', 'Shape'])

  // The same key twice: whichever the board read in front of the history,
  // the file says the last. The worker finds they differ and the board is read
  // again whole, as the file says.
  const twice = good.replace('\n  "history": ', '\n  "items": [],\n  "history": ')
    .replace(/,\n {2}"history": /, ',\n  "history": ')
  const later = twice.slice(0, twice.lastIndexOf('\n}')) + ',\n  "items": ' + JSON.stringify(saved.items.slice(0, 1)) + '\n}\n'
  const f = opened(later)
  f.answer(W.check(f.worker.asked[f.worker.asked.length - 1]))
  assert.equal(f.items.count, 1, 'read again whole, it is what the file says')
  assert.equal(f.writes.length, 0)
  console.log('ok — recording: the order of a board\'s keys never changes what is read')
}

{
  // A history from a newer Omarchyform, however it is laid out: until the
  // worker has read it nothing is edited or written, whichever way a write is
  // asked for; once it has, the board is read-only and the file as it was.
  const first = opened(plain(2))
  first.root.selectOnly(0)
  first.root.recolorItem()
  first.land()
  const file = JSON.parse(written(first).text)
  file.history.v = 2
  const pretty = JSON.stringify(file, null, 2) + '\n'
  const moved = {}
  for (const key of ['kind', 'version', 'history', 'nextId', 'items', 'links']) moved[key] = file[key]
  for (const [layout, text] of [['pretty-printed', pretty], ['pretty and moved', JSON.stringify(moved, null, 2) + '\n']]) {
    // Pretty-printed, it waits for the worker; moved, it is read whole, its
    // history comes out compact and the header already says it is newer.
    const c = opened(text)
    assert.equal(c.doc.historyChecking || c.session.damaged, true, layout + ': held or refused at once')
    assert.equal(c.root.canEdit, false, layout + ': not editable either way')
    assert.match(c.root.boardState, c.doc.historyChecking ? /Checking history/ : /Read only/)
    const ask = c.doc.historyChecking ? c.worker.asked[c.worker.asked.length - 1] : null
    // Every way a write is asked for, with the answer held back.
    c.root.selectOnly(0)
    c.root.recolorItem()
    c.items.setProperty(0, 'itext', 'typed anyway')
    c.doc.noteEdit(c.root)
    c.root.save(true)
    c.session.flushSave()
    c.root.flushSave()
    c.root.forgetHistory()
    c.root.forgetHistory()
    c.workspace.close()
    c.land()
    assert.equal(c.writes.length, 0, layout + ': nothing is written while it is read')
    // Leaving it does not wait for a save that will never start.
    c.workspace.opened = true
    c.root.openBoard('elsewhere.json')
    assert.equal(c.root.currentBoard, 'elsewhere.json', layout + ': and leaving it is not held up')
    // Read it again, and this time let the worker answer.
    const d = opened(text)
    if (d.doc.historyChecking) d.answer(W.check(d.worker.asked[d.worker.asked.length - 1]))
    d.land()
    assert.equal(d.root.canEdit, false, layout + ': read-only')
    assert.match(d.session.damageReason, /newer Omarchyform/)
    assert.equal(d.aside.written.length, 0, layout + ': not kept aside as unreadable')
    d.root.selectOnly(0)
    d.root.recolorItem()
    d.root.save(true)
    d.session.flushSave()
    d.land()
    assert.equal(d.writes.length, 0, layout + ': and never written')
    assert.equal(d.items.get(0).itint, 'accent', layout + ': the board shown as it is')
    assert.ok(ask || layout === 'pretty and moved', layout + ': the worker was asked')
  }

  // A history this reads: the same wait, then edits as usual.
  const ok = opened(written(first).text)
  ok.root.selectOnly(1)
  ok.root.cycleKind()
  assert.equal(ok.items.get(1).kind, 'note', 'not while it is read')
  ok.answer(W.check(ok.worker.asked[ok.worker.asked.length - 1]))
  assert.equal(ok.root.canEdit, true)
  ok.root.cycleKind()
  ok.land()
  assert.deepEqual(labels(ok), ['Colour', 'Shape'])

  // An answer about a board since read again, or replaced, is not about this
  // one: a late "newer" cannot make the board on screen read-only.
  const late = opened(pretty)
  const stale = W.check(late.worker.asked[late.worker.asked.length - 1])
  late.session.loadBoard(plain(2), false)
  late.answer(stale)
  assert.equal(late.root.canEdit, true, 'a late answer locks nothing')
  assert.equal(late.session.damaged, false)
  console.log('ok — recording: a newer history is never written over, however it is laid out')
}

{
  // Past the limit, the oldest tenth goes and the baseline moves on; edits
  // made while the worker trims are kept.
  const c = opened(plain(1))
  c.root.selectOnly(0)
  // From 1: setting x to the 0 it already is changes nothing, and is no record.
  for (let i = 1; i <= H.MAX_HISTORY_RECORDS + 1; i++) {
    c.root.pushUndo('Colour')
    c.root.items.setProperty(0, 'ix', i)
    c.root.save()
    c.land()
    // The harness keeps every file written; ten thousand of a growing
    // history is more than it needs to hold.
    c.writes.splice(0, c.writes.length - 1)
  }
  assert.equal(c.doc.historyTrimming, true, 'the limit asks the worker to trim')
  const ask = c.worker.asked[c.worker.asked.length - 1]
  c.root.pushUndo('Shape')
  c.root.items.setProperty(0, 'ix', -1)
  c.root.save()
  c.land()
  const reply = W.shorten(ask)
  assert.equal(reply.dropped, 1001)
  c.answer(reply)
  c.land()
  assert.match(c.root.statusText, /oldest 1001 edits left/)
  const w = written(c)
  assert.equal(w.records.length, H.MAX_HISTORY_RECORDS + 2 - 1001)
  assert.equal(w.records[w.records.length - 1].a, 'Shape', 'the edit made meanwhile is still there')
  assert.equal(w.history.base.items[0].x, 1001, 'and the baseline is where the dropped edits ended')
  assert.equal(H.verify(w.history, live(w.file)), '')
  console.log('ok — recording: past the limit the oldest edits go, nothing made meanwhile')
}

{
  // Forgetting asks twice, then writes the board without a history.
  const c = opened(plain(2))
  c.root.selectOnly(0)
  c.root.recolorItem()
  c.land()
  c.root.forgetHistory()
  assert.match(c.root.statusText, /Run it again/)
  assert.equal(written(c).file.version, 7, 'asking once forgets nothing')
  c.root.forgetHistory()
  c.land()
  const w = written(c)
  assert.equal(w.file.version, 5)
  assert.equal(w.history, undefined, 'the file no longer has one')
  assert.match(c.root.statusText, /forgotten/)
  c.root.cycleKind()
  c.land()
  assert.equal(written(c).history.base.items[0].tint, 'accent', 'the next starts from the board as it was')
  console.log('ok — recording: forgetting asks twice and starts again from here')
}

{
  // Two panes on one board make one history; a conflict copy carries it;
  // a copy made to share does not.
  const c = opened(plain(2))
  const a = c.root, b = c.second
  a.toggleSplit('side-by-side')
  a.selectOnly(0)
  a.recolorItem()
  c.land()
  b.selectOnly(1)
  b.cycleKind()
  c.land()
  assert.deepEqual(labels(c), ['Colour', 'Shape'])
  c.session.conflict = true
  b.conflictSaveCopy()
  assert.equal(JSON.parse(c.exchange.copies[0].text).history.records.length, 2, 'the copy keeps its history')
  assert.equal(JSON.parse(c.store.writeFile(c.items, c.links, 3)).history, undefined, 'a shared copy has none')
  console.log('ok — recording: two panes, one history; copies to share leave it out')
}
