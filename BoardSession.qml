import QtQuick
import Quickshell.Io
import "BoardStore.js" as Store

// Owns loading, autosave, and the transition between boards. The controller
// supplies the document models and presentation state; BoardPersistence owns I/O.
Item {
  id: session
  required property var ctl

  property bool boardLoaded: false
  property bool damaged: false
  property string saveError: ""
  property string lastSavedText: ""
  property int savingCount: 0
  property int lastSavedCount: -1
  property var pendingBoard: null
  property bool createWhenLoaded: false
  readonly property bool canEdit: boardLoaded && !damaged && pendingBoard === null
  readonly property bool busy: persistence.busy

  // Typing is debounced; structural edits call save() directly.
  function scheduleSave() {
    if (!session.boardLoaded) return
    saveTimer.restart()
  }

  function flushSave() {
    if (saveTimer.running) saveTimer.stop()
    session.save()
  }

  function openBoard(path, fresh) {
    if (!Store.safeRelative(path)) return
    if (path === session.ctl.currentBoard && !fresh) return
    session.flushSave()
    if (persistence.busy || session.saveError !== "") {
      session.pendingBoard = { path: path, fresh: fresh === true }
      if (session.saveError !== "") session.pendingBoard = null
      return
    }
    session.createWhenLoaded = fresh === true
    session.boardLoaded = false
    session.damaged = false
    session.lastSavedCount = -1
    session.ctl.undoStack = []
    session.ctl.redoStack = []
    session.ctl.markedIds = []
    session.ctl.showPinned = false
    session.ctl.selectedIndex = -1
    session.ctl.editIndex = -1
    session.ctl.linkingFrom = -1
    session.ctl.currentBoard = path
    session.ctl.resetView()
    session.ctl.writeState()
  }

  function save(allowEmpty) {
    if (!session.boardLoaded) return
    if (session.ctl.items.count === 0 && session.lastSavedCount > 0 && allowEmpty !== true) return
    if (persistence.busy) return // Completion serializes the latest model again.
    var text = Store.writeFile(session.ctl.items, session.ctl.links, session.ctl.nextId)
    session.saveError = ""
    if (text === session.lastSavedText) return
    // Remember what this write contains, so completing it does not have to
    // parse the whole board back again just to count the items.
    session.savingCount = session.ctl.items.count
    persistence.save(session.ctl.boardPath, text, session.ctl.backupPathFor(session.ctl.currentBoard), session.ctl.boardsDir, session.ctl.backupsDir)
  }

  function savedBoard(path, text) {
    // A completion belongs to the board it names. Adopting it as the baseline
    // for a different board suppresses that board's first write whenever the
    // two serialise the same — which two empty boards always do, so creating a
    // board straight after switching away from an empty one wrote nothing.
    if (path === session.ctl.boardPath) {
      session.lastSavedText = text
      session.lastSavedCount = session.savingCount
    }
    // Always compare the latest model after completion: edits made while the
    // writer was busy are coalesced here without a separate pending flag.
    session.save(true)
    if (!persistence.busy && session.pendingBoard !== null) {
      var next = session.pendingBoard
      session.pendingBoard = null
      session.openBoard(next.path, next.fresh)
    }
  }

  function failedSave(message) {
    session.saveError = message + " — ctrl+s to retry"
    if (session.ctl.browserVisible) session.ctl.browserMessage = message + " — esc, then ctrl+s to retry"
    session.pendingBoard = null
  }

  // Only a confirmed missing file may become a new, writable empty board.
  function loadBoard(raw, missing) {
    var data = Store.readFile(raw)
    session.ctl.items.clear()
    session.ctl.links.clear()
    session.damaged = !data && !missing
    session.saveError = ""
    session.ctl.nextId = 1
    session.ctl.nextColor = 0
    if (data) {
      Store.fillItems(session.ctl.items, data.items)
      Store.fillLinks(session.ctl.links, session.ctl.items, data.links)
      session.ctl.nextId = Store.nextFreeId(session.ctl.items, data.nextId)
      session.ctl.nextColor = session.ctl.items.count
    }
    session.ctl.markedIds = []
    session.ctl.showPinned = false
    session.ctl.selectedIndex = -1
    session.ctl.undoStack = []
    session.ctl.redoStack = []
    session.lastSavedCount = session.ctl.items.count
    // A damaged board is displayed empty but stays read-only.
    session.lastSavedText = data ? Store.writeFile(session.ctl.items, session.ctl.links, session.ctl.nextId) : ""
    session.boardLoaded = !session.damaged
    if (session.createWhenLoaded && session.boardLoaded) session.save(true)
    session.createWhenLoaded = false
    // Remember which board this was, so the next session opens it again.
    session.ctl.writeState()
    session.ctl.repaintLinks()
    // Filling the model tears down every delegate and takes the keyboard with
    // it. The load lands after the browser has closed, so without this a board
    // switch leaves nothing listening.
    if (!session.ctl.browserVisible) session.ctl.focusKeys()
  }

  BoardPersistence {
    id: persistence
    onCompleted: function(path, text) { session.savedBoard(path, text) }
    onFailed: function(message) { session.failedSave(message) }
    onDelayed: function(message) { session.saveError = message }
  }

  Timer {
    id: saveTimer
    interval: session.ctl.autosaveMs
    repeat: false
    onTriggered: session.save()
  }

  FileView {
    id: boardFile
    // Empty until the state file has said which board to open: loading too
    // early would mark an empty board as loaded, and the next save would write
    // that emptiness over a real file.
    path: session.ctl.stateReady ? session.ctl.boardPath : ""
    watchChanges: false
    atomicWrites: true
    printErrors: false
    // Loading and writing use separate FileViews. Ignore duplicate load
    // notifications once this board has been initialized.
    onLoaded: { if (session.boardLoaded) return; session.loadBoard(text(), false) }
    // Nothing to read is a new board; unreadable content is not.
    onLoadFailed: function(error) {
      if (session.boardLoaded) return
      session.loadBoard("", error === FileViewError.FileNotFound)
    }
  }
}
