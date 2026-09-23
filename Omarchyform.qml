pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
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
                                            root.isLight ? 0.28 : 0.18)
  readonly property int minItemSize: Store.MIN_SIZE

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
    return Qt.rgba(c.r, c.g, c.b, a)
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
  property int editIndex: -1      // -1 means normal mode: every key is a command
  property int linkingFrom: -1    // id of the first end while connecting
  property bool helpVisible: false
  property bool windowMode: false

  // Views consume session state; loading and save coordination live together.
  readonly property bool boardLoaded: session.boardLoaded
  readonly property bool damaged: session.damaged
  readonly property string saveError: session.saveError
  readonly property var pendingBoard: session.pendingBoard
  readonly property bool canEdit: session.canEdit
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

  readonly property var browserRows: Store.filterEntries(root.browserEntries, root.browserDir, root.browserQuery)

  property var activeBoard: null
  property var boardScreen: null
  readonly property real viewW: root.activeBoard ? root.activeBoard.width : 1920
  readonly property real viewH: root.activeBoard ? root.activeBoard.height : 1080

  function repaintGrid() { if (root.activeBoard) root.activeBoard.repaintGrid() }
  function repaintLinks() { if (root.activeBoard) root.activeBoard.repaintLinks() }
  function focusKeys() { if (root.activeBoard) root.activeBoard.focusKeys() }
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
    if (s.length > 100) s.shift()
    root.undoStack = s
    root.redoStack = []   // a new edit drops the redo branch
  }

  function restore(snap) {
    if (!root.canEdit) return
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
    root.pushUndo()
    var w = kind === "note" ? 180 : 160
    var h = kind === "note" ? 140 : 110
    itemModel.append({
      iid: root.nextId, kind: kind,
      ix: wx - w / 2, iy: wy - h / 2, iw: w, ih: h,
      itint: Store.TINTS[root.nextColor % Store.TINTS.length],
      itext: ""
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
    if (index < 0 || index >= itemModel.count) return
    root.pushUndo()
    var id = itemModel.get(index).iid
    itemModel.remove(index)
    // Connectors cannot outlive either end.
    for (var j = linkModel.count - 1; j >= 0; j--) {
      var l = linkModel.get(j)
      if (l.lfrom === id || l.lto === id) linkModel.remove(j)
    }
    if (root.selectedIndex >= itemModel.count) root.selectedIndex = itemModel.count - 1
    root.save(true)
    root.repaintLinks()
  }

  function recolorItem() {
    if (!root.canEdit) return
    var n = root.selected()
    if (!n) return
    root.pushUndo()
    itemModel.setProperty(root.selectedIndex, "itint", Store.cycle(Store.TINTS, n.itint))
    root.save()
  }

  function cycleKind() {
    if (!root.canEdit) return
    var n = root.selected()
    if (!n) return
    root.pushUndo()
    itemModel.setProperty(root.selectedIndex, "kind", Store.cycle(Store.KINDS, n.kind))
    root.save()
  }

  // ------------------------------------------------------------------ linking
  function toggleLinking() {
    var n = root.selected()
    if (!n) return
    if (root.linkingFrom < 0) { root.linkingFrom = n.iid; root.repaintLinks(); return }
    if (n.iid !== root.linkingFrom) root.addLink(root.linkingFrom, n.iid)
    root.linkingFrom = -1
    root.repaintLinks()
  }

  function addLink(a, b) {
    if (!root.canEdit) return
    root.pushUndo()
    for (var i = 0; i < linkModel.count; i++) {
      var l = linkModel.get(i)
      // A connector is undirected, so drawing it again removes it.
      if ((l.lfrom === a && l.lto === b) || (l.lfrom === b && l.lto === a)) {
        linkModel.remove(i)
        root.save(true)
        root.repaintLinks()
        return
      }
    }
    linkModel.append({ lfrom: a, lto: b })
    root.save()
    root.repaintLinks()
  }

  function unlinkSelected() {
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
    if (removed) { root.save(true); root.repaintLinks() }
  }

  // --------------------------------------------------------------- navigation
  function selectOnly(index) {
    root.selectedIndex = index
    root.editIndex = -1
    root.linkingFrom = -1
    root.repaintLinks()
  }

  function move(dx, dy, carry) {
    if (carry) return root.nudgeSelected(dx, dy)
    if (root.selectedIndex < 0) return root.panBy(-dx * 120, -dy * 120)
    var next = Store.nearest(itemModel, root.selectedIndex, dx, dy)
    if (next >= 0) root.selectedIndex = next
    root.centerOnSelected()
    root.repaintLinks()
  }

  function selectNext(stepBy) {
    if (itemModel.count === 0) return
    root.selectedIndex = ((root.selectedIndex + stepBy) % itemModel.count + itemModel.count) % itemModel.count
    root.centerOnSelected()
    root.repaintLinks()
  }

  function nudgeSelected(dx, dy) {
    if (!root.canEdit) return
    var n = root.selected()
    if (!n) return
    root.pushUndo()
    itemModel.setProperty(root.selectedIndex, "ix", n.ix + dx * 40)
    itemModel.setProperty(root.selectedIndex, "iy", n.iy + dy * 40)
    root.centerOnSelected()
    root.save()
  }

  // Keep the selected item on screen without yanking the view around when it
  // is already comfortably visible.
  function centerOnSelected() {
    var n = root.selected()
    if (!n) return
    var m = 60
    var sx = root.toScreenX(n.ix), sy = root.toScreenY(n.iy)
    var sw = n.iw * root.zoom, sh = n.ih * root.zoom
    if (sx < m) root.camX += m - sx
    else if (sx + sw > root.viewW - m) root.camX -= (sx + sw) - (root.viewW - m)
    if (sy < m) root.camY += m - sy
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
    root.zoom = Math.max(0.2, Math.min(1, Math.min(root.viewW / w, root.viewH / h)))
    root.camX = root.viewW / 2 - ((b.minX + b.maxX) / 2) * root.zoom
    root.camY = root.viewH / 2 - ((b.minY + b.maxY) / 2) * root.zoom
    root.repaintGrid()
    root.repaintLinks()
  }

  // -------------------------------------------------------------------- modes
  function editSelected() {
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
    root.browserVisible = true
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
    var e = root.browserCurrent()
    if (!e) return
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
    var name = root.browserInput.trim()
    var action = root.browserAction
    root.browserPrompt = ""
    root.browserInput = ""
    root.browserAction = ""
    if (!Store.nameIsValid(name)) return

    if (action === "board") {
      var path = Store.uniquePath(root.browserEntries, root.browserDir, name, false)
      root.createBoard(path)
    } else if (action === "folder") {
      var dir = Store.uniquePath(root.browserEntries, root.browserDir, name, true)
      mkdirProc.command = ["mkdir", "-p", root.boardsDir + "/" + dir]
      mkdirProc.running = true
    } else if (action === "rename") {
      root.flushSave()
      if (session.busy || root.saveError !== "") {
        root.browserMessage = "finish saving before renaming; try again"
        return
      }
      var e = root.browserCurrent()
      if (!e) return
      var target = Store.uniquePath(root.browserEntries, Store.parentOf(e.path), name, e.dir)
      moveProc.command = ["mv", "-n", root.boardsDir + "/" + e.path, root.boardsDir + "/" + target]
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
    var e = root.browserCurrent()
    if (!e) return
    // Refuse to delete the open board, or the folder it lives in.
    if (root.holdsOpenBoard(e)) {
      root.browserMessage = "that is the board you have open — switch away first"
      return
    }
    // rm -rf is not something to do on a single keystroke.
    if (root.pendingDelete !== e.path) {
      root.pendingDelete = e.path
      root.browserMessage = "press x again to delete " + Store.displayName(e)
                            + (e.dir ? "/ and everything in it" : "")
      return
    }
    root.pendingDelete = ""
    root.browserMessage = ""
    removeProc.command = e.dir
      ? ["rm", "-rf", "--", root.boardsDir + "/" + e.path]
      : ["rm", "-f", "--", root.boardsDir + "/" + e.path]
    removeProc.running = true
  }

  function browserKey(event) {
    var text = event.text
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0

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
      if (root.browserSearching) {
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
    else if (text === "a") root.prompt("board", "new board:", "")
    else if (text === "A") root.prompt("folder", "new folder:", "")
    else if (text === "r") {
      var e = root.browserCurrent()
      if (e) root.prompt("rename", "rename to:", Store.displayName(e))
    }
    else if (text === "x") root.deleteCurrent()
    else if (text === "g") { root.browserIndex = 0 }
    else if (text === "G") { root.browserIndex = root.browserRows.length - 1; root.browserClamp() }
    else return
    event.accepted = true
  }

  // ------------------------------------------------------------------ storage
  BoardSession { id: session; ctl: root }

  function scheduleSave() { session.scheduleSave() }
  function flushSave() { session.flushSave() }
  function save(allowEmpty) { session.save(allowEmpty) }
  function openBoard(path, fresh) { session.openBoard(path, fresh) }

  function writeState() {
    stateFile.setText(JSON.stringify({
      version: 1,
      lastBoard: root.currentBoard,
      windowMode: root.windowMode
    }, null, 2) + "\n")
  }

  // Which board was open last time, and whether it was windowed. Kept out of
  // the board files so the same board can be opened on two machines without
  // dragging one machine's window preference along with it.
  function applyState(raw) {
    var st = null
    try { st = JSON.parse(raw) } catch (e) { st = null }
    if (st && st.lastBoard) root.currentBoard = String(st.lastBoard)
    if (st) root.windowMode = st.windowMode === true
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

  function open(payloadJson) {
    root.boardScreen = root.focusedScreen()
    root.opened = true
    Qt.callLater(function () {
      root.focusKeys()
      root.repaintGrid()
      root.repaintLinks()
    })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.save()
    root.opened = false
    root.selectedIndex = -1
    root.editIndex = -1
    root.linkingFrom = -1
    root.helpVisible = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "thepixelgardener.omarchyform")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchyform"
  readonly property string boardsDir: root.dataDir + "/boards"
  readonly property string legacyPath: root.dataDir + "/board.json"
  readonly property string statePath: root.dataDir + "/state.json"

  // Relative to boardsDir, e.g. "work/project-a.json".
  property string currentBoard: "board.json"
  readonly property string boardPath: root.boardsDir + "/" + root.currentBoard
  readonly property string boardTitle: Store.displayName({ path: root.currentBoard, dir: false })

  // The boards directory has to exist before the first atomic write, otherwise
  // the board silently fails to save on a fresh install. A board from before
  // there were folders is copied in rather than moved, so the old file stays
  // put as a fallback.
  Process {
    id: initProc
    running: true
    command: ["mkdir", "-p", root.boardsDir]
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
    onExited: root.rescan()
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
      root.rescan()
    }
  }

  Process {
    id: removeProc
    onExited: root.rescan()
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
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
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
