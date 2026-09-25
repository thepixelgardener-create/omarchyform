pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store

// The canvas surface. Hosted by either the fullscreen overlay or the windowed
// toplevel; both share one controller, so switching never loses your place.
FocusScope {
  id: board

  required property var ctl

  focus: true
  readonly property real headerHeight: toolbar.y + toolbar.height

  property string exportDestination: ""

  function exportPng(path) {
    if (board.ctl.imageBusy) return
    if (board.ctl.items.count === 0) { board.ctl.flash("Add a note before exporting an image"); return }
    board.ctl.imageBusy = true
    exportDestination = path
    picture.save(board.ctl.dataDir + "/.image-export.png")
  }
  BoardImage {
    id: picture
    ctl: board.ctl
    onFinished: function(success) {
      if (success) board.ctl.finishPng(board.exportDestination)
      else { board.ctl.imageBusy = false; board.ctl.flash("Could not render PNG") }
    }
  }

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
  function probeImage(name) {
    sizeProbe.pending = name
    sizeProbe.source = ""
    sizeProbe.source = board.ctl.imagePath(name)
  }

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

  // Background: left drag draws a marquee, middle or right drag pans, wheel
  // zooms, double-click leaves a note.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    property real lastX: 0
    property real lastY: 0
    property bool panning: false
    property bool additive: false

    onPressed: function (mouse) {
      lastX = mouse.x
      lastY = mouse.y
      additive = (mouse.modifiers & Qt.ShiftModifier) !== 0
      // Backgrounds answer to the camera rather than the marquee: marks never
      // reach them, so a rectangle there would cost the pan and buy nothing.
      panning = mouse.button !== Qt.LeftButton || board.ctl.showPinned
      if (!panning) {
        marquee.fromX = board.ctl.toWorldX(mouse.x)
        marquee.fromY = board.ctl.toWorldY(mouse.y)
        marquee.toX = marquee.fromX
        marquee.toY = marquee.fromY
        marquee.dragging = true
        if (!additive) board.ctl.selectOnly(-1)
      }
      board.focusKeys()
    }
    onReleased: {
      panning = false
      if (!marquee.dragging) return
      var caught = marquee.wide
      marquee.dragging = false
      if (caught) board.ctl.markInRect(marquee.fromX, marquee.fromY, marquee.toX, marquee.toY, additive)
    }
    onCanceled: {
      panning = false
      marquee.dragging = false
    }
    onPositionChanged: function (mouse) {
      if (marquee.dragging) {
        marquee.toX = board.ctl.toWorldX(mouse.x)
        marquee.toY = board.ctl.toWorldY(mouse.y)
        return
      }
      if (!panning) return
      board.ctl.panBy(mouse.x - lastX, mouse.y - lastY)
      lastX = mouse.x
      lastY = mouse.y
    }
    onDoubleClicked: function (mouse) {
      if (mouse.button !== Qt.LeftButton) return
      board.ctl.addItem("note", board.ctl.toWorldX(mouse.x), board.ctl.toWorldY(mouse.y))
    }
    onWheel: function (wheel) {
      board.ctl.zoomAt(wheel.x, wheel.y, wheel.angleDelta.y > 0 ? 1.12 : 1 / 1.12)
    }
  }

  Item {
    id: backgroundWorld
    objectName: "background-world"
    anchors.fill: parent
    transform: [
      Scale { xScale: board.ctl.zoom; yScale: board.ctl.zoom },
      Translate { x: board.ctl.camX; y: board.ctl.camY }
    ]
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

  // Foreground items are above backgrounds and connectors.
  Item {
    id: foregroundWorld
    objectName: "foreground-world"
    anchors.fill: parent
    transform: [
      Scale { xScale: board.ctl.zoom; yScale: board.ctl.zoom },
      Translate { x: board.ctl.camX; y: board.ctl.camY }
    ]

    Repeater {
      model: board.ctl.items
      delegate: Node {
        ctl: board.ctl
        parent: ipinned ? backgroundWorld : foregroundWorld
      }
    }
  }

  // Held in world coordinates, so a zoom part-way through a drag keeps the
  // rectangle over the items it started on; only the drawing comes back to
  // the screen. Below the keyboard owner, above everything it selects.
  Rectangle {
    id: marquee
    property bool dragging: false
    property real fromX: 0
    property real fromY: 0
    property real toX: 0
    property real toY: 0
    // Not "left" and "top": those are final on Item, and shadowing them stops
    // Board.qml loading at all under the shell's Qt.
    readonly property real screenLeft: Math.min(board.ctl.toScreenX(fromX), board.ctl.toScreenX(toX))
    readonly property real screenTop: Math.min(board.ctl.toScreenY(fromY), board.ctl.toScreenY(toY))
    // A few pixels of slack, so a plain click on the canvas stays a click.
    readonly property bool wide: Math.abs(board.ctl.toScreenX(toX) - board.ctl.toScreenX(fromX)) > 4
                                 || Math.abs(board.ctl.toScreenY(toY) - board.ctl.toScreenY(fromY)) > 4
    visible: dragging && wide
    x: screenLeft
    y: screenTop
    width: Math.abs(board.ctl.toScreenX(toX) - board.ctl.toScreenX(fromX))
    height: Math.abs(board.ctl.toScreenY(toY) - board.ctl.toScreenY(fromY))
    color: Qt.rgba(board.ctl.accent.r, board.ctl.accent.g, board.ctl.accent.b, 0.12)
    border.width: board.ctl.borderWidth
    border.color: board.ctl.accent
    radius: board.ctl.cornerRadius
  }

  // A pasted picture is measured before it is placed, so it lands at its own
  // proportions rather than in a box that squashes it. Never shown: only an
  // open board has a scene that will load an image at all, which is why this
  // lives here rather than on the controller.
  Image {
    id: sizeProbe
    visible: false
    cache: false
    asynchronous: true
    property string pending: ""
    onStatusChanged: {
      if (pending === "" || (status !== Image.Ready && status !== Image.Error)) return
      var name = pending
      // Read off before the source is cleared: clearing it takes the natural
      // size with it.
      var w = status === Image.Ready ? implicitWidth : 0
      var h = status === Image.Ready ? implicitHeight : 0
      pending = ""
      source = ""
      board.ctl.pasteImage(name, w, h)
    }
  }

  // Pictures dragged in from a file manager. Above the canvas so the whole
  // board is a target, below the keyboard owner so nothing about typing
  // changes. The world point is worked out here, while the drop still knows
  // where it happened.
  DropArea {
    id: dropTarget
    anchors.fill: parent
    keys: ["text/uri-list"]
    onDropped: function (drop) {
      if (!drop.hasUrls) { drop.accepted = false; return }
      board.ctl.dropFiles(drop.urls, board.ctl.toWorldX(drop.x), board.ctl.toWorldY(drop.y))
      drop.acceptProposedAction()
    }
  }

  // Says the board will take it, before it is let go of.
  Rectangle {
    anchors.fill: parent
    visible: dropTarget.containsDrag
    color: "transparent"
    border.width: board.ctl.borderWidth * 2
    border.color: board.ctl.accent
    radius: board.ctl.cornerRadius
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
      "p": function () { board.ctl.togglePin() },
      "P": function () { board.ctl.togglePinnedSelection() },
      "s": function () { board.ctl.cycleKind() },
      "c": function () { board.ctl.recolorItem() },
      "d": function () { board.ctl.removeTargets() },
      " ": function () { board.ctl.toggleMark() },
      "a": function () { board.ctl.markAll() },
      "u": function () { board.ctl.undo() },
      "i": function () { board.ctl.editSelected() },
      "x": function () { board.ctl.toggleLinking() },
      "X": function () { board.ctl.unlinkSelected() },
      "w": function () { board.ctl.toggleWindowMode() },
      "g": function () { board.ctl.beginArrange() },
      "/": function () { board.ctl.beginFind() },
      "f": function () { board.ctl.fitToItems() },
      "b": function () { board.ctl.openBrowser() },
      "0": function () { board.ctl.resetView() },
      "+": function () { board.ctl.zoomCentre(1.2) },
      "=": function () { board.ctl.zoomCentre(1.2) },
      "-": function () { board.ctl.zoomCentre(1 / 1.2) },
      "?": function () { board.ctl.helpVisible = !board.ctl.helpVisible }
    })

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

      // While finding, every printable key is the query. Enter steps to the
      // next match rather than ending, because stepping is the common case.
      if (board.ctl.finding) {
        if (event.key === Qt.Key_Escape) board.ctl.endFind()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) board.ctl.nextMatch()
        else if (event.key === Qt.Key_Backspace) board.ctl.trimFind()
        else if (event.text && event.text >= " " && !ctrl) board.ctl.extendFind(event.text)
        event.accepted = true
        return
      }

      // Waiting for the second key of g. Anything that is not one of the
      // choices cancels, rather than being taken as the command it usually is:
      // a mistyped arrange should do nothing, not delete something.
      if (board.ctl.arranging) {
        var ad = keys.direction(event.key, event.text)
        if (ad && shift) board.ctl.spreadTargets(ad[0] !== 0 ? "x" : "y")
        else if (ad) board.ctl.alignTargets(ad[0] < 0 ? "left" : ad[0] > 0 ? "right"
                                           : ad[1] < 0 ? "top" : "bottom")
        else if (event.text === "c") board.ctl.alignTargets("centreX")
        else if (event.text === "m") board.ctl.alignTargets("centreY")
        else board.ctl.cancelArrange()
        event.accepted = true
        return
      }

      if (ctrl) {
        // Ctrl plus a movement key resizes, the same way Shift plus one moves.
        var rd = keys.direction(event.key, "")
        if (rd) board.ctl.resizeSelected(rd[0], rd[1])
        else if (event.key === Qt.Key_R) board.ctl.redo()
        else if (event.key === Qt.Key_Z) shift ? board.ctl.redo() : board.ctl.undo()
        else if (event.key === Qt.Key_S && shift) board.ctl.exportBoard()
        else if (event.key === Qt.Key_S) board.ctl.flushSave()
        else if (event.key === Qt.Key_N) board.ctl.newBoard()
        else if (event.key === Qt.Key_C) board.ctl.copySelection()
        else if (event.key === Qt.Key_D) board.ctl.duplicateTargets()
        else if (event.key === Qt.Key_V) board.ctl.pasteClipboard()
        else if (event.key === Qt.Key_O) board.ctl.importBoard()
        else if (event.key === Qt.Key_E) board.ctl.choosePng()
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
      else if (event.key === Qt.Key_F2) board.ctl.renameBoard()
      else if (event.key === Qt.Key_F1) board.ctl.helpVisible = !board.ctl.helpVisible
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) board.ctl.editSelected()
      else if (event.key === Qt.Key_Tab) board.ctl.selectNext(1)
      else if (event.key === Qt.Key_Backtab) board.ctl.selectNext(-1)
      else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) board.ctl.removeTargets()
      else if (event.key === Qt.Key_Space) board.ctl.toggleMark()
      else {
        var run = keys.commands[event.text]
        if (!run) return
        run()
      }
      event.accepted = true
    }
  }

  BoardToolbar {
    id: toolbar
    objectName: "board-toolbar"
    ctl: board.ctl
    anchors { top: parent.top; left: parent.left; right: parent.right; margins: board.ctl.sp(16) }
    height: implicitHeight
    visible: !board.ctl.browserVisible && !board.ctl.helpVisible
  }

  Column {
    width: parent.width - board.ctl.sp(64)
    anchors.horizontalCenter: parent.horizontalCenter
    y: toolbar.y + toolbar.height + Math.max(24, (board.height-toolbar.height-height)/2 - 32)
    spacing: board.ctl.sp(12)
    visible: board.ctl.boardLoaded && board.ctl.items.count === 0 && !board.ctl.browserVisible && !board.ctl.helpVisible
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Start with a thought."
      color: board.ctl.foreground
      font.family: board.ctl.fontFamily
      font.pixelSize: board.ctl.fontHeading
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "n  Write a note    Ctrl+V  Paste text"
      width: parent.width
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
      color: board.ctl.foreground
      font.family: board.ctl.fontFamily
      font.pixelSize: board.ctl.fontBody
    }
  }

  Rectangle {
    anchors { left: parent.left; right: parent.right; top: toolbar.bottom; topMargin: board.ctl.sp(8); margins: board.ctl.sp(16) }
    height: board.ctl.sp(36)
    visible: board.ctl.showPinned
    color: board.ctl.accent
    Text {
      anchors.centerIn: parent
      // Names the mode only: the keys live in the footer, which is where they
      // live for every other mode. Saying them twice, differently, was worse
      // than saying them once.
      text: "BACKGROUNDS"
      color: board.ctl.canvasBackground
      font.family: board.ctl.fontFamily
      font.pixelSize: board.ctl.fontBody
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
    opacity: 0.85
    font.family: board.ctl.fontFamily
    font.pixelSize: board.ctl.fontBody
    visible: !board.ctl.helpVisible && !board.ctl.browserVisible
    text: board.ctl.saveError !== "" ? board.ctl.saveError
      : board.ctl.trashIndexError !== "" ? board.ctl.trashIndexError
      : board.ctl.finding
      ? "find: " + board.ctl.findQuery + "▏"
        + (board.ctl.findQuery === "" ? ""
           : " · " + (board.ctl.findCount === 0 ? "no match"
                        : board.ctl.findCount === 1 ? "1 match" : board.ctl.findCount + " matches"))
        + " · enter: next · esc: done"
      : board.ctl.arranging ? "arrange · hjkl: edges · c/m: centres · HJKL: spread evenly · esc: cancel"
      : board.ctl.showPinned ? "backgrounds · tab/hjkl or click: select · p: unpin · esc: done"
      : board.ctl.statusText !== "" ? board.ctl.statusText
      : board.ctl.pendingBoard !== null ? "saving before switching boards…"
      : board.ctl.saving ? "saving…"
      : board.ctl.damaged && board.ctl.damageReason !== ""
      ? board.ctl.boardTitle + " " + board.ctl.damageReason + " — not opening it"
      : board.ctl.damaged
      ? board.ctl.boardTitle + " could not be read — not saving over it"
      : board.ctl.editIndex >= 0
      ? "esc: done typing"
      : board.ctl.linkingFrom >= 0
        ? "pick the other end, then x to connect · esc: cancel"
        : "n: note · r/e: shapes · x: connect · /: find · ?: keys · esc: close"
  }
}
