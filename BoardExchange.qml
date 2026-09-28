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
  // What else to say about a copy that was saved, or a board that arrived:
  // both are reported by the controller, which owns the status line.
  property string exportNote: ""
  property string createdNote: ""
  readonly property bool dialogOpen: picker.visible
  signal created(string path, bool editFirst)
  // Two answers, not one with a phrase in it. `finished` is something that
  // happened; `failed` is something the person asked for that did not, and the
  // board ranks the two differently because one can wait and the other cannot.
  // Both carry which operation they are about, so a success can take down the
  // failure it recovered from and leave the rest alone. The kinds are
  // Store.FAILURE_KINDS; "" on a `finished` means it recovers nothing.
  signal finished(string message, string kind)
  signal failed(string message, string kind)
  // A board written into the library that is not the one to open: the copy
  // someone keeps when two versions of a board have to survive.
  signal copied(string name)

  // Every way out of a failed operation comes through here. The busy flag is
  // what refuses the next import, so leaving it set after a failure strands
  // importing and exporting for the rest of the session, and a failure nobody
  // is told about looks exactly like nothing having happened.
  function fail(message, kind) {
    busy = false
    error = message
    failed(message, kind)
  }

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

  // Put this text in the library under a name nothing else has, and say what
  // that name turned out to be. The publisher does the same work it does for a
  // new board, so a copy cannot land on top of anything.
  function saveCopy(text, name) {
    if (busy) return false
    busy = true
    error = ""
    baseName = Store.nameIsValid(name) ? name : "copy"
    operation = "copy"
    output.path = ""
    output.path = exchange.ctl.dataDir + "/.copy-" + Date.now() + ".json"
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

  // What a board arriving from outside is allowed to be. A board with its
  // pictures inside it is a few megabytes; anything beyond this is refused
  // before it is read into memory rather than after.
  readonly property int maxImportBytes: 33554432

  function importPath(path) {
    if (busy) return
    error = ""
    createdNote = ""
    busy = true
    measure.source = path
    measure.command = exchange.ctl.fileCommand("filesize", [path])
    measure.running = true
  }

  Process {
    id: measure
    property string source: ""
    stdout: StdioCollector { id: measured; waitForEnd: true }
    onExited: function (code) {
      exchange.busy = false
      var bytes = code === 0 ? parseInt(measured.text, 10) : 0
      if (!isFinite(bytes) || bytes <= 0) { exchange.fail("Could not read that board", "board"); return }
      if (bytes > exchange.maxImportBytes) {
        exchange.fail("That file is " + Math.round(bytes / 1048576) + " MB — too large for a board", "board")
        return
      }
      exchange.readImport(measure.source)
    }
  }

  function readImport(path) {
    // Read it here and now. An asynchronous reload on a view that is not
    // preloaded produced neither loaded nor loadFailed, so the import simply
    // stopped; a chosen file is small enough to read on the spot.
    input.path = ""
    input.path = path
    input.reload()
    input.waitForJob()
    var raw = input.text()
    if (!raw) { exchange.fail("Could not read that board", "board"); return }
    if (!Store.readFile(raw)) { exchange.fail("That file is not a supported board", "board"); return }
    var base = Store.baseName(path).replace(/(\.omarchyform)?\.json$/i, "")
    // A copy saved to share carries its pictures inside it. They have to be
    // written into this machine's own images folder, under names of its
    // choosing, before the board can point at them.
    var carried = Store.sharedImages(raw)
    var names = Object.keys(carried)
    // A picture the file claims but this will not accept — too large, or a
    // name no board would write — means the board cannot arrive whole. It is
    // refused rather than opened with holes in it, and the file it came from
    // is untouched, so there is something left to try again with.
    var declared = Store.declaredImageCount(raw)
    if (declared !== names.length) {
      exchange.fail("That board carries " + (declared - names.length) + " of " + declared
                    + " pictures this cannot accept; nothing was imported", "board")
      return
    }
    if (names.length === 0) { exchange.stage(raw, base, false); return }
    busy = true
    exchange.sharing = { raw: raw, base: base, images: carried, names: names, at: 0, landed: {} }
    exchange.nextSharedImage()
  }

  // One picture at a time, and through a staged file rather than an argument:
  // an argument list is measured in kilobytes and a screenshot is not.
  property var sharing: null

  function nextSharedImage() {
    var job = exchange.sharing
    if (job.at >= job.names.length) {
      exchange.sharing = null
      exchange.createdNote = ""
      // stage() takes the flag straight back; it is cleared so its own guard,
      // which is there to refuse a second import, does not refuse this one.
      exchange.busy = false
      exchange.stage(Store.withSharedImages(job.raw, job.landed), job.base, false)
      return
    }
    bytes.path = ""
    bytes.path = exchange.ctl.dataDir + "/.shared-" + Date.now() + "-" + job.at + ".b64"
    var body = job.images[job.names[job.at]]
    Qt.callLater(function () { bytes.setText(body) })
  }

  function sharedImageDone(name) {
    var job = exchange.sharing
    // A picture that did not arrive is not something to paper over: the board
    // would open with an item pointing at nothing, and nothing would say why.
    // The pictures that did land stay in the pictures folder, unreferenced, in
    // the same way a picture whose item was deleted does.
    if (name === "") {
      exchange.sharing = null
      exchange.fail("A picture in that board could not be read; nothing was imported", "board")
      return
    }
    job.landed[job.names[job.at]] = name
    job.at += 1
    exchange.nextSharedImage()
  }

  FileView {
    id: bytes
    preload: false
    atomicWrites: true
    printErrors: false
    onSaved: {
      unbundle.command = exchange.ctl.fileCommand("unbundleimage",
        [exchange.ctl.imagesDir, bytes.path, "shared-" + Date.now() + "-" + exchange.sharing.at])
      unbundle.running = true
    }
    onSaveFailed: exchange.sharedImageDone("")
  }

  Process {
    id: unbundle
    stdout: StdioCollector { id: unbundled; waitForEnd: true }
    onExited: function (code) {
      exchange.sharedImageDone(code === 0 && unbundled.text ? unbundled.text : "")
    }
  }

  // Generous for a board and small enough that the encoded copy of it stays
  // something a process can hand over in one piece.
  readonly property int bundleBudget: 16777216

  // An export is a picture of one board at one moment, and collecting its
  // pictures takes long enough for that moment to pass: a board switch, a
  // deleted picture, a note typed into. So everything the export will ever
  // need is taken at the start and carried through every step — the board as
  // text, the pictures it names, which board it was and where it is going.
  // Nothing after this reads the live models.
  property var snapshot: null
  property int exportSeq: 0

  // Set by the command that asks for a copy without pictures, and cleared by
  // the one that asks for an ordinary copy: which of the two was chosen is
  // decided before the file dialog, not after it.
  property bool omitPictures: false

  function exportJson(path) {
    if (busy || !exchange.ctl.boardLoaded) return
    busy = true
    operation = "export"
    destination = path
    exportNote = exchange.omitPictures ? " · without its pictures" : ""
    exchange.exportSeq += 1
    exchange.snapshot = {
      id: exchange.exportSeq,
      board: exchange.ctl.currentBoard,
      destination: path,
      text: Store.writeFile(exchange.ctl.items, exchange.ctl.links, exchange.ctl.nextId),
      names: Store.imageNames(exchange.ctl.items)
    }
    if (exchange.omitPictures || exchange.snapshot.names.length === 0) {
      exchange.stageExport(exchange.snapshot, {})
      return
    }
    collect.forExport = exchange.snapshot.id
    collect.command = exchange.ctl.fileCommand("bundleimages",
      [exchange.ctl.imagesDir, String(exchange.bundleBudget)].concat(exchange.snapshot.names))
    collect.running = true
  }

  function stageExport(taken, images) {
    output.path = ""
    output.path = exchange.ctl.dataDir + "/.export-" + Date.now() + ".json"
    var body = Store.withEmbeddedImages(taken.text, images)
    Qt.callLater(function () { output.setText(body) })
  }

  Process {
    id: collect
    // Which export asked. An answer for an export that is no longer the one
    // running belongs to nothing and is dropped rather than published.
    property int forExport: 0
    stdout: StdioCollector { id: collected; waitForEnd: true }
    onExited: function (code) {
      if (!exchange.snapshot || collect.forExport !== exchange.snapshot.id) return
      if (code !== 0) { exchange.fail("Could not read this board's pictures", "board"); return }
      var images = {}
      var missing = 0
      var oversize = -1
      var lines = collected.text.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var at = lines[i].indexOf("\t")
        if (at < 0) continue
        var name = lines[i].slice(0, at)
        var body = lines[i].slice(at + 1)
        if (name === "!toolarge") { oversize = parseInt(body, 10); break }
        if (body === "!missing") { missing += 1; continue }
        images[name] = body
      }
      // A copy that is meant to travel is no good without the pictures it
      // names, so neither of these publishes anything. Saving a copy without
      // them is a separate thing to ask for, by that name.
      if (oversize >= 0) {
        exchange.fail("This board's pictures come to " + Math.round(oversize / 1048576)
                      + " MB, more than a copy can carry ("
                      + Math.round(exchange.bundleBudget / 1048576) + " MB)"
                      + " · save a copy without its pictures instead", "board")
        return
      }
      if (missing > 0) {
        exchange.fail(missing + (missing === 1 ? " picture this board names is" : " pictures this board names are")
                      + " missing from your library · save a copy without its pictures instead", "board")
        return
      }
      exchange.exportNote = ", with its pictures"
      exchange.stageExport(exchange.snapshot, images)
    }
  }

  function choose(action) {
    if (busy) return
    exchange.ctl.stopEditing()
    exchange.omitPictures = action === "plain"
    if (action === "plain") action = "json"
    operation = action
    picker.title = action === "import" ? "Import a board" : action === "png" ? "Export board as PNG" : "Save an editable copy"
    picker.fileMode = action === "import" ? FileDialog.OpenFile : FileDialog.SaveFile
    // A copy saved to share is named .omarchyform.json, which is what makes a
    // file manager recognise it: a board is JSON, and a glob on .json alone
    // would hand every JSON file on the machine to a note-taking program, so
    // the double extension is the only honest way to claim one. Import still
    // accepts any .json, because a board from before this is still a board.
    picker.nameFilters = action === "png" ? ["PNG image (*.png)"]
      : action === "import" ? ["Omarchyform board (*.omarchyform.json *.json)"]
      : ["Omarchyform board (*.omarchyform.json)"]
    picker.defaultSuffix = action === "png" ? "png" : action === "import" ? "json" : "omarchyform.json"
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
    // Staging writes into the app's own data folder, so this is a full disk or
    // a permission problem rather than anything the user chose. It still has to
    // end the operation: without this the board never arrives and nothing else
    // can be imported afterwards.
    onSaveFailed: function (reason) {
      exchange.fail((exchange.operation === "export" ? "Could not prepare the copy: " : "Could not prepare that board: ")
                    + FileViewError.toString(reason), "board")
    }
    onSaved: {
      if (exchange.operation === "publish" || exchange.operation === "copy") {
        publish.command = exchange.ctl.fileCommand("publish", [exchange.ctl.boardsDir, exchange.baseName, output.path])
        publish.running = true
      } else {
        publish.command = exchange.ctl.fileCommand("export",
          [output.path, exchange.snapshot.destination, exchange.ctl.dataDir])
        publish.running = true
      }
    }
  }
  Process {
    id: publish
    stdout: StdioCollector { id: published; waitForEnd: true }
    onExited: function(code) {
      exchange.busy = false
      if (code !== 0) { exchange.fail("Could not save there; choose a location outside the app data folder", "board"); return }
      if (exchange.operation === "copy") exchange.copied(published.text)
      else if (exchange.operation === "publish") exchange.created(published.text, exchange.firstNote)
      else exchange.finished("Editable copy saved" + exchange.exportNote, "board")
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
    if (text === "") { exchange.finished("nothing written on it to copy", ""); return }
    copyProc.command = exchange.ctl.fileCommand("clipcopy", [text])
    copyProc.copied = indices.length
    copyProc.running = true
  }

  Process {
    id: copyProc
    property int copied: 0
    onExited: function (code) {
      if (code !== 0) exchange.failed("Could not reach the clipboard", "clipboard")
      else exchange.finished(copyProc.copied === 1 ? "Copied" : "Copied " + copyProc.copied + " items", "clipboard")
    }
  }

  Process {
    id: copyImageProc
    onExited: function (code) {
      if (code === 0) exchange.finished("Picture copied", "clipboard")
      else exchange.failed("Could not copy that picture", "clipboard")
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
      // Checking the board before starting the copy is not enough: the switch
      // can happen while it runs. A picture on the wrong board is worse than
      // one that has to be dropped again, so the copy is abandoned in the
      // pictures folder rather than placed anywhere.
      if (code === 0 && importedName.text && done.board !== exchange.ctl.currentBoard)
        exchange.failed("Board changed; drop that picture again", "picture")
      else if (code === 0 && importedName.text) exchange.ctl.imageDropped(importedName.text, done.x, done.y)
      // 5 is the helper's way of saying the file is too big to put on a board,
      // which is worth saying differently from "that is not a picture".
      else if (code === 5) exchange.failed("That file is too large to put on a board", "picture")
      // 6 needs two pictures to arrive in the same millisecond, but saying the
      // wrong thing about it would be worse than the line it costs.
      else if (code === 6) exchange.failed("A picture of that name is already there", "picture")
      else exchange.failed("That is not an image this can read", "picture")
      exchange.nextDrop()
    }
  }

  Process {
    id: imageGrab
    stdout: StdioCollector { id: grabbed; waitForEnd: true }
    onExited: function (code) {
      if (exchange.pasteBoard !== exchange.ctl.currentBoard) { exchange.failed("Board changed; paste again", "clipboard"); return }
      // 4 is the script's way of saying the clipboard holds no picture, which
      // is not a failure: text is the other thing it could be holding.
      if (code === 4) { clipboard.running = true; return }
      if (code === 6) { exchange.failed("A picture of that name is already there", "clipboard"); return }
      if (code !== 0 || !grabbed.text) { exchange.failed("Could not read the clipboard image", "clipboard"); return }
      exchange.ctl.imagePasted(grabbed.text)
    }
  }
  Process {
    id: clipboard
    command: ["timeout", "3", "wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector { id: pasted; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { exchange.failed("Clipboard has no available text", "clipboard"); return }
      if (exchange.pasteBoard !== exchange.ctl.currentBoard) { exchange.failed("Board changed; paste again", "clipboard"); return }
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
