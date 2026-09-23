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

  // save() is a no-op until the file has been read, and refuses to shrink a
  // non-empty board to nothing unless a delete asked for it.
  property bool boardLoaded: false
  property int lastSavedCount: -1

  property var undoStack: []
  property var redoStack: []

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
    Store.fillItems(itemModel, snap.items)
    Store.fillLinks(linkModel, itemModel, snap.links)
    root.nextId = snap.nextId
    if (root.selectedIndex >= itemModel.count) root.selectedIndex = itemModel.count - 1
    root.editIndex = -1
    root.linkingFrom = -1
    root.repaintLinks()
    // Rebuilding the model tears down every delegate, which drops keyboard
    // focus; without this a second undo never reaches the key handler.
    root.focusKeys()
  }

  function undo() {
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
    var n = root.selected()
    if (!n) return
    root.pushUndo()
    itemModel.setProperty(root.selectedIndex, "itint", Store.cycle(Store.TINTS, n.itint))
    root.save()
  }

  function cycleKind() {
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
    root.save()
  }

  // Escape unwinds one layer at a time rather than closing outright.
  function back() {
    if (root.helpVisible) root.helpVisible = false
    else if (root.linkingFrom >= 0) { root.linkingFrom = -1; root.repaintLinks() }
    else root.dismiss()
  }

  // ------------------------------------------------------------------ storage
  function save(allowEmpty) {
    if (!root.boardLoaded) return
    if (itemModel.count === 0 && root.lastSavedCount > 0 && allowEmpty !== true) return
    boardFile.setText(Store.writeFile(itemModel, linkModel, root.nextId, root.windowMode))
    root.lastSavedCount = itemModel.count
  }

  function loadBoard(raw) {
    var data = Store.readFile(raw)
    if (data) {
      root.windowMode = data.windowMode
      Store.fillItems(itemModel, data.items)
      Store.fillLinks(linkModel, itemModel, data.links)
      root.nextId = Store.nextFreeId(itemModel, data.nextId)
      root.nextColor = itemModel.count
    } else {
      itemModel.clear()
      linkModel.clear()
    }
    root.selectedIndex = -1
    root.undoStack = []
    root.redoStack = []
    root.lastSavedCount = itemModel.count
    root.boardLoaded = true
    if (itemModel.count > 0) backupProc.running = true
    root.repaintLinks()
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
  readonly property string boardPath: root.dataDir + "/board.json"

  // The data directory has to exist before the first atomic write, otherwise
  // the board silently fails to save on a fresh install.
  Process {
    running: true
    command: ["mkdir", "-p", root.dataDir]
  }

  // One generation back on disk, so even a bad write is recoverable.
  Process {
    id: backupProc
    command: ["cp", "-f", root.boardPath, root.boardPath + ".bak"]
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

  FileView {
    id: boardFile
    path: root.boardPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    // setText() makes the view re-emit loaded. Without this guard every save
    // would re-run loadBoard, throwing away the undo history and the
    // selection. watchChanges is off, so our own writes are the only reloads.
    onLoaded: { if (root.boardLoaded) return; root.loadBoard(text()) }
    onLoadFailed: { if (root.boardLoaded) return; root.loadBoard("{}") }
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
