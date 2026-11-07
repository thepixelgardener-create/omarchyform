// Qt 6.4 Loader creates a child context for the texture component. Keep this
// file unbound so that component can be instantiated there; model roles still
// arrive through explicit required properties below.

import QtQuick
import QtQuick.Shapes
import "BoardStore.js" as Store

// One thing on the board: a note, a box, an ellipse or a diamond.
// Model roles arrive as required properties; everything else comes from ctl.
Item {
  id: node
  objectName: "board-item-" + iid

  required property var ctl
  readonly property var theme: node.ctl.sceneTheme
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
  required property string itexture
  readonly property string textureStyle: Store.normalizeTexture(node.itexture)
  required property string isrc

  // Deliberately not carrying Accessible properties. Attaching them to the
  // delegate broke grabToImage — the screenshot harness stopped producing a
  // single picture, and the PNG export goes through the same call — so the
  // names live on the chrome, where there are a handful of them rather than
  // one per item on the board. What an item says is in its own text.

  // Whether this item is somewhere a person could actually be looking. An item
  // that is not takes no part in how the board looks: it reads as unmarked, as
  // no match, and at full strength, whatever the board says about it.
  //
  // This is where a large board's time went. Marking a thousand items changed
  // the appearance of a thousand delegates — a ring to draw, a fill to blend,
  // an opacity to animate — and the frame that did it took two thirds of a
  // second, whether or not a single one of them was on screen. Measured with
  // tests/scene.js: 638ms at the 95th percentile before, 55ms after.
  //
  // The arithmetic is written out here rather than asked of the controller.
  // The same test says a function call per item per camera change costs twice
  // what a zoom costs without one; an expression the engine can see into does
  // not.
  readonly property bool onScreen: !node.ctl.culling
    || (node.ix * node.ctl.zoom + node.ctl.camX < node.ctl.viewW
        && (node.ix + node.iw) * node.ctl.zoom + node.ctl.camX > 0
        && node.iy * node.ctl.zoom + node.ctl.camY < node.ctl.viewH
        && (node.iy + node.ih) * node.ctl.zoom + node.ctl.camY > 0)
  // The cursor and whatever is being typed in are live wherever they are: the
  // keyboard can walk the selection off the edge of the screen, and it has to
  // still be the selection when it gets there.
  readonly property bool live: node.onScreen || node.cursor || node.editing
  // Not drawn when it is not live, which lets the scene graph skip the whole
  // subtree rather than walking thirteen items to decide each one falls
  // outside the viewport. On a three thousand item board this is the
  // difference between an idle frame costing 26ms and costing nothing.
  visible: node.live
  // A delegate being taken down has index -1, which is also what editIndex and
  // selectedIndex hold when nothing is being edited or selected. Without the
  // guard, clearing the model made every note the one being edited on its way
  // out: each handed its whole text to the editor to lay out, and reloading a
  // shared board of fifteen long notes held the shell for 56s.
  readonly property bool cursor: node.index >= 0 && node.ctl.selectedIndex === node.index
  readonly property bool marked: node.live && node.ctl.isMarked(node.iid)
  // The cursor and a mark both read as selected; the cursor keeps the heavier
  // outline so you can still tell where the keyboard is.
  readonly property bool selected: node.cursor || node.marked
  readonly property bool linkSource: node.ctl.linkingFrom === node.iid
  readonly property bool editing: node.index >= 0 && node.ctl.editIndex === node.index
  // What the note is actually drawing, so a test can read it back rather than
  // photograph it.
  readonly property string previewText: shown.text
  readonly property bool isLine: Store.isLine(node.kind)
  readonly property var lineEnds: node.isLine ? Store.lineEnds(node.ctl.items.get(node.index)) : ({ax: 0, ay: 0, bx: 1, by: 1})
  readonly property bool isNote: node.kind === "note"
  // Text with a long unbroken stretch in it is wrapped anywhere, by the note
  // and by its editor: looking for word boundaries in it would hold the whole
  // shell up. See LONG_RUN in BoardStore.js.
  readonly property bool longRun: Store.hasLongRun(node.itext)
  readonly property bool isImage: node.kind === "image"
  // Whether the file behind a picture may be drawn: "" once it has been
  // checked, "waiting" while it is, or why it is not drawn (ctl.pictureState).
  readonly property string pictureState: node.isImage ? node.ctl.pictureState(node.isrc) : ""
  // A picture is checked, then decoded off the main thread, and draws nothing
  // until both are done. An export waits for this to clear on every item
  // before it takes its picture; a picture that failed or was refused has
  // finished loading too, and draws as a line saying so.
  readonly property bool pictureLoading: node.isImage && (picture.status === Image.Loading || node.pictureState === "waiting")
  readonly property bool painted: node.kind === "ellipse" || node.kind === "diamond"
  readonly property bool foundMatch: node.live && node.ctl.matchesFind(node.itext)
  readonly property bool emphasised: node.selected || node.linkSource
  readonly property color fill: node.theme.tintFill(node.itint, node.emphasised)
  // The item's own border says what tint it carries and nothing else. Selection
  // used to thicken and brighten this border, which meant an accent-tinted item
  // sitting idle looked more selected than the cursor did on a muted one. The
  // ring below carries selection instead, in one colour at one width, whatever
  // the item is tinted.
  // A line is nothing but its outline, a stroke a box's border is drawn with,
  // so at a border's strength a plain one all but vanished on the board. It
  // is drawn nearly at full strength; a box's border stays quiet.
  readonly property color outline: node.linkSource || node.foundMatch
    ? node.theme.accent
    : node.isLine ? node.theme.tintBorder(node.itint, true)
    : node.theme.tintBorder(node.itint, false)

  // Both modes narrow the board the same way: what you are not working on
  // recedes rather than disappearing, so the shape of the board is still there.
  opacity: !node.live ? 1
    : node.ctl.showPinned && !node.ipinned ? 0.35
    : node.ctl.findDimming && !node.foundMatch ? 0.3
    : 1

  // Outside the item's own edge, so it cannot be mistaken for the item's
  // border: the cursor is a solid ring, a secondary mark a lighter one. Drawn
  // for painted shapes too, where an outline on the shape itself is hard to
  // follow around a diamond.
  Rectangle {
    anchors.fill: parent
    anchors.margins: -node.theme.sp(4)
    visible: node.selected && !node.ctl.showPinned && !node.isLine
    color: "transparent"
    radius: node.theme.cornerRadius > 0 ? node.theme.cornerRadius + node.theme.sp(4) : 0
    border.width: node.cursor ? node.theme.borderWidth * 2 : node.theme.borderWidth
    border.color: node.theme.accent
    opacity: node.cursor ? 1 : 0.55
    antialiasing: true
  }

  // A line's ring is the same ring turned to lie along the line. Around the
  // line's box it was a square around any diagonal, far from the line itself.
  // Built only while the line is selected, so a board of lines pays nothing.
  HoverHandler { id: hover }

  x: node.ix
  y: node.iy
  width: node.iw
  height: node.ih

  onXChanged: node.ctl.repaintLinks()
  onYChanged: node.ctl.repaintLinks()
  onWidthChanged: node.ctl.repaintLinks()
  onHeightChanged: node.ctl.repaintLinks()

  onEditingChanged: if (!editing) textViewport.contentY = 0

  function set(role, value) { node.ctl.items.setProperty(node.index, role, value) }

  // Notes and boxes are plain Rectangles; ellipses and diamonds need a path.
  Rectangle {
    anchors.fill: parent
    visible: !node.painted && !node.isLine
    color: node.fill
    radius: node.theme.cornerRadius
    antialiasing: true
    border.width: node.linkSource || node.foundMatch ? node.theme.borderWidth * 2 : node.theme.borderWidth
    border.color: node.outline
  }

  // Inside the frame, so the tint still reads as a border and a selection
  // still shows. Aspect is preserved: a resize letterboxes rather than
  // stretches, which is what a picture on a board should do.
  Image {
    id: picture
    anchors.fill: parent
    anchors.margins: node.theme.borderWidth
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
  // leaving an empty box that looks like a bug, and say why when the file is
  // there but was refused.
  Text {
    objectName: "picture-note"
    textFormat: Text.PlainText
    anchors.centerIn: parent
    width: parent.width - node.theme.sp(16)
    visible: node.isImage && (picture.status === Image.Error || (node.pictureState !== "" && node.pictureState !== "waiting"))
    text: node.pictureState === "" || node.pictureState === "missing" ? "missing image\n" + node.isrc
        : "picture not shown\n" + node.isrc + "\n" + node.pictureState
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    elide: Text.ElideMiddle
    maximumLineCount: 3
    // Same reason as the header: a theme's muted can sit on top of its own
    // background, and "missing image" is the one line that has to be readable.
    opacity: 0.85
    color: node.theme.foreground
    font.family: node.theme.fontFamily
    font.pixelSize: node.theme.fontBody
  }

  // Geometry, not a picture of geometry. A Canvas rasterises at the item's own
  // size and the board then magnifies it with the world transform, so a shape
  // went soft the moment you zoomed into it: measured at 400%, the outline
  // smeared across 36 pixels where the selection ring beside it — an ordinary
  // Rectangle — takes one. A Shape is triangulated by the scene graph at the
  // size it is finally drawn at, so it stays as sharp as the notes around it.
  //
  // It also needs none of the plumbing a Canvas does. The old one repainted
  // itself from seven Connections handlers, one per property that could change
  // how it looked, and a new property meant remembering to add an eighth.
  // These are bindings; there is nothing to remember.
  // Only ellipses and diamonds build one: a Shape on every note and box, hidden,
  // was a sixth of what a 5,000-item board cost to open (tests/hostile.js).
  Loader {
    objectName: "item-shape"
    anchors.fill: parent
    active: node.painted
    sourceComponent: Component {
      Shape {
        antialiasing: true
        ShapePath {
          fillColor: node.fill
          strokeColor: node.outline
          // Unchanged from the canvas, including its disagreement with the
          // Rectangle above, which thickens on foundMatch rather than on cursor.
          strokeWidth: node.cursor || node.linkSource ? node.theme.borderWidth * 2 : node.theme.borderWidth
          joinStyle: ShapePath.MiterJoin
          PathSvg { path: Store.shapePath(node.kind, node.width, node.height) }
        }
      }
    }
  }

  // qmllint disable unqualified
  // This file stays unbound for Qt 6.4's Loader (see the header), so the
  // component below reads `node` from outside its own scope, as intended.
  Loader {
    objectName: "line-shape"
    anchors.fill: parent
    active: node.isLine
    sourceComponent: Component {
      Shape {
        antialiasing: true
        ShapePath {
          // An arrow is a filled outline (Store.linePath); a plain line is a stroke.
          readonly property bool filled: node.kind === "arrow" || node.kind === "double-arrow"
          fillColor: filled ? node.outline : "transparent"
          strokeColor: filled ? "transparent" : node.outline
          strokeWidth: filled ? 0 : Store.arrowHead(node.theme.borderWidth).stroke
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin
          strokeStyle: node.kind === "dashed-line" ? ShapePath.DashLine : ShapePath.SolidLine
          dashPattern: [4, 3]
          PathSvg { path: Store.linePath(node.kind, node.width, node.height, node.lineEnds, node.theme.borderWidth) }
        }
      }
    }
  }
  // qmllint enable unqualified

  // Plain and offscreen items allocate no texture geometry.
  Loader {
    objectName: "item-texture"
    anchors.fill: parent
    active: node.live && !node.isImage && !node.isLine && node.textureStyle !== "plain"
    sourceComponent: Component {
      Shape {
        antialiasing: true
        opacity: node.textureStyle === "dots" ? 0.3 : 0.2
        ShapePath {
          fillColor: "transparent"
          strokeColor: node.outline
          strokeWidth: node.textureStyle === "dots" ? 1.6 : 1
          capStyle: ShapePath.RoundCap
          PathSvg { path: Store.texturePath(node.kind, node.textureStyle, node.width, node.height, node.theme.cornerRadius) }
        }
      }
    }
  }

  // A note has a grab strip at the top; shapes read better without.
  // A note gets a rule across the top: the same grab affordance as a filled
  // title bar, drawn the way the rest of the shell draws a divider.
  Rectangle {
    id: header
    anchors { top: parent.top; left: parent.left; right: parent.right }
    anchors.margins: node.theme.borderWidth
    height: node.theme.borderWidth
    visible: node.isNote
    color: node.outline
  }

  Flickable {
    id: textViewport
    visible: !node.isImage && !node.isLine
    anchors.fill: parent
    anchors.margins: node.theme.sp(14)
    anchors.topMargin: node.isNote ? header.height + node.theme.sp(14) : node.theme.sp(14)
    contentWidth: width
    contentHeight: editor.item ? editor.item.height : shown.height
    clip: true
    interactive: node.editing
    boundsBehavior: Flickable.StopAtBounds

  // Untrusted canvas text stays literal in previews and exports.
  Text {
    id: shown
    objectName: "note-text"
    visible: !node.editing
    width: textViewport.width
    height: Math.max(textViewport.height, contentHeight)
    text: Store.notePreview(node.itext)
    textFormat: Text.PlainText
    color: node.theme.foreground
    font.family: node.theme.fontFamily
    font.pixelSize: node.theme.fontSubtitle
    wrapMode: node.longRun ? Text.WrapAnywhere : Text.Wrap
    clip: true
    horizontalAlignment: node.isNote ? Text.AlignLeft : Text.AlignHCenter
    verticalAlignment: node.isNote ? Text.AlignTop : Text.AlignVCenter
  }

  // The editor exists only while the note is being typed in, and is made
  // again, from the board's version of the note, each time the caret arrives.
  // One per item, unused, was a third of what a 5,000-item board cost to open
  // (tests/hostile.js), and bound to `itext` it laid every note's text out a
  // second time. A paste answered after it has gone finds no field to land in.
  Loader {
    id: editor
    active: node.editing
    onLoaded: editor.item.begin()
    sourceComponent: Component {
      TextEdit {
        id: body
        objectName: "note-editor"
        width: textViewport.width
        height: Math.max(textViewport.height, contentHeight)
        color: node.theme.foreground
        font.family: node.theme.fontFamily
        font.pixelSize: node.theme.fontSubtitle
        wrapMode: node.longRun ? TextEdit.WrapAnywhere : TextEdit.Wrap
        clip: true
        // Pinned: board files are shareable, and RichText here would let someone
        // else's board inject markup into yours.
        textFormat: TextEdit.PlainText
        horizontalAlignment: node.isNote ? TextEdit.AlignLeft : TextEdit.AlignHCenter
        verticalAlignment: node.isNote ? TextEdit.AlignTop : TextEdit.AlignVCenter
        selectByMouse: true
        persistentSelection: true
        readOnly: !node.ctl.canEdit || node.ipinned
        enabled: !node.ipinned && !node.ctl.showPinned
        // Guarded so the model write cannot bounce back and reset the caret, and
        // so being handed the note when the caret arrives is never an edit.
        onTextChanged: {
          if (!body.wantsEdit || !node.ctl.canEdit || text === node.itext) return
          // A paste into the editor does not go through the clipboard helper's
          // limit, and two pastes would make a note this board then refuses to
          // open. The change is not kept, and is undone once the editor has
          // finished making it.
          if (text.length > Store.MAX_NOTE_LENGTH) { Qt.callLater(body.refuseOverlong); return }
          node.set("itext", text)
          node.ctl.scheduleSave()
        }
        function refuseOverlong() {
          if (body.text.length <= Store.MAX_NOTE_LENGTH) return
          var at = Math.min(body.cursorPosition, node.itext.length)
          body.text = node.itext
          body.cursorPosition = at
          node.ctl.flash("A note holds up to 1 MB of text")
        }
        onActiveFocusChanged: if (!activeFocus) node.ctl.flushSave()
        // Editing can end without the caret leaving first: another item selected,
        // another board opened. The editor goes, and what was typed is saved.
        Component.onDestruction: if (activeFocus) node.ctl.flushSave()
        Keys.onEscapePressed: node.ctl.stopEditing()
        // What a paste may bring in, for BoardExchange.pasteInto. Qt's own paste
        // reads everything the clipboard's owner sends before onTextChanged can
        // count it, and an owner that never stops sending takes the shell's memory
        // with it; so the paste keys are taken from the editor here, and the
        // clipboard helper reads the text instead, at most 1 MiB of it. The middle
        // button never reaches the editor: Board.qml's pan surface takes it.
        readonly property bool takesPaste: body.wantsEdit
        readonly property int pasteLimit: Store.MAX_NOTE_LENGTH
        readonly property bool pasteLines: true

        Keys.onPressed: function(event) {
          if (event.matches(StandardKey.Paste)) {
            event.accepted = true
            if (!body.readOnly) node.ctl.pasteInto(body)
            return
          }
          if ((event.modifiers & Qt.ControlModifier) === 0) return
          if (event.key === Qt.Key_N) node.ctl.newBoard()
          else if (event.key === Qt.Key_S) node.ctl.flushSave()
          else return
          event.accepted = true
        }

        readonly property bool wantsEdit: node.editing
        // The editor holds a copy of the note, not the note: it is handed the
        // board's version each time the caret arrives, so whatever changed the
        // item meanwhile — an undo restores the note on screen, which reads
        // `itext` directly — is what it shows.
        function begin() {
          body.text = node.itext
          forceActiveFocus()
          cursorPosition = length
        }
        onCursorRectangleChanged: if (wantsEdit) {
          if (cursorRectangle.y < textViewport.contentY) textViewport.contentY = cursorRectangle.y
          else if (cursorRectangle.y + cursorRectangle.height > textViewport.contentY + textViewport.height)
            textViewport.contentY = cursorRectangle.y + cursorRectangle.height - textViewport.height
        }
      }
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
    anchors.margins: node.theme.borderWidth
    width: node.theme.sp(22)
    height: node.theme.sp(14)
    visible: !node.isLine && shown.contentHeight > textViewport.height && !node.editing
    color: node.theme.tintBorder(node.itint, true)
    radius: node.theme.cornerRadius > 0 ? node.theme.sp(3) : 0
    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: "…"
      color: node.theme.canvasBackground
      font.family: node.theme.fontFamily
      font.pixelSize: node.theme.fontBody
    }
  }

  // Drag anywhere. Steps aside the moment this item is being edited, so the
  // caret still works.
  //
  // The left button only. The middle one used to press here too — it selected
  // the item and then deleted it on release — which made a pan that happened
  // to start on a note destroy it, and put the one irreversible thing on the
  // board behind the same gesture used to move around it. Deleting is del,
  // backspace, or the command that says so. Leaving the button off the list
  // rather than ignoring it in the handler matters: an accepted button is a
  // consumed one, and the board's pan surface is above this anyway.
  MouseArea {
    objectName: "node-drag"
    anchors.fill: parent
    enabled: node.ctl.editIndex !== node.index && (node.ipinned ? node.ctl.showPinned : !node.ctl.showPinned)
    acceptedButtons: Qt.LeftButton
    // While the far end of a connector is chosen, a click picks; it does not
    // drag, resize or start typing.
    cursorShape: node.ipinned || node.ctl.linkingFrom >= 0 ? Qt.PointingHandCursor : dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

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
      if (node.ipinned || !node.ctl.canEdit || node.ctl.linkingFrom >= 0 || !pressed || mouse.buttons !== Qt.LeftButton) return
      if (dragging && !node.ctl.pointerEdit) return
      var dx = mouse.x - pressX
      var dy = mouse.y - pressY
      // A few pixels of slack so a click to select never nudges it.
      if (!dragging && Math.abs(dx) + Math.abs(dy) < 3) return
      if (!dragging) node.ctl.beginPointerEdit()
      dragging = true
      // Magnetic unless shift is held: it lines up with the items it nears.
      node.ctl.moveTargets(dx, dy, (mouse.modifiers & Qt.ShiftModifier) === 0)
    }
    onReleased: {
      if (dragging) node.ctl.finishPointerEdit(false)
      dragging = false
    }
    onCanceled: { if (dragging) node.ctl.finishPointerEdit(true); dragging = false }
    onDoubleClicked: {
      if (node.isLine || node.ipinned || !node.ctl.canEdit || node.ctl.linkingFrom >= 0) return
      node.ctl.pushUndo()
      node.ctl.editIndex = node.index
    }
  }

  // Resize grip, bottom-right.
  MouseArea {
    objectName: "node-resize"
    width: 16
    height: 16
    anchors { right: parent.right; bottom: parent.bottom }
    cursorShape: Qt.SizeFDiagCursor
    enabled: node.ctl.canEdit && !node.ipinned && !node.ctl.showPinned && node.ctl.linkingFrom < 0

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
      if (sizing && !node.ctl.pointerEdit) return
      if (!sizing) { node.ctl.beginPointerEdit(); sizing = true }
      node.ctl.resizeTargets(mouse.x - pressX, mouse.y - pressY)
    }
    onReleased: {
      if (sizing) node.ctl.finishPointerEdit(false)
      sizing = false
    }
    onCanceled: { if (sizing) node.ctl.finishPointerEdit(true); sizing = false }

    visible: !node.isLine && !node.ipinned && node.ctl.linkingFrom < 0 && (node.selected || hover.hovered)
    Rectangle {
      anchors.centerIn: parent
      width: 8
      height: 2
      rotation: -45
      color: node.theme.foreground
      opacity: 0.35
    }
  }
  // qmllint disable unqualified
  // Unbound on purpose, as the line shape above: the handles read `node`.
  Repeater {
    // A line's selection is these two handles and nothing else: a box or a
    // band around a line hid the line it was meant to point out. A marked
    // line wears them fainter, the way a marked item's ring is lighter.
    model: node.isLine && node.selected && !node.ipinned && !node.ctl.showPinned && node.ctl.canEdit && node.ctl.linkingFrom < 0 ? 2 : 0
    delegate: MouseArea {
      id: endpoint
      required property int index
      objectName: "line-end-" + index
      // The end it moves, and the way out of the line there.
      readonly property real ex: (endpoint.index === 0 ? node.lineEnds.ax : node.lineEnds.bx) * node.width
      readonly property real ey: (endpoint.index === 0 ? node.lineEnds.ay : node.lineEnds.by) * node.height
      readonly property real ox: (endpoint.index === 0 ? node.lineEnds.bx : node.lineEnds.ax) * node.width
      readonly property real oy: (endpoint.index === 0 ? node.lineEnds.by : node.lineEnds.ay) * node.height
      readonly property real span: Math.max(0.01, Math.sqrt((endpoint.ex - endpoint.ox) * (endpoint.ex - endpoint.ox) + (endpoint.ey - endpoint.oy) * (endpoint.ey - endpoint.oy)))
      // Just past the end rather than on it, so an arrow's tip is not drawn
      // over: the handle sits where the line would go on.
      readonly property real clear: 7
      width: 18; height: 18
      opacity: node.cursor ? 1 : 0.55
      x: endpoint.ex + (endpoint.ex - endpoint.ox) / endpoint.span * endpoint.clear - width / 2
      y: endpoint.ey + (endpoint.ey - endpoint.oy) / endpoint.span * endpoint.clear - height / 2
      cursorShape: Qt.CrossCursor
      acceptedButtons: Qt.LeftButton
      property bool moving: false
      // Where the end is from the pointer, held for the drag, so the end
      // does not jump onto the pointer when the handle is taken.
      property real grabX: 0
      property real grabY: 0
      onPressed: function(mouse) {
        var point = endpoint.mapToItem(node.parent, mouse.x, mouse.y)
        endpoint.grabX = node.x + endpoint.ex - point.x
        endpoint.grabY = node.y + endpoint.ey - point.y
        endpoint.moving = true
        node.ctl.beginPointerEdit()
      }
      onPositionChanged: function(mouse) {
        if (!endpoint.pressed || !endpoint.moving || !node.ctl.pointerEdit || !node.ctl.canEdit) return
        var point = endpoint.mapToItem(node.parent, mouse.x, mouse.y)
        var n = node.ctl.items.get(node.index)
        var at = { x: point.x + endpoint.grabX, y: point.y + endpoint.grabY }
        // Level or upright when it is nearly so, and in line with the sides
        // and middles of other items; shift lets it lie anywhere.
        var free = (mouse.modifiers & Qt.ShiftModifier) !== 0
        var pull = 10 / Math.max(0.01, node.ctl.zoom)
        if (!free) {
          at = Store.snappedLineEnd(n, endpoint.index, at.x, at.y, pull, node.ctl.items, node.index)
          node.ctl.guides = at.guides
        } else node.ctl.guides = []
        // Put down on or near another item, the end is glued to its outline
        // and goes where the item goes from then on.
        var e = node.lineEnds
        var other = { x: node.x + (endpoint.index === 0 ? e.bx : e.ax) * node.width, y: node.y + (endpoint.index === 0 ? e.by : e.ay) * node.height }
        var glue = free ? null : Store.glueAt(node.ctl.items, at.x, at.y, node.index, pull, other)
        if (glue) { at = { x: glue.px, y: glue.py }; node.ctl.guides = [] }
        var values = Store.movedLineEnd(n, endpoint.index, at.x, at.y)
        var held = endpoint.index === 0 ? "aon" : "bon"
        values[held] = glue ? glue.id : 0
        if (glue) { values[held + "x"] = glue.x; values[held + "y"] = glue.y }
        for (var role in values) node.set(role, values[role])
        node.ctl.repaintLinks()
      }
      onReleased: { if (endpoint.moving) node.ctl.finishPointerEdit(false); endpoint.moving = false }
      onCanceled: { if (endpoint.moving) node.ctl.finishPointerEdit(true); endpoint.moving = false }
      // Hollow, and beside the end rather than on it, so the end stays in
      // sight while it moves.
      Rectangle {
        anchors.centerIn: parent
        width: 9; height: 9; radius: 5
        color: "transparent"
        border.color: node.theme.accent
        border.width: 2
      }
    }
  }

  // qmllint enable unqualified
}
