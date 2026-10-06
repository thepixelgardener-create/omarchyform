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
  readonly property bool two: split.workspace.split
  readonly property bool across: split.workspace.layout !== "stacked"
  readonly property real gap: split.two ? Math.max(1, split.theme.borderWidth) : 0
  // Where the first pane ends, in whole pixels, so neither board is drawn on a
  // fractional edge.
  readonly property real cut: !split.two ? (split.across ? split.width : split.height)
    : Math.round(((split.across ? split.width : split.height) - split.gap) * split.workspace.splitRatio)

  focus: true

  // Its place on screen: 0 first, 1 second, -1 not shown.
  function place(pane) {
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
    color: Qt.rgba(split.theme.foreground.r, split.theme.foreground.g, split.theme.foreground.b, 0.25)
  }
}
