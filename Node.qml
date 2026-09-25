pragma ComponentBehavior: Bound

import QtQuick

// One thing on the board: a note, a box, an ellipse or a diamond.
// Model roles arrive as required properties; everything else comes from ctl.
Item {
  id: node
  objectName: "board-item-" + iid

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
  required property bool ipinned
  required property string isrc

  readonly property bool cursor: node.ctl.selectedIndex === node.index
  readonly property bool marked: node.ctl.isMarked(node.iid)
  // The cursor and a mark both read as selected; the cursor keeps the heavier
  // outline so you can still tell where the keyboard is.
  readonly property bool selected: node.cursor || node.marked
  readonly property bool linkSource: node.ctl.linkingFrom === node.iid
  readonly property bool isNote: node.kind === "note"
  readonly property bool isImage: node.kind === "image"
  readonly property bool painted: node.kind === "ellipse" || node.kind === "diamond"
  readonly property bool foundMatch: node.ctl.matchesFind(node.itext)
  readonly property bool emphasised: node.selected || node.linkSource
  readonly property color fill: node.ctl.tintFill(node.itint, node.emphasised)
  // The item's own border says what tint it carries and nothing else. Selection
  // used to thicken and brighten this border, which meant an accent-tinted item
  // sitting idle looked more selected than the cursor did on a muted one. The
  // ring below carries selection instead, in one colour at one width, whatever
  // the item is tinted.
  readonly property color outline: node.linkSource || node.foundMatch
    ? node.ctl.accent
    : node.ctl.tintBorder(node.itint, false)

  // Both modes narrow the board the same way: what you are not working on
  // recedes rather than disappearing, so the shape of the board is still there.
  opacity: node.ctl.showPinned && !node.ipinned ? 0.35
    : node.ctl.findDimming && !node.foundMatch ? 0.3
    : 1

  // Outside the item's own edge, so it cannot be mistaken for the item's
  // border: the cursor is a solid ring, a secondary mark a lighter one. Drawn
  // for painted shapes too, where an outline on the shape itself is hard to
  // follow around a diamond.
  Rectangle {
    anchors.fill: parent
    anchors.margins: -node.ctl.sp(4)
    visible: node.selected && !node.ctl.showPinned
    color: "transparent"
    radius: node.ctl.cornerRadius > 0 ? node.ctl.cornerRadius + node.ctl.sp(4) : 0
    border.width: node.cursor ? node.ctl.borderWidth * 2 : node.ctl.borderWidth
    border.color: node.ctl.accent
    opacity: node.cursor ? 1 : 0.55
    antialiasing: true
  }

  HoverHandler { id: hover }

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
    border.width: node.linkSource || node.foundMatch ? node.ctl.borderWidth * 2 : node.ctl.borderWidth
    border.color: node.outline
  }

  // Inside the frame, so the tint still reads as a border and a selection
  // still shows. Aspect is preserved: a resize letterboxes rather than
  // stretches, which is what a picture on a board should do.
  Image {
    id: picture
    anchors.fill: parent
    anchors.margins: node.ctl.borderWidth
    visible: node.isImage
    source: node.isImage ? node.ctl.imagePath(node.isrc) : ""
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: false
    mipmap: true
    smooth: true
  }

  // A board can outlive the picture it points at: an image folder cleared by
  // hand, or a board copied to another machine without it. Say so rather than
  // leaving an empty box that looks like a bug.
  Text {
    anchors.centerIn: parent
    width: parent.width - node.ctl.sp(16)
    visible: node.isImage && picture.status === Image.Error
    text: "missing image\n" + node.isrc
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    elide: Text.ElideMiddle
    maximumLineCount: 3
    color: node.ctl.muted
    font.family: node.ctl.fontFamily
    font.pixelSize: node.ctl.fontBody
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
      ctx.lineWidth = node.cursor || node.linkSource ? node.ctl.borderWidth * 2 : node.ctl.borderWidth
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
      function onCursorChanged() { shape.requestPaint() }
      function onMarkedChanged() { shape.requestPaint() }
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

  Flickable {
    id: textViewport
    visible: !node.isImage
    anchors.fill: parent
    anchors.margins: node.ctl.sp(14)
    anchors.topMargin: node.isNote ? header.height + node.ctl.sp(14) : node.ctl.sp(14)
    contentWidth: width
    contentHeight: body.height
    clip: true
    interactive: node.ctl.editIndex === node.index
    boundsBehavior: Flickable.StopAtBounds

  TextEdit {
    id: body
    width: textViewport.width
    height: Math.max(textViewport.height, contentHeight)
    text: node.itext
    color: node.ctl.foreground
    font.family: node.ctl.fontFamily
    font.pixelSize: node.ctl.fontSubtitle
    wrapMode: TextEdit.Wrap
    clip: true
    // Pinned: board files are shareable, and RichText here would let someone
    // else's board inject markup into yours.
    textFormat: TextEdit.PlainText
    horizontalAlignment: node.isNote ? TextEdit.AlignLeft : TextEdit.AlignHCenter
    verticalAlignment: node.isNote ? TextEdit.AlignTop : TextEdit.AlignVCenter
    selectByMouse: true
    readOnly: !node.ctl.canEdit || node.ipinned
    enabled: !node.ipinned && !node.ctl.showPinned
    // Guarded so the model write cannot bounce back and reset the caret.
    onTextChanged: {
      if (!node.ctl.canEdit || text === node.itext) return
      node.set("itext", text)
      node.ctl.scheduleSave()
    }
    onActiveFocusChanged: if (!activeFocus) node.ctl.flushSave()
    Keys.onEscapePressed: node.ctl.stopEditing()
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
        node.ctl.newBoard()
        event.accepted = true
      } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
        node.ctl.flushSave()
        event.accepted = true
      }
    }

    readonly property bool wantsEdit: node.ctl.editIndex === node.index
    onWantsEditChanged: if (wantsEdit) {
      forceActiveFocus()
      cursorPosition = length
    } else textViewport.contentY = 0
    onCursorRectangleChanged: if (wantsEdit) {
      if (cursorRectangle.y < textViewport.contentY) textViewport.contentY = cursorRectangle.y
      else if (cursorRectangle.y + cursorRectangle.height > textViewport.contentY + textViewport.height)
        textViewport.contentY = cursorRectangle.y + cursorRectangle.height - textViewport.height
    }
  }

  }

  // More text than fits. A tinted tab in the corner rather than an ellipsis in
  // the text colour, which read as punctuation belonging to the note.
  Rectangle {
    // Bottom left: the resize grip owns the other corner, and two marks in one
    // corner read as one confusing thing.
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: node.ctl.borderWidth
    width: node.ctl.sp(22)
    height: node.ctl.sp(14)
    visible: body.contentHeight > textViewport.height && node.ctl.editIndex !== node.index
    color: node.ctl.tintBorder(node.itint, true)
    radius: node.ctl.cornerRadius > 0 ? node.ctl.sp(3) : 0
    Text {
      anchors.centerIn: parent
      text: "…"
      color: node.ctl.canvasBackground
      font.family: node.ctl.fontFamily
      font.pixelSize: node.ctl.fontBody
    }
  }

  // Drag anywhere. Steps aside the moment this item is being edited, so the
  // caret still works.
  MouseArea {
    anchors.fill: parent
    enabled: node.ctl.editIndex !== node.index && (node.ipinned ? node.ctl.showPinned : !node.ctl.showPinned)
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: node.ipinned ? Qt.PointingHandCursor : dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

    property real pressX: 0
    property real pressY: 0
    property bool dragging: false

    onPressed: function (mouse) {
      pressX = mouse.x
      pressY = mouse.y
      dragging = false
      node.ctl.pointerSelect(node.index, (mouse.modifiers & Qt.ShiftModifier) !== 0)
    }
    onPositionChanged: function (mouse) {
      if (node.ipinned || !node.ctl.canEdit || !pressed || mouse.buttons !== Qt.LeftButton) return
      var dx = mouse.x - pressX
      var dy = mouse.y - pressY
      // A few pixels of slack so a click to select never nudges it.
      if (!dragging && Math.abs(dx) + Math.abs(dy) < 3) return
      if (!dragging) node.ctl.pushUndo()
      dragging = true
      node.ctl.moveTargets(dx, dy)
    }
    onReleased: {
      if (dragging) node.ctl.save()
      dragging = false
    }
    onClicked: function (mouse) {
      if (mouse.button === Qt.MiddleButton) node.ctl.removeItem(node.index)
    }
    onDoubleClicked: {
      if (node.ipinned || !node.ctl.canEdit) return
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
    enabled: node.ctl.canEdit && !node.ipinned && !node.ctl.showPinned

    property real pressX: 0
    property real pressY: 0
    property bool sizing: false

    onPressed: function (mouse) {
      pressX = mouse.x
      pressY = mouse.y
      sizing = false
      node.ctl.pointerSelect(node.index, false)
    }
    onPositionChanged: function (mouse) {
      if (!pressed) return
      if (!sizing) { node.ctl.pushUndo(); sizing = true }
      node.ctl.resizeTargets(mouse.x - pressX, mouse.y - pressY)
    }
    onReleased: {
      if (sizing) node.ctl.save()
      sizing = false
    }

    visible: !node.ipinned && (node.selected || hover.hovered)
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
