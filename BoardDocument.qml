import QtQuick
import Quickshell.Io
import "BoardStore.js" as Store
import "BoardHistory.js" as History

// One open board: what is on it, the ids it hands out, its undo history and
// the session that loads and saves its file. A pane shows a document and the
// workspace keeps the list of them; two panes on the same board are two views
// of one of these, so they cannot disagree about what the board holds or race
// each other to write it.
//
// The session reads its controller by name, as it always has. This is that
// controller now: what the session asks of the view — forget the selection,
// frame the board, say something on the line — goes on to every pane showing
// this board, and the rest comes from the workspace.
Item {
  id: doc

  required property var workspace

  property alias items: itemModel
  property alias links: linkModel

  ListModel { id: itemModel }
  ListModel { id: linkModel }

  property int nextId: 1
  property int nextColor: 0
  property var undoStack: []
  property var redoStack: []

  // Relative to boardsDir, e.g. "work/project-a.json".
  property string currentBoard: "board.json"
  readonly property string boardPath: doc.workspace.boardsDir + "/" + doc.currentBoard
  readonly property string boardTitle: Store.displayName({ path: doc.currentBoard, dir: false })

  // ------------------------------------------------------- what panes read
  readonly property bool boardLoaded: session.boardLoaded
  readonly property bool damaged: session.damaged
  readonly property string damageReason: session.damageReason
  readonly property string saveError: session.saveError
  // Someone else wrote this board while it was open and the screen has changes
  // of its own. Autosave is waiting, and nothing but a choice clears it.
  readonly property bool diskChanged: session.conflict
  readonly property bool saving: session.busy
  readonly property var pendingBoard: session.pendingBoard
  readonly property bool canEdit: session.canEdit

  // A pane changed what is on the board. Every edit ends in a save, so this is
  // said there; the other pane showing this board looks its cursor up again,
  // because a cursor is a row and rows move when someone else deletes one.
  signal edited(var by)
  function noteEdit(by) {
    if (!doc.changed) doc.changedSince = Date.now()
    doc.changed = true
    doc.edited(by)
  }

  function save(allowEmpty) { session.save(allowEmpty) }
  // Typing that never pauses is still written, and still recorded, every five
  // seconds: the autosave delay restarts with every keystroke, and a long
  // enough run of them would otherwise keep both waiting.
  function scheduleSave() {
    if (doc.changed && Date.now() - doc.changedSince > History.MAX_CHUNK_MS) session.flushSave()
    else session.scheduleSave()
  }
  function flushSave() { session.flushSave() }
  function openBoard(path, fresh) { session.openBoard(path, fresh) }
  function useDisk() { session.useDisk() }
  function replaceDisk() { session.replaceDisk() }
  function keptAsCopy(name) { session.keptAsCopy(name) }

  // A new board opened straight into a pane: the file is made once it is
  // confirmed missing, the way a board switched to in place is made. Set when
  // the document is made, before its file has been looked for.
  property bool fresh: false
  Component.onCompleted: if (doc.fresh) session.createWhenLoaded = true

  // ------------------------------------------------ what the session reads
  readonly property int autosaveMs: doc.workspace.autosaveMs
  readonly property bool stateReady: doc.workspace.stateReady
  readonly property string boardsDir: doc.workspace.boardsDir
  readonly property string backupsDir: doc.workspace.backupsDir
  readonly property var library: doc.workspace.library
  function backupPathFor(relative) { return doc.workspace.backupPathFor(relative) }
  function lockPathFor(relative) { return doc.workspace.lockPathFor(relative) }
  function fileCommand(action, args) { return doc.workspace.fileCommand(action, args) }
  function writeState() { doc.workspace.writeState() }

  // Every pane showing this board, for what the session has to say to the view.
  function viewers() { return doc.workspace.panesViewing(doc) }

  // The pane the keyboard is in, if it is showing this board. Filling the model
  // takes the keyboard from the delegates it tears down, and only a pane that
  // had it needs it back.
  function focusKeys() {
    var pane = doc.workspace.activePane
    if (pane && pane.doc === doc) pane.focusKeys()
  }

  // The board under every view is about to be a different one, or the same one
  // read again: what was selected on it means nothing now. Leaving the board
  // also ends what was half done on it.
  function resetSelection(endModes) {
    var panes = doc.viewers()
    for (var i = 0; i < panes.length; i++) panes[i].resetSelection(endModes)
  }

  function resetView() {
    var panes = doc.viewers()
    for (var i = 0; i < panes.length; i++) panes[i].resetView()
  }

  function repaintLinks() {
    var panes = doc.viewers()
    for (var i = 0; i < panes.length; i++) panes[i].repaintLinks()
  }

  function flash(text) {
    var panes = doc.viewers()
    for (var i = 0; i < panes.length; i++) panes[i].flash(text)
  }

  // The question goes where the keyboard is, if that pane is showing this
  // board, and otherwise to whichever pane is.
  function decideConflict() {
    var pane = doc.workspace.activePane
    var panes = doc.viewers()
    if (!pane || pane.doc !== doc) pane = panes.length > 0 ? panes[0] : null
    if (pane) pane.decideConflict()
  }

  // ------------------------------------------------------------- history
  // Every completed edit, kept as text: the board's history is appended to and
  // written after the board, never parsed on this thread when the board opens
  // and never written out again whole (docs/splitview-timeline-plan.md, gate 3).
  // "" until the board has one; a board nobody has edited since it was opened
  // here is written as the plain format, with none.
  property string historyHeader: ""
  property string historyRecords: ""
  property int historyCount: 0
  property int historyBytes: 0
  property int historyLast: 0
  property real historyStart: 0
  // The history as the file had it, written back unchanged while the worker
  // reads it: until then where it ends is not known, so nothing is numbered
  // onto it. Edits made meanwhile wait, unnumbered, in historyWaiting.
  property string historyAsLoaded: ""
  property bool historyChecking: false
  property var historyWaiting: []
  property bool historyTrimming: false
  property bool historyTrimmed: false
  // Bumped whenever the history is replaced, so a worker's answer about the
  // one before is recognised and dropped.
  property int historyToken: 0
  // The board as of the last record, which the next one is the difference
  // from; and as it was opened, which a history that cannot be read starts
  // again from.
  property var head: null
  property var loadedState: null
  // The edit in progress: what it is called, whether anything has changed
  // since the last record, and since when.
  property string editLabel: ""
  property string editKey: ""
  property bool changed: false
  property real changedSince: 0

  function snapshot() {
    return { items: Store.itemRows(itemModel), links: Store.linkRows(linkModel), nextId: doc.nextId }
  }

  // An edit is starting. Whatever was in progress is a record of its own,
  // unless this is more of the same: typing in the same note, a held key
  // moving or resizing something.
  function beginEdit(label, key) {
    var same = label === doc.editLabel && key === doc.editKey && History.MERGING.indexOf(label) >= 0
    if (doc.editLabel !== "" && !same) doc.endEdit()
    doc.editLabel = label
    doc.editKey = key === undefined ? "" : key
  }

  // The edit in progress is finished: typing has stopped, the pane has lost
  // the keyboard, the board is being left.
  function endEdit() {
    doc.commitEdit()
    doc.editLabel = ""
    doc.editKey = ""
  }

  // Records whatever has changed since the last record, under the name of the
  // edit in progress. A typing session goes on under its name after a pause.
  function commitEdit() {
    if (!doc.changed) return
    doc.changed = false
    if (!doc.head || !session.boardLoaded || session.damaged) return
    var before = doc.head
    var after = doc.snapshot()
    var patch = History.diff(before, after)
    doc.head = after
    if (patch === null) return
    var now = Date.now()
    // The first edit on a board without a history starts one, from the board
    // as it was just before it.
    if (doc.historyHeader === "" && !doc.historyChecking) {
      doc.historyStart = now
      doc.historyHeader = History.startText(before, now, History.newLineage(now))
    }
    var record = { i: 0, t: Math.max(0, Math.round((now - doc.historyStart) / 1000)),
                   a: doc.editLabel !== "" ? doc.editLabel : "Edit", p: patch }
    if (History.MERGING.indexOf(record.a) < 0) { doc.editLabel = ""; doc.editKey = "" }
    if (doc.historyChecking) doc.historyWaiting = doc.historyWaiting.concat([record])
    else doc.appendRecord(record)
  }

  function appendRecord(record) {
    record.i = doc.historyLast + 1
    var text = JSON.stringify(record)
    doc.historyRecords = doc.historyRecords === "" ? text : doc.historyRecords + "," + text
    doc.historyLast = record.i
    doc.historyCount += 1
    doc.historyBytes += History.utf8Length(text) + 1
    if (doc.replay) {
      doc.replay.h.records.push(record)
      History.extendIndex(doc.replay.ix, doc.replay.h)
      indexer.start()
      doc.replayRevision += 1
    }
    if (doc.historyCount > History.MAX_HISTORY_RECORDS || doc.historyBytes > History.MAX_HISTORY_BYTES) doc.startTrim()
  }

  // What the file holds: the board as it is, after the edit in progress has
  // been recorded, with its history after it.
  function fileText() {
    doc.commitEdit()
    var history = doc.historyChecking ? doc.historyAsLoaded
      : doc.historyHeader === "" ? "" : History.joinText(doc.historyHeader, doc.historyRecords)
    return Store.writeFile(itemModel, linkModel, doc.nextId, history)
  }

  // A board has been read: from its file when it was opened, or again because
  // it changed on disk. Its history is taken as text and handed to the worker
  // to read. Answers why the board must be read-only, or "".
  function adoptHistory(text, boardText) {
    doc.historyToken += 1
    doc.dropReplay()
    doc.head = doc.snapshot()
    doc.loadedState = doc.head
    doc.editLabel = ""
    doc.editKey = ""
    doc.changed = false
    doc.historyWaiting = []
    doc.historyTrimming = false
    doc.historyHeader = ""
    doc.historyRecords = ""
    doc.historyCount = 0
    doc.historyBytes = 0
    doc.historyLast = 0
    doc.historyAsLoaded = text
    doc.historyChecking = false
    if (text === "") return ""
    var parts = History.splitText(text)
    var facts = parts ? History.headerFacts(parts.header) : null
    if (facts && facts.v > History.HISTORY_VERSION) return "has history from a newer Omarchyform"
    if (parts) {
      doc.historyHeader = parts.header
      doc.historyRecords = parts.records
      doc.historyLast = History.lastNumber(parts.records)
    }
    doc.historyStart = facts && typeof facts.start === "number" ? facts.start : Date.now()
    doc.historyChecking = true
    // Laid out some other way, by an editor's formatter say: the worker sends
    // it back in this writer's shape rather than this thread parsing it.
    historyWorker.sendMessage({ check: true, token: doc.historyToken, history: text, board: boardText,
                                now: Date.now(), normalize: parts === null })
    return ""
  }

  function checkedHistory(answer) {
    // One answer per reading; a second is not news.
    if (!doc.historyChecking) return
    doc.historyChecking = false
    if (answer.unreadable) {
      // Kept, not repaired: the old history goes beside the board's backups,
      // and a new one starts from the board as it was opened.
      doc.setAside(doc.historyAsLoaded)
      var now = Date.now()
      doc.historyStart = now
      doc.historyHeader = History.startText(doc.loadedState, now, History.newLineage(now))
      doc.historyRecords = ""
      doc.historyCount = 0
      doc.historyBytes = 0
      doc.historyLast = 0
      doc.flash("This board's history could not be read (" + answer.error + "); it starts again from here")
    } else {
      var normal = answer.text !== "" ? History.splitText(answer.text) : null
      if (normal) {
        doc.historyHeader = normal.header
        doc.historyRecords = normal.records
        var facts = History.headerFacts(normal.header)
        if (facts && typeof facts.start === "number") doc.historyStart = facts.start
      }
      doc.historyCount = answer.count
      doc.historyBytes = answer.bytes
      doc.historyLast = answer.last
      if (answer.bridge !== "") {
        doc.historyRecords = doc.historyRecords === "" ? answer.bridge : doc.historyRecords + "," + answer.bridge
      }
    }
    doc.historyAsLoaded = ""
    var waiting = doc.historyWaiting
    doc.historyWaiting = []
    for (var i = 0; i < waiting.length; i++) doc.appendRecord(waiting[i])
    if (answer.bridge !== "" || answer.unreadable || waiting.length > 0) session.save(true)
  }

  // Past either limit, the oldest tenth goes: the worker trims a copy, and the
  // records taken while it did are put back after it.
  function startTrim() {
    if (doc.historyTrimming || doc.historyChecking || doc.historyHeader === "") return
    doc.historyTrimming = true
    historyWorker.sendMessage({ trim: true, token: doc.historyToken,
                                history: History.joinText(doc.historyHeader, doc.historyRecords) })
  }

  function trimmedHistory(answer) {
    if (!doc.historyTrimming) return
    doc.historyTrimming = false
    var parts = answer.error === "" ? History.splitText(answer.text) : null
    if (!parts) return
    var since = doc.historyRecords.indexOf('{"i":' + (answer.last + 1) + ",")
    var tail = since >= 0 ? doc.historyRecords.slice(since) : ""
    doc.historyHeader = parts.header
    doc.historyRecords = tail === "" ? parts.records : parts.records === "" ? tail : parts.records + "," + tail
    doc.historyCount = answer.count + (doc.historyLast - answer.last)
    doc.historyBytes = answer.bytes + (tail === "" ? 0 : History.utf8Length(tail) + 1)
    if (!doc.historyTrimmed)
      doc.flash("The oldest " + answer.dropped + " edits left this board's history; it keeps the newest "
                + History.MAX_HISTORY_RECORDS)
    doc.historyTrimmed = true
    // A pane looking back reads the trimmed history again; where it was may
    // be one of the edits that went.
    if (doc.replay) doc.readReplay()
    session.save(true)
  }

  // Forgets every edit, and starts again from the board as it is. Written
  // straight away, as a board with no history.
  function forgetHistory() {
    doc.endEdit()
    doc.historyToken += 1
    doc.dropReplay()
    doc.historyHeader = ""
    doc.historyRecords = ""
    doc.historyCount = 0
    doc.historyBytes = 0
    doc.historyLast = 0
    doc.historyAsLoaded = ""
    doc.historyChecking = false
    doc.historyWaiting = []
    doc.historyTrimming = false
    doc.head = doc.snapshot()
    session.save(true)
  }

  // ---------------------------------------------------------------- replay
  // The history parsed, with the index a timeline seeks with, while any pane
  // is looking back through it: read once however many panes look, extended as
  // edits are recorded, read again after a trim, and let go when the last pane
  // stops looking. Parsed here, on the shell's thread, because seeking from a
  // worker cost more than it saved (gate 3).
  property var replay: null
  property int replayUsers: 0
  // Bumped whenever what the replay holds changes, for the panes looking.
  property int replayRevision: 0

  // Answers "" or why there is nothing to look back through.
  function openReplay() {
    if (doc.historyChecking) return "still reading this board's history · try again in a moment"
    // The edit in progress is the latest step, so the timeline ends where the
    // board is.
    doc.endEdit()
    if (doc.historyHeader === "") return "this board has no history yet · it starts with the next edit"
    if (!doc.replay && !doc.readReplay()) return "this board's history could not be read"
    doc.replayUsers += 1
    return ""
  }

  function closeReplay() {
    doc.replayUsers = Math.max(0, doc.replayUsers - 1)
    if (doc.replayUsers === 0) doc.dropReplay()
  }

  function readReplay() {
    var h
    try { h = JSON.parse(History.joinText(doc.historyHeader, doc.historyRecords)) } catch (e) { h = null }
    if (!h || History.checkShape(h) !== "") { doc.dropReplay(); return false }
    doc.replay = { h: h, ix: History.newIndex(h, 100) }
    indexer.start()
    doc.replayRevision += 1
    return true
  }

  function dropReplay() {
    indexer.stop()
    if (doc.replay === null) return
    doc.replay = null
    doc.replayRevision += 1
  }

  // A slice of the index at a time, between frames: 200 records took at most
  // 17ms on a 3000-item board (tests/history-bench.js).
  function indexReplay() {
    if (!doc.replay || History.indexSome(doc.replay.ix, doc.replay.h, 200)) indexer.stop()
  }
  Timer { id: indexer; interval: 1; repeat: true; onTriggered: doc.indexReplay() }

  // The board after `count` records: 0 is where the history starts.
  function replayState(count) {
    return doc.replay ? History.stateAt(doc.replay.ix, doc.replay.h, count) : null
  }

  // A history that could not be read, kept where the board's backups are,
  // under a name of its own so nothing overwrites it.
  function setAside(text) {
    if (text === "") return
    aside.path = ""
    aside.path = doc.backupsDir + "/" + Store.lockKey(doc.currentBoard) + ".history-" + Date.now() + ".json"
    var body = text
    Qt.callLater(function () { aside.setText(body) })
  }
  FileView { id: aside; preload: false; atomicWrites: true; printErrors: false }

  WorkerScript {
    id: historyWorker
    source: "BoardHistoryWorker.js"
    onMessage: function (answer) {
      if (answer.token !== doc.historyToken) return
      if (answer.kind === "checked") doc.checkedHistory(answer)
      else if (answer.kind === "trimmed") doc.trimmedHistory(answer)
    }
  }

  BoardSession { id: session; ctl: doc }
}
