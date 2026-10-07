// The timeline: a pane stepping, jumping, scrubbing and playing through its
// board's history, read-only, while the board goes on being edited. Every
// state shown is checked against a snapshot taken when that edit was made.
// The workspace, panes and documents run from their QML sources, as in
// tests/controller.js; the history worker from its own file.
const assert = require('assert/strict')
const fs = require('fs')
const path = require('path')
const vm = require('vm')
const { loadStore } = require('../bin/store')
const { controller } = require('./workspace-harness')

const S = loadStore()

const rows = model => S.itemRows(model).map(r => [r.id, r.kind, r.x, r.y, r.tint, r.text])

// A board with three notes and five edits, keeping a snapshot after each.
function edited() {
  const c = controller()
  c.session.loadBoard(JSON.stringify({ kind: 'omarchyform.board', version: 5, nextId: 4, links: [],
    items: [1, 2, 3].map(id => ({ id, kind: 'note', x: id * 300, y: 0, w: 220, h: 160, tint: 'foreground',
      text: 'note ' + id, pinned: false, src: '' })) }, null, 2) + '\n', false)
  const land = () => { while (c.persistence.busy) c.complete() }
  const snaps = [rows(c.items)]
  const step = act => { act(); land(); snaps.push(rows(c.items)) }
  const a = c.root
  step(() => { a.selectOnly(0); a.recolorItem() })
  step(() => { a.selectOnly(1); a.nudgeSelected(1, 0); c.session.flushSave() })
  step(() => { a.selectOnly(2); a.cycleKind() })
  step(() => { a.selectOnly(0); a.removeTargets() })
  step(() => { a.selectOnly(0); a.editSelected(); a.items.setProperty(0, 'itext', 'typed'); a.stopEditing() })
  return Object.assign(c, { land, snaps })
}

{
  // Nothing to look back through yet is said, not shown as an empty timeline.
  const c = controller()
  c.session.loadBoard('{"version":5,"nextId":1,"items":[],"links":[]}', false)
  c.root.toggleTimeline()
  assert.equal(c.root.timeline, false)
  assert.match(c.root.statusText, /no history yet/)
  console.log('ok — timeline: a board with no history says so')
}

{
  // Step, jump and scrub: each shows exactly the board as it was then.
  const c = edited()
  const a = c.root
  assert.equal(c.doc.historyCount, 5)
  a.toggleTimeline()
  c.index()
  assert.equal(a.timeline, true)
  assert.equal(a.lookingBack, false, 'it opens on the board as it is')
  assert.match(a.timelineSays, /^now · 5 steps/)

  a.timelineStep(-1)
  assert.equal(a.lookingBack, true)
  assert.deepEqual(rows(a.items), c.snaps[4], 'one step back is the board before the latest edit')
  assert.match(a.timelineSays, /^step 4 of 5 · Delete · \d\d:\d\d$/)
  for (let k = 3; k >= 0; k--) {
    a.timelineStep(-1)
    assert.deepEqual(rows(a.items), c.snaps[k], 'step ' + k)
  }
  a.timelineStep(-1)
  assert.deepEqual(rows(a.items), c.snaps[0], 'and no further than where it starts')
  assert.match(a.timelineSays, /^step 0 of 5 · where the history starts/)
  a.timelineLatest()
  assert.deepEqual(rows(a.items), c.snaps[5])
  a.timelineFirst()
  assert.deepEqual(rows(a.items), c.snaps[0])
  a.scrubTo(0.6)
  a.scrubNow()
  assert.deepEqual(rows(a.items), c.snaps[3], 'six tenths along five steps is the third')
  assert.equal(a.timelineFraction, 0.6)

  // A note too long to lay out, which only a hand-made history can hold, is
  // not shown: the step is refused, as the live board refuses such a note.
  const long = c.doc.replay.h.records[1]
  const kept = JSON.stringify(long.p)
  long.p = { s: [[2, { text: 'x'.repeat(S.MAX_NOTE_LENGTH + 1) }]] }
  a.showRecord(a.firstRecord() + 2)
  assert.match(a.statusText, /too long to show/)
  assert.deepEqual(rows(a.items), c.snaps[3], 'and the step on screen stays')
  long.p = JSON.parse(kept)
  a.statusText = ''

  // Read-only: the commands refuse, nothing is recorded, nothing goes out.
  a.selectOnly(0)
  a.recolorItem()
  a.removeTargets()
  a.addRelative('note')
  c.land()
  assert.equal(c.doc.historyCount, 5, 'an earlier version is not edited')
  assert.deepEqual(rows(c.items), c.snaps[5], 'and the board as it is is untouched')
  a.choosePng('theme')
  a.exportBoard()
  assert.deepEqual(c.exchange.chosen, [], 'nothing is sent out from an earlier version')

  // Escape is back to now, then out of the timeline.
  a.timelineBack()
  assert.equal(a.lookingBack, false)
  assert.equal(a.items, c.items, 'the board as it is, live')
  a.timelineBack()
  assert.equal(a.timeline, false)
  assert.equal(c.doc.replay, null, 'and the history it read is let go')
  console.log('ok — timeline: every step is the board as it was, and only to look at')
}

