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
  // Why a damaged board is read-only, when it is not simply unreadable.
  property string damageReason: ""
  property string saveError: ""
  property string lastSavedText: ""
  property int savingCount: 0
  property int lastSavedCount: -1
  property var pendingBoard: null
  property bool createWhenLoaded: false
  // Set when a board is opened, so its first load frames the view; see loadBoard.
  // True to begin with: the board a session starts on is loaded by the file
  // watcher when the shell starts, not through openBoard, and it is opened
  // all the same.
  property bool frameWhenLoaded: true
  // A newer version of the open board is on disk and the screen has changes of
  // its own. Autosave stops while this is set and nothing clears it but a
  // decision: leaving the board, closing, renaming and the save timer all have
  // to leave both versions intact, because none of them is someone choosing.
  property bool conflict: false
  // Which resolution is in flight, so a failed one can put the conflict back
  // rather than losing the edits it was trying to keep.
  property string resolving: ""
  // The revision this session believes is on disk: what the last write
  // produced, or what checking the path before opening it reported. A write
  // that does not still find this refuses rather than replacing it.
  property string revision: ""
  property bool forceNextSave: false
  readonly property bool diskReading: diskRead.running
  readonly property bool canEdit: boardLoaded && !damaged && pendingBoard === null && !diskReading
  readonly property bool busy: persistence.busy || diskReading

  // Typing is debounced; structural edits call save() directly.
  function scheduleSave() {
    if (!session.boardLoaded) return
    saveTimer.restart()
  }

  // Routine flushing: write what is waiting, now rather than in a moment.
  // It does not resolve a conflict. Leaving a board, closing one and renaming
  // all come through here, and none of them is a person choosing which version
  // of a board to keep — so all of them leave both versions where they are.
  function flushSave() {
    if (saveTimer.running) saveTimer.stop()
    session.save()
  }

  function openBoard(path, fresh) {
    if (!Store.safeRelative(path) || session.diskReading) return
    if (path === session.ctl.currentBoard && !fresh) return
    // Leaving is not a decision. Both versions of this board still exist, and
    // walking away from it would drop the one that is only on screen — so the
    // switch waits for someone to say which one to keep.
    if (session.conflict) {
      session.ctl.flash("Two versions of this board exist · ctrl+s to choose which to keep")
      session.ctl.decideConflict()
      return
    }
    session.flushSave()
    // A slow write only delays the switch; it runs once the write completes.
    // failedSave() drops the queued switch if the write fails instead.
    if (persistence.busy) {
      session.pendingBoard = { path: path, fresh: fresh === true }
      return
    }
    if (session.saveError !== "") return
    session.createWhenLoaded = fresh === true
    session.clearConflict()
    session.resolving = ""
    session.forceNextSave = false
    session.revision = ""
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
    // Again once it has loaded: the view frames what is on the board, and until
    // then the model still holds the one being left.
    session.frameWhenLoaded = true
    session.ctl.writeState()
  }

  function save(allowEmpty) {
    if (!session.boardLoaded || session.diskReading) return
    // Something else wrote this board and the screen disagrees with it. Waiting
    // is the only safe answer: a debounced keystroke must not be what decides
    // whose version survives.
    if (session.conflict) return
    if (session.ctl.items.count === 0 && session.lastSavedCount > 0 && allowEmpty !== true) return
    if (persistence.busy) return // Completion serializes the latest model again.
    var text = Store.writeFile(session.ctl.items, session.ctl.links, session.ctl.nextId)
    session.saveError = ""
    if (text === session.lastSavedText && !session.forceNextSave) return
    // Remember what this write contains, so completing it does not have to
    // parse the whole board back again just to count the items.
    session.savingCount = session.ctl.items.count
    persistence.save(session.ctl.boardPath, text,
                     session.ctl.backupPathFor(session.ctl.currentBoard),
                     session.ctl.boardsDir, session.ctl.backupsDir,
                     session.ctl.lockPathFor(session.ctl.currentBoard),
                     session.forceNextSave ? "-" : session.revision)
    session.forceNextSave = false
  }

  function savedBoard(path, text, revision) {
    session.revision = revision
    if (session.resolving === "replace") session.clearConflict()
    session.resolving = ""
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
    // A resolution that failed is not a resolution. The edits are still on
    // screen and the other version is still on disk, so the choice stands.
    if (session.resolving === "replace") {
      session.conflict = true
      session.resolving = ""
    }
  }

  // The write was refused because the file is no longer the revision this
  // session last saw. Nothing was written and the text is still in hand, so
  // the only question is whether what is there now is really someone else's.
  function staleSave(path, revision) {
    session.revision = revision
    if (path !== session.ctl.boardPath) return
    var raw = session.readDisk()
    var mine = Store.writeFile(session.ctl.items, session.ctl.links, session.ctl.nextId)
    session.resolving = ""
    // Not a version this session knows about: someone else wrote it, and only
    // a person can say which of the two survives.
    if (raw !== session.lastSavedText && raw !== persistence.contents && raw !== mine) {
      session.raiseConflict()
      return
    }
    // Ours after all — a revision read before the file had settled, or a write
    // recorded late. The baseline moves to what is actually there, and
    // anything still unsaved is written again against the revision it has.
    var data = Store.readFile(raw)
    session.lastSavedText = raw
    session.lastSavedCount = data ? data.items.length : 0
    session.save(true)
  }

  // Nothing of the disk version is kept: whichever way out is chosen reads the
  // file again, with the revision that goes with what it reads.
  function raiseConflict() {
    // A refused switch is cancelled; resolving stays on the current board.
    session.pendingBoard = null
    session.conflict = true
    session.ctl.flash("Board changed on disk · ctrl+s to choose which version to keep")
  }

  function clearConflict() {
    session.conflict = false
  }

  // The three ways out. Each one leaves the edits on screen until the thing it
  // chose has actually happened.
  function useDisk() {
    if (!session.conflict) return
    session.requestDisk(true)
  }

  function replaceDisk() {
    if (!session.conflict || !session.boardLoaded || persistence.busy || session.diskReading) return
    session.resolving = "replace"
    session.conflict = false
    session.forceNextSave = true
    session.save(true)
  }

  // Called once a copy of the local edits has actually been written. The board
  // then takes the version from disk, so both survive and neither is guessed.
  function keptAsCopy(name) {
    session.conflict = true
    session.useDisk()
    session.ctl.flash("Your version was saved as " + name)
  }

  // The helper reads bytes and their revision under the same lock as commits.
  // Keep the originating board and local text with the request; a late answer
  // must never replace a different board or edits made after the read began.
  function requestDisk(resolve) {
    if (session.diskReading || persistence.busy) return
    diskRead.board = session.ctl.currentBoard
    diskRead.localText = Store.writeFile(session.ctl.items, session.ctl.links, session.ctl.nextId)
    diskRead.resolve = resolve
    diskRead.command = session.ctl.fileCommand("snapshot",
      [session.ctl.boardPath, session.ctl.lockPathFor(session.ctl.currentBoard), session.ctl.boardsDir])
    diskRead.running = true
  }

  function acceptDisk(board, localText, resolve, result) {
    if (board !== session.ctl.currentBoard) return
    var split = result.indexOf("\n")
    var raw = split >= 0 ? result.slice(split + 1) : ""
    if (split < 1 || !Store.readFile(raw)) {
      session.diskReadFailed(board)
      return
    }
    var mine = Store.writeFile(session.ctl.items, session.ctl.links, session.ctl.nextId)
    if (mine !== localText || (!resolve && (session.conflict || mine !== session.lastSavedText))) {
      session.raiseConflict()
      return
    }
    session.pendingBoard = null
    session.revision = result.slice(0, split)
    session.clearConflict()
    session.loadBoard(raw, false)
    session.ctl.flash(resolve ? "Kept the version from disk" : "Board changed on disk; reloaded")
  }

  function diskReadFailed(board) {
    if (board !== session.ctl.currentBoard) return
    session.pendingBoard = null
    session.saveError = "Could not read the disk version; local edits kept — ctrl+s to retry"
    session.ctl.flash(session.saveError)
  }

  Process {
    id: diskRead
    property string board: ""
    property string localText: ""
    property bool resolve: false
    stdout: StdioCollector { id: diskContents; waitForEnd: true }
    onExited: function (code) {
      if (code !== 0) session.diskReadFailed(diskRead.board)
      else session.acceptDisk(diskRead.board, diskRead.localText, diskRead.resolve, diskContents.text)
    }
  }

  // Only a confirmed missing file may become a new, writable empty board.
  function loadBoard(raw, missing) {
    var data = Store.readFile(raw)
    session.ctl.items.clear()
    session.ctl.links.clear()
    session.damaged = !data && !missing
    session.damageReason = ""
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
    // Only for a board being opened. A reload because the file changed under an
    // open board keeps the view where it is.
    if (session.frameWhenLoaded) {
      session.frameWhenLoaded = false
      session.ctl.resetView()
    }
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

  // The board is a file in a folder people are invited to hand-edit, and the
  // command line writes boards too. Without watching it, the two ends overwrite
  // each other in silence: the shell keeps its own copy in memory and the next
  // keystroke saves it over whatever arrived.
  function readDisk() {
    reader.path = ""
    reader.path = session.ctl.boardPath
    reader.reload()
    reader.waitForJob()
    return reader.text()
  }

  function externalWrite() {
    if (!session.boardLoaded || session.pendingBoard !== null || session.conflict) return
    var raw = session.readDisk()
    if (raw === "") return
    var mine = Store.writeFile(session.ctl.items, session.ctl.links, session.ctl.nextId)
    // Our own writes arrive here as well, and the content is what tells them
    // apart. Comparing text rather than watching the writer means a
    // notification that arrives late is still recognised as ours.
    if (raw === mine || raw === session.lastSavedText || raw === persistence.contents) return
    if (mine === session.lastSavedText) {
      // Nothing unsaved on screen, so the newer version simply wins: a board
      // built by the command line appears instead of being overwritten.
      session.requestDisk(false)
      return
    }
    session.raiseConflict()
  }

  FileView {
    id: reader
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  BoardPersistence {
    id: persistence
    onCompleted: function(path, text, revision) { session.savedBoard(path, text, revision) }
    onFailed: function(message) { session.failedSave(message) }
    onStale: function(path, revision) { session.staleSave(path, revision) }
    onDelayed: function(message) { session.saveError = message }
  }

  Timer {
    id: saveTimer
    interval: session.ctl.autosaveMs
    repeat: false
    onTriggered: session.save()
  }

  // Saving refuses a path that goes through a symlink inside the boards
  // folder. Loading applies the same rule first: otherwise such a board opens
  // and edits normally, and nothing typed into it can ever reach disk.
  readonly property string wantedPath: session.ctl.stateReady ? session.ctl.boardPath : ""
  property string checkedPath: ""
  onWantedPathChanged: { session.checkedPath = ""; session.checkPath() }

  function checkPath() {
    if (session.wantedPath === "" || pathCheck.running) return
    pathCheck.checking = session.wantedPath
    pathCheck.command = session.ctl.fileCommand("check", [session.ctl.boardsDir, session.ctl.currentBoard])
    pathCheck.running = true
  }

  function refusePath() {
    session.loadBoard("", false)
    session.damageReason = "goes through a symlink"
  }

  Process {
    id: pathCheck
    property string checking: ""
    // Checking the path also reports what revision is there, so the first
    // write after opening knows what it is replacing.
    stdout: StdioCollector { id: checkedRevision; waitForEnd: true }
    onExited: function(code) {
      // The board changed while this one was being checked: check the new one.
      if (pathCheck.checking !== session.wantedPath) { session.checkPath(); return }
      if (code === 0) {
        session.revision = checkedRevision.text
        session.checkedPath = pathCheck.checking
      }
      else if (!session.boardLoaded) session.refusePath()
    }
  }

  FileView {
    id: boardFile
    // Empty until the state file has said which board to open, and until that
    // board's path has been checked: loading too early would mark an empty
    // board as loaded, and the next save would write that emptiness over a
    // real file.
    path: session.wantedPath !== "" && session.checkedPath === session.wantedPath ? session.wantedPath : ""
    watchChanges: true
    onFileChanged: session.externalWrite()
    atomicWrites: true
    printErrors: false
    // Loading and writing use separate FileViews. Ignore duplicate load
    // notifications once this board has been initialized.
    onLoaded: { if (session.boardLoaded || path === "") return; session.loadBoard(text(), false) }
    // Nothing to read is a new board; unreadable content is not.
    onLoadFailed: function(error) {
      if (session.boardLoaded || path === "") return
      session.loadBoard("", error === FileViewError.FileNotFound)
    }
  }
}
