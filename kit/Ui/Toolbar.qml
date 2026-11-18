import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Theme" as Commons

// An app toolbar: IconButtons and Buttons in three slots (leading at the left, center in the
// middle, trailing at the right), groups split by ToolbarSeparators, an optional overflow "…"
// IconButton at the end, and a 1px track rule along the bottom.
//
//   Toolbar {
//     IconButton { iconText: "" }                   // children go to `leading`
//     ToolbarSeparator {}
//     IconButton { iconText: "" }
//     trailing: [ Button { text: "Share" } ]
//     overflow: true
//     onOverflowTriggered: moreMenu.open()
//   }
//
// Items in a slot sit xxs apart, vertically centered; the bar is sm inside its edges.
Item {
  id: root

  default property alias leading: leadingRow.data
  property alias center: centerRow.data
  property alias trailing: trailingRow.data
  property bool overflow: false
  property bool overflowHasCursor: false
  property bool divided: true

  signal overflowTriggered()

  readonly property real _pad: Style.spacing.sm
  readonly property real _content: Math.max(leadingRow.implicitHeight, centerRow.implicitHeight, endRow.implicitHeight)

  implicitWidth: leadingRow.implicitWidth + centerRow.implicitWidth + endRow.implicitWidth + _pad * 2 + Style.spacing.huge * 2
  implicitHeight: _content + _pad * 2 + (divided ? 1 : 0)

  RowLayout {
    id: leadingRow
    x: root._pad
    y: root._pad + Math.round((root._content - implicitHeight) / 2)
    spacing: Style.spacing.xxs
  }

  RowLayout {
    id: centerRow
    x: Math.round((root.width - implicitWidth) / 2)
    y: root._pad + Math.round((root._content - implicitHeight) / 2)
    spacing: Style.spacing.xxs
  }

  RowLayout {
    id: endRow
    x: root.width - root._pad - implicitWidth
    y: root._pad + Math.round((root._content - implicitHeight) / 2)
    spacing: Style.spacing.xxs

    RowLayout {
      id: trailingRow
      spacing: Style.spacing.xxs
    }

    PanelActionButton {
      visible: root.overflow
      iconText: ""
      hasCursor: root.overflowHasCursor
      onClicked: root.overflowTriggered()
    }
  }

  Rectangle {
    visible: root.divided
    y: root.height - 1
    width: root.width
    height: 1
    color: Commons.Color.track
  }
}
