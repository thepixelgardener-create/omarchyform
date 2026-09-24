pragma ComponentBehavior: Bound

import QtQuick

// One thing on the board: a note, a box, an ellipse or a diamond.
// Model roles arrive as required properties; everything else comes from ctl.
Item {
  id: node

  required property var ctl
  required property int index
  required property int iid
  required property string kind
  required property real ix
  required property real iy
  required property real iw
  required property real ih
  required property string itint
  required property string itext

  readonly property bool selected: node.ctl.selectedIndex === node.index
  readonly property bool linkSource: node.ctl.linkingFrom === node.iid
  readonly property bool isNote: node.kind === "note"
  readonly property bool painted: node.kind === "ellipse" || node.kind === "diamond"
  readonly property bool emphasised: node.selected || node.linkSource
  readonly property color fill: node.ctl.tintFill(node.itint, node.emphasised)
  readonly property color outline: node.linkSource
    ? node.ctl.accent
    : node.ctl.tintBorder(node.itint, node.selected)

  x: node.ix
  y: node.iy
  width: node.iw
  height: node.ih

  onXChanged: node.ctl.repaintLinks()
  onYChanged: node.ctl.repaintLinks()
  onWidthChanged: node.ctl.repaintLinks()
  onHeightChanged: node.ctl.repaintLinks()

  function set(role, value) { node.ctl.items.setProperty(node.index, role, value) }

  // Notes and boxes are plain Rectangles; ellipses and diamonds need a path.
  Rectangle {
    anchors.fill: parent
    visible: !node.painted
    color: node.fill
    radius: node.ctl.cornerRadius
    antialiasing: true
    border.width: node.emphasised ? node.ctl.borderWidth * 2 : node.ctl.borderWidth
    border.color: node.outline
  }

  Canvas {
    id: shape
    anchors.fill: parent
    visible: node.painted
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
      ctx.fillStyle = node.fill
      ctx.fill()
      ctx.strokeStyle = node.outline
      ctx.lineWidth = node.emphasised ? node.ctl.borderWidth * 2 : node.ctl.borderWidth
      ctx.stroke()
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Connections {
      target: node
      function onFillChanged() { shape.requestPaint() }
      function onOutlineChanged() { shape.requestPaint() }
      function onKindChanged() { shape.requestPaint() }
      function onSelectedChanged() { shape.requestPaint() }
      function onLinkSourceChanged() { shape.requestPaint() }
    }
  }

  // A note has a grab strip at the top; shapes read better without.
  // A note gets a rule across the top: the same grab affordance as a filled
  // title bar, drawn the way the rest of the shell draws a divider.
  Rectangle {
    id: header
    anchors { top: parent.top; left: parent.left; right: parent.right }
    anchors.margins: node.ctl.borderWidth
    height: node.ctl.borderWidth * 3
    visible: node.isNote
    color: node.outline
  }

  TextEdit {
    id: body
    anchors.fill: parent
    anchors.margins: node.ctl.sp(10)
    anchors.topMargin: node.isNote ? header.height + node.ctl.sp(10) : node.ctl.sp(10)
    text: node.itext
    color: node.ctl.foreground
    font.family: node.ctl.fontFamily
    font.pixelSize: node.ctl.fontSubtitle
    wrapMode: TextEdit.Wrap
    // Pinned: board files are shareable, and RichText here would let someone
    // else's board inject markup into yours.
    textFormat: TextEdit.PlainText
    horizontalAlignment: node.isNote ? TextEdit.AlignLeft : TextEdit.AlignHCenter
    verticalAlignment: node.isNote ? TextEdit.AlignTop : TextEdit.AlignVCenter
    selectByMouse: true
    readOnly: !node.ctl.canEdit
    // Guarded so the model write cannot bounce back and reset the caret.
    onTextChanged: {
      if (!node.ctl.canEdit || text === node.itext) return
      node.set("itext", text)
      node.ctl.scheduleSave()
    }
    onActiveFocusChanged: if (!activeFocus) node.ctl.flushSave()
    Keys.onEscapePressed: node.ctl.stopEditing()
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
        node.ctl.flushSave()
        event.accepted = true
      }
    }

    readonly property bool wantsEdit: node.ctl.editIndex === node.index
    onWantsEditChanged: if (wantsEdit) {
      forceActiveFocus()
      cursorPosition = length
    }
  }

  // Drag anywhere. Steps aside the moment this item is being edited, so the
  // caret still works.
  MouseArea {
    anchors.fill: parent
    enabled: node.ctl.editIndex !== node.index
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

    property real pressX: 0
    property real pressY: 0
    property bool dragging: false

    onPressed: function (mouse) {
      pressX = mouse.x
      pressY = mouse.y
      dragging = false
      node.ctl.selectOnly(node.index)
    }
    onPositionChanged: function (mouse) {
      if (!node.ctl.canEdit || !pressed || mouse.buttons !== Qt.LeftButton) return
      var dx = mouse.x - pressX
      var dy = mouse.y - pressY
      // A few pixels of slack so a click to select never nudges it.
      if (!dragging && Math.abs(dx) + Math.abs(dy) < 3) return
      if (!dragging) node.ctl.pushUndo()
      dragging = true
      node.set("ix", node.ix + dx)
      node.set("iy", node.iy + dy)
    }
    onReleased: {
      if (dragging) node.ctl.save()
      dragging = false
    }
    onClicked: function (mouse) {
      if (mouse.button === Qt.MiddleButton) node.ctl.removeItem(node.index)
    }
    onDoubleClicked: {
      if (!node.ctl.canEdit) return
      node.ctl.pushUndo()
      node.ctl.editIndex = node.index
    }
  }

  // Resize grip, bottom-right.
  MouseArea {
    width: 16
    height: 16
    anchors { right: parent.right; bottom: parent.bottom }
    cursorShape: Qt.SizeFDiagCursor
    enabled: node.ctl.canEdit

    property real pressX: 0
    property real pressY: 0
    property bool sizing: false

    onPressed: function (mouse) {
      pressX = mouse.x
      pressY = mouse.y
      sizing = false
      node.ctl.selectedIndex = node.index
    }
    onPositionChanged: function (mouse) {
      if (!pressed) return
      if (!sizing) { node.ctl.pushUndo(); sizing = true }
      node.set("iw", Math.max(node.ctl.minItemSize, node.iw + (mouse.x - pressX)))
      node.set("ih", Math.max(node.ctl.minItemSize, node.ih + (mouse.y - pressY)))
    }
    onReleased: {
      if (sizing) node.ctl.save()
      sizing = false
    }

    Rectangle {
      anchors.centerIn: parent
      width: 8
      height: 2
      rotation: -45
      color: node.ctl.foreground
      opacity: 0.35
    }
  }
}
