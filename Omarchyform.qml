pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import "BoardStore.js" as Store

// Controller and plugin entry point. Owns the state, the file, and the two
// surfaces the board can live on. The drawing lives in Board.qml and Node.qml,
// the pure logic in BoardStore.js.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // --------------------------------------------------------------- appearance
  // What the board looks like is in Theme.qml: one object to pass around and
  // one object for a test to hold, rather than twenty properties here that a
  // stub has to guess at.
  Theme { id: themeTokens }
  readonly property Theme theme: themeTokens

  readonly property int minItemSize: Store.MIN_SIZE

  // The step is what the eye sees, so it is divided by the zoom: otherwise one
  // press moves an eighth of the distance when zoomed out and four times it
  // when zoomed in.
  readonly property real worldStep: root.step / root.zoom

  // -------------------------------------------------------------------- state
  property alias items: itemModel
  property alias links: linkModel

  ListModel { id: itemModel }
  ListModel { id: linkModel }

  property real camX: 0
  property real camY: 0
  property real zoom: 1

  property int nextId: 1
  property int nextColor: 0
  property int selectedIndex: -1
  // Ids of the items marked alongside the cursor. Ids rather than indices,
  // because a delete renumbers indices and a mark must survive that.
  property var markedIds: []
  // A lookup beside the list rather than a scan through it. isMarked is a
  // binding on every delegate, so marking the board used to ask n x m
  // questions before the next frame could start — a thousand items marked
  // meant a million comparisons, and a board that stopped for two thirds of a
  // second. Rebuilt once per change of the list, then read once per item.
  readonly property var markedLookup: {
    var lookup = {}
    for (var mi = 0; mi < root.markedIds.length; mi++) lookup[root.markedIds[mi]] = true
    return lookup
  }
  property int editIndex: -1      // -1 means normal mode: every key is a command
  property int linkingFrom: -1    // id of the first end while connecting
  // What pressing x again would do to the two ends chosen so far, so the line
  // under the header can say it before it happens. addLink asks the same
  // question of the same table when it carries it out, so the promise and the
  // change cannot come apart.
  //
  // It follows the two things that move during the gesture — which end is
  // first, and where the cursor is now. The connectors themselves do not
  // change while one is being drawn: completing it is what ends the gesture.
  readonly property string linkOutcome: {
    if (root.linkingFrom < 0 || !root.canEdit) return "none"
    if (root.selectedIndex < 0 || root.selectedIndex >= itemModel.count) return "none"
    var n = itemModel.get(root.selectedIndex)
    // A background takes no connectors, so it is not a far end to promise one.
    if (!n || n.ipinned) return "none"
    return Store.linkAt(linkModel, root.linkingFrom, n.iid).outcome
  }
  property bool helpVisible: false
  property bool showPinned: false
  property string pendingFirstNote: ""
  property bool launchNewBoard: false
  property bool imageBusy: false
  readonly property bool exchangeBusy: exchange.busy
  readonly property bool dialogOpen: exchange.dialogOpen
  readonly property string boardState: root.damaged ? "Read only" : root.saveError !== "" ? "Save failed"
    : root.diskChanged ? "Changed on disk" : root.saving ? "Saving…" : "Saved locally"
  onBoardLoadedChanged: if (root.boardLoaded && root.pendingFirstNote === root.currentBoard) {
    root.pendingFirstNote = ""
    Qt.callLater(function() {
      root.selectedIndex = 0
      root.editIndex = 0
      root.centerOnSelected()
    })
  }

  function newBoard() {
    if (!root.stateReady || root.exchangeBusy || !root.filesystemReady()) return
    root.stopEditing()
    exchange.newBoard()
  }

  function pasteText(text) {
    if (!root.canEdit || !text) return
    root.addItem("note", root.toWorldX(root.viewW / 2), root.toWorldY(root.viewH / 2))
    itemModel.setProperty(root.selectedIndex, "itext", text)
    itemModel.setProperty(root.selectedIndex, "iw", 300)
    itemModel.setProperty(root.selectedIndex, "ih", 200)
    root.save()
    root.flash("Text pasted · enter to edit", "paste")
    root.focusKeys()
  }

  // Sizing needs the picture loaded, and only an open board has a scene that
  // will load one, so the board measures it and calls back.
  // Measuring is asynchronous and a scene has one probe, so pictures wait their
  // turn rather than overwriting each other's pending name. Each carries where
  // it should land: a paste goes to the middle of the view, a drop to the point
  // it was let go of.
  property var imageQueue: []

  function imagePasted(name) { root.enqueueImage(name, 0, 0, false) }
  function imageDropped(name, wx, wy) { root.enqueueImage(name, wx, wy, true) }

  function enqueueImage(name, wx, wy, atPoint) {
    var q = root.imageQueue.slice()
    q.push({ name: name, x: wx, y: wy, atPoint: atPoint, board: root.currentBoard })
    root.imageQueue = q
    if (q.length === 1) root.pumpImages()
  }

  // Each waiting picture names the board it was meant for. Measuring is a round
  // trip through the scene, so a board switch can happen between asking and
  // being answered, and anything waiting for a board that is no longer open is
  // dropped here instead of landing on the one that is.
  function pumpImages() {
    var waiting = root.imageQueue
    var stale = 0
    while (waiting.length > stale && waiting[stale].board !== root.currentBoard) stale += 1
    if (stale > 0) {
      root.imageQueue = waiting.slice(stale)
      root.report(stale === 1 ? "Board changed; that picture was not added"
                              : "Board changed; " + stale + " pictures were not added",
                  waiting[0].atPoint ? "picture" : "paste")
    }
    if (root.imageQueue.length === 0) return
    if (root.activeBoard) root.activeBoard.probeImage(root.imageQueue[0].name)
    else root.pasteImage(root.imageQueue[0].name, 0, 0)
  }

  // Files arrive from another application, so nothing here trusts them: the
  // paths are filtered to plain local ones, and the helper decides whether each
  // is really a picture and what it is called once it is ours.
  function dropFiles(urls, wx, wy) {
    if (!root.canEdit) { root.flash("this board is read-only"); return }
    var entries = []
    for (var i = 0; i < urls.length; i++) {
      var dropped = Store.localPath(String(urls[i]))
      if (dropped === "") continue
      // Staggered, so a handful let go together do not land in one stack.
      entries.push({ path: dropped,
                     x: wx + entries.length * Store.DUPLICATE_OFFSET,
                     y: wy + entries.length * Store.DUPLICATE_OFFSET })
    }
    if (entries.length === 0) { root.flash("drop an image file from your files"); return }
    exchange.importDropped(entries)
  }

  function pasteImage(name, naturalWidth, naturalHeight) {
    // The head of the queue says where this one goes. Called without one — a
    // board that never opened a scene — it lands in the middle of the view.
    var placing = root.imageQueue.length > 0 && root.imageQueue[0].name === name
      ? root.imageQueue[0] : null
    if (placing) root.imageQueue = root.imageQueue.slice(1)
    // The size arrived after a board switch. The point this was meant for
    // belongs to a board that is no longer open, so the picture is not placed.
    if (placing && placing.board !== root.currentBoard) {
      root.report("Board changed; that picture was not added",
                  placing.atPoint ? "picture" : "paste")
      root.pumpImages()
      return
    }
    if (!root.canEdit || !Store.imageIsValid(name)) { root.pumpImages(); return }
    var w = naturalWidth > 0 ? naturalWidth : 320
    var h = naturalHeight > 0 ? naturalHeight : 240
    // Big enough to see, small enough that a phone screenshot does not arrive
    // taller than the board. Aspect is kept, so nothing is squashed.
    var fit = Math.min(1, 360 / Math.max(w, h))
    var fitW = Math.max(root.minItemSize, Math.round(w * fit))
    var fitH = Math.max(root.minItemSize, Math.round(h * fit))
    var atX = placing && placing.atPoint ? placing.x : root.toWorldX(root.viewW / 2)
    var atY = placing && placing.atPoint ? placing.y : root.toWorldY(root.viewH / 2)
    root.addItem("image", atX, atY)
    itemModel.setProperty(root.selectedIndex, "isrc", name)
    itemModel.setProperty(root.selectedIndex, "iw", fitW)
    itemModel.setProperty(root.selectedIndex, "ih", fitH)
    // addItem centres an item of its default size; the picture's own size is
    // only known now, so it is re-centred on the point it was actually meant
    // for rather than sitting half a picture away from it.
    itemModel.setProperty(root.selectedIndex, "ix", atX - fitW / 2)
    itemModel.setProperty(root.selectedIndex, "iy", atY - fitH / 2)
    root.save()
    // A drop carries the point it was let go of; a paste does not. That is
    // also which operation it recovers: the file manager or the clipboard.
    root.flash(naturalWidth > 0 ? "Image added" : "Image added · it could not be read, so the size is a guess",
               placing && placing.atPoint ? "picture" : "paste")
    root.focusKeys()
    root.pumpImages()
  }

  function copySelection() {
    var t = root.targets()
    if (t.length === 0) { root.flash("nothing selected to copy"); return }
    exchange.copyItems(t)
  }

  function pasteClipboard() { exchange.paste() }
  function importBoard() { exchange.choose("import") }
  function exportBoard() { exchange.choose("json") }
  // The copy that deliberately leaves the pictures behind. Asking for it is a
  // separate thing with a name of its own, because a copy that quietly arrives
  // without them is what this used to do by accident.
  function exportBoardPlain() { exchange.choose("plain") }
  // Which colours the next picture is drawn in. Set by the command that asked
  // for it and read by the board when it renders, rather than carried through
  // the file dialog: choosing where to put a picture and choosing what it looks
  // like are two questions, and the dialog belongs to the desktop.
  property string pngPalette: "theme"

  function choosePng(palette) {
    root.pngPalette = Store.exportPalette(palette) === null && palette !== "theme"
      ? "theme" : (palette === undefined ? "theme" : palette)
    exchange.choose("png")
  }
  // Whether the last picture was framed around a marked set rather than the
  // whole board. Read off before rendering, because marks can be dropped while
  // the helper is still copying the file into place.
  property bool pngCropped: false
  function exportPng(path) {
    if (!root.activeBoard) return
    root.pngCropped = root.targets().length > 0
    root.activeBoard.exportPng(path)
  }

  function finishPng(path) {
    imagePublish.command = root.fileCommand("export", [root.dataDir + "/.image-export.png", path, root.dataDir])
    imagePublish.running = true
  }
  Process {
    id: imagePublish
    onExited: function(code) {
      root.imageBusy = false
      // What it actually made a picture of, because the two things that can
      // vary are the two things worth confirming afterwards.
      if (code === 0) root.flash("PNG saved · " + Store.exportNote(root.pngPalette, root.pngCropped), "png")
      else root.report("Could not save PNG; choose a location outside the app data folder", "png")
    }
  }

  function renameBoard() {
    root.openBrowser()
    root.prompt("rename-current", "board name:", root.boardTitle)
  }

  Timer {
    interval: 20
    repeat: true
    running: root.launchNewBoard
    onTriggered: if (root.stateReady && !root.browserBusy && !root.exchangeBusy) {
      root.launchNewBoard = false
      root.newBoard()
    }
  }

  // A board handed in from outside — a file manager opening one, or a summon
  // carrying a path. It waits for the same three things a new board waits for,
  // because a summon arrives before the state has been read and importing into
  // a board that is still loading is how you lose one.
  //
  // It goes through the exchange rather than straight to openBoard: a path
  // from outside is not a board in the library, and the exchange is what knows
  // how to bring one in, refuse what is not a board, and leave the original
  // alone.
  property string launchOpenPath: ""
  Timer {
    interval: 20
    repeat: true
    running: root.launchOpenPath !== ""
    onTriggered: if (root.stateReady && !root.browserBusy && !root.exchangeBusy) {
      var path = root.launchOpenPath
      root.launchOpenPath = ""
      exchange.importPath(path)
    }
  }

  BoardExchange {
    id: exchange
    ctl: root
    onCreated: function(path, editFirst) {
      if (editFirst) root.pendingFirstNote = path
      root.openBoard(path, false)
      root.rescan()
      root.flash(editFirst ? "New board · F2 to name it" : "Board imported" + exchange.createdNote, "board")
    }
    onFinished: function(message, kind) { root.flash(message, kind) }
    onFailed: function(message, kind) { root.report(message, kind) }
    onCopied: function(name) {
      root.rescan()
      session.keptAsCopy(name)
    }
  }

  // A line that says what just happened and then goes away. Deleting is one
  // keystroke, so it should at least say so, and say how to take it back.
  property string statusText: ""
  // Something happened and is worth a moment of the line. `kind` says which
  // operation it belongs to, and is only passed where a success means an
  // earlier failure of the same kind has recovered — copying something out
  // after the clipboard would not answer. A success of another kind says
  // nothing about it and leaves it where it is.
  function flash(text, kind) {
    root.statusText = text
    statusTimer.restart()
    if (kind !== undefined && kind !== "" && kind === root.failureKind) root.clearFailure()
  }

  // Something the person asked for did not happen. It outranks the gesture
  // they have started since, because a flash they were not looking at is a
  // failure they never learn about, and these arrive on a subprocess's own
  // schedule rather than on the keystroke that caused them.
  property string failureText: ""
  property string failureKind: ""

  function report(message, kind) {
    root.failureText = message
    root.failureKind = Store.isFailureKind(kind) ? kind : ""
    // Replacing a visible failure leaves failureVisible true, so its binding
    // alone cannot reset the elapsed time. Hidden failures wait for visibility.
    if (root.failureVisible) failureTimer.restart()
  }

  function clearFailure() {
    root.failureText = ""
    root.failureKind = ""
  }

  // Everything the line under the header is decided from, gathered in one
  // place. A function rather than a property so that the suite gets it along
  // with the rest of the controller: the decision it feeds is the same one the
  // board draws with, and a second copy of it here is how `opened` went missing
  // from one side and a failure timed out unseen.
  function statusState() {
    return {
      opened: root.opened, helpVisible: root.helpVisible,
      browserVisible: root.browserVisible, finding: root.finding,
      saveError: root.saveError, trashIndexError: root.trashIndexError,
      diskChanged: root.diskChanged, damaged: root.damaged,
      failureText: root.failureText,
      paletteVisible: root.paletteVisible, arranging: root.arranging,
      showPinned: root.showPinned, editing: root.editIndex >= 0,
      linking: root.linkingFrom >= 0, statusText: root.statusText,
      switching: root.pendingBoard !== null, saving: root.saving
    }
  }

  // Whether the line is actually showing the failure, which is what the timer
  // below runs on: one that is not on screen is not spending its time on
  // screen. Asked of the same decision the board draws with, so the two cannot
  // come apart again.
  readonly property bool failureVisible: Store.statusTier(root.statusState()) === "failure"

  // Configurable from the bar widget's settings, and remembered in state.json
  // so opening from the keyboard uses the same values.
  property int autosaveMs: 700
  property int step: 40
  property bool showGrid: true
  property string canvasPattern: "Dots"
  property bool startWindowed: false
  property bool windowMode: false

  // Views consume session state; loading and save coordination live together.
  readonly property bool boardLoaded: session.boardLoaded
  readonly property bool damaged: session.damaged
  readonly property string damageReason: session.damageReason
  readonly property string saveError: session.saveError
  // Someone else wrote this board while it was open and the screen has changes
  // of its own. Autosave is waiting, and nothing but a choice clears it.
  readonly property bool diskChanged: session.conflict
  // The panel that offers the three ways out. The conflict itself is shown
  // whether or not this is open, because it does not go away by being ignored.
  property bool conflictVisible: false
  property int conflictIndex: 0

  function decideConflict() {
    if (!root.diskChanged) return
    root.stopEditing()
    root.paletteVisible = false
    root.menuVisible = false
    root.conflictVisible = true
    root.conflictIndex = 0
    root.focusKeys()
  }

  function endConflictChoice() {
    root.conflictVisible = false
    root.focusKeys()
  }

  function moveConflict(step) {
    var n = 3
    root.conflictIndex = ((root.conflictIndex + step) % n + n) % n
  }

  function runConflictChoice() {
    if (root.conflictIndex === 0) root.conflictUseDisk()
    else if (root.conflictIndex === 1) root.conflictSaveCopy()
    else root.conflictReplaceDisk()
  }

  function conflictUseDisk() {
    root.conflictVisible = false
    session.useDisk()
  }

  function conflictReplaceDisk() {
    root.conflictVisible = false
    session.replaceDisk()
  }

  // The copy is written through the same publisher a new board goes through,
  // so it lands under a name nothing else has. Only once it is actually there
  // does the board take the version from disk.
  function conflictSaveCopy() {
    if (!root.diskChanged || root.exchangeBusy) return
    root.conflictVisible = false
    var base = Store.baseName(root.currentBoard).replace(/\.json$/i, "")
    exchange.saveCopy(Store.writeFile(itemModel, linkModel, root.nextId), base + "-mine")
  }
  readonly property bool saving: session.busy
  readonly property var pendingBoard: session.pendingBoard
  readonly property bool canEdit: session.canEdit && !root.browserBusy && !root.imageBusy
  property bool stateReady: false

  property var undoStack: []
  property var redoStack: []

  // ------------------------------------------------------------------ browser
  property bool browserVisible: false
  property string browserDir: ""
  property string browserQuery: ""
  property int browserIndex: 0
  property var browserEntries: []
  // "" when navigating; otherwise the label of the line being typed into.
  property bool browserSearching: false
  property string browserPrompt: ""
  property string browserInput: ""
  property string browserAction: ""
  // Armed by the first x, cleared by anything else.
  property string pendingDelete: ""
  // A line of feedback shown in place of the path, cleared by the next key.
  property string browserMessage: ""
  // The browser shows the trash instead of the boards while this is on.
  property bool browserTrash: false
  property var trashEntries: []
  property bool trashIndexSaving: false
  property bool trashIndexLoading: true
  property bool trashIndexNeedsRead: true
  property string trashIndexError: ""
  readonly property bool browserBusy: mkdirProc.running || moveProc.running || trashProc.running
    || restoreProc.running || purgeProc.running || root.trashIndexSaving || root.trashIndexLoading

  function refreshTrashIndex() {
    if (root.trashIndexSaving || (root.trashIndexError !== "" && !root.trashIndexNeedsRead)) return
    root.trashIndexLoading = true
    root.trashIndexNeedsRead = true
    trashIndexFile.reload()
  }

  function acceptTrashIndex(raw) {
    root.trashIndexLoading = false
    if (root.trashIndexSaving || (root.trashIndexError !== "" && !root.trashIndexNeedsRead)) return
    var parsed = null
    try { parsed = JSON.parse(raw) } catch (e) {}
    var entries = Store.readTrash(raw)
    if (!parsed || (parsed.version !== undefined && parsed.version !== 1) || !Array.isArray(parsed.entries) || entries.length !== parsed.entries.length) {
      root.trashIndexNeedsRead = true
      root.trashIndexError = "trash index is invalid — repair index.json, then ctrl+s to reload"
      return
    }
    root.trashEntries = entries
    root.trashIndexNeedsRead = false
    root.trashIndexError = ""
  }

  function fileCommand(action, args) {
    return ["bash", decodeURIComponent(Qt.resolvedUrl("BoardFiles.sh").toString().replace(/^file:\/\//, "")), action].concat(args)
  }

  function filesystemReady() {
    if (root.browserBusy) { root.browserMessage = "finishing the previous operation…"; return false }
    if (root.trashIndexError !== "") { root.browserMessage = root.trashIndexError; return false }
    return true
  }

  readonly property var browserRows: root.browserTrash
    ? Store.sortedTrash(root.trashEntries)
    : Store.filterEntries(root.browserEntries, root.browserDir, root.browserQuery)

  property var activeBoard: null
  // Whether the view was last set with no surface to measure the header on.
  property bool framePending: false
  onActiveBoardChanged: if (root.activeBoard && root.framePending) Qt.callLater(root.resetView)
  property var boardScreen: null
  readonly property real viewW: root.activeBoard ? root.activeBoard.width : 1920
  readonly property real viewH: root.activeBoard ? root.activeBoard.height : 1080

  function repaintGrid() { if (root.activeBoard) root.activeBoard.repaintGrid() }
  // A batch of items moving is still one repaint. Each item writes two
  // properties, and each write reaches this through the delegate's own
  // onXChanged, so dragging a marked board asked for a repaint twice per item
  // per frame. The canvas coalesces the paint; it does not coalesce being
  // asked. Held off while a batch runs, then asked for once.
  property bool batching: false
  function repaintLinks() {
    if (root.batching) return
    if (root.activeBoard) root.activeBoard.repaintLinks()
  }
  function focusKeys() {
    if (!root.paletteVisible && root.editIndex >= 0 && root.textEditor) root.textEditor.forceActiveFocus()
    else if (root.activeBoard) root.activeBoard.focusKeys()
  }
  function isMarked(id) { return root.markedLookup[id] === true }
  readonly property bool culling: true
  // The accent as markup understands it. The hint lines name their keys in it,
  // the way btop colours the letter a menu entry answers to, and StyledText
  // wants a string where the rest of the board wants a colour.
  readonly property string accentMarkup: Store.hexColor(root.theme.accent)

  // What an operation applies to: everything marked, or the cursor alone.
  // Descending, so removing by index cannot shift the ones still to come.
  function targets() {
    var out = []
    if (root.markedIds.length === 0)
      return root.selectedIndex >= 0 && !itemModel.get(root.selectedIndex).ipinned ? [root.selectedIndex] : []
    // One read of the row rather than two: get() builds a wrapper object
    // each time, and this runs on every frame of a drag.
    var lookup = root.markedLookup
    for (var i = itemModel.count - 1; i >= 0; i--) {
      var n = itemModel.get(i)
      if (!n.ipinned && lookup[n.iid] === true) out.push(i)
    }
    return out
  }

  function toggleMark() {
    var n = root.selected()
    if (!n || n.ipinned) return
    var m = root.markedIds.slice()
    var at = m.indexOf(n.iid)
    if (at >= 0) m.splice(at, 1)
    else m.push(n.iid)
    root.markedIds = m
    root.flash(m.length === 0 ? "nothing marked" : m.length + " marked")
    root.repaintLinks()
  }

  function markAll() {
    var m = []
    for (var i = 0; i < itemModel.count; i++) {
      var n = itemModel.get(i)
      if (!n.ipinned) m.push(n.iid)
    }
    root.markedIds = m
    root.flash(m.length + " marked")
    root.repaintLinks()
  }

  // The marquee hands back world coordinates, so a mark survives a pan or a
  // zoom that happens mid-drag. Additive keeps what was already marked.
  function markInRect(x0, y0, x1, y1, additive) {
    var ids = Store.idsInRect(itemModel,
                              Math.min(x0, x1), Math.min(y0, y1),
                              Math.max(x0, x1), Math.max(y0, y1))
    var m = additive ? root.markedIds.slice() : []
    // A sweep that adds to a large selection scanned the whole of it for
    // every item it touched; the set says the same thing in one read.
    var seen = {}
    for (var s0 = 0; s0 < m.length; s0++) seen[m[s0]] = true
    for (var i = 0; i < ids.length; i++)
      if (seen[ids[i]] !== true) { seen[ids[i]] = true; m.push(ids[i]) }
    root.markedIds = m
    // Leave a cursor inside the marked set so the keyboard carries on from
    // where the rectangle finished rather than from wherever it last was.
    if (m.length === 0) root.selectedIndex = -1
    else if (root.selectedIndex < 0 || !root.isMarked(itemModel.get(root.selectedIndex).iid))
      root.selectedIndex = Store.indexOfId(itemModel, m[m.length - 1])
    root.editIndex = -1
    root.linkingFrom = -1
    root.repaintLinks()
    root.flash(m.length === 0 ? "nothing marked" : m.length + " marked")
    root.focusKeys()
  }

  function clearMarks() {
    if (root.markedIds.length === 0) return false
    root.markedIds = []
    root.repaintLinks()
    return true
  }

  function togglePin() {
    if (!root.canEdit) return
    var n = root.selected()
    var unpin = n && n.ipinned
    var t = unpin ? [root.selectedIndex] : root.targets()
    if (t.length === 0) return
    root.pushUndo()
    for (var i = 0; i < t.length; i++) itemModel.setProperty(t[i], "ipinned", !unpin)
    root.markedIds = []
    root.editIndex = -1
    root.linkingFrom = -1
    root.showPinned = false
    if (!unpin) root.selectedIndex = -1
    root.save()
    root.flash(unpin ? "unpinned" : "pinned as background · shift+p to select backgrounds")
    root.focusKeys()
  }

  function togglePinnedSelection() {
    root.showPinned = !root.showPinned
    root.markedIds = []
    root.selectedIndex = -1
    root.editIndex = -1
    root.linkingFrom = -1
    root.selectNext(1)
    root.focusKeys()
  }

  function selected() { return root.selectedIndex >= 0 ? itemModel.get(root.selectedIndex) : null }

  function toWorldX(sx) { return (sx - root.camX) / root.zoom }
  function toWorldY(sy) { return (sy - root.camY) / root.zoom }
  function toScreenX(wx) { return wx * root.zoom + root.camX }
  function toScreenY(wy) { return wy * root.zoom + root.camY }

  // ------------------------------------------------------------------ history
  function snapshot() {
    return { items: Store.itemRows(itemModel), links: Store.linkRows(linkModel), nextId: root.nextId }
  }

  function pushUndo() {
    if (!root.boardLoaded) return
    var s = root.undoStack.slice()
    s.push(root.snapshot())
    // A snapshot holds the whole board, so depth has to give way as boards
    // grow: a hundred steps of three thousand items is twenty-four megabytes
    // held in the shell. Ten steps of a large board, a hundred of a small one.
    var maxSteps = Math.min(100, Math.max(10, Math.floor(20000 / Math.max(1, itemModel.count))))
    while (s.length > maxSteps) s.shift()
    root.undoStack = s
    root.redoStack = []   // a new edit drops the redo branch
  }

  function restore(snap) {
    if (!root.canEdit) return
    root.markedIds = []
    Store.fillItems(itemModel, snap.items)
    Store.fillLinks(linkModel, itemModel, snap.links)
    root.nextId = snap.nextId
    if (root.selectedIndex >= itemModel.count) root.selectedIndex = itemModel.count - 1
    root.editIndex = -1
    root.linkingFrom = -1
    root.repaintLinks()
    // Rebuilding the model tears down every delegate, which drops keyboard
    // focus; without this a second undo never reaches the key handler.
    if (!root.browserVisible) root.focusKeys()
  }

  function undo() {
    if (!root.canEdit) return
    if (root.undoStack.length === 0) return
    var from = root.undoStack.slice()
    var to = root.redoStack.slice()
    to.push(root.snapshot())
    var target = from.pop()
    root.undoStack = from
    root.redoStack = to
    root.restore(target)
    root.save(true)
  }

  function redo() {
    if (!root.canEdit) return
    if (root.redoStack.length === 0) return
    var from = root.redoStack.slice()
    var to = root.undoStack.slice()
    to.push(root.snapshot())
    var target = from.pop()
    root.redoStack = from
    root.undoStack = to
    root.restore(target)
    root.save(true)
  }

  // -------------------------------------------------------------------- items
  function addItem(kind, wx, wy) {
    if (!root.canEdit) return
    root.showPinned = false
    root.markedIds = []
    root.pushUndo()
    var w = kind === "note" ? 180 : 160
    var h = kind === "note" ? 140 : 110
    itemModel.append({
      iid: root.nextId, kind: kind,
      ix: wx - w / 2, iy: wy - h / 2, iw: w, ih: h,
      itint: Store.TINTS[root.nextColor % Store.TINTS.length],
      itext: "", ipinned: false, isrc: ""
    })
    root.nextId += 1
    root.nextColor += 1
    root.selectedIndex = itemModel.count - 1
    root.save()
    root.repaintLinks()
  }

  // A new item lands beside the selected one, so building a row is just
  // n, n, n without touching the mouse.
  function addRelative(kind) {
    var n = root.selected()
    if (n) root.addItem(kind, n.ix + n.iw + 120, n.iy + n.ih / 2)
    else root.addItem(kind, root.toWorldX(root.viewW / 2), root.toWorldY(root.viewH / 2))
    root.centerOnSelected()
    root.editSelected()
  }

  function removeItem(index) {
    if (!root.canEdit) return
    if (index < 0 || index >= itemModel.count || itemModel.get(index).ipinned) return
    root.removeAt([index])
  }

  function removeTargets() {
    if (!root.canEdit) return
    root.removeAt(root.targets())
  }

  // The commands in the menu all have keys of their own, so the menu is a
  // reminder rather than the way in, and it costs no height until asked for.
  property bool menuVisible: false
  property bool zoomMenuVisible: false
  // Which item the keyboard is on. Opening starts at the first, so the menu can
  // be walked without reaching for the mouse.
  property int menuIndex: 0

  function toggleMenu() {
    root.menuVisible = !root.menuVisible
    root.zoomMenuVisible = false
    root.menuIndex = 0
    root.focusKeys()
  }

  function moveMenu(step) {
    var n = Store.menuEntries(root.zoomMenuVisible).length
    root.menuIndex = ((root.menuIndex + step) % n + n) % n
  }

  // The dispatch lives here rather than in the toolbar, so a click and a
  // keystroke take the same path and the list can be tested without a scene.
  function runMenu(index) {
    var entry = Store.menuEntries(root.zoomMenuVisible)[index]
    if (!entry || typeof root[entry.run] !== "function") return
    var fromZoom = root.zoomMenuVisible
    if (!entry.keepOpen) root.closeMenu()
    if (entry.arg === undefined) root[entry.run]()
    else root[entry.run](entry.arg)
    if (fromZoom && !entry.keepOpen) root.focusKeys()
  }

  function closeMenu() {
    root.menuVisible = false
    root.zoomMenuVisible = false
    root.menuIndex = 0
  }

  function openZoomMenu() {
    root.zoomMenuVisible = true
    var percent = Math.round(root.zoom * 100)
    root.menuIndex = 1
    for (var i = 0; i < Store.ZOOM_LEVELS.length; i++) {
      if (Math.round(Store.ZOOM_LEVELS[i] * 100) === percent) {
        root.menuIndex = i + 1
        break
      }
    }
    root.focusKeys()
  }

  function backToMenu() {
    root.zoomMenuVisible = false
    root.menuIndex = Store.menuIndex("zoom")
  }

  function setZoom(level) { root.zoomCentre(level / root.zoom) }
  function showHelp() { root.helpVisible = true }

  function toggleHelp() { root.helpVisible = !root.helpVisible }

  // ------------------------------------------------------------- the palette
  // Every command by name. The keys are fast once they are in your hands and
  // useless before that: a board you have not opened in a month is a list of
  // letters to remember, and one you have never opened is worse. `:` opens
  // this, typing narrows it, enter runs it — and what it runs is the function
  // the key runs, because both come out of the one table in BoardStore.
  property bool paletteVisible: false
  property string paletteQuery: ""
  property int paletteIndex: 0
  // "all" is every command; "selection" is the ones that act on what is
  // selected, which is what a menu of actions for it offers.
  property string paletteScope: "all"
  property var textEditor: null
  onEditIndexChanged: root.textEditor = null

  function beginTextPalette(editor) {
    if (!root.canEdit || root.editIndex < 0) return
    root.textEditor = editor
    root.beginPalette("typing")
  }

  function markText(style) {
    var marks = Store.TEXT_MARKS[style]
    if (root.commandReady("typing") && marks) root.textEditor.style(marks[0], marks[1])
  }

  function headText() {
    if (root.commandReady("typing")) root.textEditor.heading()
  }
  readonly property var paletteMatches: root.paletteVisible
    ? Store.matchCommands(root.paletteQuery, root.paletteScope) : []
  // How many rows the panel draws. The rest are still there to be typed at.
  readonly property int paletteRows: 9

  // The same panel, opened on the commands that act on what is selected. A
  // menu of actions rather than a second list to keep in step with the first:
  // it is the one table, filtered, dispatched the same way.
  function beginSelectionActions() {
    if (!root.canEdit) return
    if (root.targets().length === 0 && !(root.selected() && root.selected().ipinned)) {
      root.flash("nothing selected · space marks the one under the cursor")
      return
    }
    root.beginPalette("selection")
  }

  function beginPalette(scope) {
    if (!root.boardLoaded && !root.damaged) return
    root.paletteScope = scope === "typing" ? "typing" : scope === "selection" ? "selection" : "all"
    if (root.paletteScope !== "typing") root.stopEditing()
    root.menuVisible = false
    root.paletteVisible = true
    root.paletteQuery = ""
    root.paletteIndex = 0
    root.focusKeys()
  }

  function endPalette() {
    root.paletteVisible = false
    root.paletteQuery = ""
    root.paletteIndex = 0
  }

  // One way for the query to change, whether it came from the field in the
  // panel, a test, or the screenshot harness. The cursor goes back to the top,
  // because the row it was on now means something else.
  function setPaletteQuery(text) {
    if (text === root.paletteQuery) return
    root.paletteQuery = text
    root.paletteIndex = 0
  }

  function movePalette(step) {
    var n = root.paletteMatches.length
    if (n === 0) return
    root.paletteIndex = ((root.paletteIndex + step) % n + n) % n
  }

  // Whether a command can do anything at this moment. Every one of these
  // functions already refuses politely on its own, but a command run from a
  // list that then appears to do nothing teaches the wrong thing about it.
  function commandReady(needs) {
    if (needs === "conflict") return root.diskChanged
    if (needs === "edit") return root.canEdit
    if (!root.canEdit) return needs === ""
    if (needs === "typing") return root.editIndex >= 0 && !!root.textEditor
    if (needs === "target") return root.targets().length > 0
    // A background under the cursor counts: which one is on top, and whether
    // it stays a background at all, are questions about it.
    if (needs === "item") return root.targets().length > 0 || (root.selected() !== null && root.selected().ipinned)
    if (needs === "group") return root.targets().length >= 2
    return true
  }

  function commandExcuse(needs) {
    if (needs === "conflict") return "this board has not changed underneath you"
    if (!root.canEdit) return root.damaged ? "this board is read-only" : "the board is not ready yet"
    if (needs === "typing") return "start editing a note"
    if (needs === "group") return "mark two or more"
    if (needs === "target" || needs === "item") return "nothing is selected"
    return "not now"
  }

  function runPaletteChoice() {
    var choice = root.paletteMatches[root.paletteIndex]
    if (!choice) { root.flash(root.paletteQuery === "" ? "no commands" : "no command goes by that"); return }
    root.endPalette()
    root.runCommand(choice.name)
  }

  // The one dispatch. A name that is not in the table runs nothing, and a
  // function the table names but the controller does not have would be a
  // mistake in the table — which tests/contract.js refuses to let ship.
  function runCommand(name) {
    var command = Store.commandByName(name)
    if (!command || typeof root[command.run] !== "function") return
    if (!root.commandReady(command.needs)) {
      root.flash(command.name + " · " + root.commandExcuse(command.needs))
      return
    }
    if (command.arg === undefined) root[command.run]()
    else root[command.run](command.arg)
  }

  // Finding is navigation, not editing, so it works on a board that cannot be
  // written to as well as one that can.
  property bool finding: false
  property string findQuery: ""
  property int findCount: 0
  // One read for the whole board rather than a query test per item: while this
  // is true, anything that does not match recedes.
  readonly property bool findDimming: root.finding && root.findQuery !== ""
  // Lowered once per keystroke rather than once per item per keystroke:
  // matchesFind is a binding on every delegate.
  readonly property string findNeedle: root.findQuery.toLowerCase()

  function beginFind() {
    if (itemModel.count === 0) { root.flash("nothing on this board to find yet"); return }
    root.showPinned = false
    root.stopEditing()
    root.finding = true
    root.findQuery = ""
    root.findCount = 0
  }

  function endFind() {
    root.finding = false
    root.findQuery = ""
    root.findCount = 0
  }

  // One way for the query to change, whether it came from the field on the
  // board, a test, or the screenshot harness — so what is exercised without a
  // scene is what typing into it does.
  function setFindQuery(text) {
    if (text === root.findQuery) return
    root.findQuery = text
    root.refreshFind()
  }

  // The board follows the typing: the first match is selected and centred as
  // the query narrows, so you see where you are going before pressing Enter.
  function refreshFind() {
    var m = Store.findMatches(itemModel, root.findQuery)
    root.findCount = m.length
    if (m.length === 0) return
    root.selectedIndex = m[0]
    root.centerOnSelected()
  }

  function nextMatch() {
    var m = Store.findMatches(itemModel, root.findQuery)
    root.findCount = m.length
    if (m.length === 0) { root.flash(root.findQuery === "" ? "type something to find" : "no match"); return }
    var at = -1
    for (var i = 0; i < m.length; i++) if (m[i] === root.selectedIndex) { at = i; break }
    root.selectedIndex = m[(at + 1) % m.length]
    root.centerOnSelected()
  }

  // Asked per item, so it takes the text it already has rather than scanning
  // the model once for every note on the board.
  function matchesFind(text) {
    if (!root.findDimming || typeof text !== "string") return false
    return text.toLowerCase().indexOf(root.findNeedle) >= 0
  }

  // Arranging is a two-key command: g, then which edge. A mode rather than six
  // more bindings, because the second key is a direction the hands already know
  // and the footer can say what the choices are while it waits.
  property bool arranging: false

  function beginArrange() {
    if (!root.canEdit) return
    if (root.targets().length < 2) { root.flash("mark two or more items to arrange them"); return }
    root.arranging = true
  }

  function cancelArrange() { root.arranging = false }

  function alignTargets(edge) {
    root.arranging = false
    if (!root.canEdit) return
    var moves = Store.alignMoves(itemModel, root.targets(), edge)
    if (moves.length === 0) { root.flash("already aligned"); return }
    root.applyMoves(moves)
    root.flash("aligned " + moves.length + (moves.length === 1 ? " item" : " items"))
  }

  function spreadTargets(axis) {
    root.arranging = false
    if (!root.canEdit) return
    var t = root.targets()
    if (t.length < 3) { root.flash("mark three or more items to spread them"); return }
    var moves = Store.spreadMoves(itemModel, t, axis)
    if (moves.length === 0) { root.flash("already evenly spaced"); return }
    root.applyMoves(moves)
    root.flash("spread " + moves.length + (moves.length === 1 ? " item" : " items"))
  }

  function applyMoves(moves) {
    root.pushUndo()
    for (var i = 0; i < moves.length; i++) {
      itemModel.setProperty(moves[i].index, "ix", moves[i].x)
      itemModel.setProperty(moves[i].index, "iy", moves[i].y)
    }
    root.save()
    root.repaintLinks()
  }

  // A copy lands offset from its original rather than on top of it, and becomes
  // the selection, so duplicating then pushing it somewhere is two commands
  // instead of four.
  function duplicateTargets() {
    if (!root.canEdit) return
    var t = root.targets()
    if (t.length === 0) return
    // targets() comes back descending; copying in board order keeps the copies
    // stacked the way the originals were.
    var ordered = t.slice().sort(function (a, b) { return a - b })
    root.pushUndo()
    var fresh = []
    var byOriginal = ({})
    for (var i = 0; i < ordered.length; i++) {
      var n = itemModel.get(ordered[i])
      var id = root.nextId
      root.nextId += 1
      byOriginal[n.iid] = id
      // An image copy points at the same file: the picture is shared by every
      // board already, and duplicating one should not duplicate megabytes.
      itemModel.append({
        iid: id, kind: n.kind,
        ix: n.ix + Store.DUPLICATE_OFFSET, iy: n.iy + Store.DUPLICATE_OFFSET,
        iw: n.iw, ih: n.ih, itint: n.itint, itext: n.itext, ipinned: false, isrc: n.isrc
      })
      fresh.push(id)
    }
    // A connector is copied only when both of its ends were: half of one would
    // have to guess which original it still joins.
    var rows = Store.linkRows(linkModel)
    for (var j = 0; j < rows.length; j++)
      if (byOriginal[rows[j].from] !== undefined && byOriginal[rows[j].to] !== undefined)
        linkModel.append({ lfrom: byOriginal[rows[j].from], lto: byOriginal[rows[j].to] })
    root.markedIds = fresh.length > 1 ? fresh : []
    root.selectedIndex = itemModel.count - 1
    root.save()
    root.repaintLinks()
    root.flash(fresh.length === 1 ? "Duplicated" : "Duplicated " + fresh.length + " items")
  }

  // Indices must arrive descending: removing one shifts every index after it.
  function removeAt(indices) {
    if (indices.length === 0) return
    root.pushUndo()
    for (var k = 0; k < indices.length; k++) {
      var id = itemModel.get(indices[k]).iid
      itemModel.remove(indices[k])
      // Connectors cannot outlive either end.
      for (var j = linkModel.count - 1; j >= 0; j--) {
        var l = linkModel.get(j)
        if (l.lfrom === id || l.lto === id) linkModel.remove(j)
      }
    }
    root.markedIds = []
    if (root.selectedIndex >= itemModel.count) root.selectedIndex = itemModel.count - 1
    root.save(true)
    root.repaintLinks()
    root.flash((indices.length === 1 ? "deleted" : indices.length + " deleted") + " · u to undo")
    if (!root.browserVisible) root.focusKeys()
  }

  // The cursor item decides the next value and the rest follow it, so a mixed
  // selection lands on one colour rather than each cycling from its own.
  // Which item is drawn over which. The order of the model is the order they
  // are painted in, so this moves rows and nothing else: an item keeps its id,
  // its connectors and whether it is pinned — backgrounds are a layer of their
  // own and stay one, so this changes the order within that layer rather than
  // taking anything out of it.
  function layerTargets(where) {
    if (!root.canEdit) return
    // A background under the cursor is its own target, the way unpinning
    // treats it: targets() leaves backgrounds out of the commands that act on
    // the working canvas, and which background is on top is still a question.
    var here = root.selected()
    var t = here && here.ipinned ? [root.selectedIndex] : root.targets()
    if (t.length === 0) { root.flash("nothing selected to move"); return }
    var moves = Store.layerMoves(itemModel.count, t, where)
    if (moves.length === 0) {
      root.flash(where === "front" || where === "forward" ? "already at the front" : "already at the back")
      return
    }
    root.pushUndo()
    // The cursor follows its item rather than its position, which is about to
    // be somebody else's.
    var cursor = root.selectedIndex >= 0 ? itemModel.get(root.selectedIndex).iid : -1
    for (var i = 0; i < moves.length; i++) itemModel.move(moves[i].from, moves[i].to, 1)
    if (cursor >= 0) root.selectedIndex = Store.indexOfId(itemModel, cursor)
    root.save()
    root.repaintLinks()
  }

  function recolorItem() {
    if (!root.canEdit) return
    var n = root.selected()
    var t = root.targets()
    if (!n || t.length === 0) return
    root.pushUndo()
    var next = Store.cycle(Store.TINTS, n.itint)
    for (var i = 0; i < t.length; i++) itemModel.setProperty(t[i], "itint", next)
    root.save()
  }

  function cycleKind() {
    if (!root.canEdit) return
    var n = root.selected()
    var t = root.targets()
    if (!n || t.length === 0) return
    // Turning an image into a box would drop the picture with no way back, so
    // it keeps its shape and takes the rest of the selection with it.
    if (n.kind === "image") { root.flash("an image keeps its shape"); return }
    root.pushUndo()
    var next = Store.cycle(Store.KINDS, n.kind)
    for (var i = 0; i < t.length; i++)
      if (itemModel.get(t[i]).kind !== "image") itemModel.setProperty(t[i], "kind", next)
    root.save()
  }

  // ------------------------------------------------------------------ linking
  function toggleLinking() {
    if (root.selected() && root.selected().ipinned) return
    var n = root.selected()
    if (!n) return
    if (root.linkingFrom < 0) {
      root.linkingFrom = n.iid
      // Whatever the line was saying is about the last thing that finished,
      // not about the one starting now. The order below the header already
      // keeps it from covering the outcome while this runs; dropping it here
      // is so it cannot come back out from under it afterwards either.
      root.statusText = ""
      root.repaintLinks()
      return
    }
    if (n.iid !== root.linkingFrom) root.addLink(root.linkingFrom, n.iid)
    root.linkingFrom = -1
    root.repaintLinks()
  }

  // Connectors point somewhere: an arrow carries a meaning a plain line
  // cannot. Only one runs between any pair, so drawing the same pair again
  // either turns it round or takes it away.
  function addLink(a, b) {
    if (!root.canEdit) return
    // The same question the hint asked while the far end was being chosen, so
    // what happens here is what the board said was about to happen.
    var found = Store.linkAt(linkModel, a, b)
    if (found.outcome === "none") return
    root.pushUndo()
    if (found.outcome === "remove") {
      linkModel.remove(found.at)
      root.save(true)
      root.repaintLinks()
      root.flash("connector removed · u to undo")
      return
    }
    if (found.outcome === "reverse") {
      linkModel.setProperty(found.at, "lfrom", a)
      linkModel.setProperty(found.at, "lto", b)
      root.save()
      root.repaintLinks()
      return
    }
    linkModel.append({ lfrom: a, lto: b })
    root.save()
    root.repaintLinks()
  }

  function unlinkSelected() {
    if (root.selected() && root.selected().ipinned) return
    if (!root.canEdit) return
    var n = root.selected()
    if (!n) return
    var removed = false
    for (var j = linkModel.count - 1; j >= 0; j--) {
      var l = linkModel.get(j)
      if (l.lfrom === n.iid || l.lto === n.iid) {
        if (!removed) { root.pushUndo(); removed = true }
        linkModel.remove(j)
      }
    }
    if (removed) { root.save(true); root.repaintLinks(); root.flash("connectors removed · u to undo") }
  }

  // --------------------------------------------------------------- navigation
  function pointerSelect(index, additive) {
    if (additive && !itemModel.get(index).ipinned) {
      if (root.markedIds.length === 0 && root.selectedIndex >= 0 && root.selectedIndex !== index
          && !itemModel.get(root.selectedIndex).ipinned) root.markedIds = [itemModel.get(root.selectedIndex).iid]
      root.selectedIndex = index
      root.toggleMark()
    } else if (root.isMarked(itemModel.get(index).iid)) {
      root.selectedIndex = index
    } else root.selectOnly(index)
    root.editIndex = -1
    root.linkingFrom = -1
    root.focusKeys()
  }

  function moveTargets(dx, dy) {
    if (!root.canEdit) return
    var t = root.targets()
    root.batching = true
    try {
      for (var i = 0; i < t.length; i++) {
        var n = itemModel.get(t[i])
        itemModel.setProperty(t[i], "ix", n.ix + dx)
        itemModel.setProperty(t[i], "iy", n.iy + dy)
      }
    } finally { root.batching = false }
    root.repaintLinks()
  }

  function resizeTargets(dx, dy) {
    if (!root.canEdit) return
    var t = root.targets()
    root.batching = true
    try {
      for (var i = 0; i < t.length; i++) {
        var n = itemModel.get(t[i])
        itemModel.setProperty(t[i], "iw", Math.max(root.minItemSize, n.iw + dx))
        itemModel.setProperty(t[i], "ih", Math.max(root.minItemSize, n.ih + dy))
      }
    } finally { root.batching = false }
    root.repaintLinks()
  }

  function selectOnly(index) {
    root.markedIds = []
    root.selectedIndex = index
    root.editIndex = -1
    root.linkingFrom = -1
    root.repaintLinks()
  }

  function move(dx, dy, carry) {
    if (carry) return root.nudgeSelected(dx, dy)
    if (root.selectedIndex < 0) return root.panBy(-dx * 120, -dy * 120)
    var next = Store.nearest(itemModel, root.selectedIndex, dx, dy, root.showPinned)
    if (next >= 0) root.selectedIndex = next
    root.centerOnSelected()
    root.repaintLinks()
  }

  function selectNext(stepBy) {
    if (itemModel.count === 0) return
    var start = root.selectedIndex
    if (start < 0) start = stepBy > 0 ? -1 : 0
    var found = -1
    for (var i = 1; i <= itemModel.count; i++) {
      var at = ((start + stepBy * i) % itemModel.count + itemModel.count) % itemModel.count
      if ((itemModel.get(at).ipinned === true) === root.showPinned) { found = at; break }
    }
    root.selectedIndex = found
    root.centerOnSelected()
    root.repaintLinks()
  }

  function nudgeSelected(dx, dy) {
    if (!root.canEdit) return
    var t = root.targets()
    if (t.length === 0) return
    root.pushUndo()
    root.moveTargets(dx * root.worldStep, dy * root.worldStep)
    root.centerOnSelected()
    root.save()
  }

  // Resize from the bottom-right, the same corner the mouse grip pulls, so the
  // item's top-left stays where you put it.
  function resizeSelected(dx, dy) {
    if (!root.canEdit) return
    var t = root.targets()
    if (t.length === 0) return
    // Nothing to record when every one of them is already at the minimum.
    var moved = false
    for (var i = 0; i < t.length; i++) {
      var n = itemModel.get(t[i])
      if (Math.max(root.minItemSize, n.iw + dx * root.worldStep) !== n.iw) { moved = true; break }
      if (Math.max(root.minItemSize, n.ih + dy * root.worldStep) !== n.ih) { moved = true; break }
    }
    if (!moved) return
    root.pushUndo()
    root.resizeTargets(dx * root.worldStep, dy * root.worldStep)
    root.centerOnSelected()
    root.save()
  }

  // Keep the selection visible without moving a comfortably framed view.
  function centerOnSelected() {
    var n = root.selected()
    if (!n) return
    var m = 60
    var topInset = root.activeBoard ? root.activeBoard.canvasTop + 24 : m
    var sx = root.toScreenX(n.ix), sy = root.toScreenY(n.iy)
    var sw = n.iw * root.zoom, sh = n.ih * root.zoom
    if (sx < m) root.camX += m - sx
    else if (sx + sw > root.viewW - m) root.camX -= (sx + sw) - (root.viewW - m)
    if (sy < topInset) root.camY += topInset - sy
    else if (sy + sh > root.viewH - m) root.camY -= (sy + sh) - (root.viewH - m)
    root.repaintGrid()
    root.repaintLinks()
  }

  function panBy(dx, dy) {
    root.camX += dx
    root.camY += dy
    root.repaintGrid()
    root.repaintLinks()
  }

  function zoomAt(sx, sy, factor) {
    var next = Math.max(0.2, Math.min(4, root.zoom * factor))
    if (next === root.zoom) return
    // Keep the point under the cursor pinned while the scale changes.
    var wx = root.toWorldX(sx), wy = root.toWorldY(sy)
    root.zoom = next
    root.camX = sx - wx * root.zoom
    root.camY = sy - wy * root.zoom
    root.repaintGrid()
    root.repaintLinks()
  }

  function zoomCentre(factor) { root.zoomAt(root.viewW / 2, root.viewH / 2, factor) }

  // A board opens, and `0` goes back to it, at 100% with the top-left of what
  // is on it just inside the window: clear of the header and the line under
  // it, which are laid over the canvas. It used to put the world's origin at
  // the window's corner, and a board's first row sat under the header.
  //
  // The header is measured on the surface, and a board loads when the shell
  // starts, long before anyone opens it. So a view set with no surface to
  // measure is set again when one arrives — and only then, so switching
  // between fullscreen and windowed keeps your place.
  function resetView() {
    var m = 24
    var b = Store.bounds(itemModel)
    root.zoom = 1
    root.camX = m - (b ? b.minX : 0)
    root.camY = (root.activeBoard ? root.activeBoard.canvasTop : 0) + m - (b ? b.minY : 0)
    root.framePending = !root.activeBoard
    root.repaintGrid()
    root.repaintLinks()
  }

  // Centre on everything, so a board is never lost off-screen after a big pan.
  function fitToItems() {
    var b = Store.bounds(itemModel)
    if (!b) return root.resetView()
    var pad = 80
    var w = (b.maxX - b.minX) + pad * 2
    var h = (b.maxY - b.minY) + pad * 2
    var top = root.activeBoard ? root.activeBoard.canvasTop : 0
    root.zoom = Math.max(0.2, Math.min(1, Math.min(root.viewW / w, Math.max(100, root.viewH - top) / h)))
    root.camX = root.viewW / 2 - ((b.minX + b.maxX) / 2) * root.zoom
    root.camY = (top + root.viewH) / 2 - ((b.minY + b.maxY) / 2) * root.zoom
    root.repaintGrid()
    root.repaintLinks()
  }

  // -------------------------------------------------------------------- modes
  function editSelected() {
    if (root.selected() && root.selected().ipinned) return
    if (!root.canEdit) return
    if (root.selectedIndex < 0) return
    root.pushUndo()
    root.editIndex = root.selectedIndex
  }

  function stopEditing() {
    root.textEditor = null
    root.editIndex = -1
    root.focusKeys()
    root.save()
  }

  function toggleWindowMode() {
    root.windowMode = !root.windowMode
    root.writeState()
  }

  // Escape unwinds one layer at a time rather than closing outright.
  function back() {
    if (root.helpVisible) root.helpVisible = false
    else if (root.menuVisible) root.menuVisible = false
    else if (root.finding) root.endFind()
    else if (root.arranging) root.arranging = false
    else if (root.showPinned) { root.showPinned = false; root.selectedIndex = -1 }
    else if (root.clearMarks()) root.flash("marks cleared")
    else if (root.linkingFrom >= 0) { root.linkingFrom = -1; root.repaintLinks() }
    // Last, so escape never has to choose between dismissing a failure and
    // leaving a mode — and before closing, so the keystroke that takes an
    // answer down is not also the one that closes the board.
    else if (root.failureText !== "") root.clearFailure()
    else root.dismiss()
  }

  // ------------------------------------------------------------------ browser
  function openBrowser() {
    root.flushSave()
    root.browserQuery = ""
    root.browserSearching = false
    root.browserPrompt = ""
    root.browserInput = ""
    root.browserMessage = ""
    root.pendingDelete = ""
    root.browserIndex = 0
    root.browserDir = Store.parentOf(root.currentBoard)
    root.browserTrash = false
    root.browserVisible = true
    root.refreshTrashIndex()
    root.rescan()
  }

  function closeBrowser() {
    root.browserVisible = false
    root.browserPrompt = ""
    root.browserQuery = ""
    root.browserSearching = false
    root.focusKeys()
  }

  function rescan() { scanProc.running = true }

  function browserClamp() {
    var n = root.browserRows.length
    if (n === 0) root.browserIndex = 0
    else if (root.browserIndex >= n) root.browserIndex = n - 1
    else if (root.browserIndex < 0) root.browserIndex = 0
  }

  function browserCurrent() {
    var rows = root.browserRows
    if (root.browserIndex < 0 || root.browserIndex >= rows.length) return null
    return rows[root.browserIndex]
  }

  // Enter descends into a folder or opens a board.
  function browserEnter() {
    // Opening a board or folder does not touch the trash, so a broken trash
    // index must not block it; restoreCurrent() checks the index itself.
    if (root.browserBusy) { root.browserMessage = "finishing the previous operation…"; return }
    var e = root.browserCurrent()
    if (!e) return
    if (root.browserTrash) { root.restoreCurrent(); return }
    if (e.dir) {
      root.browserDir = e.path
      root.browserQuery = ""
      root.browserIndex = 0
      return
    }
    root.openBoard(e.path)
    root.closeBrowser()
  }

  function browserUp() {
    if (root.browserSearching) { root.browserSearching = false; root.browserQuery = ""; root.browserIndex = 0; return }
    if (root.browserDir === "") return
    var leaving = root.browserDir
    root.browserDir = Store.parentOf(leaving)
    root.browserIndex = 0
    // Land on the folder we just came out of, the way cd .. leaves you.
    var rows = root.browserRows
    for (var i = 0; i < rows.length; i++) if (rows[i].path === leaving) root.browserIndex = i
  }

  function prompt(action, label, initial) {
    root.browserAction = action
    root.browserPrompt = label
    root.browserInput = initial || ""
  }

  function cancelPrompt() {
    root.browserAction = ""
    root.browserPrompt = ""
    root.browserInput = ""
  }

  function commitPrompt() {
    if (!root.filesystemReady()) return
    var name = root.browserInput.trim()
    var action = root.browserAction
    root.browserPrompt = ""
    root.browserInput = ""
    root.browserAction = ""
    if (!Store.nameIsValid(name)) { root.browserMessage = "use a name without slashes or control characters"; return }

    if (action === "board") {
      var path = Store.uniquePath(root.browserEntries, root.browserDir, name, false)
      root.createBoard(path)
    } else if (action === "folder") {
      var dir = Store.uniquePath(root.browserEntries, root.browserDir, name, true)
      mkdirProc.command = root.fileCommand("mkdir", [root.boardsDir, dir])
      mkdirProc.running = true
    } else if (action === "rename" || action === "rename-current") {
      if (root.diskChanged) {
        root.browserMessage = "two versions of this board exist — esc, then ctrl+s to choose"
        return
      }
      root.flushSave()
      if (session.busy || root.saveError !== "") {
        root.browserMessage = "finish saving before renaming; try again"
        return
      }
      var e = action === "rename-current" ? {path: root.currentBoard, dir: false} : root.browserCurrent()
      if (!e) return
      if (name === Store.displayName(e)) { root.closeBrowser(); return }
      var target = Store.uniquePath(root.browserEntries, Store.parentOf(e.path), name, e.dir)
      moveProc.command = root.fileCommand("move", [root.boardsDir, e.path, root.boardsDir, target])
      moveProc.renamedFrom = e.path
      moveProc.renamedTo = target
      moveProc.running = true
    }
  }

  // A new board is created by pointing at it and saving: the file appears with
  // an empty board in it, which is also what makes it the open one.
  function createBoard(path) {
    root.openBoard(path, true)
    root.closeBrowser()
  }

  // True when this entry is, or contains, the board that is open.
  function holdsOpenBoard(e) {
    if (!e.dir) return e.path === root.currentBoard
    return root.currentBoard.indexOf(e.path + "/") === 0
  }

  function deleteCurrent() {
    if (!root.filesystemReady()) return
    var e = root.browserCurrent()
    if (!e) return

    if (root.browserTrash) {
      // Inside the trash there is nowhere further to put something, so this
      // one really does destroy it.
      if (root.pendingDelete !== e.file) {
        root.pendingDelete = e.file
        root.browserMessage = "press x again to destroy " + Store.baseName(e.path) + " for good"
        return
      }
      root.pendingDelete = ""
      root.browserMessage = ""
      purgeProc.entryFile = e.file
      purgeProc.command = root.fileCommand("purge", [root.trashDir, e.file])
      purgeProc.running = true
      return
    }

    // Refuse to delete the open board, or the folder it lives in.
    if (root.holdsOpenBoard(e)) {
      root.browserMessage = "that is the board you have open — switch away first"
      return
    }
    if (root.pendingDelete !== e.path) {
      root.pendingDelete = e.path
      root.browserMessage = "press x again to move " + Store.displayName(e)
                            + (e.dir ? "/ and everything in it" : "") + " to the trash"
      return
    }
    root.pendingDelete = ""
    root.browserMessage = ""

    var stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss")
    var file = Store.trashFile(root.trashEntries, e.path, stamp)
    trashProc.pending = { file: file, path: e.path, dir: e.dir, at: stamp }
    trashProc.command = root.fileCommand("move", [root.boardsDir, e.path, root.trashDir, file])
    trashProc.running = true
  }

  function restoreCurrent() {
    if (!root.filesystemReady()) return
    var e = root.browserCurrent()
    if (!e || !root.browserTrash) return
    restoreProc.entryFile = e.file
    restoreProc.command = root.fileCommand("move", [root.trashDir, e.file, root.boardsDir, e.path])
    restoreProc.running = true
  }

  function toggleTrash() {
    root.browserTrash = !root.browserTrash
    root.browserIndex = 0
    root.browserQuery = ""
    root.browserSearching = false
    root.pendingDelete = ""
    root.browserMessage = ""
    if (root.browserTrash) root.refreshTrashIndex()
  }

  function saveTrashIndex(entries) {
    root.trashEntries = entries
    root.trashIndexSaving = true
    root.trashIndexNeedsRead = false
    root.trashIndexError = ""
    trashIndexFile.setText(Store.writeTrash(entries))
  }

  function browserKey(event) {
    if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
      root.retryTrashIndex()
      event.accepted = true
      return
    }
    var text = event.text

    // Arming a delete lasts exactly until the next keystroke.
    if (text !== "x") {
      root.pendingDelete = ""
      root.browserMessage = ""
    }

    // While typing a name, every printable key is input.
    if (root.browserPrompt !== "") {
      if (event.key === Qt.Key_Escape) root.cancelPrompt()
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commitPrompt()
      else if (event.key === Qt.Key_Backspace) root.browserInput = root.browserInput.slice(0, -1)
      else if (text && text >= " ") root.browserInput += text
      else return
      event.accepted = true
      return
    }

    // While searching, printable keys extend the query; the arrow keys and
    // Enter still navigate the results.
    if (root.browserSearching && text && text >= " ") {
      root.browserQuery += text
      root.browserIndex = 0
      event.accepted = true
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (root.browserTrash) { root.toggleTrash() }
      else if (root.browserSearching) {
        root.browserSearching = false
        root.browserQuery = ""
        root.browserIndex = 0
      } else root.closeBrowser()
    }
    else if (event.key === Qt.Key_Down || text === "j") { root.browserIndex += 1; root.browserClamp() }
    else if (event.key === Qt.Key_Up || text === "k") { root.browserIndex -= 1; root.browserClamp() }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || text === "l"
             || event.key === Qt.Key_Right) root.browserEnter()
    else if (event.key === Qt.Key_Left || text === "h") root.browserUp()
    else if (event.key === Qt.Key_Backspace) {
      if (root.browserSearching) {
        root.browserQuery = root.browserQuery.slice(0, -1)
        if (root.browserQuery === "") root.browserSearching = false
        root.browserIndex = 0
      } else root.browserUp()
    }
    else if (text === "/") { root.browserSearching = true; root.browserQuery = ""; root.browserIndex = 0 }
    else if (root.browserTrash && ["a", "A", "r"].indexOf(text) >= 0) root.browserMessage = "enter: restore this item · t: return to boards"
    else if (text === "a") root.prompt("board", "new board:", "")
    else if (text === "A") root.prompt("folder", "new folder:", "")
    else if (text === "r") {
      var e = root.browserCurrent()
      if (e) root.prompt("rename", "rename to:", Store.displayName(e))
    }
    else if (text === "x") root.deleteCurrent()
    else if (text === "t") root.toggleTrash()
    else if (text === "g") { root.browserIndex = 0 }
    else if (text === "G") { root.browserIndex = root.browserRows.length - 1; root.browserClamp() }
    else return
    event.accepted = true
  }

  // ------------------------------------------------------------------ storage
  BoardSession { id: session; ctl: root }

  function scheduleSave() { session.scheduleSave() }
  function retryTrashIndex() {
    if (root.trashIndexLoading || root.trashIndexSaving || root.trashIndexError === "") return
    if (root.trashIndexNeedsRead) root.refreshTrashIndex()
    else root.saveTrashIndex(root.trashEntries)
  }
  // ctrl+s with a conflict outstanding is not a save: it is the moment someone
  // is asking about it, which is when the choices are worth putting on screen.
  function flushSave() {
    root.retryTrashIndex()
    if (root.diskChanged) { root.decideConflict(); return }
    session.flushSave()
  }
  function save(allowEmpty) { session.save(allowEmpty) }
  function openBoard(path, fresh) { session.openBoard(path, fresh) }

  function writeState() {
    stateFile.setText(JSON.stringify({
      version: 1,
      lastBoard: root.currentBoard,
      windowMode: root.windowMode,
      autosaveMs: root.autosaveMs,
      step: root.step,
      showGrid: root.showGrid,
      canvasPattern: root.canvasPattern,
      startWindowed: root.startWindowed
    }, null, 2) + "\n")
  }

  // Which board was open last time, and whether it was windowed. Kept out of
  // the board files so the same board can be opened on two machines without
  // dragging one machine's window preference along with it.
  function applyState(raw) {
    var st = null
    try { st = JSON.parse(raw) } catch (e) { st = null }
    if (st && Store.safeRelative(st.lastBoard)) root.currentBoard = st.lastBoard
    if (st) {
      root.windowMode = st.windowMode === true
      if (typeof st.autosaveMs === "number") root.autosaveMs = st.autosaveMs
      if (typeof st.step === "number") root.step = st.step
      if (typeof st.showGrid === "boolean") root.showGrid = st.showGrid
      if (Store.CANVAS_PATTERNS.indexOf(st.canvasPattern) >= 0) root.canvasPattern = st.canvasPattern
      if (typeof st.startWindowed === "boolean") root.startWindowed = st.startWindowed
      // With no board open yet, the bar's preference decides the surface.
      if (st.windowMode === undefined) root.windowMode = root.startWindowed
    }
    root.stateReady = true
  }

  // ----------------------------------------------------------------- lifecycle
  // The output Hyprland has focused, which is where a keyboard-summoned board
  // belongs. Without this the overlay lands wherever Quickshell picks, which
  // on a two-monitor desk is rarely the one being used.
  function focusedScreen() {
    // The same guard the theme reads its own singletons through: this one is
    // Hyprland's, and it is no more a versioned API than the palette is.
    var monitor = root.theme.token(function () { return Hyprland.focusedMonitor }, null)
    var wanted = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === wanted) return screens[i]
    return screens[0]
  }

  // A summon from the bar carries that widget's settings. Applying them here
  // and writing them to state keeps the two entry points in step: configure on
  // the bar, and the keybinding opens the same board the same way.
  function applyPayload(payloadJson) {
    var p = null
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { return false }
    if (!p || !p.settings) return false
    var st = p.settings
    if (typeof st.autosaveMs === "number") root.autosaveMs = Math.max(100, Math.min(5000, st.autosaveMs))
    if (typeof st.step === "number") root.step = Math.max(5, Math.min(200, st.step))
    if (typeof st.showGrid === "boolean") root.showGrid = st.showGrid
    if (Store.CANVAS_PATTERNS.indexOf(st.canvasPattern) >= 0) root.canvasPattern = st.canvasPattern
    if (typeof st.startWindowed === "boolean") root.startWindowed = st.startWindowed
    return true
  }

  function open(payloadJson) {
    var request = null
    try { request = JSON.parse(payloadJson || "{}") } catch (e) {}
    if (request && request.action === "new") root.launchNewBoard = true
    if (request && request.action === "open" && typeof request.path === "string" && request.path !== "")
      root.launchOpenPath = request.path
    if (root.applyPayload(payloadJson)) root.writeState()
    root.boardScreen = root.focusedScreen()
    root.opened = true
    Qt.callLater(function () {
      root.focusKeys()
      root.repaintGrid()
      root.repaintLinks()
    })
  }

  // The host calls close() for IPC hide/toggle; Escape and window close use
  // the same cleanup before notifying the scoped shell facade.
  function close() {
    if (root.imageBusy) { root.flash("Finishing image export…"); return }
    // Closing is not a decision either. A board with two versions keeps both —
    // the edits stay in the session, and the question is still there when it
    // comes back — rather than being asked on the way out of the window.
    if (!root.diskChanged) root.flushSave()
    root.opened = false
    root.markedIds = []
    root.showPinned = false
    root.selectedIndex = -1
    root.editIndex = -1
    root.linkingFrom = -1
    root.helpVisible = false
    root.browserVisible = false
    root.browserPrompt = ""
    root.browserInput = ""
    root.browserAction = ""
    root.browserQuery = ""
    root.browserSearching = false
    root.browserMessage = ""
    root.pendingDelete = ""
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "thepixelgardener.omarchyform")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchyform"
  readonly property string boardsDir: root.dataDir + "/boards"
  // Backups sit outside the boards tree: that tree is meant to be browsed,
  // hand-edited and committed, and .bak files beside every board are noise in
  // all three. The relative path is flattened so one directory holds them all
  // without needing a folder created for every board folder.
  readonly property string backupsDir: root.dataDir + "/backups"
  // Deleting moves a board aside rather than destroying it. The index records
  // where each one came from, so putting it back is exact.
  readonly property string trashDir: root.dataDir + "/trash"
  readonly property string trashIndexPath: root.trashDir + "/index.json"
  // Pasted pictures are shared by every board, and nothing deletes them: a
  // board in the trash still points at its images, and so does a copy someone
  // exported last month. An orphan costs disk; a missing one costs the board.
  readonly property string imagesDir: root.dataDir + "/images"
  // One lock per board, outside the boards tree: the folder people are invited
  // to browse, hand-edit and commit stays free of files that are not boards.
  readonly property string locksDir: root.dataDir + "/locks"
  function lockPathFor(relative) {
    return root.locksDir + "/" + Store.lockKey(String(relative)) + ".lock"
  }

  // The only way a file name out of a board file becomes a URL to load.
  function imagePath(name) {
    return Store.imageIsValid(name) ? "file://" + root.imagesDir + "/" + name : ""
  }

  function backupPathFor(relative) {
    return root.backupsDir + "/" + "v2/" + relative + ".bak"
  }
  readonly property string legacyPath: root.dataDir + "/board.json"
  readonly property string statePath: root.dataDir + "/state.json"

  // Relative to boardsDir, e.g. "work/project-a.json".
  property string currentBoard: "board.json"
  readonly property string boardPath: root.boardsDir + "/" + root.currentBoard
  readonly property string boardTitle: Store.displayName({ path: root.currentBoard, dir: false })

  Timer {
    id: statusTimer
    interval: 2600
    repeat: false
    onTriggered: root.statusText = ""
  }

  // Longer than a flash, because it is an answer rather than an acknowledgement
  // — and it only runs while the failure is the thing on the line. Held behind
  // a conflict or under the browser it does not tick, so a failure cannot
  // expire in the time it spent where nobody could read it.
  Timer {
    id: failureTimer
    interval: 6000
    repeat: false
    running: root.failureVisible
    onTriggered: root.clearFailure()
  }

  // The boards directory has to exist before the first atomic write, otherwise
  // the board silently fails to save on a fresh install. A board from before
  // there were folders is copied in rather than moved, so the old file stays
  // put as a fallback.
  Process {
    id: initProc
    running: true
    command: ["mkdir", "-p", root.boardsDir, root.backupsDir, root.trashDir, root.imagesDir, root.locksDir]
    onExited: migrateProc.running = true
  }

  Process {
    id: migrateProc
    command: ["cp", "-n", root.legacyPath, root.boardsDir + "/board.json"]
    onExited: stateFile.reload()
  }

  Process {
    id: scanProc
    command: ["find", root.boardsDir, "-mindepth", "1", "-printf", "%y\\t%P\\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.browserEntries = Store.parseListing(text)
        root.browserClamp()
      }
    }
  }

  Process {
    id: mkdirProc
    onExited: function(code) {
      if (code !== 0) root.browserMessage = "could not create that folder"
      root.rescan()
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
        if (root.currentBoard === from) {
          root.currentBoard = moveProc.renamedTo
          root.writeState()
        } else if (root.currentBoard.indexOf(from + "/") === 0) {
          root.currentBoard = moveProc.renamedTo + root.currentBoard.slice(from.length)
          root.writeState()
        }
      }
      if (code !== 0) root.browserMessage = "could not rename that; destination exists or path is unavailable"
      root.rescan()
    }
  }

  Process {
    id: trashProc
    property var pending: null
    onExited: function (code) {
      if (code === 0 && trashProc.pending) {
        var next = root.trashEntries.slice()
        next.push(trashProc.pending)
        root.saveTrashIndex(next)
        root.flash("moved to the trash · t in the browser to get it back")
      } else if (code !== 0) {
        root.browserMessage = "could not move that to the trash"
      }
      trashProc.pending = null
      root.rescan()
    }
  }

  Process {
    id: restoreProc
    property string entryFile: ""
    onExited: function (code) {
      if (code === 0) {
        root.saveTrashIndex(Store.withoutTrash(root.trashEntries, restoreProc.entryFile))
        root.browserMessage = "restored"
      } else {
        root.browserMessage = "could not restore that; something is in its place"
      }
      restoreProc.entryFile = ""
      root.rescan()
    }
  }

  Process {
    id: purgeProc
    property string entryFile: ""
    onExited: function (code) {
      if (code === 0) root.saveTrashIndex(Store.withoutTrash(root.trashEntries, purgeProc.entryFile))
      else root.browserMessage = "could not remove that trash entry"
      purgeProc.entryFile = ""
    }
  }

  FileView {
    id: trashIndexFile
    path: root.trashIndexPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.acceptTrashIndex(text())
    onLoadFailed: function(error) {
      root.trashIndexLoading = false
      if (root.trashIndexSaving || !root.trashIndexNeedsRead) return
      if (error === FileViewError.FileNotFound) {
        root.trashEntries = []
        root.trashIndexNeedsRead = false
        root.trashIndexError = ""
      } else root.trashIndexError = "trash index could not be read — ctrl+s to retry"
    }
    onSaved: { root.trashIndexSaving = false; root.trashIndexError = "" }
    onSaveFailed: {
      root.trashIndexSaving = false
      root.trashIndexError = "trash index could not be saved — ctrl+s to retry; keep the board open"
      root.browserMessage = root.trashIndexError
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("")
  }

  // ----------------------------------------------------------------- surfaces
  // Built through Variants so the surface is constructed with its screen
  // already set: assigning `screen` to a window that already exists leaves it
  // unmapped, which looks exactly like the board failing to open.
  Variants {
    model: root.opened && !root.windowMode && root.boardScreen ? [root.boardScreen] : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        visible: true
        color: "transparent"
        WlrLayershell.namespace: "omarchyform"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.dialogOpen ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }

        Board {
          anchors.fill: parent
          ctl: root
        }
      }
    }
  }

  // An ordinary toplevel, so Hyprland tiles it beside your other windows.
  FloatingWindow {
    id: boardWindow
    visible: root.opened && root.windowMode
    title: "Omarchyform"
    color: root.theme.canvasBackground
    implicitWidth: 1100
    implicitHeight: 750
    minimumSize: Qt.size(480, 360)

    // Closing from the titlebar or a compositor keybind ends the session the
    // same way Escape does.
    onVisibleChanged: if (!visible && root.opened && root.windowMode) root.dismiss()

    Loader {
      anchors.fill: parent
      focus: true
      active: boardWindow.visible
      sourceComponent: Component {
        Board { ctl: root }
      }
    }
  }
}