{
  // Edits arriving do not move where a pane is looking; playing stops where
  // the history ended when it started; two panes share one reading.
  const c = edited()
  const a = c.root, b = c.second
  a.toggleSplit('side-by-side')
  c.workspace.activate(a)
  a.toggleTimeline()
  c.index()
  a.timelineStep(-1)
  a.timelineStep(-1)
  const at = a.timelineRecord
  b.selectOnly(0)
  b.cycleKind()
  c.land()
  assert.equal(c.doc.historyCount, 6)
  assert.equal(a.timelineRecord, at, 'the step looked at stays')
  assert.deepEqual(rows(a.items), c.snaps[3])
  assert.match(a.timelineSays, /of 6/, 'and the new edit is counted')

  a.togglePlay()
  assert.equal(a.playing, true)
  assert.deepEqual(rows(a.items), c.snaps[3], 'played from a step part-way, it carries on from there')
  b.recolorItem()
  c.land()
  let ticks = 0
  while (a.playing && ticks++ < 50) a.playStep()
  assert.equal(a.timelineRecord, 6, 'it stopped at the step that was last when it started')
  assert.equal(a.lastRecord(), 7)

  b.toggleTimeline()
  assert.equal(c.doc.replayUsers, 2, 'one reading for both panes')
  b.leaveTimeline()
  assert.notEqual(c.doc.replay, null, 'still held while one pane looks')
  console.log('ok — timeline: new edits do not move it, and playing stops where it began')
}

{
  // The oldest edits leaving, and the history being forgotten, while a pane
  // looks back.
  const H = loadStore(fs.readFileSync(path.join(__dirname, '..', 'BoardHistory.js'), 'utf8'))
  const context = vm.createContext(Object.assign({ WorkerScript: { sendMessage() {} } }, H))
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'BoardHistoryWorker.js'), 'utf8')
    .replace(/^Qt\.include\(.*\)$/m, ''), context)
  const c = edited()
  const a = c.root
  a.toggleTimeline()
  c.index()
  a.timelineFirst()
  // What trimming answers, as if this were past the limit: the first two go.
  const h = JSON.parse(c.doc.historyHeader + c.doc.historyRecords + ']}')
  const w = H.working(h.base)
  H.apply(w, h.records[0].p)
  H.apply(w, h.records[1].p)
  h.base = H.copyState(H.stateOf(w))
  h.records = h.records.slice(2)
  const size = H.measure(h)
  c.doc.historyTrimming = true
  c.answer({ kind: 'trimmed', token: c.doc.historyToken, error: '', text: JSON.stringify(h), dropped: 2,
             count: size.count, bytes: size.bytes, last: size.last })
  c.index()
  assert.match(a.statusText, /oldest, which have left/)
  assert.equal(a.timelineRecord, 2, 'it goes to the oldest step there still is')
  assert.deepEqual(rows(a.items), c.snaps[2])

  // Forgetting is an edit, so it is done from now; the timeline closes with it.
  a.forgetHistory()
  assert.equal(c.doc.historyHeader !== '', true, 'not from an earlier version')
  a.timelineNow()
  a.forgetHistory()
  a.forgetHistory()
  assert.equal(a.timeline, false, 'a forgotten history closes the timeline')
  assert.match(a.statusText, /forgotten|replaced/)
  console.log('ok — timeline: the oldest edits leaving, or all of them, while looking back')
}

{
  // Compare: an earlier version beside the board as it is.
  const c = edited()
  const a = c.root, b = c.second
  a.compareWithCurrent()
  c.index()
  assert.equal(c.workspace.split, true)
  assert.equal(c.workspace.activePane, a, 'the keyboard stays with the earlier version')
  assert.equal(a.lookingBack, true)
  assert.deepEqual(rows(a.items), c.snaps[4], 'one edit back')
  assert.equal(b.doc, a.doc)
  assert.equal(b.timeline, false, 'beside the board as it is')
  assert.deepEqual(rows(b.items), c.snaps[5])

  // With another board in the other pane, it asks before replacing it.
  const d = edited()
  d.root.toggleSplit('side-by-side')
  d.second.openBoard('other.json')
  d.workspace.activate(d.root)
  d.root.compareWithCurrent()
  assert.equal(d.second.currentBoard, 'other.json', 'not on the first ask')
  assert.match(d.root.statusText, /run it again/)
  const other = d.second.doc
  d.root.compareWithCurrent()
  // Leaving the other board waits for its last write, as any switch does.
  while (d.of(other).persistence.busy) d.of(other).complete()
  d.workspace.retryLeave()
  assert.equal(d.second.doc, d.root.doc, 'on the second')
  assert.equal(d.root.lookingBack, true)
  console.log('ok — timeline: compare puts an earlier version beside the board as it is')
}
