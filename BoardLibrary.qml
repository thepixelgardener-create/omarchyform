import QtQuick
import Quickshell.Io
import "BoardStore.js" as Store

// The board library: browsing the boards folder, naming boards and folders,
// and the trash. It is told where the library is and which board is open, and
// asks for everything else — opening a board, a word on the board — through
// its signals, so it holds no controller and a test can drive it on its own.
// Browser.qml draws it; Omarchyform.qml wires it to the rest of the board.
Item {
  id: library

  // ---------------------------------------------------------- what it is told
  required property string boardsDir
  required property string trashDir
  required property string trashIndexPath
  // BoardFiles.sh, as a path: every change to the library goes through it.
  required property string helperScript
  // The board that is open. Browsing starts in its folder, and neither it nor
  // a folder holding it can be sent to the trash from under it.
  property string currentBoard: ""
  // Whether the open board can be renamed now: not while two versions of it
  // are outstanding, nor while a save is in flight or has failed.
  property bool boardConflicted: false
  property bool boardSettled: true

  // --------------------------------------------------------- what it asks for
  signal openRequested(string path, bool fresh)
  // The open board was renamed, or a folder it is in was: this is where it is.
  signal currentMoved(string path)
  // A word on the board, for something that finished after the browser had
  // nothing left to say it in.
  signal notice(string message)
  // The browser closed; the keyboard goes back to the board.
  signal closed()
  // A rename is about to ask whether the open board is settled: save it first.
  signal aboutToRename()

  function fileCommand(action, args) {
    return ["bash", library.helperScript, action].concat(args)
  }

  // -------------------------------------------------------------------- state
  property bool showing: false
  property string dir: ""
  property string query: ""
  property int index: 0
  property var entries: []
  property bool searching: false
  // "" when navigating; otherwise the label of the line being typed into.
  property string promptLabel: ""
  property string input: ""
  property string action: ""
  // Armed by the first x, cleared by anything else.
  property string pendingDelete: ""
  // A line of feedback shown in place of the path, cleared by the next key.
  property string message: ""
  // The browser shows the trash instead of the boards while this is on.
  property bool inTrash: false
  property var trashEntries: []
  property bool trashIndexSaving: false
  property bool trashIndexLoading: true
  property bool trashIndexNeedsRead: true
  property string trashIndexError: ""
  readonly property bool busy: mkdirProc.running || moveProc.running || trashProc.running
    || restoreProc.running || purgeProc.running || library.trashIndexSaving || library.trashIndexLoading

  function refreshTrashIndex() {
    if (library.trashIndexSaving || (library.trashIndexError !== "" && !library.trashIndexNeedsRead)) return
    library.trashIndexLoading = true
    library.trashIndexNeedsRead = true
    trashIndexFile.reload()
  }

  function acceptTrashIndex(raw) {
    library.trashIndexLoading = false
    if (library.trashIndexSaving || (library.trashIndexError !== "" && !library.trashIndexNeedsRead)) return
    var parsed = null
    try { parsed = JSON.parse(raw) } catch (e) {}
    var listed = Store.readTrash(raw)
    if (!parsed || (parsed.version !== undefined && parsed.version !== 1) || !Array.isArray(parsed.entries) || listed.length !== parsed.entries.length) {
      library.trashIndexNeedsRead = true
      library.trashIndexError = "trash index is invalid — repair index.json, then ctrl+s to reload"
      return
    }
    library.trashEntries = listed
    library.trashIndexNeedsRead = false
    library.trashIndexError = ""
  }

  function ready() {
    if (library.busy) { library.message = "finishing the previous operation…"; return false }
    if (library.trashIndexError !== "") { library.message = library.trashIndexError; return false }
    return true
  }

  readonly property var rows: library.inTrash
    ? Store.sortedTrash(library.trashEntries)
    : Store.filterEntries(library.entries, library.dir, library.query)

  // ----------------------------------------------------------------- browsing
  function show() {
    library.query = ""
    library.searching = false
    library.promptLabel = ""
    library.input = ""
    library.message = ""
    library.pendingDelete = ""
    library.index = 0
    library.dir = Store.parentOf(library.currentBoard)
    library.inTrash = false
    library.showing = true
    library.refreshTrashIndex()
    library.rescan()
  }

  function hide() {
    library.showing = false
    library.promptLabel = ""
    library.query = ""
    library.searching = false
    library.closed()
  }

  function rescan() { scanProc.running = true }

  function clamp() {
    var n = library.rows.length
    if (n === 0) library.index = 0
    else if (library.index >= n) library.index = n - 1
    else if (library.index < 0) library.index = 0
  }

  function current() {
    var rows = library.rows
    if (library.index < 0 || library.index >= rows.length) return null
    return rows[library.index]
  }

  // Enter descends into a folder or opens a board.
  function enter() {
    // Opening a board or folder does not touch the trash, so a broken trash
    // index must not block it; restoreCurrent() checks the index itself.
    if (library.busy) { library.message = "finishing the previous operation…"; return }
    var e = library.current()
    if (!e) return
    if (library.inTrash) { library.restoreCurrent(); return }
    if (e.dir) {
      library.dir = e.path
      library.query = ""
      library.index = 0
      return
    }
    library.openRequested(e.path, false)
    library.hide()
  }

  function up() {
    if (library.searching) { library.searching = false; library.query = ""; library.index = 0; return }
    if (library.dir === "") return
    var leaving = library.dir
    library.dir = Store.parentOf(leaving)
    library.index = 0
    // Land on the folder we just came out of, the way cd .. leaves you.
    var rows = library.rows
    for (var i = 0; i < rows.length; i++) if (rows[i].path === leaving) library.index = i
  }

  function ask(action, label, initial) {
    library.action = action
    library.promptLabel = label
    library.input = initial || ""
  }

  function cancelPrompt() {
    library.action = ""
    library.promptLabel = ""
    library.input = ""
  }

  function commitPrompt() {
    if (!library.ready()) return
    var name = library.input.trim()
    var action = library.action
    library.promptLabel = ""
    library.input = ""
    library.action = ""
    if (!Store.nameIsValid(name)) { library.message = "use a name without slashes or control characters"; return }

    if (action === "board") {
      var path = Store.uniquePath(library.entries, library.dir, name, false)
      library.createBoard(path)
    } else if (action === "folder") {
      var dir = Store.uniquePath(library.entries, library.dir, name, true)
      mkdirProc.command = library.fileCommand("mkdir", [library.boardsDir, dir])
      mkdirProc.running = true
    } else if (action === "rename" || action === "rename-current") {
      if (library.boardConflicted) {
        library.message = "two versions of this board exist — esc, then ctrl+s to choose"
        return
      }
      library.aboutToRename()
      if (!library.boardSettled) {
        library.message = "finish saving before renaming; try again"
        return
      }
      var e = action === "rename-current" ? {path: library.currentBoard, dir: false} : library.current()
      if (!e) return
      if (name === Store.displayName(e)) { library.hide(); return }
      var target = Store.uniquePath(library.entries, Store.parentOf(e.path), name, e.dir)
      moveProc.command = library.fileCommand("move", [library.boardsDir, e.path, library.boardsDir, target])
      moveProc.renamedFrom = e.path
      moveProc.renamedTo = target
      moveProc.running = true
    }
  }

  // A new board is created by pointing at it and saving: the file appears with
  // an empty board in it, which is also what makes it the open one.
  function createBoard(path) {
    library.openRequested(path, true)
    library.hide()
  }

  // True when this entry is, or contains, the board that is open.
  function holdsOpenBoard(e) {
    if (!e.dir) return e.path === library.currentBoard
    return library.currentBoard.indexOf(e.path + "/") === 0
  }

  function deleteCurrent() {
    if (!library.ready()) return
    var e = library.current()
    if (!e) return

    if (library.inTrash) {
      // Inside the trash there is nowhere further to put something, so this
      // one really does destroy it.
      if (library.pendingDelete !== e.file) {
        library.pendingDelete = e.file
        library.message = "press x again to destroy " + Store.baseName(e.path) + " for good"
        return
      }
      library.pendingDelete = ""
      library.message = ""
      purgeProc.entryFile = e.file
      purgeProc.command = library.fileCommand("purge", [library.trashDir, e.file])
      purgeProc.running = true
      return
    }

    // Refuse to delete the open board, or the folder it lives in.
    if (library.holdsOpenBoard(e)) {
      library.message = "that is the board you have open — switch away first"
      return
    }
    if (library.pendingDelete !== e.path) {
      library.pendingDelete = e.path
      library.message = "press x again to move " + Store.displayName(e)
                            + (e.dir ? "/ and everything in it" : "") + " to the trash"
      return
    }
    library.pendingDelete = ""
    library.message = ""

    var stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss")
    var file = Store.trashFile(library.trashEntries, e.path, stamp)
    trashProc.pending = { file: file, path: e.path, dir: e.dir, at: stamp }
    trashProc.command = library.fileCommand("move", [library.boardsDir, e.path, library.trashDir, file])
    trashProc.running = true
  }

  function restoreCurrent() {
    if (!library.ready()) return
    var e = library.current()
    if (!e || !library.inTrash) return
    restoreProc.entryFile = e.file
    restoreProc.command = library.fileCommand("move", [library.trashDir, e.file, library.boardsDir, e.path])
    restoreProc.running = true
  }

  function toggleTrash() {
    library.inTrash = !library.inTrash
    library.index = 0
    library.query = ""
    library.searching = false
    library.pendingDelete = ""
    library.message = ""
    if (library.inTrash) library.refreshTrashIndex()
  }

  function saveTrashIndex(entries) {
    library.trashEntries = entries
    library.trashIndexSaving = true
    library.trashIndexNeedsRead = false
    library.trashIndexError = ""
    trashIndexFile.setText(Store.writeTrash(entries))
  }

  function key(event) {
    if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
      library.retryTrashIndex()
      event.accepted = true
      return
    }
    var text = event.text

    // Arming a delete lasts exactly until the next keystroke.
    if (text !== "x") {
      library.pendingDelete = ""
      library.message = ""
    }

    // While typing a name, every printable key is input.
    if (library.promptLabel !== "") {
      if (event.key === Qt.Key_Escape) library.cancelPrompt()
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) library.commitPrompt()
      else if (event.key === Qt.Key_Backspace) library.input = library.input.slice(0, -1)
      else if (text && text >= " ") library.input += text
      else return
      event.accepted = true
      return
    }

    // While searching, printable keys extend the query; the arrow keys and
    // Enter still navigate the results.
    if (library.searching && text && text >= " ") {
      library.query += text
      library.index = 0
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (library.inTrash) { library.toggleTrash() }
      else if (library.searching) {
        library.searching = false
        library.query = ""
        library.index = 0
      } else library.hide()
    }
    else if (event.key === Qt.Key_Down || text === "j") { library.index += 1; library.clamp() }
    else if (event.key === Qt.Key_Up || text === "k") { library.index -= 1; library.clamp() }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || text === "l"
             || event.key === Qt.Key_Right) library.enter()
    else if (event.key === Qt.Key_Left || text === "h") library.up()
    else if (event.key === Qt.Key_Backspace) {
      if (library.searching) {
        library.query = library.query.slice(0, -1)
        if (library.query === "") library.searching = false
        library.index = 0
      } else library.up()
    }
    else if (text === "/") { library.searching = true; library.query = ""; library.index = 0 }
    else if (library.inTrash && ["a", "A", "r"].indexOf(text) >= 0) library.message = "enter: restore this item · t: return to boards"
    else if (text === "a") library.ask("board", "new board:", "")
    else if (text === "A") library.ask("folder", "new folder:", "")
    else if (text === "r") {
      var e = library.current()
      if (e) library.ask("rename", "rename to:", Store.displayName(e))
    }
    else if (text === "x") library.deleteCurrent()
    else if (text === "t") library.toggleTrash()
    else if (text === "g") { library.index = 0 }
    else if (text === "G") { library.index = library.rows.length - 1; library.clamp() }
    else return
    event.accepted = true
  }

  function retryTrashIndex() {
    if (library.trashIndexLoading || library.trashIndexSaving || library.trashIndexError === "") return
    if (library.trashIndexNeedsRead) library.refreshTrashIndex()
    else library.saveTrashIndex(library.trashEntries)
  }
  // Everything a closed board forgets: the browser comes back shut, on no
  // prompt, search or half-armed delete.
  function reset() {
    library.showing = false
    library.promptLabel = ""
    library.input = ""
    library.action = ""
    library.query = ""
    library.searching = false
    library.message = ""
    library.pendingDelete = ""
  }


  Process {
    id: scanProc
    command: ["find", library.boardsDir, "-mindepth", "1", "-printf", "%y\\t%P\\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        library.entries = Store.parseListing(text)
        library.clamp()
      }
    }
  }

  Process {
    id: mkdirProc
    onExited: function(code) {
      if (code !== 0) library.message = "could not create that folder"
      library.rescan()
    }
  }

  Process {
    id: moveProc
    property string renamedFrom: ""
    property string renamedTo: ""
    onExited: function (code) {
      // Follow the open board, whether it was renamed itself or sits inside a
      // folder that was.
      if (code === 0) {
        var from = moveProc.renamedFrom
        if (library.currentBoard === from) library.currentMoved(moveProc.renamedTo)
        else if (library.currentBoard.indexOf(from + "/") === 0)
          library.currentMoved(moveProc.renamedTo + library.currentBoard.slice(from.length))
      }
      if (code !== 0) library.message = "could not rename that; destination exists or path is unavailable"
      library.rescan()
    }
  }

  Process {
    id: trashProc
    property var pending: null
    onExited: function (code) {
      if (code === 0 && trashProc.pending) {
        var next = library.trashEntries.slice()
        next.push(trashProc.pending)
        library.saveTrashIndex(next)
        library.notice("moved to the trash · t in the browser to get it back")
      } else if (code !== 0) {
        library.message = "could not move that to the trash"
      }
      trashProc.pending = null
      library.rescan()
    }
  }

  Process {
    id: restoreProc
    property string entryFile: ""
    onExited: function (code) {
      if (code === 0) {
        library.saveTrashIndex(Store.withoutTrash(library.trashEntries, restoreProc.entryFile))
        library.message = "restored"
      } else {
        library.message = "could not restore that; something is in its place"
      }
      restoreProc.entryFile = ""
      library.rescan()
    }
  }

  Process {
    id: purgeProc
    property string entryFile: ""
    onExited: function (code) {
      if (code === 0) library.saveTrashIndex(Store.withoutTrash(library.trashEntries, purgeProc.entryFile))
      else library.message = "could not remove that trash entry"
      purgeProc.entryFile = ""
    }
  }

  FileView {
    id: trashIndexFile
    path: library.trashIndexPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: library.acceptTrashIndex(text())
    onLoadFailed: function(error) {
      library.trashIndexLoading = false
      if (library.trashIndexSaving || !library.trashIndexNeedsRead) return
      if (error === FileViewError.FileNotFound) {
        library.trashEntries = []
        library.trashIndexNeedsRead = false
        library.trashIndexError = ""
      } else library.trashIndexError = "trash index could not be read — ctrl+s to retry"
    }
    onSaved: { library.trashIndexSaving = false; library.trashIndexError = "" }
    onSaveFailed: {
      library.trashIndexSaving = false
      library.trashIndexError = "trash index could not be saved — ctrl+s to retry; keep the board open"
      library.message = library.trashIndexError
    }
  }
}
