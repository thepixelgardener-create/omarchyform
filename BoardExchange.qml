import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import Quickshell.Io
import "BoardStore.js" as Store

// Import/export snapshots are independent of the open board's save pipeline.
Item {
  id: exchange
  objectName: "board-exchange"
  required property var ctl
  property bool busy: false
  property bool firstNote: false
  property string baseName: ""
  property string operation: ""
  property string destination: ""
  property string error: ""
  property string pasteBoard: ""
  readonly property bool dialogOpen: picker.visible
  signal created(string path, bool editFirst)
  signal finished(string message)


  function stage(text, name, editFirst) {
    if (busy) return false
    busy = true
    error = ""
    firstNote = editFirst
    baseName = Store.nameIsValid(name) ? name : "imported"
    operation = "publish"
    // Cleared and deferred: writing in the same turn as the path assignment
    // goes to the path the view still holds, and onSaved never arrives.
    output.path = ""
    output.path = exchange.ctl.dataDir + "/.import-" + Date.now() + ".json"
    var body = text
    Qt.callLater(function () { output.setText(body) })
    return true
  }

  function newBoard() {
    var text = JSON.stringify({version: 4, nextId: 2, items: [
      {id: 1, kind: "note", x: -90, y: -70, w: 240, h: 160,
       text: "", tint: "foreground", pinned: false}], links: []}) + "\n"
    return stage(text, "untitled", true)
  }

  function importPath(path) {
    if (busy) return
    error = ""
    // Read it here and now. An asynchronous reload on a view that is not
    // preloaded produced neither loaded nor loadFailed, so the import simply
    // stopped; a chosen file is small enough to read on the spot.
    input.path = ""
    input.path = path
    input.reload()
    input.waitForJob()
    var raw = input.text()
    if (!raw) { exchange.fail("Could not read that board"); return }
    if (!Store.readFile(raw)) { exchange.fail("That file is not a supported board"); return }
    exchange.stage(raw, Store.baseName(path).replace(/\.json$/i, ""), false)
  }

  function exportJson(path) {
    if (busy || !exchange.ctl.boardLoaded) return
    busy = true
    operation = "export"
    destination = path
    output.path = ""
    output.path = exchange.ctl.dataDir + "/.export-" + Date.now() + ".json"
    var body = Store.writeFile(exchange.ctl.items, exchange.ctl.links, exchange.ctl.nextId)
    Qt.callLater(function () { output.setText(body) })
  }

  function choose(action) {
    if (busy) return
    exchange.ctl.stopEditing()
    operation = action
    picker.title = action === "import" ? "Import a board" : action === "png" ? "Export board as PNG" : "Save an editable copy"
    picker.fileMode = action === "import" ? FileDialog.OpenFile : FileDialog.SaveFile
    picker.nameFilters = action === "png" ? ["PNG image (*.png)"] : ["Omarchyform board (*.json)"]
    picker.defaultSuffix = action === "png" ? "png" : "json"
    picker.open()
  }

  // One paste, two possible clipboards. The picture is asked for first: if a
  // copy carries both an image and its text fallback, the image is the thing
  // that was copied.
  function paste() {
    if (clipboard.running || imageGrab.running || !exchange.ctl.canEdit) return
    pasteBoard = exchange.ctl.currentBoard
    imageGrab.command = exchange.ctl.fileCommand("clipimage", [exchange.ctl.imagesDir, "paste-" + Date.now()])
    imageGrab.running = true
  }

  FileView {
    id: input
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  FileView {
    id: output
    preload: false
    atomicWrites: true
    printErrors: false
    onSaved: {
      if (exchange.operation === "publish") {
        publish.command = exchange.ctl.fileCommand("publish", [exchange.ctl.boardsDir, exchange.baseName, output.path])
        publish.running = true
      } else {
        publish.command = exchange.ctl.fileCommand("export", [output.path, exchange.destination, exchange.ctl.dataDir])
        publish.running = true
      }
    }
  }
  Process {
    id: publish
    stdout: StdioCollector { id: published; waitForEnd: true }
    onExited: function(code) {
      exchange.busy = false
      if (code !== 0) { exchange.fail("Could not save there; choose a location outside the app data folder"); return }
      if (exchange.operation === "publish") exchange.created(published.text, exchange.firstNote)
      else exchange.finished("Editable copy saved")
    }
  }
  // Copying out. One picture on its own goes as the picture, so it can be
  // pasted into anything that takes an image; anything else goes as text,
  // because that is what the rest of an item is.
  function copyItems(indices) {
    if (copyProc.running || copyImageProc.running) return
    if (indices.length === 1) {
      var only = exchange.ctl.items.get(indices[0])
      if (only.kind === "image" && only.isrc !== "") {
        copyImageProc.command = exchange.ctl.fileCommand("clipcopyimage",
          [exchange.ctl.imagesDir, only.isrc])
        copyImageProc.running = true
        return
      }
    }
    var text = Store.copyText(exchange.ctl.items, indices)
    if (text === "") { exchange.finished("nothing written on it to copy"); return }
    copyProc.command = exchange.ctl.fileCommand("clipcopy", [text])
    copyProc.copied = indices.length
    copyProc.running = true
  }

  Process {
    id: copyProc
    property int copied: 0
    onExited: function (code) {
      if (code !== 0) exchange.finished("Could not reach the clipboard")
      else exchange.finished(copyProc.copied === 1 ? "Copied" : "Copied " + copyProc.copied + " items")
    }
  }

  Process {
    id: copyImageProc
    onExited: function (code) {
      exchange.finished(code === 0 ? "Picture copied" : "Could not copy that picture")
    }
  }

  // Dropped files are copied one at a time: a Process is a single slot, and a
  // drop of five screenshots should not race itself. Each entry remembers the
  // board it was meant for, so a switch part-way through does not scatter
  // pictures onto the wrong one.
  property var dropQueue: []
  property int dropSeq: 0

  function importDropped(entries) {
    var queued = exchange.dropQueue.slice()
    for (var i = 0; i < entries.length; i++)
      queued.push({ path: entries[i].path, x: entries[i].x, y: entries[i].y,
                    board: exchange.ctl.currentBoard })
    exchange.dropQueue = queued
    if (!imageImport.running) exchange.nextDrop()
  }

  function nextDrop() {
    if (exchange.dropQueue.length === 0) return
    var next = exchange.dropQueue[0]
    if (next.board !== exchange.ctl.currentBoard) {
      exchange.dropQueue = exchange.dropQueue.slice(1)
      exchange.nextDrop()
      return
    }
    exchange.dropSeq += 1
    imageImport.command = exchange.ctl.fileCommand("importimage",
      [exchange.ctl.imagesDir, "drop-" + Date.now() + "-" + exchange.dropSeq, next.path])
    imageImport.running = true
  }

  Process {
    id: imageImport
    stdout: StdioCollector { id: importedName; waitForEnd: true }
    onExited: function (code) {
      var done = exchange.dropQueue[0]
      exchange.dropQueue = exchange.dropQueue.slice(1)
      if (code === 0 && importedName.text) exchange.ctl.imageDropped(importedName.text, done.x, done.y)
      // 5 is the helper's way of saying the file is too big to put on a board,
      // which is worth saying differently from "that is not a picture".
      else if (code === 5) exchange.finished("That file is too large to put on a board")
      else exchange.finished("That is not an image this can read")
      exchange.nextDrop()
    }
  }

  Process {
    id: imageGrab
    stdout: StdioCollector { id: grabbed; waitForEnd: true }
    onExited: function (code) {
      if (exchange.pasteBoard !== exchange.ctl.currentBoard) { exchange.finished("Board changed; paste again"); return }
      // 4 is the script's way of saying the clipboard holds no picture, which
      // is not a failure: text is the other thing it could be holding.
      if (code === 4) { clipboard.running = true; return }
      if (code !== 0 || !grabbed.text) { exchange.finished("Could not read the clipboard image"); return }
      exchange.ctl.imagePasted(grabbed.text)
    }
  }
  Process {
    id: clipboard
    command: ["timeout", "3", "wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector { id: pasted; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { exchange.finished("Clipboard has no available text"); return }
      if (exchange.pasteBoard !== exchange.ctl.currentBoard) { exchange.finished("Board changed; paste again"); return }
      exchange.ctl.pasteText(pasted.text)
    }
  }
  FileDialog {
    id: picker
    parentWindow: exchange.ctl.activeBoard ? exchange.ctl.activeBoard.Window.window : null
    onAccepted: {
      var path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
      if (exchange.operation === "import") exchange.importPath(path)
      else if (exchange.operation === "png") exchange.ctl.exportPng(path)
      else exchange.exportJson(path)
      exchange.ctl.focusKeys()
    }
    onRejected: exchange.ctl.focusKeys()
  }
}
