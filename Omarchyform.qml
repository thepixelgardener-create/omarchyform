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
  // Every read of the shell's internal singletons goes through a guard: they
  // are not a versioned API, and a rename upstream should cost a wrong colour,
  // not a board that refuses to open. (An import that disappears entirely is
  // still fatal — QML has no optional imports.)
  function token(read, fallback) {
    try {
      var v = read()
      return v === undefined || v === null ? fallback : v
    } catch (e) {
      return fallback
    }
  }
  function sp(n) { return root.token(function () { return Style.space(n) }, n) }

  property color canvasBackground: root.token(function () { return Color.background }, "#101315")
  property color foreground: root.token(function () { return Color.foreground }, "#CACCCC")
  property color accent: root.token(function () { return Color.accent }, "#CACCCC")
  property color urgent: root.token(function () { return Color.urgent }, "#A55555")
  property color muted: root.token(function () { return Color.muted }, "#707880")

  // The theme's own font, at the theme's own sizes, so the board follows
  // `omarchy display text size` like everything else on the desktop.
  property string fontFamily: root.token(function () { return Style.font.family },
                                          root.token(function () { return Style.font.menuFamily }, "monospace"))
  readonly property int fontBody: root.token(function () { return Style.font.body }, 12)
  readonly property int fontSubtitle: root.token(function () { return Style.font.subtitle }, 13)
  readonly property int fontHeading: root.token(function () { return Style.font.heading }, 16)

  // Omarchy is square-cornered with hairline borders by default; both come
  // from the theme rather than being invented here.
  readonly property int cornerRadius: root.token(function () { return Style.cornerRadius }, 0)
  readonly property int borderWidth: Math.max(1, root.token(function () { return Style.normalBorderWidth }, 1))

  // Day or night is a property of the theme, not a setting of ours: Omarchy
  // themes declare `mode` in colors.toml. Luminance is only the fallback for a
  // third-party theme that leaves it out.
  readonly property string themePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
  property string themeMode: ""
  readonly property bool isLight: root.themeMode !== ""
    ? root.themeMode === "light"
    : Store.isLightColor(root.canvasBackground.r, root.canvasBackground.g, root.canvasBackground.b)

  // A wash reads differently on paper than on ink, so the weights differ.
  readonly property color dotColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                                            root.isLight ? 0.13 : 0.08)
  readonly property int minItemSize: Store.MIN_SIZE

  // The step is what the eye sees, so it is divided by the zoom: otherwise one
  // press moves an eighth of the distance when zoomed out and four times it
  // when zoomed in.
  readonly property real worldStep: root.step / root.zoom

  // An item is a translucent wash of a theme role plus a hairline of the same
  // role, which is how the rest of the shell draws a surface.
  function tintColor(tint) {
    if (tint === "accent") return root.accent
    if (tint === "urgent") return root.urgent
    if (tint === "muted") return root.muted
    return root.foreground
  }
  function tintFill(tint, strong) {
    var c = root.tintColor(tint)
    var a = root.isLight ? (strong ? 0.20 : 0.10) : (strong ? 0.22 : 0.12)
    return Qt.rgba(c.r * a + root.canvasBackground.r * (1-a), c.g * a + root.canvasBackground.g * (1-a), c.b * a + root.canvasBackground.b * (1-a), 1)
  }
  function tintBorder(tint, strong) {
    var c = root.tintColor(tint)
    var a = strong ? 1.0 : (root.isLight ? 0.55 : 0.45)
    return Qt.rgba(c.r, c.g, c.b, a)
  }

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
  property int editIndex: -1      // -1 means normal mode: every key is a command
  property int linkingFrom: -1    // id of the first end while connecting
  property bool helpVisible: false
  property bool showPinned: false
  property string pendingFirstNote: ""
  property bool launchNewBoard: false
  property bool imageBusy: false
  readonly property bool exchangeBusy: exchange.busy
  readonly property bool dialogOpen: exchange.dialogOpen
  readonly property string boardState: root.damaged ? "Read only" : root.saveError !== "" ? "Save failed" : root.saving ? "Saving…" : "Saved locally"
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
    root.flash("Text pasted · enter to edit")
    root.focusKeys()
  }

  // Sizing needs the picture loaded, and only an open board has a scene that
  // will load one, so the board measures it and calls back.
  function imagePasted(name) {
    if (root.activeBoard) root.activeBoard.probeImage(name)
    else root.pasteImage(name, 0, 0)
  }

  function pasteImage(name, naturalWidth, naturalHeight) {
    if (!root.canEdit || !Store.imageIsValid(name)) return
    var w = naturalWidth > 0 ? naturalWidth : 320
    var h = naturalHeight > 0 ? naturalHeight : 240
    // Big enough to see, small enough that a phone screenshot does not arrive
    // taller than the board. Aspect is kept, so nothing is squashed.
    var fit = Math.min(1, 360 / Math.max(w, h))
    root.addItem("image", root.toWorldX(root.viewW / 2), root.toWorldY(root.viewH / 2))
    itemModel.setProperty(root.selectedIndex, "isrc", name)
    itemModel.setProperty(root.selectedIndex, "iw", Math.max(root.minItemSize, Math.round(w * fit)))
    itemModel.setProperty(root.selectedIndex, "ih", Math.max(root.minItemSize, Math.round(h * fit)))
    root.save()
    root.flash(naturalWidth > 0 ? "Image pasted" : "Image pasted · it could not be read, so the size is a guess")
    root.focusKeys()
  }

  function pasteClipboard() { exchange.paste() }
  function importBoard() { exchange.choose("import") }
  function exportBoard() { exchange.choose("json") }
  function choosePng() { exchange.choose("png") }
  function exportPng(path) { if (root.activeBoard) root.activeBoard.exportPng(path) }

  function finishPng(path) {
    imagePublish.command = root.fileCommand("export", [root.dataDir + "/.image-export.png", path, root.dataDir])
    imagePublish.running = true
  }
  Process {
    id: imagePublish
    onExited: function(code) {
      root.imageBusy = false
      root.flash(code === 0 ? "PNG saved · full board, without controls" : "Could not save PNG; choose a location outside the app data folder")
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

  BoardExchange {
    id: exchange
    ctl: root
    onCreated: function(path, editFirst) {
      if (editFirst) root.pendingFirstNote = path
      root.openBoard(path, false)
      root.rescan()
      root.flash(editFirst ? "New board · F2 to name it" : "Board imported")
    }
    onFinished: function(message) { root.flash(message) }
  }

  // A line that says what just happened and then goes away. Deleting is one
  // keystroke, so it should at least say so, and say how to take it back.
  property string statusText: ""
  function flash(text) {
    root.statusText = text
    statusTimer.restart()
  }

  // Configurable from the bar widget's settings, and remembered in state.json
  // so opening from the keyboard uses the same values.
  property int autosaveMs: 700
  property int step: 40
  property bool showGrid: true
  property bool startWindowed: false
  property bool windowMode: false

  // Views consume session state; loading and save coordination live together.
  readonly property bool boardLoaded: session.boardLoaded
  readonly property bool damaged: session.damaged
  readonly property string damageReason: session.damageReason
  readonly property string saveError: session.saveError
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
  property var boardScreen: null
  readonly property real viewW: root.activeBoard ? root.activeBoard.width : 1920
  readonly property real viewH: root.activeBoard ? root.activeBoard.height : 1080

  function repaintGrid() { if (root.activeBoard) root.activeBoard.repaintGrid() }
  function repaintLinks() { if (root.activeBoard) root.activeBoard.repaintLinks() }
  function focusKeys() { if (root.activeBoard) root.activeBoard.focusKeys() }
  function isMarked(id) { return root.markedIds.indexOf(id) >= 0 }

  // What an operation applies to: everything marked, or the cursor alone.
  // Descending, so removing by index cannot shift the ones still to come.
  function targets() {
    var out = []
    if (root.markedIds.length === 0)
      return root.selectedIndex >= 0 && !itemModel.get(root.selectedIndex).ipinned ? [root.selectedIndex] : []
    for (var i = itemModel.count - 1; i >= 0; i--)
      if (!itemModel.get(i).ipinned && root.isMarked(itemModel.get(i).iid)) out.push(i)
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
    for (var i = 0; i < itemModel.count; i++)
      if (!itemModel.get(i).ipinned) m.push(itemModel.get(i).iid)
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
    for (var i = 0; i < ids.length; i++)
      if (m.indexOf(ids[i]) < 0) m.push(ids[i])
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
    if (root.linkingFrom < 0) { root.linkingFrom = n.iid; root.repaintLinks(); return }
    if (n.iid !== root.linkingFrom) root.addLink(root.linkingFrom, n.iid)
    root.linkingFrom = -1
    root.repaintLinks()
  }

  // Connectors point somewhere: an arrow carries a meaning a plain line
  // cannot. Only one runs between any pair, so drawing the same pair again
  // either turns it round or takes it away.
  function addLink(a, b) {
    if (!root.canEdit) return
    root.pushUndo()
    for (var i = 0; i < linkModel.count; i++) {
      var l = linkModel.get(i)
      if (l.lfrom === a && l.lto === b) {
        linkModel.remove(i)
        root.save(true)
        root.repaintLinks()
        root.flash("connector removed · u to undo")
        return
      }
      if (l.lfrom === b && l.lto === a) {
        linkModel.setProperty(i, "lfrom", a)
        linkModel.setProperty(i, "lto", b)
        root.save()
        root.repaintLinks()
        return
      }
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
    for (var i = 0; i < t.length; i++) {
      var n = itemModel.get(t[i])
      itemModel.setProperty(t[i], "ix", n.ix + dx)
      itemModel.setProperty(t[i], "iy", n.iy + dy)
    }
  }

  function resizeTargets(dx, dy) {
    if (!root.canEdit) return
    var t = root.targets()
    for (var i = 0; i < t.length; i++) {
      var n = itemModel.get(t[i])
      itemModel.setProperty(t[i], "iw", Math.max(root.minItemSize, n.iw + dx))
      itemModel.setProperty(t[i], "ih", Math.max(root.minItemSize, n.ih + dy))
    }
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
    var topInset = root.activeBoard ? root.activeBoard.headerHeight + 24 : m
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

  function resetView() {
    root.camX = 0
    root.camY = 0
    root.zoom = 1
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
    root.zoom = Math.max(0.2, Math.min(1, Math.min(root.viewW / w, Math.max(100, root.viewH - (root.activeBoard ? root.activeBoard.headerHeight : 0)) / h)))
    root.camX = root.viewW / 2 - ((b.minX + b.maxX) / 2) * root.zoom
    root.camY = ((root.activeBoard ? root.activeBoard.headerHeight : 0) + root.viewH) / 2 - ((b.minY + b.maxY) / 2) * root.zoom
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
    else if (root.showPinned) { root.showPinned = false; root.selectedIndex = -1 }
    else if (root.clearMarks()) root.flash("marks cleared")
    else if (root.linkingFrom >= 0) { root.linkingFrom = -1; root.repaintLinks() }
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
      if (event.key === Qt.Key_Escape) { root.browserPrompt = ""; root.browserInput = ""; root.browserAction = "" }
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
  function flushSave() { root.retryTrashIndex(); session.flushSave() }
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
    var monitor = root.token(function () { return Hyprland.focusedMonitor }, null)
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
    if (typeof st.startWindowed === "boolean") root.startWindowed = st.startWindowed
    return true
  }

  function open(payloadJson) {
    var request = null
    try { request = JSON.parse(payloadJson || "{}") } catch (e) {}
    if (request && request.action === "new") root.launchNewBoard = true
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
    root.flushSave()
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

  // The boards directory has to exist before the first atomic write, otherwise
  // the board silently fails to save on a fresh install. A board from before
  // there were folders is copied in rather than moved, so the old file stays
  // put as a fallback.
  Process {
    id: initProc
    running: true
    command: ["mkdir", "-p", root.boardsDir, root.backupsDir, root.trashDir, root.imagesDir]
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

  FileView {
    id: themeFile
    path: root.themePath
    watchChanges: true
    printErrors: false
    onLoaded: root.themeMode = Store.parseThemeMode(text())
    onLoadFailed: root.themeMode = ""
    onFileChanged: reload()
  }

  // The current theme is a symlink, so a switch retargets it rather than
  // editing the file a watcher is holding. The shell updates its own colours
  // on every theme change, so follow that instead.
  onCanvasBackgroundChanged: themeFile.reload()

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
    color: root.canvasBackground
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
