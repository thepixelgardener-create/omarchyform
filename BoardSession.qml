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
  // A newer version of the open board is on disk and the screen has changes of
  // its own. Autosave stops while this is set and nothing clears it but a
  // decision: leaving the board, closing, renaming and the save timer all have
  // to leave both versions intact, because none of them is someone choosing.
  property bool conflict: false
  // What is on disk, kept so the choice can be acted on without reading again
  // and finding a third version.
  property string conflictText: ""
  property string conflictBoard: ""
  // Which resolution is in flight, so a failed one can put the conflict back
  // rather than losing the edits it was trying to keep.
  property string resolving: ""
  // The revision this session believes is on disk: what the last write
  // produced, or what checking the path before opening it reported. A write
  // that does not still find this refuses rather than replacing it.
  property string revision: ""
  property bool forceNextSave: false
  readonly property bool canEdit: boardLoaded && !damaged && pendingBoard === null
  readonly property bool busy: persistence.busy

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
    if (!Store.safeRelative(path)) return
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
    session.ctl.writeState()
  }

  function save(allowEmpty) {
    if (!session.boardLoaded) return
    // Something else wrote this board and the screen disagrees with it. Waiting
    // is the only safe answer: a debounced keystroke must not be what decides
    // whose version survives.
    if (session.conflict) return
    if (session.ctl.items.count === 0 && session.lastSavedCount > 0 && allowEmpty !== true) return
    if (persistence.busy) return // Completion serializes the latest model again.
    var text = Store.writeFile(session.ctl.items, session.ctl.links, session.ctl.nextId)
    session.saveError = ""
    if (text === session.lastSavedText) return
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
      session.raiseConflict(raw)
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

  function raiseConflict(diskText) {
    session.conflict = true
    session.conflictText = diskText
    session.conflictBoard = session.ctl.currentBoard
    session.ctl.flash("Board changed on disk · ctrl+s to choose which version to keep")
  }

  function clearConflict() {
    session.conflict = false
    session.conflictText = ""
    session.conflictBoard = ""
  }

  // The three ways out. Each one leaves the edits on screen until the thing it
  // chose has actually happened.
  function useDisk() {
    if (!session.conflict) return
    var text = session.conflictText
    session.clearConflict()
    session.loadBoard(text, false)
    session.refreshRevision()
    session.ctl.flash("Kept the version from disk")
  }

  function replaceDisk() {
    if (!session.conflict) return
    session.resolving = "replace"
    session.conflict = false
    session.forceNextSave = true
    session.save(true)
    // Nothing to write means the two agree after all, which is a resolution.
    if (!persistence.busy && session.resolving === "replace") {
      session.resolving = ""
      session.forceNextSave = false
    }
    session.conflictText = ""
    session.conflictBoard = ""
  }

  // Called once a copy of the local edits has actually been written. The board
  // then takes the version from disk, so both survive and neither is guessed.
  function keptAsCopy(name) {
    session.conflict = true
    session.useDisk()
    session.ctl.flash("Your version was saved as " + name)
  }

  function refreshRevision() {
    revisionProc.command = ["bash", decodeURIComponent(Qt.resolvedUrl("BoardFiles.sh").toString().replace(/^file:\/\//, "")),
      "revision", session.ctl.boardPath]
    revisionProc.running = true
  }

  Process {
    id: revisionProc
    stdout: StdioCollector { id: revisionOut; waitForEnd: true }
    onExited: function (code) { if (code === 0) session.revision = revisionOut.text }
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
      session.loadBoard(raw, false)
      session.refreshRevision()
      session.ctl.flash("Board changed on disk; reloaded")
      return
    }
    session.raiseConflict(raw)
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
    pathCheck.command = ["bash", decodeURIComponent(Qt.resolvedUrl("BoardFiles.sh").toString().replace(/^file:\/\//, "")),
      "check", session.ctl.boardsDir, session.ctl.currentBoard]
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
