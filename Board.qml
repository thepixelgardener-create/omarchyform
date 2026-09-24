pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store

// The canvas surface. Hosted by either the fullscreen overlay or the windowed
// toplevel; both share one controller, so switching never loses your place.
FocusScope {
  id: board

  required property var ctl

  focus: true

  // A filled head at the target end, pointing the way the connector runs.
  function arrowHead(ctx, fromX, fromY, toX, toY) {
    var angle = Math.atan2(toY - fromY, toX - fromX)
    var size = Math.max(7, 7 * board.ctl.zoom)
    var spread = 0.42
    ctx.beginPath()
    ctx.moveTo(toX, toY)
    ctx.lineTo(toX - size * Math.cos(angle - spread), toY - size * Math.sin(angle - spread))
    ctx.lineTo(toX - size * Math.cos(angle + spread), toY - size * Math.sin(angle + spread))
    ctx.closePath()
    ctx.fillStyle = board.ctl.foreground
    ctx.fill()
  }

  function repaintGrid() { grid.requestPaint() }
  function repaintLinks() { linkCanvas.requestPaint() }
  function focusKeys() { keys.forceActiveFocus() }

  Connections {
    target: board.ctl
    function onDotColorChanged() { board.repaintGrid() }
    function onForegroundChanged() { board.repaintLinks() }
  }

  // A real window hands focus to its content item, not to whatever is nested
  // inside it, so claim it explicitly on both surfaces.
  Component.onCompleted: {
    board.ctl.activeBoard = board
    Qt.callLater(board.focusKeys)
  }
  Component.onDestruction: if (board.ctl.activeBoard === board) board.ctl.activeBoard = null

  Rectangle {
    anchors.fill: parent
    color: board.ctl.canvasBackground
  }

  // Dots and connectors are drawn in screen space so they keep their weight
  // however far you zoom out, rather than scaling into mush.
  Canvas {
    id: grid
    anchors.fill: parent
    visible: board.ctl.showGrid
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var step = 40 * board.ctl.zoom
      if (step < 8) return
      ctx.fillStyle = board.ctl.dotColor
      var r = Math.max(1, 1.2 * board.ctl.zoom)
      for (var x = board.ctl.camX % step; x < width; x += step)
        for (var y = board.ctl.camY % step; y < height; y += step) {
          ctx.beginPath()
          ctx.arc(x, y, r, 0, Math.PI * 2)
          ctx.fill()
        }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  Canvas {
    id: linkCanvas
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.strokeStyle = board.ctl.foreground
      ctx.lineWidth = Math.max(1, 1.5 * board.ctl.zoom)
      ctx.globalAlpha = 0.55

      var items = board.ctl.items
      var links = board.ctl.links
      var byId = Store.idIndex(items)

      for (var i = 0; i < links.count; i++) {
        var l = links.get(i)
        var ai = byId[l.lfrom]
        var bi = byId[l.lto]
        if (ai === undefined || bi === undefined) continue
        var a = items.get(ai)
        var b = items.get(bi)
        var acx = a.ix + a.iw / 2, acy = a.iy + a.ih / 2
        var bcx = b.ix + b.iw / 2, bcy = b.iy + b.ih / 2
        var p = Store.edgePoint(a, acx, acy, bcx, bcy)
        var q = Store.edgePoint(b, bcx, bcy, acx, acy)
        var px = board.ctl.toScreenX(p.x), py = board.ctl.toScreenY(p.y)
        var qx = board.ctl.toScreenX(q.x), qy = board.ctl.toScreenY(q.y)
        ctx.beginPath()
        ctx.moveTo(px, py)
        ctx.lineTo(qx, qy)
        ctx.stroke()
        board.arrowHead(ctx, px, py, qx, qy)
      }

      // While picking the far end, trail a dashed line to the selection so it
      // is obvious what is about to be joined.
      var si = byId[board.ctl.linkingFrom]
      if (si !== undefined && board.ctl.selectedIndex >= 0 && si !== board.ctl.selectedIndex) {
        var s = items.get(si)
        var t = items.get(board.ctl.selectedIndex)
        ctx.globalAlpha = 0.9
        ctx.setLineDash([6, 5])
        ctx.beginPath()
        ctx.moveTo(board.ctl.toScreenX(s.ix + s.iw / 2), board.ctl.toScreenY(s.iy + s.ih / 2))
        ctx.lineTo(board.ctl.toScreenX(t.ix + t.iw / 2), board.ctl.toScreenY(t.iy + t.ih / 2))
        ctx.stroke()
        ctx.setLineDash([])
      }
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  // Background: drag to pan, wheel to zoom, double-click for a note.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    property real lastX: 0
    property real lastY: 0
    property bool panning: false

    onPressed: function (mouse) {
      lastX = mouse.x
      lastY = mouse.y
      panning = true
      board.ctl.selectOnly(-1)
      board.focusKeys()
    }
    onReleased: panning = false
    onPositionChanged: function (mouse) {
      if (!panning) return
      board.ctl.panBy(mouse.x - lastX, mouse.y - lastY)
      lastX = mouse.x
      lastY = mouse.y
    }
    onDoubleClicked: function (mouse) {
      board.ctl.addItem("note", board.ctl.toWorldX(mouse.x), board.ctl.toWorldY(mouse.y))
    }
    onWheel: function (wheel) {
      board.ctl.zoomAt(wheel.x, wheel.y, wheel.angleDelta.y > 0 ? 1.12 : 1 / 1.12)
    }
  }

  // The world. Everything inside is positioned in canvas coordinates.
  Item {
    anchors.fill: parent
    transform: [
      Scale { xScale: board.ctl.zoom; yScale: board.ctl.zoom },
      Translate { x: board.ctl.camX; y: board.ctl.camY }
    ]

    Repeater {
      model: board.ctl.items
      delegate: Node { ctl: board.ctl }
    }
  }

  // Keyboard owner. Lives above the canvas so Escape always lands here.
  Item {
    id: keys
    anchors.fill: parent
    // Focus moves between the canvas and the browser declaratively. Leaving
    // both claiming it strands the keyboard on whichever hid last.
    focus: !board.ctl.browserVisible

    // Printable keys are a table rather than a ladder of else-ifs: adding a
    // command is one line, and the cheat sheet is the only other place to
    // touch.
    readonly property var commands: ({
      "n": function () { board.ctl.addRelative("note") },
      "r": function () { board.ctl.addRelative("rect") },
      "e": function () { board.ctl.addRelative("ellipse") },
      "s": function () { board.ctl.cycleKind() },
      "c": function () { board.ctl.recolorItem() },
      "d": function () { board.ctl.removeItem(board.ctl.selectedIndex) },
      "u": function () { board.ctl.undo() },
      "i": function () { board.ctl.editSelected() },
      "x": function () { board.ctl.toggleLinking() },
      "X": function () { board.ctl.unlinkSelected() },
      "w": function () { board.ctl.toggleWindowMode() },
      "f": function () { board.ctl.fitToItems() },
      "b": function () { board.ctl.openBrowser() },
      "0": function () { board.ctl.resetView() },
      "+": function () { board.ctl.zoomCentre(1.2) },
      "=": function () { board.ctl.zoomCentre(1.2) },
      "-": function () { board.ctl.zoomCentre(1 / 1.2) },
      "?": function () { board.ctl.helpVisible = !board.ctl.helpVisible }
    })

    readonly property var arrows: ({})

    // Matched on key codes as well as text: holding Ctrl turns the letter in
    // event.text into a control character, so text alone would miss.
    function direction(key, text) {
      if (key === Qt.Key_Left || key === Qt.Key_H || text === "h" || text === "H") return [-1, 0]
      if (key === Qt.Key_Right || key === Qt.Key_L || text === "l" || text === "L") return [1, 0]
      if (key === Qt.Key_Up || key === Qt.Key_K || text === "k" || text === "K") return [0, -1]
      if (key === Qt.Key_Down || key === Qt.Key_J || text === "j" || text === "J") return [0, 1]
      return null
    }

    Keys.onPressed: function (event) {
      if (board.ctl.helpVisible) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_F1 || event.text === "?") board.ctl.helpVisible = false
        else if (event.key === Qt.Key_Down || event.text === "j") help.scroll(board.ctl.fontBody * 2)
        else if (event.key === Qt.Key_Up || event.text === "k") help.scroll(-board.ctl.fontBody * 2)
        else if (event.key === Qt.Key_PageDown) help.scroll(help.height * 0.8)
        else if (event.key === Qt.Key_PageUp) help.scroll(-help.height * 0.8)
        event.accepted = true
        return
      }
      var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
      var shift = (event.modifiers & Qt.ShiftModifier) !== 0

      if (ctrl) {
        // Ctrl plus a movement key resizes, the same way Shift plus one moves.
        var rd = keys.direction(event.key, "")
        if (rd) board.ctl.resizeSelected(rd[0], rd[1])
        else if (event.key === Qt.Key_R) board.ctl.redo()
        else if (event.key === Qt.Key_Z) shift ? board.ctl.redo() : board.ctl.undo()
        else if (event.key === Qt.Key_S) board.ctl.save()
        else return
        event.accepted = true
        return
      }

      // Movement does double duty: bare keys move the selection, shifted keys
      // carry the selected item along with them.
      var d = keys.direction(event.key, event.text)
      if (d) {
        board.ctl.move(d[0], d[1], shift)
        event.accepted = true
        return
      }

      if (event.key === Qt.Key_Escape) board.ctl.back()
      else if (event.key === Qt.Key_F1) board.ctl.helpVisible = !board.ctl.helpVisible
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) board.ctl.editSelected()
      else if (event.key === Qt.Key_Tab) board.ctl.selectNext(1)
      else if (event.key === Qt.Key_Backtab) board.ctl.selectNext(-1)
      else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) board.ctl.removeItem(board.ctl.selectedIndex)
      else {
        var run = keys.commands[event.text]
        if (!run) return
        run()
      }
      event.accepted = true
    }
  }

  // The board browser sits above the canvas and takes the keyboard while open.
  Browser {
    anchors.fill: parent
    ctl: board.ctl
  }

  // Help consumes input so browsing shortcuts cannot edit the board behind it.
  MouseArea {
    anchors.fill: parent
    visible: board.ctl.helpVisible
    onClicked: board.ctl.helpVisible = false
  }
  Help {
    id: help
    anchors.centerIn: parent
    ctl: board.ctl
  }

  Text {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: board.ctl.sp(16)
    anchors.rightMargin: board.ctl.sp(16)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    anchors.bottom: parent.bottom
    anchors.bottomMargin: board.ctl.sp(16)
    color: board.ctl.foreground
    opacity: 0.55
    font.family: board.ctl.fontFamily
    font.pixelSize: board.ctl.fontBody
    visible: !board.ctl.helpVisible && !board.ctl.browserVisible
    text: board.ctl.saveError !== "" ? board.ctl.saveError
      : board.ctl.pendingBoard !== null ? "saving before switching boards…"
      : board.ctl.saving ? "saving…"
      : board.ctl.damaged
      ? board.ctl.boardTitle + " could not be read — not saving over it"
      : board.ctl.editIndex >= 0
      ? "esc: done typing"
      : board.ctl.linkingFrom >= 0
        ? "pick the other end, then x to connect  ·  esc: cancel"
        : board.ctl.boardTitle + "  ·  n: note  ·  r/e: shapes  ·  x: connect  ·  u: undo  ·  b: boards  ·  ?: all keys  ·  esc: close"
  }
}
