pragma ComponentBehavior: Bound

import Quickshell.Io
import QtQuick
import "BoardStore.js" as Store
import "BoardHistory.js" as History

// One view of a board, and the controller every view reads as `ctl`: where the
// camera is, what is selected, which mode the keys are in, what the line under
// the header says, and every command the keys and the palette run. What is on
// the board belongs to its document, which another pane may be showing too;
// the settings, the library, the files and the windows belong to the
// workspace, Omarchyform.qml. The drawing lives in Board.qml and Node.qml and
// the pure logic in BoardStore.js.
Item {
  id: root

  required property var workspace
  // The board this pane shows. Null only before the state file has said which.
  property var doc: null
  readonly property bool opened: root.workspace.opened

  // Whether the keyboard is in this pane, and whether there is another one.
  readonly property bool active: root.workspace.activePane === root
  readonly property bool split: root.workspace.split
  // Two panes asked for and room on screen for only this one.
  readonly property bool squeezed: root.workspace.squeezed
  // The browser is drawn over the pane that opened it, which is the active one:
  // the workspace does not let the keyboard move while it is up.
  readonly property bool browsing: root.active && root.library.showing
  // Waiting to leave a board nobody else is showing until its last write has
  // landed. Editing stops meanwhile, as it does during a switch in place.
  property bool leaving: false

  // --------------------------------------------------------------- appearance
  // What the board looks like is in Theme.qml, held by the workspace: one
  // object for every pane, and one object for a test to hold.
  readonly property Theme theme: root.workspace.theme

  readonly property int minItemSize: Store.MIN_SIZE

  // The step is what the eye sees, so it is divided by the zoom: otherwise one
  // press moves an eighth of the distance when zoomed out and four times it
  // when zoomed in.
  readonly property real worldStep: root.step / root.zoom

  // -------------------------------------------------------------------- state
  // The board's contents, as the views read them. A pane with no board yet
  // reads as an empty one rather than as null.
  // Looking back, they are the board as it was: models of the pane's own,
  // which nothing edits and nothing saves.
  readonly property ListModel items: root.lookingBack ? pastItems : root.doc ? root.doc.items : noItems
  readonly property ListModel links: root.lookingBack ? pastLinks : root.doc ? root.doc.links : noLinks
  ListModel { id: pastItems }
  ListModel { id: pastLinks }
  ListModel { id: noItems }
  ListModel { id: noLinks }

  property real camX: 0
  property real camY: 0
  property real zoom: 1

  readonly property int nextId: root.doc ? root.doc.nextId : 1
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
    if (root.selectedIndex < 0 || root.selectedIndex >= root.items.count) return "none"
    var n = root.items.get(root.selectedIndex)
    // A background takes no connectors, so it is not a far end to promise one.
    if (!n || n.ipinned) return "none"
    return Store.linkAt(root.links, root.linkingFrom, n.iid).outcome
  }
  property bool helpVisible: false
  property bool showPinned: false
  property string pendingFirstNote: ""
  property bool imageBusy: false
  readonly property bool exchangeBusy: root.workspace.exchange.busy
  readonly property bool dialogOpen: root.workspace.exchange.dialogOpen
  readonly property string boardState: root.lookingBack ? "Earlier version · read only"
    : root.damaged ? "Read only" : root.saveError !== "" ? "Save failed"
    : root.diskChanged ? "Changed on disk" : root.saving ? "Saving…" : "Saved locally"
  // Only a board made to be typed into. A pane that has just been given a
  // board can hear that it loaded before it hears which board it is, and an
  // empty wish matched against a name not yet there is a match.
  onBoardLoadedChanged: if (root.boardLoaded && root.pendingFirstNote !== ""
                            && root.pendingFirstNote === root.currentBoard) {
    root.pendingFirstNote = ""
    Qt.callLater(function() {
      root.selectedIndex = 0
      // Typing into it is an edit like any other, and its record says so.
      if (root.items.count > 0) root.doc.beginEdit("Typing", String(root.items.get(0).iid))
      root.editIndex = 0
      root.centerOnSelected()
    })
  }

  function newBoard() {
    if (!root.stateReady || root.exchangeBusy || !root.library.ready()) return
    root.stopEditing()
    root.workspace.exchange.newBoard()
  }

  function pasteText(text) {
    if (!root.canEdit || !text) return
    root.addItem("note", root.toWorldX(root.viewW / 2), root.toWorldY(root.viewH / 2), "Paste")
    root.items.setProperty(root.selectedIndex, "itext", text)
    root.items.setProperty(root.selectedIndex, "iw", 300)
    root.items.setProperty(root.selectedIndex, "ih", 200)
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
    root.workspace.exchange.importDropped(entries)
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
    root.items.setProperty(root.selectedIndex, "isrc", name)
    root.items.setProperty(root.selectedIndex, "iw", fitW)
    root.items.setProperty(root.selectedIndex, "ih", fitH)
    // addItem centres an item of its default size; the picture's own size is
    // only known now, so it is re-centred on the point it was actually meant
    // for rather than sitting half a picture away from it.
    root.items.setProperty(root.selectedIndex, "ix", atX - fitW / 2)
    root.items.setProperty(root.selectedIndex, "iy", atY - fitH / 2)
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
    root.workspace.exchange.copyItems(t)
  }

  function pasteClipboard() { root.workspace.exchange.paste() }
  function importBoard() { root.workspace.exchange.choose("import") }
  // What goes out is the board as it is. Sending an earlier version out is
  // not something this does yet, so looking back it says so.
  function exportsNow() {
    if (!root.lookingBack) return true
    root.flash("this is an earlier version · esc returns to now, which is what goes out")
    return false
  }
  function exportBoard() { if (root.exportsNow()) root.workspace.exchange.choose("json") }
  // The copy that deliberately leaves the pictures behind. Asking for it is a
  // separate thing with a name of its own, because a copy that quietly arrives
  // without them is what this used to do by accident.
  function exportBoardPlain() { if (root.exportsNow()) root.workspace.exchange.choose("plain") }
  // Which colours the next picture is drawn in. Set by the command that asked
  // for it and read by the board when it renders, rather than carried through
  // the file dialog: choosing where to put a picture and choosing what it looks
  // like are two questions, and the dialog belongs to the desktop.
  property string pngPalette: "theme"

  function choosePng(palette) {
    // Both panes render into the same file on the way out, so a second picture
    // waits for the first rather than being drawn over it.
    if (root.workspace.imageBusy) { root.flash("Finishing image export…"); return }
    if (!root.exportsNow()) return
    root.pngPalette = Store.EXPORT_PALETTE_NAMES.indexOf(palette) >= 0 ? palette : "theme"
    root.workspace.exchange.choose("png")
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
    root.library.ask("rename-current", "board name:", root.boardTitle)
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
      opened: root.opened, helpVisible: root.helpVisible, active: root.active,
      browserVisible: root.browsing, finding: root.finding,
      saveError: root.saveError, trashIndexError: root.library.trashIndexError,
      diskChanged: root.diskChanged, damaged: root.damaged,
      failureText: root.failureText,
      paletteVisible: root.paletteVisible, arranging: root.arranging,
      showPinned: root.showPinned, editing: root.editIndex >= 0,
      linking: root.linkingFrom >= 0, statusText: root.statusText,
      switching: root.pendingBoard !== null || root.leaving, saving: root.saving, timeline: root.timeline
    }
  }

  // Whether the line is actually showing the failure, which is what the timer
  // below runs on: one that is not on screen is not spending its time on
  // screen. Asked of the same decision the board draws with, so the two cannot
  // come apart again.
  readonly property bool failureVisible: Store.statusTier(root.statusState()) === "failure"

  // The workspace's settings, as the views read them.
  readonly property int step: root.workspace.step
  readonly property bool showGrid: root.workspace.showGrid
  readonly property string canvasPattern: root.workspace.canvasPattern

  // The document's state, as the views read it; loading and save coordination
  // live together in its session.
  readonly property bool boardLoaded: root.doc !== null && root.doc.boardLoaded
  readonly property bool damaged: root.doc !== null && root.doc.damaged
  readonly property string damageReason: root.doc ? root.doc.damageReason : ""
  readonly property string saveError: root.doc ? root.doc.saveError : ""
  // Someone else wrote this board while it was open and the screen has changes
  // of its own. Autosave is waiting, and nothing but a choice clears it.
  readonly property bool diskChanged: root.doc !== null && root.doc.diskChanged
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
    root.doc.useDisk()
  }

  function conflictReplaceDisk() {
    root.conflictVisible = false
    root.doc.replaceDisk()
  }

  // The copy is written through the same publisher a new board goes through,
  // so it lands under a name nothing else has. Only once it is actually there
  // does the board take the version from disk.
  function conflictSaveCopy() {
    if (!root.diskChanged || root.exchangeBusy) return
    root.conflictVisible = false
    var base = Store.baseName(root.currentBoard).replace(/\.json$/i, "")
    // The copy keeps this version's history with it.
    root.workspace.saveConflictCopy(root.doc, root.doc.fileText(), base + "-mine")
  }
  readonly property bool saving: root.doc !== null && root.doc.saving
  readonly property var pendingBoard: root.doc ? root.doc.pendingBoard : null
  // One picture renders at a time across the workspace, and nothing changes
  // under it while it does: a board shown twice is still one board.
  // An earlier version is to look at: nothing in this pane changes it.
  readonly property bool canEdit: root.doc !== null && root.doc.canEdit && !root.library.busy
    && !root.leaving && !root.workspace.imageBusy && !root.lookingBack
  readonly property bool stateReady: root.workspace.stateReady

  function fileCommand(action, args) { return root.workspace.fileCommand(action, args) }

  property var activeBoard: null
  // Whether the view was last set with no surface to measure the header on.
  property bool framePending: false
  onActiveBoardChanged: if (root.activeBoard && root.framePending) Qt.callLater(root.resetView)
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
      return root.selectedIndex >= 0 && !root.items.get(root.selectedIndex).ipinned ? [root.selectedIndex] : []
    // One read of the row rather than two: get() builds a wrapper object
    // each time, and this runs on every frame of a drag.
    var lookup = root.markedLookup
    var model = root.items
    for (var i = model.count - 1; i >= 0; i--) {
      var n = model.get(i)
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
    for (var i = 0; i < root.items.count; i++) {
      var n = root.items.get(i)
      if (!n.ipinned) m.push(n.iid)
    }
    root.markedIds = m
    root.flash(m.length + " marked")
    root.repaintLinks()
  }

  // The marquee hands back world coordinates, so a mark survives a pan or a
  // zoom that happens mid-drag. Additive keeps what was already marked.
  function markInRect(x0, y0, x1, y1, additive) {
    var ids = Store.idsInRect(root.items,
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
    else if (root.selectedIndex < 0 || !root.isMarked(root.items.get(root.selectedIndex).iid))
      root.selectedIndex = Store.indexOfId(root.items, m[m.length - 1])
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
    root.pushUndo(unpin ? "Unpin" : "Pin")
    for (var i = 0; i < t.length; i++) root.items.setProperty(t[i], "ipinned", !unpin)
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

  function selected() { return root.selectedIndex >= 0 ? root.items.get(root.selectedIndex) : null }

  function toWorldX(sx) { return (sx - root.camX) / root.zoom }
  function toWorldY(sy) { return (sy - root.camY) / root.zoom }
  function toScreenX(wx) { return wx * root.zoom + root.camX }
  function toScreenY(wy) { return wy * root.zoom + root.camY }

  // ------------------------------------------------------------------ history
  function snapshot() {
    return { items: Store.itemRows(root.items), links: Store.linkRows(root.links), nextId: root.nextId }
  }

  // An edit is starting, and this is what it is called: the label its record
  // carries in the board's history. `key` says which typing session it is,
  // so typing in another note is a record of its own.
  function pushUndo(label, key) {
    if (!root.boardLoaded) return
    root.doc.beginEdit(label || "Edit", key === undefined ? "" : String(key))
    var s = root.doc.undoStack.slice()
    s.push(root.snapshot())
    // A snapshot holds the whole board, so depth has to give way as boards
    // grow: a hundred steps of three thousand items is twenty-four megabytes
    // held in the shell. Ten steps of a large board, a hundred of a small one.
    var maxSteps = Math.min(100, Math.max(10, Math.floor(20000 / Math.max(1, root.items.count))))
    while (s.length > maxSteps) s.shift()
    root.doc.undoStack = s
    root.doc.redoStack = []   // a new edit drops the redo branch
  }

  function restore(snap) {
    if (!root.canEdit) return
    root.markedIds = []
    Store.fillItems(root.items, snap.items)
    Store.fillLinks(root.links, root.items, snap.links)
    root.doc.nextId = snap.nextId
    if (root.selectedIndex >= root.items.count) root.selectedIndex = root.items.count - 1
    root.editIndex = -1
    root.linkingFrom = -1
    root.repaintLinks()
    // Rebuilding the model tears down every delegate, which drops keyboard
    // focus; without this a second undo never reaches the key handler.
    if (!root.library.showing) root.focusKeys()
  }

  function undo() {
    if (!root.canEdit) return
    if (root.doc.undoStack.length === 0) return
    // An undo is an edit of its own in the history: the board went back.
    root.doc.beginEdit("Undo", "")
    var from = root.doc.undoStack.slice()
    var to = root.doc.redoStack.slice()
    to.push(root.snapshot())
    var target = from.pop()
    root.doc.undoStack = from
    root.doc.redoStack = to
    root.restore(target)
    root.save(true)
  }

  function redo() {
    if (!root.canEdit) return
    if (root.doc.redoStack.length === 0) return
    root.doc.beginEdit("Redo", "")
    var from = root.doc.redoStack.slice()
    var to = root.doc.undoStack.slice()
    to.push(root.snapshot())
    var target = from.pop()
    root.doc.redoStack = from
    root.doc.undoStack = to
    root.restore(target)
    root.save(true)
  }

  // -------------------------------------------------------------------- items
  function addItem(kind, wx, wy, label) {
    if (!root.canEdit) return
    root.showPinned = false
    root.markedIds = []
    root.pushUndo(label || Store.ADD_LABELS[kind] || "New item")
    var w = kind === "note" ? 180 : 160
    var h = kind === "note" ? 140 : 110
    root.items.append({
      iid: root.nextId, kind: kind,
      ix: wx - w / 2, iy: wy - h / 2, iw: w, ih: h,
      itint: Store.TINTS[root.doc.nextColor % Store.TINTS.length],
      itext: "", ipinned: false, isrc: ""
    })
    root.doc.nextId += 1
    root.doc.nextColor += 1
    root.selectedIndex = root.items.count - 1
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
    if (index < 0 || index >= root.items.count || root.items.get(index).ipinned) return
    root.removeAt([index])
  }

  function removeTargets() {
    if (!root.canEdit) return
    root.removeAt(root.targets())
  }

  // The menu exposes common actions without needing to know their keys.
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
  function chooseCanvasBackground() {
    root.beginPalette("all")
    root.setPaletteQuery("Canvas background:")
    var current = root.showGrid ? root.canvasPattern : "Plain"
    for (var i = 0; i < root.paletteMatches.length; i++)
      if (root.paletteMatches[i].arg === current) root.paletteIndex = i
  }

  // Every pane wears the same background: it is a setting, not part of a board.
  function setCanvasBackground(pattern) {
    if (!root.workspace.setCanvasBackground(pattern)) return
    root.flash("Canvas background: " + pattern)
  }

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
    if (root.lookingBack) return "this is an earlier version · esc returns to now"
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
    if (root.items.count === 0) { root.flash("nothing on this board to find yet"); return }
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
    var m = Store.findMatches(root.items, root.findQuery)
    root.findCount = m.length
    if (m.length === 0) return
    root.selectedIndex = m[0]
    root.centerOnSelected()
  }

  function nextMatch() {
    var m = Store.findMatches(root.items, root.findQuery)
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
    var moves = Store.alignMoves(root.items, root.targets(), edge)
    if (moves.length === 0) { root.flash("already aligned"); return }
    root.applyMoves(moves, "Align")
    root.flash("aligned " + moves.length + (moves.length === 1 ? " item" : " items"))
  }

  function spreadTargets(axis) {
    root.arranging = false
    if (!root.canEdit) return
    var t = root.targets()
    if (t.length < 3) { root.flash("mark three or more items to spread them"); return }
    var moves = Store.spreadMoves(root.items, t, axis)
    if (moves.length === 0) { root.flash("already evenly spaced"); return }
    root.applyMoves(moves, "Spread")
    root.flash("spread " + moves.length + (moves.length === 1 ? " item" : " items"))
  }

  function applyMoves(moves, label) {
    root.pushUndo(label)
    for (var i = 0; i < moves.length; i++) {
      root.items.setProperty(moves[i].index, "ix", moves[i].x)
      root.items.setProperty(moves[i].index, "iy", moves[i].y)
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
    root.pushUndo("Duplicate")
    var fresh = []
    var byOriginal = ({})
    for (var i = 0; i < ordered.length; i++) {
      var n = root.items.get(ordered[i])
      var id = root.nextId
      root.doc.nextId += 1
      byOriginal[n.iid] = id
      // An image copy points at the same file: the picture is shared by every
      // board already, and duplicating one should not duplicate megabytes.
      root.items.append({
        iid: id, kind: n.kind,
        ix: n.ix + Store.DUPLICATE_OFFSET, iy: n.iy + Store.DUPLICATE_OFFSET,
        iw: n.iw, ih: n.ih, itint: n.itint, itext: n.itext, ipinned: false, isrc: n.isrc
      })
      fresh.push(id)
    }
    // A connector is copied only when both of its ends were: half of one would
    // have to guess which original it still joins.
    var rows = Store.linkRows(root.links)
    for (var j = 0; j < rows.length; j++)
      if (byOriginal[rows[j].from] !== undefined && byOriginal[rows[j].to] !== undefined)
        root.links.append({ lfrom: byOriginal[rows[j].from], lto: byOriginal[rows[j].to] })
    root.markedIds = fresh.length > 1 ? fresh : []
    root.selectedIndex = root.items.count - 1
    root.save()
    root.repaintLinks()
    root.flash(fresh.length === 1 ? "Duplicated" : "Duplicated " + fresh.length + " items")
  }

  // Indices must arrive descending: removing one shifts every index after it.
  function removeAt(indices) {
    if (indices.length === 0) return
    root.pushUndo("Delete")
    for (var k = 0; k < indices.length; k++) {
      var id = root.items.get(indices[k]).iid
      root.items.remove(indices[k])
      // Connectors cannot outlive either end.
      for (var j = root.links.count - 1; j >= 0; j--) {
        var l = root.links.get(j)
        if (l.lfrom === id || l.lto === id) root.links.remove(j)
      }
    }
    root.markedIds = []
    if (root.selectedIndex >= root.items.count) root.selectedIndex = root.items.count - 1
    root.save(true)
    root.repaintLinks()
    root.flash((indices.length === 1 ? "deleted" : indices.length + " deleted") + " · u to undo")
    if (!root.library.showing) root.focusKeys()
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
    var moves = Store.layerMoves(root.items.count, t, where)
    if (moves.length === 0) {
      root.flash(where === "front" || where === "forward" ? "already at the front" : "already at the back")
      return
    }
    root.pushUndo("Reorder")
    // The cursor follows its item rather than its position, which is about to
    // be somebody else's.
    var cursor = root.selectedIndex >= 0 ? root.items.get(root.selectedIndex).iid : -1
    for (var i = 0; i < moves.length; i++) root.items.move(moves[i].from, moves[i].to, 1)
    if (cursor >= 0) root.selectedIndex = Store.indexOfId(root.items, cursor)
    root.save()
    root.repaintLinks()
  }

  function recolorItem() {
    if (!root.canEdit) return
    var n = root.selected()
    var t = root.targets()
    if (!n || t.length === 0) return
    root.pushUndo("Colour")
    var next = Store.cycle(Store.TINTS, n.itint)
    for (var i = 0; i < t.length; i++) root.items.setProperty(t[i], "itint", next)
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
    root.pushUndo("Shape")
    var next = Store.cycle(Store.KINDS, n.kind)
    for (var i = 0; i < t.length; i++)
      if (root.items.get(t[i]).kind !== "image") root.items.setProperty(t[i], "kind", next)
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
    var found = Store.linkAt(root.links, a, b)
    if (found.outcome === "none") return
    root.pushUndo(found.outcome === "remove" ? "Remove connector" : found.outcome === "reverse" ? "Turn connector" : "Connect")
    if (found.outcome === "remove") {
      root.links.remove(found.at)
      root.save(true)
      root.repaintLinks()
      root.flash("connector removed · u to undo")
      return
    }
    if (found.outcome === "reverse") {
      root.links.setProperty(found.at, "lfrom", a)
      root.links.setProperty(found.at, "lto", b)
      root.save()
      root.repaintLinks()
      return
    }
    root.links.append({ lfrom: a, lto: b })
    root.save()
    root.repaintLinks()
  }

  function unlinkSelected() {
    if (root.selected() && root.selected().ipinned) return
    if (!root.canEdit) return
    var n = root.selected()
    if (!n) return
    var removed = false
    for (var j = root.links.count - 1; j >= 0; j--) {
      var l = root.links.get(j)
      if (l.lfrom === n.iid || l.lto === n.iid) {
        if (!removed) { root.pushUndo("Remove connectors"); removed = true }
        root.links.remove(j)
      }
    }
    if (removed) { root.save(true); root.repaintLinks(); root.flash("connectors removed · u to undo") }
  }

  // --------------------------------------------------------------- navigation
  function pointerSelect(index, additive) {
    if (additive && !root.items.get(index).ipinned) {
      if (root.markedIds.length === 0 && root.selectedIndex >= 0 && root.selectedIndex !== index
          && !root.items.get(root.selectedIndex).ipinned) root.markedIds = [root.items.get(root.selectedIndex).iid]
      root.selectedIndex = index
      root.toggleMark()
    } else if (root.isMarked(root.items.get(index).iid)) {
      root.selectedIndex = index
    } else root.selectOnly(index)
    root.editIndex = -1
    root.linkingFrom = -1
    root.focusKeys()
  }

  function moveTargets(dx, dy) {
    if (!root.canEdit) return
    var t = root.targets()
    var model = root.items
    root.batching = true
    try {
      for (var i = 0; i < t.length; i++) {
        var n = model.get(t[i])
        model.setProperty(t[i], "ix", n.ix + dx)
        model.setProperty(t[i], "iy", n.iy + dy)
      }
    } finally { root.batching = false }
    root.repaintLinks()
  }

  function resizeTargets(dx, dy) {
    if (!root.canEdit) return
    var t = root.targets()
    var model = root.items
    root.batching = true
    try {
      for (var i = 0; i < t.length; i++) {
        var n = model.get(t[i])
        model.setProperty(t[i], "iw", Math.max(root.minItemSize, n.iw + dx))
        model.setProperty(t[i], "ih", Math.max(root.minItemSize, n.ih + dy))
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
    var next = Store.nearest(root.items, root.selectedIndex, dx, dy, root.showPinned)
    if (next >= 0) root.selectedIndex = next
    root.centerOnSelected()
    root.repaintLinks()
  }

  function selectNext(stepBy) {
    if (root.items.count === 0) return
    var start = root.selectedIndex
    if (start < 0) start = stepBy > 0 ? -1 : 0
    var found = -1
    for (var i = 1; i <= root.items.count; i++) {
      var at = ((start + stepBy * i) % root.items.count + root.items.count) % root.items.count
      if ((root.items.get(at).ipinned === true) === root.showPinned) { found = at; break }
    }
    root.selectedIndex = found
    root.centerOnSelected()
    root.repaintLinks()
  }

  function nudgeSelected(dx, dy) {
    if (!root.canEdit) return
    var t = root.targets()
    if (t.length === 0) return
    root.pushUndo("Move")
    root.moveTargets(dx * root.worldStep, dy * root.worldStep)
    root.centerOnSelected()
    // Scheduled rather than written: a held key is one move, and one record.
    root.scheduleSave()
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
      var n = root.items.get(t[i])
      if (Math.max(root.minItemSize, n.iw + dx * root.worldStep) !== n.iw) { moved = true; break }
      if (Math.max(root.minItemSize, n.ih + dy * root.worldStep) !== n.ih) { moved = true; break }
    }
    if (!moved) return
    root.pushUndo("Resize")
    root.resizeTargets(dx * root.worldStep, dy * root.worldStep)
    root.centerOnSelected()
    root.scheduleSave()
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
    var b = Store.bounds(root.items)
    root.zoom = 1
    root.camX = m - (b ? b.minX : 0)
    root.camY = (root.activeBoard ? root.activeBoard.canvasTop : 0) + m - (b ? b.minY : 0)
    root.framePending = !root.activeBoard
    root.repaintGrid()
    root.repaintLinks()
  }

  // Centre on everything, so a board is never lost off-screen after a big pan.
  function fitToItems() {
    var b = Store.bounds(root.items)
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
    root.pushUndo("Typing", root.selected().iid)
    root.editIndex = root.selectedIndex
  }

  function stopEditing() {
    root.textEditor = null
    root.editIndex = -1
    root.focusKeys()
    root.save()
    // Done typing is the end of that record, however soon the next one starts.
    if (root.doc) root.doc.endEdit()
  }

  function toggleWindowMode() { root.workspace.toggleWindowMode() }

  // Forgets every edit this board remembers and starts again from it as it
  // is: text deleted from a note otherwise stays in its file's history. Asked
  // for twice, because nothing brings it back.
  property real forgetArmedAt: 0
  function forgetHistory() {
    if (!root.canEdit) return
    if (root.doc.historyHeader === "" && !root.doc.historyChecking) {
      root.flash("this board has no history to forget")
      return
    }
    if (Date.now() - root.forgetArmedAt > 6000) {
      root.forgetArmedAt = Date.now()
      root.flash("Forget every edit this board remembers? Run it again to forget them")
      return
    }
    root.forgetArmedAt = 0
    root.doc.forgetHistory()
    root.flash("History forgotten · it starts again from here")
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

  // ------------------------------------------------------------------ library
  // Browsing, naming, folders and the trash, in BoardLibrary.qml, which the
  // workspace holds: there is one boards folder, however many panes.
  readonly property BoardLibrary library: root.workspace.library

  // The two ways in that are commands, so the palette and the keys can name
  // them: what is open is saved before the library is looked at.
  function openBrowser() {
    root.flushSave()
    root.library.show()
  }

  // ------------------------------------------------------------------ storage
  // The document saves; the pane says when. ctrl+s with a conflict outstanding
  // is not a save: it is the moment someone is asking about it, which is when
  // the choices are worth putting on screen.
  function scheduleSave() {
    if (!root.doc) return
    root.noteEdit()
    root.doc.scheduleSave()
  }
  function flushSave() {
    root.library.retryTrashIndex()
    if (root.diskChanged) { root.decideConflict(); return }
    if (root.doc) root.doc.flushSave()
  }
  function save(allowEmpty) {
    if (!root.doc) return
    root.noteEdit()
    root.doc.save(allowEmpty)
  }

  // ------------------------------------------------------------ two panes
  // The cursor is a row, and a row is only an item until someone else deletes
  // or reorders one. So the pane remembers which item its cursor is on, and
  // when the other pane edits the board it finds that item again — or lets
  // go, if it is gone. Marks are ids already; the ones that no longer name
  // anything are dropped so the count they show is true.
  property int cursorId: -1
  onSelectedIndexChanged: root.cursorId = root.idAt(root.selectedIndex)
  function idAt(index) {
    return index >= 0 && index < root.items.count ? root.items.get(index).iid : -1
  }

  // Said at every save, which is where every edit ends. Its own cursor first:
  // an edit here can have moved the row under it, and what it now points at is
  // what it is on.
  function noteEdit() {
    root.cursorId = root.idAt(root.selectedIndex)
    root.doc.noteEdit(root)
  }

  function followEdit() {
    var at = root.cursorId < 0 ? -1 : Store.indexOfId(root.items, root.cursorId)
    if (at !== root.selectedIndex) root.selectedIndex = at
    if (root.markedIds.length > 0) {
      var present = Store.idIndex(root.items)
      var kept = root.markedIds.filter(function (id) { return present[id] !== undefined })
      if (kept.length !== root.markedIds.length) root.markedIds = kept
    }
    if (root.linkingFrom >= 0 && Store.indexOfId(root.items, root.linkingFrom) < 0) root.linkingFrom = -1
    root.repaintLinks()
  }

  Connections {
    target: root.doc
    function onEdited(by) { if (by !== root) root.followEdit() }
  }

  // The keyboard is going to the other pane. What was half done here ends the
  // way Escape would end it, typing included, so two views of one board never
  // both have an editor open; what is selected stays for when it comes back.
  function deactivate() {
    if (root.editIndex >= 0) root.stopEditing()
    if (root.finding) root.endFind()
    if (root.paletteVisible) root.endPalette()
    root.closeMenu()
    root.arranging = false
    root.conflictVisible = false
    root.helpVisible = false
    if (root.linkingFrom >= 0) { root.linkingFrom = -1; root.repaintLinks() }
  }

  function activate() { root.workspace.activate(root) }
  function toggleSplit(layout) { root.workspace.toggleSplit(layout) }
  function otherPane() { root.workspace.focusOther() }
  function evenSplit() { root.workspace.evenSplit() }
  // Which board this pane shows is the workspace's to change: another pane may
  // already have that board open, or still be showing this one.
  function openBoard(path, fresh) { root.workspace.openInPane(root, path, fresh) }

  // The document's board is about to be a different one, or the same one read
  // again: what was selected on it means nothing now. Leaving it also ends
  // whatever was half done.
  function resetSelection(endModes) {
    root.markedIds = []
    root.showPinned = false
    root.selectedIndex = -1
    if (!endModes) return
    root.editIndex = -1
    root.linkingFrom = -1
  }

  // The surface is going away. What was half done on it ends; the board and
  // the camera stay where they were for when it comes back.
  function closeView() {
    root.stopPlaying()
    root.markedIds = []
    root.showPinned = false
    root.selectedIndex = -1
    root.editIndex = -1
    root.linkingFrom = -1
    root.helpVisible = false
  }

  function dismiss() { root.workspace.dismiss() }

  // ------------------------------------------------------------ the timeline
  // `t`: the board's history, a step at a time. The pane keeps which step it
  // shows as that record's number rather than a place in a list, so edits
  // arriving and the oldest leaving do not move it. Live is a state of its
  // own: following the board as it is, rather than the latest step taken.
  property bool timeline: false
  property bool timelineLive: true
  property int timelineRecord: 0
  readonly property bool lookingBack: root.timeline && !root.timelineLive
  // The document whose replay this pane holds, so leaving lets go of that one
  // even when the pane has already moved to another board.
  property var replayDoc: null
  property bool playing: false
  property real playSpeed: 1
  property int playEnd: 0
  property int scrubWanted: 0

  // The first and last steps there are: the number of the record before the
  // first, which is where the history starts, and of the last.
  function firstRecord() {
    var r = root.replayDoc && root.replayDoc.replay ? root.replayDoc.replay.h.records : []
    return r.length > 0 ? r[0].i - 1 : root.replayDoc ? root.replayDoc.historyLast : 0
  }
  function lastRecord() {
    var r = root.replayDoc && root.replayDoc.replay ? root.replayDoc.replay.h.records : []
    return r.length > 0 ? r[r.length - 1].i : root.firstRecord()
  }

  function toggleTimeline() {
    if (root.timeline) root.leaveTimeline()
    else root.enterTimeline()
  }

  function enterTimeline() {
    if (!root.doc || root.timeline) return
    if (root.editIndex >= 0) root.stopEditing()
    root.endFind()
    root.arranging = false
    root.linkingFrom = -1
    var why = root.doc.openReplay()
    if (why !== "") { root.flash(why); return }
    root.replayDoc = root.doc
    root.timeline = true
    root.timelineLive = true
    root.timelineRecord = root.lastRecord()
    root.statusText = ""
  }

  function leaveTimeline() {
    if (!root.timeline) return
    root.stopPlaying()
    var wasBack = root.lookingBack
    root.timeline = false
    root.timelineLive = true
    if (root.replayDoc) root.replayDoc.closeReplay()
    root.replayDoc = null
    pastItems.clear()
    pastLinks.clear()
    // The cursor and the marks were rows of the earlier board.
    if (wasBack) root.resetSelection(true)
    root.repaintLinks()
  }

  // Back to the board as it is, still in the timeline. Escape again leaves it.
  function timelineNow() {
    root.stopPlaying()
    if (!root.lookingBack) return
    root.timelineLive = true
    root.timelineRecord = root.lastRecord()
    root.resetSelection(true)
    root.repaintLinks()
  }

  function timelineBack() {
    if (root.lookingBack) root.timelineNow()
    else root.leaveTimeline()
  }

  // Shows the board as it was after record `n`, held within the steps there
  // are. The first step back from the board as it is clears what was selected
  // on it: those were rows of a board that is not the one on screen.
  function showRecord(n) {
    if (!root.timeline || !root.replayDoc || !root.replayDoc.replay) return
    var first = root.firstRecord(), last = root.lastRecord()
    var at = Math.max(first, Math.min(last, Math.round(n)))
    var state = root.replayDoc.replayState(at - first)
    if (!state) return
    // The live board refuses a note too long to lay out without holding the
    // shell up; an earlier one is held to the same, whatever its file says.
    if (Store.overlongNote(state.items) >= 0) {
      root.stopPlaying()
      root.flash("a note at step " + (at - first) + " is too long to show")
      return
    }
    if (!root.lookingBack) root.resetSelection(true)
    root.timelineRecord = at
    root.timelineLive = false
    Store.syncItems(pastItems, state.items)
    pastLinks.clear()
    for (var i = 0; i < state.links.length; i++) pastLinks.append({ lfrom: state.links[i].from, lto: state.links[i].to })
    if (root.selectedIndex >= pastItems.count) root.selectedIndex = -1
    root.repaintLinks()
  }

  // From the board as it is, a step back is the board before the latest edit:
  // the latest edit is what is on screen already.
  function timelineStep(by) {
    root.stopPlaying()
    if (root.lookingBack) { root.showRecord(root.timelineRecord + by); return }
    if (by > 0) { root.flash("this is the board as it is now"); return }
    if (root.lastRecord() === root.firstRecord()) { root.flash("nothing to step back to yet"); return }
    root.showRecord(root.lastRecord() + by)
  }

  function timelineFirst() { root.stopPlaying(); root.showRecord(root.firstRecord()) }
  function timelineLatest() { root.stopPlaying(); root.showRecord(root.lastRecord()) }

  // Plays forward a step at a time, one a second at 1x however long the edits
  // took. From the board as it is, or from the last step, it starts again at
  // the beginning; either way it stops at the step that was last when it
  // started, so edits arriving meanwhile do not keep it going.
  function togglePlay() {
    if (!root.timeline) return
    if (root.playing) { root.stopPlaying(); return }
    var first = root.firstRecord(), last = root.lastRecord()
    if (last === first) { root.flash("nothing to play yet"); return }
    if (!root.lookingBack || root.timelineRecord >= last) root.showRecord(first)
    root.playEnd = last
    root.playing = true
  }

  function stopPlaying() { root.playing = false }

  function playStep() {
    if (!root.playing) return
    if (root.timelineRecord >= root.playEnd || !root.lookingBack) { root.stopPlaying(); return }
    root.showRecord(root.timelineRecord + 1)
    if (root.timelineRecord >= root.playEnd) root.stopPlaying()
  }

  function setPlaySpeed(speed) {
    if ([0.5, 1, 2, 4].indexOf(speed) < 0) return
    root.playSpeed = speed
    root.flash("playing at " + speed + "x")
  }

  Timer {
    id: player
    interval: 1000 / root.playSpeed
    repeat: true
    running: root.playing
    onTriggered: root.playStep()
  }

  // A pointer on the strip: where along it, from 0 to 1. Asked for as often as
  // the pointer moves and shown at most once a frame, the latest asked for.
  function scrubTo(fraction) {
    if (!root.timeline) return
    root.stopPlaying()
    var first = root.firstRecord(), last = root.lastRecord()
    root.scrubWanted = Math.round(first + Math.max(0, Math.min(1, fraction)) * (last - first))
    if (!scrubber.running) scrubber.start()
  }
  function scrubNow() { root.showRecord(root.scrubWanted) }
  Timer { id: scrubber; interval: 16; repeat: false; onTriggered: root.scrubNow() }

  // The replay changed under the pane: edits arrived, the oldest were trimmed,
  // or the history was replaced. Where it was is kept if it is still there.
  function followReplay() {
    if (!root.timeline) return
    if (!root.replayDoc || !root.replayDoc.replay) {
      root.leaveTimeline()
      root.flash("this board's history was replaced · the timeline closed")
      return
    }
    if (!root.lookingBack) { root.timelineRecord = root.lastRecord(); return }
    if (root.timelineRecord < root.firstRecord()) {
      root.flash("that step was among the oldest, which have left the history")
      root.showRecord(root.firstRecord())
    } else root.showRecord(root.timelineRecord)
  }
  Connections {
    target: root.replayDoc
    function onReplayRevisionChanged() { root.followReplay() }
  }
  onDocChanged: if (root.timeline && root.replayDoc !== root.doc) root.leaveTimeline()

  // What the strip says, and where along it the step is. Both name what they
  // follow, so they are worked out again when it changes.
  readonly property string timelineSays: root.timeline
    ? root.timelineText(root.timelineRecord, root.timelineLive, root.playing, root.playSpeed,
                        root.replayDoc ? root.replayDoc.replayRevision : 0) : ""
  readonly property real timelineFraction: root.timeline
    ? root.timelinePlace(root.timelineRecord, root.timelineLive,
                         root.replayDoc ? root.replayDoc.replayRevision : 0) : 0

  function timelineText(record, live, playing, speed, revision) {
    if (!root.replayDoc || !root.replayDoc.replay) return ""
    var first = root.firstRecord(), last = root.lastRecord()
    var steps = last - first
    if (live) return "now · " + steps + (steps === 1 ? " step" : " steps") + " back to where the history starts"
    var h = root.replayDoc.replay.h
    var shown = record > first ? h.records[record - first - 1] : null
    return "step " + (record - first) + " of " + steps + " · " + History.stepLabel(shown, h.start, Date.now())
      + (playing ? " · playing " + speed + "x" : "")
  }

  function timelinePlace(record, live, revision) {
    if (live) return 1
    var first = root.firstRecord(), last = root.lastRecord()
    return last > first ? (record - first) / (last - first) : 1
  }

  // `T`: an earlier version beside the board as it is now. The other pane
  // shows this board live; this one steps back one edit, or stays where it
  // is if it is already looking back. Another board in the other pane is
  // replaced only when asked twice, because that is a pane someone chose.
  property real compareArmedAt: 0
  function compareWithCurrent() {
    if (!root.doc) return
    var other = root.workspace.otherOf(root)
    if (other && other.doc !== root.doc) {
      if (Date.now() - root.compareArmedAt > 6000) {
        root.compareArmedAt = Date.now()
        root.flash("the other pane shows " + other.boardTitle + " · run it again to put this board there instead")
        return
      }
      root.compareArmedAt = 0
      other.openBoard(root.currentBoard, false)
    }
    if (!other) {
      root.workspace.toggleSplit("side-by-side")
      root.workspace.activate(root)
      other = root.workspace.otherOf(root)
    }
    if (other && other.timeline) other.leaveTimeline()
    if (!root.timeline) root.enterTimeline()
    if (!root.timeline) return
    if (!root.lookingBack) root.showRecord(root.lastRecord() - 1)
    root.flash("an earlier version here, the board as it is now in the other pane")
  }

  // ------------------------------------------------------- the workspace's
  readonly property string dataDir: root.workspace.dataDir
  readonly property string boardsDir: root.workspace.boardsDir
  readonly property string imagesDir: root.workspace.imagesDir
  function imagePath(name) { return root.workspace.imagePath(name) }

  readonly property string currentBoard: root.doc ? root.doc.currentBoard : ""
  readonly property string boardTitle: root.doc ? root.doc.boardTitle : ""

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
}
