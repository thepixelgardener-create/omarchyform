pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store

// The canvas surface. Hosted by either the fullscreen overlay or the windowed
// toplevel; both share one controller, so switching never loses your place.
FocusScope {
  id: board

  required property var ctl
  readonly property var theme: board.ctl.theme

  focus: true
  readonly property real headerHeight: toolbar.y + toolbar.height
  // Where the canvas comes clear of everything laid over its top: the header,
  // the backgrounds banner, and the line of hints or the find query under
  // them. That line wraps in a narrow window, so framing the board from the
  // header alone put its top row underneath the hints.
  readonly property real canvasTop: Math.max(headerHeight,
    banner.visible ? banner.y + banner.height : 0,
    status.visible ? status.y + status.height : 0,
    findLine.visible ? findLine.y + findLine.height : 0)

  property string exportDestination: ""

  function exportPng(path) {
    if (board.ctl.imageBusy) return
    if (board.ctl.items.count === 0) { board.ctl.flash("Add a note before exporting an image"); return }
    board.ctl.imageBusy = true
    exportDestination = path
    picture.exportColors = board.ctl.pngPalette
    // What is marked is what the picture is framed around; with nothing marked
    // it is the whole board, which is what exporting has always meant.
    picture.crop = board.ctl.targets()
    picture.save(board.ctl.dataDir + "/.image-export.png")
  }
  BoardImage {
    id: picture
    ctl: board.ctl
    onFinished: function(success, reason) {
      if (success) board.ctl.finishPng(board.exportDestination)
      else { board.ctl.imageBusy = false; board.ctl.flash(reason !== "" ? reason : "Could not render PNG") }
    }
    onStillLoading: board.ctl.flash("Waiting for pictures to load…")
  }

  // A connector as the board draws it: the line and head that
  // Store.connectorGeometry worked out in board units, through the camera.
  // The camera is passed in rather than asked for through ctl.toScreenX: this
  // runs for every corner of every connector on every frame of a pan, and a
  // call into the controller costs more than the arithmetic it does.
  function strokeConnector(ctx, g, zoom, camX, camY) {
    ctx.beginPath()
    ctx.moveTo(g.fromX * zoom + camX, g.fromY * zoom + camY)
    ctx.lineTo(g.toX * zoom + camX, g.toY * zoom + camY)
    ctx.stroke()
  }
  function fillArrowHead(ctx, g, zoom, camX, camY) {
    ctx.beginPath()
    ctx.moveTo(g.toX * zoom + camX, g.toY * zoom + camY)
    ctx.lineTo(g.leftX * zoom + camX, g.leftY * zoom + camY)
    ctx.lineTo(g.rightX * zoom + camX, g.rightY * zoom + camY)
    ctx.closePath()
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

  // Both canvases paint with colours rather than bind to them, so a theme
  // change has to be told to them.
  Connections {
    target: board.theme
    function onDotColorChanged() { board.repaintGrid() }
    function onForegroundChanged() { board.repaintLinks() }
  }

  // A real window hands focus to its content item, not to whatever is nested
  // inside it, so claim it explicitly on both surfaces.
  // With two panes, only the one the keyboard is in takes it. Later rather
  // than now, and only if this board is still here by then: a window resized
  // across the room for two panes builds and drops boards in one turn.
  Component.onCompleted: {
    board.ctl.activeBoard = board
    Qt.callLater(function () {
      if (typeof board.focusKeys === "function" && board.ctl && board.ctl.active) board.focusKeys()
    })
  }
  Component.onDestruction: if (board.ctl.activeBoard === board) board.ctl.activeBoard = null

  Rectangle {
    anchors.fill: parent
    color: board.theme.canvasBackground
  }

  // Patterns and connectors are drawn in screen space so they keep their weight
  // however far you zoom out, rather than scaling into mush.
  Canvas {
    id: grid
    anchors.fill: parent
    visible: board.ctl.showGrid
    readonly property string pattern: board.ctl.canvasPattern
    onPatternChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var step = 40 * board.ctl.zoom
      if (step < 8) return
      // The origin stays attached to the world, including when the camera
      // crosses zero. Lines use one path and one stroke per repaint.
      var startX = ((board.ctl.camX % step) + step) % step
      var startY = ((board.ctl.camY % step) + step) % step
      if (grid.pattern === "Grid" || grid.pattern === "Ruled") {
        ctx.strokeStyle = board.theme.dotColor
        ctx.lineWidth = 1
        // A continuous line carries more ink than a dot; keep it behind the
        // notes. Snap to pixels so a stationary line stays crisp.
        ctx.globalAlpha = 0.65
        ctx.beginPath()
        if (grid.pattern === "Grid") {
          for (var gx = startX; gx < width; gx += step) {
            var px = Math.floor(gx) + 0.5
            ctx.moveTo(px, 0)
            ctx.lineTo(px, height)
          }
        }
        for (var gy = startY; gy < height; gy += step) {
          var py = Math.floor(gy) + 0.5
          ctx.moveTo(0, py)
          ctx.lineTo(width, py)
        }
        ctx.stroke()
        return
      }
      ctx.fillStyle = board.theme.dotColor
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

  // Background: left drag draws a marquee, right drag pans, wheel zooms,
  // double-click leaves a note. The middle button is not listed because it
  // never reaches here: the pan surface further down owns it for the whole
  // canvas, so a middle drag pans the same way whether it starts on bare
  // canvas or on top of something.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    property real lastX: 0
    property real lastY: 0
    property bool panning: false
    property bool additive: false
    // A right button that never moved is a click, not a pan: the one gesture
    // that asks what can be done with what is selected.
    property bool dragged: false

    onPressed: function (mouse) {
      lastX = mouse.x
      lastY = mouse.y
      dragged = false
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
    onReleased: function (mouse) {
      panning = false
      if (mouse.button === Qt.RightButton && !dragged) {
        board.ctl.beginSelectionActions()
        return
      }
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
      if (Math.abs(mouse.x - lastX) + Math.abs(mouse.y - lastY) > 0) dragged = true
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
      ctx.strokeStyle = board.theme.foreground
      ctx.fillStyle = board.theme.foreground
      ctx.lineWidth = Math.max(1, 1.5 * board.ctl.zoom)
      ctx.globalAlpha = Store.CONNECTOR_ALPHA
      var zoom = board.ctl.zoom, camX = board.ctl.camX, camY = board.ctl.camY
      // Never smaller on screen than 7 pixels, however far out the view is.
      var head = Math.max(7, 7 * zoom) / zoom

      var items = board.ctl.items
      var links = board.ctl.links
      var byId = Store.idIndex(items)

      for (var i = 0; i < links.count; i++) {
        var l = links.get(i)
        var ai = byId[l.lfrom]
        var bi = byId[l.lto]
        if (ai === undefined || bi === undefined) continue
        var g = Store.connectorGeometry(items.get(ai), items.get(bi), head)
        board.strokeConnector(ctx, g, zoom, camX, camY)
        board.fillArrowHead(ctx, g, zoom, camX, camY)
      }

      // While picking the far end, trail a dashed line to the selection so it
      // is obvious what is about to be joined: edge to edge, where the
      // connector it would make is going to run.
      var si = byId[board.ctl.linkingFrom]
      if (si !== undefined && board.ctl.selectedIndex >= 0 && si !== board.ctl.selectedIndex) {
        ctx.globalAlpha = 0.9
        ctx.setLineDash([6, 5])
        board.strokeConnector(ctx, Store.connectorGeometry(items.get(si), items.get(board.ctl.selectedIndex), 0),
                              zoom, camX, camY)
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
        // Stacked by place on the board rather than left to the repeater: it
        // stands each item after the one before it, and cannot once that one
        // is a background living in the other layer — so an item brought
        // forward over a board that starts with one stayed where it was.
        z: index
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
    color: Qt.rgba(board.theme.accent.r, board.theme.accent.g, board.theme.accent.b, 0.12)
    border.width: board.theme.borderWidth
    border.color: board.theme.accent
    radius: board.theme.cornerRadius
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
      if (pending === "" || (sizeProbe.status !== Image.Ready && sizeProbe.status !== Image.Error)) return
      var name = pending
      // Read off before the source is cleared: clearing it takes the natural
      // size with it.
      var w = sizeProbe.status === Image.Ready ? sizeProbe.implicitWidth : 0
      var h = sizeProbe.status === Image.Ready ? sizeProbe.implicitHeight : 0
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
    border.width: board.theme.borderWidth * 2
    border.color: board.theme.accent
    radius: board.theme.cornerRadius
  }

  // Keyboard owner. Lives above the canvas so Escape always lands here.
  Item {
    id: keys
    anchors.fill: parent
    // Focus moves between the canvas and the browser declaratively. Leaving
    // both claiming it strands the keyboard on whichever hid last.
    focus: !board.ctl.browsing

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
      " ": function () { board.ctl.toggleMark() },
      "a": function () { board.ctl.markAll() },
      "u": function () { board.ctl.undo() },
      "i": function () { board.ctl.editSelected() },
      "x": function () { board.ctl.toggleLinking() },
      "X": function () { board.ctl.unlinkSelected() },
      "w": function () { board.ctl.toggleWindowMode() },
      "v": function () { board.ctl.toggleSplit("side-by-side") },
      "V": function () { board.ctl.toggleSplit("stacked") },
      "o": function () { board.ctl.otherPane() },
      "g": function () { board.ctl.beginArrange() },
      "/": function () { board.ctl.beginFind() },
      "m": function () { board.ctl.toggleMenu() },
      "f": function () { board.ctl.fitToItems() },
      "b": function () { board.ctl.openBrowser() },
      "0": function () { board.ctl.resetView() },
      "+": function () { board.ctl.zoomCentre(1.2) },
      "=": function () { board.ctl.zoomCentre(1.2) },
      "-": function () { board.ctl.zoomCentre(1 / 1.2) },
      "?": function () { board.ctl.toggleHelp() },
      ":": function () { board.ctl.beginPalette() },
      ".": function () { board.ctl.beginSelectionActions() },
      "]": function () { board.ctl.layerTargets("forward") },
      "[": function () { board.ctl.layerTargets("backward") },
      "}": function () { board.ctl.layerTargets("front") },
      "{": function () { board.ctl.layerTargets("back") }
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
        else if (event.key === Qt.Key_Down || event.text === "j") help.scroll(board.theme.fontBody * 2)
        else if (event.key === Qt.Key_Up || event.text === "k") help.scroll(-board.theme.fontBody * 2)
        else if (event.key === Qt.Key_PageDown) help.scroll(help.height * 0.8)
        else if (event.key === Qt.Key_PageUp) help.scroll(-help.height * 0.8)
        event.accepted = true
        return
      }
      var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
      var shift = (event.modifiers & Qt.ShiftModifier) !== 0

      // The menu is open: the keyboard walks it. Anything that is not one of
      // these closes it without running its usual command, the same rule the
      // arrange mode follows.
      if (board.ctl.menuVisible) {
        var md = keys.direction(event.key, event.text)
        if (event.key === Qt.Key_Escape || event.text === "m") board.ctl.toggleMenu()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) board.ctl.runMenu(board.ctl.menuIndex)
        else if (event.key === Qt.Key_Tab) board.ctl.moveMenu(shift ? -1 : 1)
        else if (event.key === Qt.Key_Backtab) board.ctl.moveMenu(-1)
        else if (md) board.ctl.moveMenu(md[0] !== 0 ? md[0] : md[1])
        else board.ctl.menuVisible = false
        event.accepted = true
        return
      }

      // Two versions of the board, and a question that does not go away. It
      // takes the keyboard while it is up, but closing it decides nothing.
      if (board.ctl.conflictVisible) {
        var cd = keys.direction(event.key, event.text)
        if (event.key === Qt.Key_Escape) board.ctl.endConflictChoice()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) board.ctl.runConflictChoice()
        else if (event.text === "1") { board.ctl.conflictIndex = 0; board.ctl.runConflictChoice() }
        else if (event.text === "2") { board.ctl.conflictIndex = 1; board.ctl.runConflictChoice() }
        else if (event.text === "3") { board.ctl.conflictIndex = 2; board.ctl.runConflictChoice() }
        else if (event.key === Qt.Key_Tab) board.ctl.moveConflict(shift ? -1 : 1)
        else if (event.key === Qt.Key_Backtab) board.ctl.moveConflict(-1)
        else if (cd) board.ctl.moveConflict(cd[1] !== 0 ? cd[1] : cd[0])
        event.accepted = true
        return
      }

      // The palette is open: the query is a text field with the keyboard in
      // it, so what reaches here is what the field does not want. The list is
      // walked with the arrows or tab rather than j and k — here those are
      // letters, the same way they are while finding.
      if (board.ctl.paletteVisible) {
        board.paletteKey(event)
        // Nothing else on the board runs while the palette is up, whether or
        // not the field has the keyboard: a letter typed at it is a letter.
        event.accepted = true
        return
      }

      // The query is a text field with the keyboard in it, so what reaches
      // here while finding is what the field does not want. Enter steps to the
      // next match rather than ending, because stepping is the common case.
      if (board.ctl.finding) {
        board.findKey(event)
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

      // Omarchy normally forwards Super+C/V as Ctrl+C/V. Handle Meta
      // directly too when the compositor leaves those chords to the app.
      if ((event.modifiers & Qt.MetaModifier) !== 0) {
        if (event.key === Qt.Key_C) board.ctl.copySelection()
        else if (event.key === Qt.Key_V) board.ctl.pasteClipboard()
        else return
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
        else if (event.key === Qt.Key_E) board.ctl.choosePng("theme")
        else if (event.key === Qt.Key_P) board.ctl.beginPalette()
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
      else if (event.key === Qt.Key_F1) board.ctl.toggleHelp()
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) board.ctl.editSelected()
      else if (event.key === Qt.Key_Tab) board.ctl.selectNext(1)
      else if (event.key === Qt.Key_Backtab) board.ctl.selectNext(-1)
      // Delete and Backspace, and nothing shorter. `d` sat in the table beside
      // s, c and e, so a finger one key out destroyed what it was aiming at;
      // the two keys that mean delete everywhere else say so themselves.
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

  // Middle drag pans, wherever it starts. It sits above the canvas and
  // everything drawn on it, and below the header, the panels and the browser,
  // which own their own input.
  //
  // Above the items on purpose. A middle press used to land on whatever was
  // under it: on an item it selected and then deleted it, and on a note being
  // typed in it reached the editor underneath, where the middle button pastes
  // the primary selection. Taking the button away from each of those in turn
  // leaves the next one to find. Taking it here means none of them are ever
  // offered it, so a pan cannot select, move, resize, type into, paste over or
  // delete what it crosses — and a middle press that never moves does nothing
  // at all.
  //
  // The displacement is read in screen pixels and handed to the camera
  // unchanged, so the board keeps up with the pointer at any zoom. Measuring
  // it inside an item would give world units instead, which is a pan that
  // runs four times too fast at 400%.
  //
  // Only the middle button is accepted, so a left press, a right press, a
  // hover and the wheel all fall straight through to what is underneath. It
  // sets no cursor shape for the same reason: an item's own cursor still wins.
  MouseArea {
    id: panSurface
    objectName: "pan-surface"
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
    property real lastX: 0
    property real lastY: 0
    onPressed: function (mouse) {
      panSurface.lastX = mouse.x
      panSurface.lastY = mouse.y
    }
    onPositionChanged: function (mouse) {
      board.ctl.panBy(mouse.x - panSurface.lastX, mouse.y - panSurface.lastY)
      panSurface.lastX = mouse.x
      panSurface.lastY = mouse.y
    }
  }

  // The board steps back while a panel is asking for attention, as the desktop
  // does behind the shell's own menu. Over the canvas and under the header and
  // the line beneath it, which go on saying what the keys do in that panel.
  // The browser dims everything itself, header and all, as it covers it.
  Rectangle {
    objectName: "panel-scrim"
    anchors.fill: parent
    visible: board.ctl.paletteVisible || board.ctl.conflictVisible || board.ctl.helpVisible
    color: board.theme.panelScrim
  }

  BoardToolbar {
    id: toolbar
    objectName: "board-toolbar"
    ctl: board.ctl
    anchors { top: parent.top; left: parent.left; right: parent.right; margins: board.theme.sp(16) }
    height: implicitHeight
    visible: !board.ctl.browsing && !board.ctl.helpVisible
  }

  Column {
    width: parent.width - board.theme.sp(64)
    anchors.horizontalCenter: parent.horizontalCenter
    y: toolbar.y + toolbar.height + Math.max(24, (board.height-toolbar.height-height)/2 - 32)
    spacing: board.theme.sp(12)
    visible: board.ctl.boardLoaded && board.ctl.items.count === 0 && !board.ctl.browsing && !board.ctl.helpVisible
    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Start with a thought."
      color: board.theme.foreground
      font.family: board.theme.fontFamily
      font.pixelSize: board.theme.fontHeading
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.StyledText
      text: Store.hintLine(Store.START_HINTS, board.ctl.accentMarkup)
      width: parent.width
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
      color: board.theme.foreground
      font.family: board.theme.fontFamily
      font.pixelSize: board.theme.fontBody
    }
  }

  Rectangle {
    id: banner
    anchors { left: parent.left; right: parent.right; top: toolbar.bottom; topMargin: board.theme.sp(8); margins: board.theme.sp(16) }
    height: board.theme.sp(36)
    visible: board.ctl.showPinned
    color: board.theme.accent
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      // Names the mode only: the keys live on the line below, where they live
      // for every other mode. Saying them twice, differently, was worse than
      // saying them once.
      text: "BACKGROUNDS"
      color: board.theme.canvasBackground
      font.family: board.theme.fontFamily
      font.pixelSize: board.theme.fontBody
    }
  }

  // Where the palette goes, for the same reason, and never both at once.
  Conflict {
    id: conflictPanel
    objectName: "conflict-panel"
    ctl: board.ctl
    anchors.horizontalCenter: parent.horizontalCenter
    // Below the line under the header, not a fixed distance below the header:
    // that line wraps in a narrow window, and its second row drew over the top
    // of the panel.
    y: board.canvasTop + board.theme.sp(8)
  }

  // Under the header, where the eye already is when a command is wanted, and
  // above the canvas because it is a mode rather than part of the board.
  Commands {
    id: commandPalette
    objectName: "command-palette"
    ctl: board.ctl
    board: board
    anchors.horizontalCenter: parent.horizontalCenter
    y: board.canvasTop + board.theme.sp(8)
  }

  // The board browser sits above the canvas and takes the keyboard while open.
  Browser {
    anchors.fill: parent
    ctl: board.ctl
    library: board.ctl.library
    shown: board.ctl.browsing
  }

  // Help consumes input so browsing shortcuts cannot edit the board behind it,
  // and every button of it: the pan surface is underneath, and the canvas is
  // not something to be moved around behind a panel covering it.
  MouseArea {
    anchors.fill: parent
    visible: board.ctl.helpVisible
    acceptedButtons: Qt.AllButtons
    onClicked: function (mouse) { if (mouse.button === Qt.LeftButton) board.ctl.helpVisible = false }
  }
  Help {
    id: help
    objectName: "help-panel"
    anchors.centerIn: parent
    ctl: board.ctl
  }

  // What the palette's query field does not own. Two callers: the field, which
  // has the keyboard while the palette is up, and the board's handler behind
  // it, so a field that has somehow not been given the keyboard cannot leave
  // the board running commands under the panel.
  function paletteKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (event.key === Qt.Key_Escape) board.ctl.endPalette()
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) board.ctl.runPaletteChoice()
    else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) board.ctl.movePalette(1)
    else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) board.ctl.movePalette(-1)
    else if (ctrl && event.key === Qt.Key_N) board.ctl.movePalette(1)
    else if (ctrl && event.key === Qt.Key_P) board.ctl.movePalette(-1)
    else return
    event.accepted = true
  }

  // What the query field does not own. The field has the keyboard while
  // finding, so this is what it hands back; the board's own handler calls the
  // same function, because a field that has somehow not been given the
  // keyboard must not leave escape meaning "close the board".
  function findKey(event) {
    if (event.key === Qt.Key_Escape) board.ctl.endFind()
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) board.ctl.nextMatch()
    else return
    event.accepted = true
  }

  // The find query, in the status line's place while it is being typed. A
  // drawn cursor after a string that only ever grew at the end could not be
  // moved through, selected, pasted into, or composed in a language that needs
  // an input method — and the board it searches can be written in one.
  Row {
    id: findLine
    visible: board.ctl.finding && !board.ctl.helpVisible && !board.ctl.browsing
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: banner.visible ? banner.bottom : toolbar.bottom
    anchors.topMargin: board.theme.sp(8)
    width: Math.min(parent.width - board.theme.sp(32), implicitWidth)
    height: implicitHeight

    Text {
      textFormat: Text.PlainText
      id: findLabel
      text: "find: "
      color: board.theme.foreground
      opacity: 0.85
      font.family: board.theme.fontFamily
      font.pixelSize: board.theme.fontBody
    }

    TextInput {
      id: findField
      // Wide enough to see the caret in an empty query, and it grows with what
      // is typed rather than reserving a box the board has to look at.
      width: Math.max(board.theme.sp(24), Math.min(implicitWidth + board.theme.sp(2), board.width / 3))
      clip: true
      color: board.theme.foreground
      selectionColor: board.theme.accent
      selectedTextColor: board.theme.canvasBackground
      selectByMouse: true
      font.family: board.theme.fontFamily
      font.pixelSize: board.theme.fontBody

      // Typed into, it is the query. Set from anywhere else — a test, the
      // screenshot harness, a find reopened on the query it had — it follows,
      // so the two cannot show different things. Both sides check before
      // writing, so neither can chase the other.
      Accessible.role: Accessible.EditableText
      Accessible.name: "Find on this board"
      Accessible.description: board.ctl.findCount + " matches"

      onTextChanged: board.ctl.setFindQuery(text)
      readonly property string query: board.ctl.findQuery
      onQueryChanged: if (findField.query !== findField.text) findField.text = findField.query

      // Deferred for the same reason the browser's field defers: whatever
      // else is being set as finding begins lands here on its own, and
      // selecting has to be the last thing that happens.
      readonly property bool wanted: board.ctl.finding
      onWantedChanged: {
        if (!wanted) { board.ctl.focusKeys(); return }
        Qt.callLater(function () {
          if (!board.ctl.finding) return
          findField.text = board.ctl.findQuery
          findField.forceActiveFocus()
          findField.selectAll()
        })
      }

      // The board decides what these two mean; everything else is typing.
      Keys.onPressed: function (event) { board.findKey(event) }
    }

    Text {
      textFormat: Text.StyledText
      // As wide as it needs, and no wider: a Row is as wide as its children,
      // and one child claiming the rest of the window pushes the line it is
      // centred in over to the left. A theme with large text in a small window
      // wraps it instead, the way the status line it stands in for wrapped.
      width: Math.min(implicitWidth,
                      Math.max(0, board.width - board.theme.sp(32) - findLabel.width - findField.width))
      wrapMode: Text.Wrap
      color: board.theme.foreground
      opacity: 0.85
      font.family: board.theme.fontFamily
      font.pixelSize: board.theme.fontBody
      text: (board.ctl.findQuery === "" ? ""
             : " · " + (board.ctl.findCount === 0 ? "no match"
                        : board.ctl.findCount === 1 ? "1 match" : board.ctl.findCount + " matches"))
            + " · " + Store.hintLine(Store.FIND_HINTS, board.ctl.accentMarkup)
    }
  }

  // Under the header rather than at the far edge: the name, the commands and
  // whatever the board is saying are one block to look at, and the bottom of
  // the canvas is left to the board.
  Text {
    id: status
    objectName: "board-status"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: board.theme.sp(16)
    anchors.rightMargin: board.theme.sp(16)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    anchors.top: banner.visible ? banner.bottom : toolbar.bottom
    anchors.topMargin: board.theme.sp(8)
    color: board.theme.foreground
    opacity: 0.85
    font.family: board.theme.fontFamily
    font.pixelSize: board.theme.fontBody
    visible: status.tier !== "none"
    // Markup, so a key can be a different colour from the word it sits in.
    // Everything reaching this line from a board file, a file name or the
    // keyboard is escaped on the way: this is the one place on the board that
    // renders tags, and a board is a file other people can send you.
    textFormat: Text.StyledText
    // Which of the things wanting this line gets it is decided in BoardStore,
    // by the same call the controller makes to know whether a failure is on
    // screen and its time is running. Here it is only joined and coloured.
    readonly property string tier: Store.statusTier(board.ctl.statusState())
    text:
      status.tier === "saveError" ? Store.escapeMarkup(board.ctl.saveError)
      : status.tier === "trashIndexError" ? Store.escapeMarkup(board.ctl.library.trashIndexError)
      : status.tier === "conflict"
      ? Store.escapeMarkup(board.ctl.boardTitle) + " changed on disk · "
        + Store.hintMarkup("ctrl+s", "choose which version to keep", board.ctl.accentMarkup)
      : status.tier === "damaged"
      ? Store.escapeMarkup(board.ctl.damageReason !== ""
          ? board.ctl.boardTitle + " " + board.ctl.damageReason + " — not opening it"
          : board.ctl.boardTitle + " could not be read — not saving over it")
      // Escaped like any other text that has been through a file name or a
      // helper's output: this is the one place on the board that renders tags.
      : status.tier === "failure" ? Store.escapeMarkup(board.ctl.failureText)
      : status.tier === "palette"
      ? "commands · " + Store.hintLine(Store.PALETTE_HINTS, board.ctl.accentMarkup)
      : status.tier === "arrange"
      ? "arrange · " + Store.hintLine(Store.ARRANGE_HINTS, board.ctl.accentMarkup)
      : status.tier === "backgrounds"
      ? "backgrounds · " + Store.hintLine(Store.PINNED_HINTS, board.ctl.accentMarkup)
      : status.tier === "editing"
      ? Store.hintMarkup("esc", "done typing", board.ctl.accentMarkup)
      // While the far end is being chosen, the line says what x will do to
      // this pair rather than what x is for: connect them, turn the one that
      // is already there round, or take it away. The controller works that out
      // from the same table addLink changes, so the line cannot promise one
      // thing and the board do another.
      : status.tier === "linking"
      ? Store.linkHint(board.ctl.linkOutcome, board.ctl.accentMarkup)
      : status.tier === "flash" ? Store.escapeMarkup(board.ctl.statusText)
      : status.tier === "switching" ? "saving before switching boards…"
      : status.tier === "saving" ? "saving…"
      // The other pane is still there when the window is too small to show
      // it, and the line says how to reach it rather than leave it forgotten.
      : (board.ctl.squeezed ? Store.hintMarkup("o", "the other pane", board.ctl.accentMarkup) + " \u00b7 " : "")
        + Store.hintLine(Store.BOARD_HINTS, board.ctl.accentMarkup)
  }

  // Which of two panes the keys go to: the accent round its edge, the way the
  // desktop marks the focused window. Nothing at all with one pane.
  Rectangle {
    objectName: "active-pane"
    anchors.fill: parent
    visible: board.ctl.split && board.ctl.active
    color: "transparent"
    border.width: board.theme.borderWidth * 2
    border.color: board.theme.accent
  }

  // A press on the pane that is only being looked at moves the keyboard here,
  // then carries on to whatever is under it, so the click that chooses a pane
  // can also be the one that selects, drags or pans in it. It takes no
  // buttons once the pane is active, and none at all with one pane.
  MouseArea {
    objectName: "pane-activation"
    anchors.fill: parent
    enabled: board.ctl.split && !board.ctl.active
    acceptedButtons: Qt.AllButtons
    onPressed: function (mouse) {
      board.ctl.activate()
      mouse.accepted = false
    }
  }
}
