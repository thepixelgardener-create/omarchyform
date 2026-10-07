// Recording a board's history as it is edited: where one edit ends and the
// next begins, that what is written can always be played back to the board it
// was written with, and what happens when a history is opened that ends
// elsewhere, cannot be read, comes from a newer version, or has grown past its
// limits. The workspace, panes and documents run from their QML sources, as in
// tests/controller.js; the history worker runs from its own file.
const assert = require('assert/strict')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const { loadStore } = require('../bin/store')
const { controller } = require('./workspace-harness')

const H = loadStore(fs.readFileSync(path.join(__dirname, '..', 'BoardHistory.js'), 'utf8'))

// BoardHistoryWorker.js as the worker thread runs it: its Qt.include is the
// codec's own functions, in scope.
function worker() {
  const context = vm.createContext(Object.assign({ WorkerScript: { sendMessage() {} } }, H))
  const source = fs.readFileSync(path.join(__dirname, '..', 'BoardHistoryWorker.js'), 'utf8')
    .replace(/^Qt\.include\(.*\)$/m, '')
  vm.runInContext(source, context)
  return { check: m => context.check(m), shorten: m => context.shorten(m) }
}
const W = worker()

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
  // A board without a history gets one at its first edit, starting from the
  // board as it was just before it, and is written in the newest format.
  const c = opened(plain(2))
  assert.equal(c.doc.historyChecking, false, 'nothing to read')
  c.root.selectOnly(0)
  c.root.recolorItem()
  c.land()
  const w = written(c)
  assert.equal(w.file.version, 6)
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
  // numbered onto it, and what is written carries it exactly as it was.
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
  const meanwhile = written(c)
  assert.equal(meanwhile.records.length, 1, 'the history goes out as it came in')
  assert.equal(meanwhile.file.items[1].kind, 'rect', 'with the board as it is now in front of it')

  const reply = W.check(asked)
  assert.equal(reply.error, '')
  assert.equal(reply.bridge, '', 'it ends at the board it was opened with')
  c.answer(reply)
  c.land()
  const w = written(c)
  assert.deepEqual(w.records.map(r => [r.i, r.a]), [[1, 'Colour'], [2, 'Shape']],
    'the edit made while it was read follows, numbered after it')
  assert.equal(H.verify(w.history, live(w.file)), '')
  // The same answer twice is not news, and one about a history that has since
  // been replaced is not about this one.
  c.answer(Object.assign({}, reply, { count: 999 }))
  assert.notEqual(c.doc.historyCount, 999, 'a second answer changes nothing')
  const again = opened(saved)
  const stale = W.check(again.worker.asked[again.worker.asked.length - 1])
  again.root.forgetHistory()
  again.root.forgetHistory()
  again.doc.historyChecking = true
  again.answer(Object.assign({}, stale, { count: 999 }))
  assert.notEqual(again.doc.historyCount, 999, 'an answer about a forgotten history is dropped')
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
  c.root.selectOnly(0)
  c.root.recolorItem()
  c.answer(W.check(c.worker.asked[c.worker.asked.length - 1]))
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
  assert.equal(written(c).file.version, 6, 'asking once forgets nothing')
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
