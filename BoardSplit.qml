pragma ComponentBehavior: Bound

import QtQuick

// What either surface shows: one board, or two side by side or stacked, with a
// hairline between them. Both boards are built once, for as long as the
// surface is up, so moving the keyboard, swapping which one comes first,
// changing the layout or squeezing the window never builds one again: a pane
// that is not on screen has its board hidden, not destroyed.
//
// The boards are this item's parent's children rather than its own. Every
// item between a board and its window is paid for on every frame of a zoom —
// on a 3000-item board two levels of plain Item cost 3ms a frame in
// `npm run bench:scene`, and this wrapper with a Loader under it cost 4ms — so
// the boards sit where a single board always sat, and this item holds only the
// divider, above them.
Item {
  id: split

  required property var workspace
  readonly property var theme: split.workspace.theme
  readonly property bool across: split.workspace.layout !== "stacked"
  // Along the way the panes are laid out: the width side by side, the height
  // stacked.
  readonly property real span: split.across ? split.width : split.height
  readonly property real line: Math.max(1, split.theme.borderWidth)
  // A pane narrower than this has no room for its header and a note.
  readonly property real minPane: 320
  readonly property bool fits: split.span - split.line >= 2 * split.minPane
  readonly property bool two: split.workspace.split && split.fits
  // Two panes asked for, room for one: the pane the keyboard is in is shown,
  // `o` swaps it for the other, and the layout waits for the room to return.
  readonly property bool squeezed: split.workspace.split && !split.fits
  readonly property real gap: split.two ? split.line : 0
  readonly property real usable: split.span - split.gap
  // Where the first pane ends, in whole pixels so neither board is drawn on a
  // fractional edge, and never so far that the other is left without room.
  readonly property real cut: !split.two ? split.span
    : Math.round(Math.max(split.minPane, Math.min(split.usable - split.minPane, split.usable * split.workspace.splitRatio)))

  // Above the boards, which are its siblings.
  z: 1

  // The workspace is told, because the hint line in the pane says so. Put back
  // when this surface goes away.
  Binding {
    target: split.workspace
    property: "squeezed"
    value: split.squeezed
  }

  // Its place on screen: 0 first, 1 second, -1 not shown.
  function place(pane) {
    if (split.squeezed) return pane === split.workspace.activePane ? 0 : -1
    var at = split.workspace.panes.indexOf(pane)
    return at === 0 || (at === 1 && split.two) ? at : -1
  }

  function boardX(at) { return split.x + (at === 1 && split.across ? split.cut + split.gap : 0) }
  function boardY(at) { return split.y + (at === 1 && !split.across ? split.cut + split.gap : 0) }
  function boardWidth(at) {
    return !split.across || !split.two ? split.width : at === 1 ? split.width - split.cut - split.gap : split.cut
  }
  function boardHeight(at) {
    return split.across || !split.two ? split.height : at === 1 ? split.height - split.cut - split.gap : split.cut
  }

  // Written out rather than repeated: a Repeater stacks what it makes beside
  // itself, and these are not beside it.
  Board {
    id: firstBoard
    readonly property int at: split.place(firstBoard.ctl)
    parent: split.parent
    objectName: "pane-slot-0"
    ctl: split.workspace.paneSlots[0]
    visible: firstBoard.at >= 0
    focus: firstBoard.ctl === split.workspace.activePane
    x: split.boardX(firstBoard.at)
    y: split.boardY(firstBoard.at)
    width: split.boardWidth(firstBoard.at)
    height: split.boardHeight(firstBoard.at)
  }

  Board {
    id: secondBoard
    readonly property int at: split.place(secondBoard.ctl)
    parent: split.parent
    objectName: "pane-slot-1"
    ctl: split.workspace.paneSlots[1]
    visible: secondBoard.at >= 0
    focus: secondBoard.ctl === split.workspace.activePane
    x: split.boardX(secondBoard.at)
    y: split.boardY(secondBoard.at)
    width: split.boardWidth(secondBoard.at)
    height: split.boardHeight(secondBoard.at)
  }

  Rectangle {
    objectName: "split-divider"
    visible: split.two
    x: split.across ? split.cut : 0
    y: split.across ? 0 : split.cut
    width: split.across ? split.gap : split.width
    height: split.across ? split.height : split.gap
    color: Qt.rgba(split.theme.foreground.r, split.theme.foreground.g, split.theme.foreground.b,
                   handle.containsMouse || handle.pressed ? 0.6 : 0.25)
  }

  // Wider than the line it moves, so a pointer can find it. Dragged, it moves
  // the line and nothing else; let go of, the place is remembered; double-
  // clicked, it goes back to the middle.
  MouseArea {
    id: handle
    objectName: "split-handle"
    visible: split.two
    hoverEnabled: true
    preventStealing: true
    x: split.across ? split.cut - 3 : 0
    y: split.across ? 0 : split.cut - 3
    width: split.across ? split.gap + 6 : split.width
    height: split.across ? split.height : split.gap + 6
    cursorShape: split.across ? Qt.SplitHCursor : Qt.SplitVCursor
    onPositionChanged: function (mouse) {
      if (!handle.pressed) return
      var point = handle.mapToItem(split, mouse.x, mouse.y)
      var at = split.across ? point.x : point.y
      var held = Math.max(split.minPane, Math.min(split.usable - split.minPane, at))
      split.workspace.setSplitRatio(held / split.usable)
    }
    onReleased: split.workspace.writeState()
    onDoubleClicked: split.workspace.evenSplit()
  }
}
