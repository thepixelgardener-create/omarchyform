pragma ComponentBehavior: Bound

import QtQuick

// What either surface shows: one board, or two side by side or stacked, with a
// hairline between them. Each pane keeps its own board for as long as it is on
// screen, so moving the keyboard, swapping which one comes first or changing
// the layout never builds a board again; only a pane leaving the screen does.
FocusScope {
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

  focus: true

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

  Repeater {
    model: split.workspace.paneSlots

    delegate: Loader {
      id: slot
      required property var modelData
      required property int index
      objectName: "pane-slot-" + slot.index
      readonly property int at: split.place(slot.modelData)

      active: slot.at >= 0
      focus: slot.modelData === split.workspace.activePane
      x: slot.at === 1 && split.across ? split.cut + split.gap : 0
      y: slot.at === 1 && !split.across ? split.cut + split.gap : 0
      width: !split.across || !split.two ? split.width
        : slot.at === 0 ? split.cut : split.width - split.cut - split.gap
      height: split.across || !split.two ? split.height
        : slot.at === 0 ? split.cut : split.height - split.cut - split.gap

      sourceComponent: Component {
        Board { ctl: slot.modelData }
      }
    }
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
