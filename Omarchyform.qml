pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false

  // Shares the [menu] surface tokens so themes style the canvas chrome too.
  // Every read of the shell's internal singletons goes through a guard: they
  // are not a versioned API, and a rename upstream should cost a wrong colour,
  // not a board that refuses to open. (An import that disappears entirely is
  // still fatal — QML has no optional imports.)
  readonly property color fallbackBackground: "#12131A"
  readonly property color fallbackForeground: "#E6E6E6"

  function token(read, fallback) {
    try {
      var v = read()
      return v === undefined || v === null ? fallback : v
    } catch (e) {
      return fallback
    }
  }

  function sp(n) { return root.token(function () { return Style.space(n) }, n) }

  property color canvasBackground: root.token(function () { return Color.menu.background }, root.fallbackBackground)
  property color foreground: root.token(function () { return Color.menu.text }, root.fallbackForeground)
  property color dotColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
  property string fontFamily: root.token(function () { return Style.font.menuFamily }, "monospace")
  readonly property int cornerRadius: root.token(function () { return Style.cornerRadius }, 8)

  // The output Hyprland has focused, which is where a keyboard-summoned board
  // belongs. Without this the overlay lands on whichever screen Quickshell
  // picks, which on a two-monitor desk is rarely the one being used.
  property var boardScreen: null

  function focusedScreen() {
    var monitor = root.token(function () { return Hyprland.focusedMonitor }, null)
    var wanted = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === wanted) return screens[i]
    return screens[0]
  }

  // Item colors are deliberately fixed rather than themed: a board reads as a
  // board because the paper stays the same when the desktop theme changes.
  readonly property var swatches: ["#F7D794", "#F3A0A0", "#A8D8B9", "#A3C4E8", "#D4B5E8", "#F0C9A0"]
  readonly property color ink: "#2C2C2A"
  readonly property var kinds: ["note", "rect", "ellipse", "diamond"]

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchyform"
  readonly property string boardPath: root.dataDir + "/board.json"

  // The camera. screen = world * zoom + cam.
  property real camX: 0
  property real camY: 0
  property real zoom: 1
  readonly property real minZoom: 0.2
  readonly property real maxZoom: 4

  property int nextId: 1
  property int nextColor: 0
  property int selectedIndex: -1
  // The item currently being typed into. -1 means we are in normal mode and
  // every key is a command.
  property int editIndex: -1
  property bool helpVisible: false

  // Holds the id of the first end while a connector is being drawn.
  property int linkingFrom: -1

  // false: fullscreen layer-shell overlay. true: an ordinary Hyprland window
  // that tiles and floats like any other app.
  property bool windowMode: false

  // Guards against writing an empty board over a good file. save() is a no-op
  // until the file has actually been read, and refuses to shrink a non-empty
  // board to nothing unless a delete asked for it.
  property bool boardLoaded: false
  property int lastSavedCount: -1

  property var activeBoard: null
  readonly property real viewW: root.activeBoard ? root.activeBoard.width : 1920
  readonly property real viewH: root.activeBoard ? root.activeBoard.height : 1080

  readonly property int minItemSize: 60
  readonly property int nudgeStep: 40
  readonly property int undoLimit: 100

  ListModel { id: items }
  ListModel { id: links }

  property var undoStack: []
  property var redoStack: []

  function repaintGrid() { if (root.activeBoard) root.activeBoard.repaintGrid() }
  function repaintLinks() { if (root.activeBoard) root.activeBoard.repaintLinks() }
  function focusKeys() { if (root.activeBoard) root.activeBoard.focusKeys() }

  function toWorldX(sx) { return (sx - root.camX) / root.zoom }
  function toWorldY(sy) { return (sy - root.camY) / root.zoom }
  function toScreenX(wx) { return wx * root.zoom + root.camX }
  function toScreenY(wy) { return wy * root.zoom + root.camY }

  // ---------------------------------------------------------------- history

  function snapshot() {
    var its = []
    for (var i = 0; i < items.count; i++) {
      var n = items.get(i)
      its.push({ id: n.iid, kind: n.kind, x: n.ix, y: n.iy, w: n.iw, h: n.ih, color: n.icolor, text: n.itext })
    }
    var ls = []
    for (var j = 0; j < links.count; j++) {
      var l = links.get(j)
      ls.push({ from: l.lfrom, to: l.lto })
    }
    return JSON.stringify({ items: its, links: ls, nextId: root.nextId })
  }

  // Called before every mutation. Redo is dropped the moment a new edit lands,
  // which is what people expect from an undo stack.
  function pushUndo() {
    if (!root.boardLoaded) return
    var s = root.undoStack.slice()
    s.push(root.snapshot())
    if (s.length > root.undoLimit) s.shift()
    root.undoStack = s
    root.redoStack = []
  }

  function applySnapshot(raw) {
    var d = JSON.parse(raw)
    items.clear()
    for (var i = 0; i < d.items.length; i++) {
      var n = d.items[i]
      items.append({ iid: n.id, kind: n.kind, ix: n.x, iy: n.y, iw: n.w, ih: n.h, icolor: n.color, itext: n.text })
    }
    links.clear()
    for (var j = 0; j < d.links.length; j++) links.append({ lfrom: d.links[j].from, lto: d.links[j].to })
    root.nextId = d.nextId
    if (root.selectedIndex >= items.count) root.selectedIndex = items.count - 1
    root.editIndex = -1
    root.linkingFrom = -1
    root.repaintLinks()
    // Rebuilding the model tears down every delegate, which drops keyboard
    // focus; without this a second undo never reaches the key handler.
    root.focusKeys()
  }

  function undo() {
    if (root.undoStack.length === 0) return
    var u = root.undoStack.slice()
    var prev = u.pop()
    var r = root.redoStack.slice()
    r.push(root.snapshot())
    root.undoStack = u
    root.redoStack = r
    root.applySnapshot(prev)
    root.save(true)
  }

  function redo() {
    if (root.redoStack.length === 0) return
    var r = root.redoStack.slice()
    var next = r.pop()
    var u = root.undoStack.slice()
    u.push(root.snapshot())
    root.redoStack = r
    root.undoStack = u
    root.applySnapshot(next)
    root.save(true)
  }

  // ------------------------------------------------------------------ items

  function indexOfId(id) {
    for (var i = 0; i < items.count; i++) if (items.get(i).iid === id) return i
    return -1
  }

  function addItem(kind, wx, wy) {
    root.pushUndo()
    var w = kind === "note" ? 180 : 160
    var h = kind === "note" ? 140 : 110
    items.append({
      iid: root.nextId,
      kind: kind,
      ix: wx - w / 2,
      iy: wy - h / 2,
      iw: w,
      ih: h,
      icolor: root.swatches[root.nextColor % root.swatches.length],
      itext: ""
    })
    root.nextId += 1
    root.nextColor += 1
    root.selectedIndex = items.count - 1
    root.save()
    root.repaintLinks()
  }

  function removeItem(index) {
    if (index < 0 || index >= items.count) return
    root.pushUndo()
    var id = items.get(index).iid
    items.remove(index)
    // Connectors cannot outlive either end.
    for (var j = links.count - 1; j >= 0; j--) {
      var l = links.get(j)
      if (l.lfrom === id || l.lto === id) links.remove(j)
    }
    if (root.selectedIndex >= items.count) root.selectedIndex = items.count - 1
    root.save(true)
    root.repaintLinks()
  }

  function recolorItem(index) {
    if (index < 0 || index >= items.count) return
    root.pushUndo()
    var current = root.swatches.indexOf(items.get(index).icolor)
    items.setProperty(index, "icolor", root.swatches[(current + 1) % root.swatches.length])
    root.save()
  }

  function cycleKind(index) {
    if (index < 0 || index >= items.count) return
    root.pushUndo()
    var current = root.kinds.indexOf(items.get(index).kind)
    items.setProperty(index, "kind", root.kinds[(current + 1) % root.kinds.length])
    root.save()
  }

  // --------------------------------------------------------------- linking

  function toggleLinking() {
    if (root.selectedIndex < 0) return
    if (root.linkingFrom < 0) {
      root.linkingFrom = items.get(root.selectedIndex).iid
      return
    }
    var target = items.get(root.selectedIndex).iid
    if (target !== root.linkingFrom) root.addLink(root.linkingFrom, target)
    root.linkingFrom = -1
  }

  function addLink(a, b) {
    for (var i = 0; i < links.count; i++) {
      var l = links.get(i)
      // A connector is undirected here, so drawing it again removes it.
      if ((l.lfrom === a && l.lto === b) || (l.lfrom === b && l.lto === a)) {
        root.pushUndo()
        links.remove(i)
        root.save(true)
        root.repaintLinks()
        return
      }
    }
    root.pushUndo()
    links.append({ lfrom: a, lto: b })
    root.save()
    root.repaintLinks()
  }

  function unlinkSelected() {
    if (root.selectedIndex < 0) return
    var id = items.get(root.selectedIndex).iid
    var removed = false
    for (var j = links.count - 1; j >= 0; j--) {
      var l = links.get(j)
      if (l.lfrom === id || l.lto === id) {
        if (!removed) { root.pushUndo(); removed = true }
        links.remove(j)
      }
    }
    if (removed) { root.save(true); root.repaintLinks() }
  }

  // ------------------------------------------------------------- navigation

  // Spatial selection: jump to the nearest item in a direction, scoring by
  // distance along the axis plus a penalty for drifting off it. This is what
  // makes hjkl feel like moving around a board rather than cycling a list.
  function selectDirection(dx, dy) {
    if (items.count === 0) return
    if (root.selectedIndex < 0) { root.selectedIndex = 0; root.centerOnSelected(); return }
    var from = items.get(root.selectedIndex)
    var fx = from.ix + from.iw / 2
    var fy = from.iy + from.ih / 2
    var best = -1
    var bestScore = Infinity
    for (var i = 0; i < items.count; i++) {
      if (i === root.selectedIndex) continue
      var n = items.get(i)
      var ax = (n.ix + n.iw / 2) - fx
      var ay = (n.iy + n.ih / 2) - fy
      var along = ax * dx + ay * dy
      if (along <= 0) continue
      var off = Math.abs(ax * dy + ay * dx)
      var score = along + off * 2
      if (score < bestScore) { bestScore = score; best = i }
    }
    if (best >= 0) {
      root.selectedIndex = best
      root.centerOnSelected()
    }
  }

  function selectNext(step) {
    if (items.count === 0) return
    root.selectedIndex = ((root.selectedIndex + step) % items.count + items.count) % items.count
    root.centerOnSelected()
  }

  // Keep the selected item on screen without yanking the view around when it
  // is already comfortably visible.
  function centerOnSelected() {
    if (root.selectedIndex < 0) return
    var n = items.get(root.selectedIndex)
    var sx = root.toScreenX(n.ix)
    var sy = root.toScreenY(n.iy)
    var sw = n.iw * root.zoom
    var sh = n.ih * root.zoom
    var m = 60
    if (sx < m) root.camX += m - sx
    else if (sx + sw > root.viewW - m) root.camX -= (sx + sw) - (root.viewW - m)
    if (sy < m) root.camY += m - sy
    else if (sy + sh > root.viewH - m) root.camY -= (sy + sh) - (root.viewH - m)
    root.repaintGrid()
    root.repaintLinks()
  }

  function nudgeSelected(dx, dy) {
    if (root.selectedIndex < 0) return
    root.pushUndo()
    var n = items.get(root.selectedIndex)
    items.setProperty(root.selectedIndex, "ix", n.ix + dx * root.nudgeStep)
    items.setProperty(root.selectedIndex, "iy", n.iy + dy * root.nudgeStep)
    root.centerOnSelected()
    root.save()
  }

  function pan(dx, dy) {
    root.camX -= dx * 120
    root.camY -= dy * 120
    root.repaintGrid()
    root.repaintLinks()
  }

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

  // A new item lands beside the selected one, so building a row is just
  // n, n, n without touching the mouse.
  function addRelative(kind) {
    if (root.selectedIndex < 0) {
      root.addItem(kind, root.toWorldX(root.viewW / 2), root.toWorldY(root.viewH / 2))
    } else {
      var n = items.get(root.selectedIndex)
      root.addItem(kind, n.ix + n.iw + 120, n.iy + n.ih / 2)
    }
    root.centerOnSelected()
    root.editSelected()
  }

  function zoomAt(sx, sy, factor) {
    var next = Math.max(root.minZoom, Math.min(root.maxZoom, root.zoom * factor))
    if (next === root.zoom) return
    // Keep the point under the cursor pinned while the scale changes.
    var wx = root.toWorldX(sx)
    var wy = root.toWorldY(sy)
    root.zoom = next
    root.camX = sx - wx * root.zoom
    root.camY = sy - wy * root.zoom
    root.repaintGrid()
    root.repaintLinks()
  }

  function resetView() {
    root.camX = 0
    root.camY = 0
    root.zoom = 1
    root.repaintGrid()
    root.repaintLinks()
  }

  // Centre the camera on everything that exists, so a board is never lost
  // off-screen after a big pan.
  function fitToItems() {
    if (items.count === 0) { root.resetView(); return }
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (var i = 0; i < items.count; i++) {
      var n = items.get(i)
      minX = Math.min(minX, n.ix)
      minY = Math.min(minY, n.iy)
      maxX = Math.max(maxX, n.ix + n.iw)
      maxY = Math.max(maxY, n.iy + n.ih)
    }
    var pad = 80
    var w = (maxX - minX) + pad * 2
    var h = (maxY - minY) + pad * 2
    root.zoom = Math.max(root.minZoom, Math.min(1, Math.min(root.viewW / w, root.viewH / h)))
    root.camX = root.viewW / 2 - ((minX + maxX) / 2) * root.zoom
    root.camY = root.viewH / 2 - ((minY + maxY) / 2) * root.zoom
    root.repaintGrid()
    root.repaintLinks()
  }

  function toggleWindowMode() {
    root.windowMode = !root.windowMode
    root.save()
  }

  // ---------------------------------------------------------------- storage

  function save(allowEmpty) {
    if (!root.boardLoaded) return
    var its = []
    for (var i = 0; i < items.count; i++) {
      var n = items.get(i)
      its.push({ id: n.iid, kind: n.kind, x: n.ix, y: n.iy, w: n.iw, h: n.ih, color: n.icolor, text: n.itext })
    }
    if (its.length === 0 && root.lastSavedCount > 0 && allowEmpty !== true) return
    var ls = []
    for (var j = 0; j < links.count; j++) ls.push({ from: links.get(j).lfrom, to: links.get(j).lto })
    boardFile.setText(JSON.stringify({
      version: 2,
      windowMode: root.windowMode,
      nextId: root.nextId,
      items: its,
      links: ls
    }, null, 2) + "\n")
    root.lastSavedCount = its.length
  }

  function markLoaded(count) {
    root.lastSavedCount = count
    root.boardLoaded = true
    if (count > 0) backupProc.running = true
  }

  function loadBoard(raw) {
    items.clear()
    links.clear()
    var parsed
    try { parsed = JSON.parse(raw) } catch (e) { root.markLoaded(0); return }
    if (!parsed) { root.markLoaded(0); return }

    root.windowMode = parsed.windowMode === true

    // v1 stored a flat notes[] with no ids; give each one an id on the way in.
    var incoming = parsed.items ? parsed.items : (parsed.notes ? parsed.notes : [])
    var id = parsed.nextId ? parsed.nextId : 1
    for (var i = 0; i < incoming.length; i++) {
      var n = incoming[i]
      var thisId = n.id ? n.id : id++
      items.append({
        iid: thisId,
        kind: n.kind ? n.kind : "note",
        ix: n.x || 0,
        iy: n.y || 0,
        iw: Math.max(root.minItemSize, n.w || 180),
        ih: Math.max(root.minItemSize, n.h || 140),
        icolor: n.color || root.swatches[0],
        itext: n.text || ""
      })
    }
    root.nextId = parsed.nextId ? parsed.nextId : 1
    for (var k = 0; k < items.count; k++) root.nextId = Math.max(root.nextId, items.get(k).iid + 1)

    if (parsed.links) {
      for (var j = 0; j < parsed.links.length; j++) {
        var l = parsed.links[j]
        // Drop connectors whose ends did not survive.
        if (root.indexOfId(l.from) >= 0 && root.indexOfId(l.to) >= 0)
          links.append({ lfrom: l.from, lto: l.to })
      }
    }

    root.nextColor = items.count
    root.selectedIndex = -1
    root.undoStack = []
    root.redoStack = []
    root.markLoaded(items.count)
    root.repaintLinks()
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

  function close() {
    root.opened = false
  }

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

  // The data directory has to exist before the first atomic write, otherwise
  // the board silently fails to save on a fresh install.
  Process {
    running: true
    command: ["mkdir", "-p", root.dataDir]
  }

  Process {
    id: backupProc
    command: ["cp", "-f", root.boardPath, root.boardPath + ".bak"]
  }

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

  // ------------------------------------------------------------------ board

  Component {
    id: boardContent

    FocusScope {
      id: board
      anchors.fill: parent
      focus: true

      function repaintGrid() { grid.requestPaint() }
      function repaintLinks() { linkCanvas.requestPaint() }
      function focusKeys() { keyCatcher.forceActiveFocus() }

      // Where a connector meets an item: walk from its centre toward the other
      // end until we cross the bounding box.
      function edgePoint(it, cx, cy, tx, ty) {
        var dx = tx - cx
        var dy = ty - cy
        if (dx === 0 && dy === 0) return { x: cx, y: cy }
        var hw = it.iw / 2
        var hh = it.ih / 2
        var scale = Math.min(
          dx === 0 ? Infinity : hw / Math.abs(dx),
          dy === 0 ? Infinity : hh / Math.abs(dy))
        return { x: cx + dx * scale, y: cy + dy * scale }
      }

      // A real window hands focus to its content item, not to whatever is
      // nested inside a Loader, so claim it explicitly on both surfaces.
      Component.onCompleted: {
        root.activeBoard = board
        Qt.callLater(board.focusKeys)
      }
      Component.onDestruction: if (root.activeBoard === board) root.activeBoard = null

      Rectangle {
        anchors.fill: parent
        color: root.canvasBackground
      }

      // The dot grid. Drawn in screen space and repainted as the camera moves,
      // so the dots stay crisp instead of scaling into mush.
      Canvas {
        id: grid
        anchors.fill: parent
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var step = 40 * root.zoom
          if (step < 8) return
          var ox = root.camX % step
          var oy = root.camY % step
          ctx.fillStyle = root.dotColor
          var r = Math.max(1, 1.2 * root.zoom)
          for (var x = ox; x < width; x += step) {
            for (var y = oy; y < height; y += step) {
              ctx.beginPath()
              ctx.arc(x, y, r, 0, Math.PI * 2)
              ctx.fill()
            }
          }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
      }

      // Connectors, drawn in screen space beneath the items so the lines stay
      // the same weight however far you zoom out.
      Canvas {
        id: linkCanvas
        anchors.fill: parent
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.strokeStyle = root.foreground
          ctx.lineWidth = Math.max(1, 1.5 * root.zoom)
          ctx.globalAlpha = 0.55

          for (var i = 0; i < links.count; i++) {
            var l = links.get(i)
            var ai = root.indexOfId(l.lfrom)
            var bi = root.indexOfId(l.lto)
            if (ai < 0 || bi < 0) continue
            var a = items.get(ai)
            var b = items.get(bi)
            var acx = a.ix + a.iw / 2, acy = a.iy + a.ih / 2
            var bcx = b.ix + b.iw / 2, bcy = b.iy + b.ih / 2
            var p = board.edgePoint(a, acx, acy, bcx, bcy)
            var q = board.edgePoint(b, bcx, bcy, acx, acy)
            ctx.beginPath()
            ctx.moveTo(root.toScreenX(p.x), root.toScreenY(p.y))
            ctx.lineTo(root.toScreenX(q.x), root.toScreenY(q.y))
            ctx.stroke()
          }

          // While picking the far end, trail a dashed line to the selection so
          // it is obvious what is about to be joined.
          if (root.linkingFrom >= 0 && root.selectedIndex >= 0) {
            var si = root.indexOfId(root.linkingFrom)
            if (si >= 0 && si !== root.selectedIndex) {
              var s = items.get(si)
              var t = items.get(root.selectedIndex)
              ctx.globalAlpha = 0.9
              ctx.setLineDash([6, 5])
              ctx.beginPath()
              ctx.moveTo(root.toScreenX(s.ix + s.iw / 2), root.toScreenY(s.iy + s.ih / 2))
              ctx.lineTo(root.toScreenX(t.ix + t.iw / 2), root.toScreenY(t.iy + t.ih / 2))
              ctx.stroke()
              ctx.setLineDash([])
            }
          }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
      }

      // Background: drag to pan, wheel to zoom, double-click for a note.
      MouseArea {
        id: canvasArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        property real lastX: 0
        property real lastY: 0
        property bool panning: false

        onPressed: function (mouse) {
          lastX = mouse.x
          lastY = mouse.y
          panning = true
          root.selectedIndex = -1
          root.editIndex = -1
          root.linkingFrom = -1
          board.focusKeys()
          linkCanvas.requestPaint()
        }
        onReleased: panning = false
        onPositionChanged: function (mouse) {
          if (!panning) return
          root.camX += mouse.x - lastX
          root.camY += mouse.y - lastY
          lastX = mouse.x
          lastY = mouse.y
          grid.requestPaint()
          linkCanvas.requestPaint()
        }
        onDoubleClicked: function (mouse) {
          root.addItem("note", root.toWorldX(mouse.x), root.toWorldY(mouse.y))
        }
        onWheel: function (wheel) {
          root.zoomAt(wheel.x, wheel.y, wheel.angleDelta.y > 0 ? 1.12 : 1 / 1.12)
        }
      }

      // The world. Everything inside is positioned in canvas coordinates.
      Item {
        id: world
        anchors.fill: parent
        transform: [
          Scale { xScale: root.zoom; yScale: root.zoom },
          Translate { x: root.camX; y: root.camY }
        ]

        Repeater {
          model: items

          Item {
            id: node

            required property int index
            required property int iid
            required property string kind
            required property real ix
            required property real iy
            required property real iw
            required property real ih
            required property color icolor
            required property string itext

            readonly property bool selected: root.selectedIndex === node.index
            readonly property bool isLinkSource: root.linkingFrom === node.iid
            readonly property bool isNote: node.kind === "note"

            x: node.ix
            y: node.iy
            width: node.iw
            height: node.ih

            onXChanged: linkCanvas.requestPaint()
            onYChanged: linkCanvas.requestPaint()
            onWidthChanged: linkCanvas.requestPaint()
            onHeightChanged: linkCanvas.requestPaint()

            // Notes and boxes are plain Rectangles; ellipses and diamonds need
            // a path, so they are painted.
            Rectangle {
              anchors.fill: parent
              visible: node.kind === "note" || node.kind === "rect"
              color: node.icolor
              radius: 6
              antialiasing: true
              border.width: node.selected || node.isLinkSource ? 2 : 0
              border.color: node.isLinkSource ? root.foreground : root.ink
            }

            Canvas {
              id: shapeCanvas
              anchors.fill: parent
              visible: node.kind === "ellipse" || node.kind === "diamond"
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.beginPath()
                if (node.kind === "ellipse") {
                  ctx.ellipse(1, 1, Math.max(1, width - 2), Math.max(1, height - 2))
                } else {
                  ctx.moveTo(width / 2, 1)
                  ctx.lineTo(width - 1, height / 2)
                  ctx.lineTo(width / 2, height - 1)
                  ctx.lineTo(1, height / 2)
                  ctx.closePath()
                }
                ctx.fillStyle = node.icolor
                ctx.fill()
                if (node.selected || node.isLinkSource) {
                  ctx.strokeStyle = node.isLinkSource ? root.foreground : root.ink
                  ctx.lineWidth = 2
                  ctx.stroke()
                }
              }
              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()

              Connections {
                target: node
                function onIcolorChanged() { shapeCanvas.requestPaint() }
                function onKindChanged() { shapeCanvas.requestPaint() }
                function onSelectedChanged() { shapeCanvas.requestPaint() }
                function onIsLinkSourceChanged() { shapeCanvas.requestPaint() }
              }
            }

            // A note has a grab strip at the top; shapes read better without.
            Rectangle {
              id: header
              anchors { top: parent.top; left: parent.left; right: parent.right }
              height: 24
              radius: 6
              visible: node.isNote
              color: Qt.darker(node.icolor, 1.12)
            }

            TextEdit {
              id: body
              anchors.fill: parent
              anchors.margins: node.isNote ? 10 : 16
              anchors.topMargin: node.isNote ? header.height + 8 : 16
              text: node.itext
              color: root.ink
              font.family: root.fontFamily
              font.pixelSize: 14
              wrapMode: TextEdit.Wrap
              // Pinned: board files are shareable, and RichText here would let
              // someone else's board inject markup into yours.
              textFormat: TextEdit.PlainText
              horizontalAlignment: node.isNote ? TextEdit.AlignLeft : TextEdit.AlignHCenter
              verticalAlignment: node.isNote ? TextEdit.AlignTop : TextEdit.AlignVCenter
              selectByMouse: true
              // Guarded so the model write cannot bounce back and reset the caret.
              onTextChanged: if (text !== node.itext) items.setProperty(node.index, "itext", text)
              onActiveFocusChanged: if (!activeFocus) root.save()
              Keys.onEscapePressed: root.stopEditing()

              readonly property bool wantsEdit: root.editIndex === node.index
              onWantsEditChanged: if (wantsEdit) {
                forceActiveFocus()
                cursorPosition = length
              }
            }

            // Drag anywhere. Steps aside the moment this item is being edited,
            // so the caret still works.
            MouseArea {
              id: dragArea
              anchors.fill: parent
              enabled: root.editIndex !== node.index
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton
              cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

              property real pressX: 0
              property real pressY: 0
              property bool dragging: false

              onPressed: function (mouse) {
                pressX = mouse.x
                pressY = mouse.y
                dragging = false
                root.selectedIndex = node.index
                root.editIndex = -1
                board.focusKeys()
                linkCanvas.requestPaint()
              }
              onPositionChanged: function (mouse) {
                if (!pressed || mouse.buttons !== Qt.LeftButton) return
                var ddx = mouse.x - pressX
                var ddy = mouse.y - pressY
                // A few pixels of slack so a click to select never nudges it.
                if (!dragging && Math.abs(ddx) + Math.abs(ddy) < 3) return
                if (!dragging) root.pushUndo()
                dragging = true
                items.setProperty(node.index, "ix", node.ix + ddx)
                items.setProperty(node.index, "iy", node.iy + ddy)
              }
              onReleased: {
                if (dragging) root.save()
                dragging = false
              }
              onClicked: function (mouse) {
                if (mouse.button === Qt.MiddleButton) root.removeItem(node.index)
              }
              onDoubleClicked: function (mouse) {
                root.pushUndo()
                root.editIndex = node.index
              }
            }

            // Resize grip, bottom-right.
            MouseArea {
              width: 16
              height: 16
              anchors { right: parent.right; bottom: parent.bottom }
              cursorShape: Qt.SizeFDiagCursor
              property real pressX: 0
              property real pressY: 0
              property bool sizing: false

              onPressed: function (mouse) {
                pressX = mouse.x
                pressY = mouse.y
                sizing = false
                root.selectedIndex = node.index
              }
              onPositionChanged: function (mouse) {
                if (!pressed) return
                if (!sizing) { root.pushUndo(); sizing = true }
                items.setProperty(node.index, "iw", Math.max(root.minItemSize, node.iw + (mouse.x - pressX)))
                items.setProperty(node.index, "ih", Math.max(root.minItemSize, node.ih + (mouse.y - pressY)))
              }
              onReleased: {
                if (sizing) root.save()
                sizing = false
              }

              Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 2
                rotation: -45
                color: root.ink
                opacity: 0.35
              }
            }
          }
        }
      }

      // Keyboard owner. Lives above the canvas so Escape always lands here.
      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function (event) {
          var shift = (event.modifiers & Qt.ShiftModifier) !== 0
          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          var k = event.key

          // Movement keys do double duty: bare keys move the selection,
          // shifted keys carry the selected item along with them.
          var dx = 0, dy = 0
          if (k === Qt.Key_H || k === Qt.Key_Left) dx = -1
          else if (k === Qt.Key_L || k === Qt.Key_Right) dx = 1
          else if (k === Qt.Key_K || k === Qt.Key_Up) dy = -1
          else if (k === Qt.Key_J || k === Qt.Key_Down) dy = 1

          if (dx !== 0 || dy !== 0) {
            if (shift) root.nudgeSelected(dx, dy)
            else if (root.selectedIndex < 0) root.pan(dx, dy)
            else root.selectDirection(dx, dy)
            linkCanvas.requestPaint()
            event.accepted = true
            return
          }

          if (ctrl && k === Qt.Key_R) {
            root.redo()
          } else if (ctrl && k === Qt.Key_Z) {
            if (shift) root.redo(); else root.undo()
          } else if (ctrl && k === Qt.Key_S) {
            root.save()
          } else if (k === Qt.Key_Question || k === Qt.Key_F1) {
            root.helpVisible = !root.helpVisible
          } else if (k === Qt.Key_Escape) {
            // Escape backs out of the cheat sheet, then a pending connector,
            // then the board itself.
            if (root.helpVisible) root.helpVisible = false
            else if (root.linkingFrom >= 0) { root.linkingFrom = -1; linkCanvas.requestPaint() }
            else root.dismiss()
          } else if (k === Qt.Key_U) {
            root.undo()
          } else if (k === Qt.Key_N) {
            root.addRelative("note")
          } else if (k === Qt.Key_R) {
            root.addRelative("rect")
          } else if (k === Qt.Key_E) {
            root.addRelative("ellipse")
          } else if (k === Qt.Key_S) {
            root.cycleKind(root.selectedIndex)
          } else if (k === Qt.Key_X) {
            if (shift) root.unlinkSelected()
            else root.toggleLinking()
            linkCanvas.requestPaint()
          } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_I) {
            root.editSelected()
          } else if (k === Qt.Key_Tab) {
            root.selectNext(1)
            linkCanvas.requestPaint()
          } else if (k === Qt.Key_Backtab) {
            root.selectNext(-1)
            linkCanvas.requestPaint()
          } else if (k === Qt.Key_D || k === Qt.Key_Delete || k === Qt.Key_Backspace) {
            root.removeItem(root.selectedIndex)
          } else if (k === Qt.Key_C) {
            root.recolorItem(root.selectedIndex)
          } else if (k === Qt.Key_W) {
            root.toggleWindowMode()
          } else if (k === Qt.Key_F) {
            root.fitToItems()
          } else if (k === Qt.Key_0) {
            root.resetView()
          } else if (k === Qt.Key_Plus || k === Qt.Key_Equal) {
            root.zoomAt(board.width / 2, board.height / 2, 1.2)
          } else if (k === Qt.Key_Minus) {
            root.zoomAt(board.width / 2, board.height / 2, 1 / 1.2)
          } else {
            return
          }
          event.accepted = true
        }
      }

      // Keybinding cheat sheet, on ? or F1.
      Rectangle {
        anchors.centerIn: parent
        visible: root.helpVisible
        width: helpColumn.width + root.sp(56)
        height: helpColumn.height + root.sp(48)
        color: root.canvasBackground
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
        radius: root.cornerRadius

        Column {
          id: helpColumn
          anchors.centerIn: parent
          spacing: root.sp(6)

          Text {
            text: "Omarchyform"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 16
            bottomPadding: root.sp(8)
          }

          Repeater {
            model: [
              ["n", "new note beside the selected one"],
              ["r / e", "new box / ellipse"],
              ["s", "cycle shape: note, box, ellipse, diamond"],
              ["x", "connect: press on one, then on another"],
              ["X", "remove every connector on this item"],
              ["u / ctrl+r", "undo / redo"],
              ["enter / i", "type in the selected item"],
              ["esc", "back out, then close the board"],
              ["h j k l", "move the selection around"],
              ["H J K L", "push the selected item"],
              ["tab", "cycle through everything"],
              ["d", "delete the selected item"],
              ["c", "change its colour"],
              ["w", "fullscreen or windowed"],
              ["f", "fit the whole board on screen"],
              ["0", "reset the view"],
              ["+ / -", "zoom"],
              ["? / F1", "this list"],
              ["drag", "move an item, or the canvas"],
              ["wheel", "zoom at the pointer"]
            ]

            Row {
              required property var modelData
              spacing: root.sp(16)

              Text {
                width: root.sp(96)
                text: parent.modelData[0]
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 13
              }
              Text {
                text: parent.modelData[1]
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: 13
              }
            }
          }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.sp(16)
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: 12
        visible: !root.helpVisible
        text: root.editIndex >= 0
          ? "esc: done typing"
          : root.linkingFrom >= 0
            ? "pick the other end, then x to connect  ·  esc: cancel"
            : "n: note  ·  r/e: shapes  ·  x: connect  ·  u: undo  ·  hjkl: move  ·  ?: all keys  ·  esc: close"
      }
    }
  }

  // Fullscreen overlay, above everything, its own keyboard grab.
  //
  // Built through Variants rather than as a bare PanelWindow so the surface is
  // constructed with its screen already set: assigning `screen` to a window
  // that already exists leaves it unmapped, which on a two-monitor desk looks
  // exactly like the board failing to open.
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

        Loader {
          anchors.fill: parent
          focus: true
          sourceComponent: boardContent
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

    // Closing the window from the titlebar or a compositor keybind should end
    // the session the same way Escape does.
    onVisibleChanged: {
      if (!visible && root.opened && root.windowMode) root.dismiss()
    }

    Loader {
      anchors.fill: parent
      focus: true
      active: boardWindow.visible
      sourceComponent: boardContent
    }
  }
}
