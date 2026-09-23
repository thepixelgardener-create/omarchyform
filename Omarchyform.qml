pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
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
  property color canvasBackground: Color.menu.background
  property color foreground: Color.menu.text
  property color dotColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
  property string fontFamily: Style.font.menuFamily

  // Note colors are deliberately fixed rather than themed: a board reads as a
  // board because the paper stays the same when the desktop theme changes.
  readonly property var noteColors: ["#F7D794", "#F3A0A0", "#A8D8B9", "#A3C4E8", "#D4B5E8", "#F0C9A0"]
  readonly property color noteInk: "#2C2C2A"

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchyform"
  readonly property string boardPath: root.dataDir + "/board.json"

  // The camera. screen = world * zoom + cam.
  property real camX: 0
  property real camY: 0
  property real zoom: 1
  readonly property real minZoom: 0.2
  readonly property real maxZoom: 4

  property int nextColor: 0
  property int selectedIndex: -1
  // The note currently being typed into. -1 means we are in normal mode and
  // every key is a command.
  property int editIndex: -1
  property bool helpVisible: false

  // false: fullscreen layer-shell overlay. true: an ordinary Hyprland window
  // that tiles and floats like any other app.
  property bool windowMode: false

  // Whichever board is currently instantiated, overlay or window. The camera
  // and key handling are shared state; only the surface hosting them changes.
  property var activeBoard: null
  readonly property real viewW: root.activeBoard ? root.activeBoard.width : 1920
  readonly property real viewH: root.activeBoard ? root.activeBoard.height : 1080

  function repaintGrid() { if (root.activeBoard) root.activeBoard.repaintGrid() }
  function focusKeys() { if (root.activeBoard) root.activeBoard.focusKeys() }

  function toggleWindowMode() {
    root.windowMode = !root.windowMode
    root.save()
  }

  readonly property int minNoteSize: 80
  readonly property int nudgeStep: 40

  ListModel { id: notes }

  function toWorldX(sx) { return (sx - root.camX) / root.zoom }
  function toWorldY(sy) { return (sy - root.camY) / root.zoom }

  function addNote(wx, wy) {
    notes.append({
      nx: wx - 90,
      ny: wy - 70,
      nw: 180,
      nh: 140,
      ncolor: root.noteColors[root.nextColor % root.noteColors.length],
      ntext: ""
    })
    root.nextColor += 1
    root.selectedIndex = notes.count - 1
    root.save()
  }

  function removeNote(index) {
    if (index < 0 || index >= notes.count) return
    notes.remove(index)
    if (root.selectedIndex >= notes.count) root.selectedIndex = notes.count - 1
    root.save()
  }

  function recolorNote(index) {
    if (index < 0 || index >= notes.count) return
    var current = root.noteColors.indexOf(notes.get(index).ncolor)
    var next = root.noteColors[(current + 1) % root.noteColors.length]
    notes.setProperty(index, "ncolor", next)
    root.save()
  }

  // Spatial selection: jump to the nearest note in a direction, scoring by
  // distance along the axis plus a penalty for drifting off it. This is what
  // makes hjkl feel like moving around a board rather than cycling a list.
  function selectDirection(dx, dy) {
    if (notes.count === 0) return
    if (root.selectedIndex < 0) { root.selectedIndex = 0; root.centerOnSelected(); return }
    var from = notes.get(root.selectedIndex)
    var fx = from.nx + from.nw / 2
    var fy = from.ny + from.nh / 2
    var best = -1
    var bestScore = Infinity
    for (var i = 0; i < notes.count; i++) {
      if (i === root.selectedIndex) continue
      var n = notes.get(i)
      var ax = (n.nx + n.nw / 2) - fx
      var ay = (n.ny + n.nh / 2) - fy
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
    if (notes.count === 0) return
    root.selectedIndex = ((root.selectedIndex + step) % notes.count + notes.count) % notes.count
    root.centerOnSelected()
  }

  // Keep the selected note on screen without yanking the view around when it
  // is already comfortably visible.
  function centerOnSelected() {
    if (root.selectedIndex < 0) return
    var n = notes.get(root.selectedIndex)
    var sx = n.nx * root.zoom + root.camX
    var sy = n.ny * root.zoom + root.camY
    var sw = n.nw * root.zoom
    var sh = n.nh * root.zoom
    var m = 60
    if (sx < m) root.camX += m - sx
    else if (sx + sw > root.viewW - m) root.camX -= (sx + sw) - (root.viewW - m)
    if (sy < m) root.camY += m - sy
    else if (sy + sh > root.viewH - m) root.camY -= (sy + sh) - (root.viewH - m)
    root.repaintGrid()
  }

  function nudgeSelected(dx, dy) {
    if (root.selectedIndex < 0) return
    var n = notes.get(root.selectedIndex)
    notes.setProperty(root.selectedIndex, "nx", n.nx + dx * root.nudgeStep)
    notes.setProperty(root.selectedIndex, "ny", n.ny + dy * root.nudgeStep)
    root.centerOnSelected()
    root.save()
  }

  function pan(dx, dy) {
    root.camX -= dx * 120
    root.camY -= dy * 120
    root.repaintGrid()
  }

  function editSelected() {
    if (root.selectedIndex < 0) return
    root.editIndex = root.selectedIndex
  }

  function stopEditing() {
    root.editIndex = -1
    root.focusKeys()
    root.save()
  }

  // A new note lands beside the selected one, so building a row or a column is
  // just n, n, n without touching the mouse.
  function addNoteRelative() {
    if (root.selectedIndex < 0) {
      root.addNote(root.toWorldX(root.viewW / 2), root.toWorldY(root.viewH / 2))
    } else {
      var n = notes.get(root.selectedIndex)
      root.addNote(n.nx + n.nw + 30 + 90, n.ny + 70)
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
  }

  function resetView() {
    root.camX = 0
    root.camY = 0
    root.zoom = 1
    root.repaintGrid()
  }

  // Centre the camera on everything that exists, so a board is never lost
  // off-screen after a big pan.
  function fitToNotes() {
    if (notes.count === 0) { root.resetView(); return }
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (var i = 0; i < notes.count; i++) {
      var n = notes.get(i)
      minX = Math.min(minX, n.nx)
      minY = Math.min(minY, n.ny)
      maxX = Math.max(maxX, n.nx + n.nw)
      maxY = Math.max(maxY, n.ny + n.nh)
    }
    var pad = 80
    var w = (maxX - minX) + pad * 2
    var h = (maxY - minY) + pad * 2
    root.zoom = Math.max(root.minZoom, Math.min(1, Math.min(root.viewW / w, root.viewH / h)))
    root.camX = root.viewW / 2 - ((minX + maxX) / 2) * root.zoom
    root.camY = root.viewH / 2 - ((minY + maxY) / 2) * root.zoom
    root.repaintGrid()
  }

  function save() {
    var out = []
    for (var i = 0; i < notes.count; i++) {
      var n = notes.get(i)
      out.push({ x: n.nx, y: n.ny, w: n.nw, h: n.nh, color: n.ncolor, text: n.ntext })
    }
    boardFile.setText(JSON.stringify({ version: 1, windowMode: root.windowMode, notes: out }, null, 2) + "\n")
  }

  function loadBoard(raw) {
    notes.clear()
    var parsed
    try { parsed = JSON.parse(raw) } catch (e) { return }
    if (!parsed) return
    root.windowMode = parsed.windowMode === true
    if (!parsed.notes) return
    for (var i = 0; i < parsed.notes.length; i++) {
      var n = parsed.notes[i]
      notes.append({
        nx: n.x || 0,
        ny: n.y || 0,
        nw: Math.max(root.minNoteSize, n.w || 180),
        nh: Math.max(root.minNoteSize, n.h || 140),
        ncolor: n.color || root.noteColors[0],
        ntext: n.text || ""
      })
    }
    root.nextColor = notes.count
    root.selectedIndex = -1
  }

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function () {
      root.focusKeys()
      root.repaintGrid()
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
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchyform")
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

  FileView {
    id: boardFile
    path: root.boardPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadBoard(text())
    onLoadFailed: root.loadBoard("{}")
  }
  Component {
    id: boardContent

    FocusScope {
      id: board
      anchors.fill: parent
      focus: true

      function repaintGrid() { grid.requestPaint() }
      function focusKeys() { keyCatcher.forceActiveFocus() }

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

      // Background interaction: drag to pan, wheel to zoom, double-click for a note.
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
          keyCatcher.forceActiveFocus()
        }
        onReleased: panning = false
        onPositionChanged: function (mouse) {
          if (!panning) return
          root.camX += mouse.x - lastX
          root.camY += mouse.y - lastY
          lastX = mouse.x
          lastY = mouse.y
          grid.requestPaint()
        }
        onDoubleClicked: function (mouse) {
          root.addNote(root.toWorldX(mouse.x), root.toWorldY(mouse.y))
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
          model: notes

          Rectangle {
            id: note

            required property int index
            required property real nx
            required property real ny
            required property real nw
            required property real nh
            required property color ncolor
            required property string ntext

            readonly property bool selected: root.selectedIndex === note.index

            x: note.nx
            y: note.ny
            width: note.nw
            height: note.nh
            color: note.ncolor
            radius: 6
            antialiasing: true
            border.width: note.selected ? 2 : 0
            border.color: root.noteInk

            // Header strip: a visual grab handle. The whole note is draggable,
            // but the strip tells you so at a glance.
            Rectangle {
              id: header
              anchors { top: parent.top; left: parent.left; right: parent.right }
              height: 24
              radius: parent.radius
              color: Qt.darker(note.ncolor, 1.12)
            }

            TextEdit {
              id: body
              anchors.fill: parent
              anchors.margins: 10
              anchors.topMargin: header.height + 8
              text: note.ntext
              color: root.noteInk
              font.family: root.fontFamily
              font.pixelSize: 14
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              // Guarded so the model write cannot bounce back and reset the caret.
              onTextChanged: if (text !== note.ntext) notes.setProperty(note.index, "ntext", text)
              onActiveFocusChanged: if (!activeFocus) root.save()
              Keys.onEscapePressed: root.stopEditing()

              // Entering edit mode from the keyboard focuses this editor and puts
              // the caret at the end, ready to type.
              readonly property bool wantsEdit: root.editIndex === note.index
              onWantsEditChanged: if (wantsEdit) {
                forceActiveFocus()
                cursorPosition = length
              }

            }

            // Drag anywhere on the note. Sits above the text but steps aside the
            // moment this note is being edited, so the caret still works.
            MouseArea {
              id: dragArea
              anchors.fill: parent
              enabled: root.editIndex !== note.index
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton
              cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

              property real pressX: 0
              property real pressY: 0
              property bool dragging: false

              onPressed: function (mouse) {
                pressX = mouse.x
                pressY = mouse.y
                dragging = false
                root.selectedIndex = note.index
                root.editIndex = -1
                keyCatcher.forceActiveFocus()
              }
              onPositionChanged: function (mouse) {
                if (!pressed || mouse.buttons !== Qt.LeftButton) return
                var ddx = mouse.x - pressX
                var ddy = mouse.y - pressY
                // A few pixels of slack so a click to select never nudges a note.
                if (!dragging && Math.abs(ddx) + Math.abs(ddy) < 3) return
                dragging = true
                notes.setProperty(note.index, "nx", note.nx + ddx)
                notes.setProperty(note.index, "ny", note.ny + ddy)
              }
              onReleased: {
                if (dragging) root.save()
                dragging = false
              }
              onClicked: function (mouse) {
                if (mouse.button === Qt.MiddleButton) root.removeNote(note.index)
              }
              onDoubleClicked: function (mouse) {
                root.editIndex = note.index
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

              onPressed: function (mouse) {
                pressX = mouse.x
                pressY = mouse.y
                root.selectedIndex = note.index
              }
              onPositionChanged: function (mouse) {
                if (!pressed) return
                notes.setProperty(note.index, "nw", Math.max(root.minNoteSize, note.nw + (mouse.x - pressX)))
                notes.setProperty(note.index, "nh", Math.max(root.minNoteSize, note.nh + (mouse.y - pressY)))
              }
              onReleased: root.save()

              Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 2
                rotation: -45
                color: root.noteInk
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
          var k = event.key

          // Movement keys do double duty: bare keys move the selection, shifted
          // keys carry the selected note along with them.
          var dx = 0, dy = 0
          if (k === Qt.Key_H || k === Qt.Key_Left) dx = -1
          else if (k === Qt.Key_L || k === Qt.Key_Right) dx = 1
          else if (k === Qt.Key_K || k === Qt.Key_Up) dy = -1
          else if (k === Qt.Key_J || k === Qt.Key_Down) dy = 1

          if (dx !== 0 || dy !== 0) {
            if (shift) root.nudgeSelected(dx, dy)
            else if (root.selectedIndex < 0) root.pan(dx, dy)
            else root.selectDirection(dx, dy)
            event.accepted = true
            return
          }

          if (k === Qt.Key_Question || k === Qt.Key_F1) {
            root.helpVisible = !root.helpVisible
          } else if (k === Qt.Key_Escape) {
            // Escape backs out of the cheat sheet before it closes the board.
            if (root.helpVisible) root.helpVisible = false
            else root.dismiss()
          } else if (k === Qt.Key_N) {
            root.addNoteRelative()
          } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_I) {
            root.editSelected()
          } else if (k === Qt.Key_Tab) {
            root.selectNext(1)
          } else if (k === Qt.Key_Backtab) {
            root.selectNext(-1)
          } else if (k === Qt.Key_D || k === Qt.Key_Delete || k === Qt.Key_Backspace) {
            root.removeNote(root.selectedIndex)
          } else if (k === Qt.Key_C) {
            root.recolorNote(root.selectedIndex)
          } else if (k === Qt.Key_W) {
            root.toggleWindowMode()
          } else if (k === Qt.Key_F) {
            root.fitToNotes()
          } else if (k === Qt.Key_0) {
            root.resetView()
          } else if (k === Qt.Key_Plus || k === Qt.Key_Equal) {
            root.zoomAt(board.width / 2, board.height / 2, 1.2)
          } else if (k === Qt.Key_Minus) {
            root.zoomAt(board.width / 2, board.height / 2, 1 / 1.2)
          } else if (k === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
            root.save()
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
        width: helpColumn.width + Style.space(56)
        height: helpColumn.height + Style.space(48)
        color: root.canvasBackground
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
        radius: Style.cornerRadius

        Column {
          id: helpColumn
          anchors.centerIn: parent
          spacing: Style.space(6)

          Text {
            text: "Omarchyform"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 16
            bottomPadding: Style.space(8)
          }

          Repeater {
            model: [
              ["n", "new note beside the selected one"],
              ["enter / i", "type in the selected note"],
              ["esc", "stop typing, then close the board"],
              ["h j k l", "move the selection around"],
              ["H J K L", "push the selected note"],
              ["tab", "cycle through every note"],
              ["d", "delete the selected note"],
              ["c", "change its colour"],
              ["w", "fullscreen or windowed"],
            ["f", "fit the whole board on screen"],
              ["0", "reset the view"],
              ["+ / -", "zoom"],
              ["? / F1", "this list"],
              ["drag", "move a note, or the canvas"],
              ["wheel", "zoom at the pointer"]
            ]

            Row {
              required property var modelData
              spacing: Style.space(16)

              Text {
                width: Style.space(90)
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
        anchors.bottomMargin: Style.space(16)
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: 12
        visible: !root.helpVisible
        text: root.editIndex >= 0
          ? "esc: done typing"
          : "n: new  ·  hjkl: move around  ·  enter: type  ·  d: delete  ·  w: " + (root.windowMode ? "fullscreen" : "windowed") + "  ·  ?: all keys  ·  esc: close"
      }
    }
  }

  // Fullscreen overlay, above everything, its own keyboard grab.
  PanelWindow {
    id: panel
    visible: root.opened && !root.windowMode
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchyform"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Loader {
      anchors.fill: parent
      focus: true
      active: panel.visible
      sourceComponent: boardContent
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
