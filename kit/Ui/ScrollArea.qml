import QtQuick
import QtQuick.Controls
import "../Theme"
import "../Theme" as Commons

// A vertical scroll view capped at `maxHeight`, with Omarchy's thin scrollbar beside it: a
// `track` groove `scrollbarThickness` wide and a foreground-glass thumb, corners min(4, radius).
// The bar shows only while the content overflows, and overlays the content's right edge rather
// than reserving a gutter (as the shell's AsNeeded bars do): a short list is as wide as its
// siblings, and nothing reflows when the bar appears. Rows keep their content clear of it with
// their own padding (ListRow's controlPaddingX). Scrolling stops at the ends; the thumb drags.
//
//   ScrollArea {
//     maxHeight: 240
//     ListRow { ... }
//     ListRow { ... }
//   }
//
// Children stack in a column `spacing` apart, as wide as the area.
// ensureVisible(item) scrolls just far enough to show a child (the cursor's row after a key).
Item {
  id: root

  property real maxHeight: Number.POSITIVE_INFINITY
  property real spacing: 0
  default property alias content: column.data
  readonly property alias flickable: flick
  readonly property alias contentColumn: column
  readonly property int thickness: Style.spacing.scrollbarThickness
  readonly property bool overflowing: column.implicitHeight > flick.height + 0.5

  function ensureVisibleRange(y, h) {
    var top = flick.contentY
    var bottom = top + flick.height
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    if (y < top) flick.contentY = Math.max(0, y)
    else if (y + h > bottom) flick.contentY = Math.min(maxY, y + h - flick.height)
  }

  function ensureVisible(item) {
    if (!item) return
    var p = item.mapToItem(column, 0, 0)
    ensureVisibleRange(p.y, item.height)
  }

  implicitWidth: column.implicitWidth
  implicitHeight: Math.min(column.implicitHeight, maxHeight)

  Flickable {
    id: flick
    width: root.width
    height: root.height
    contentWidth: width
    contentHeight: column.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: column
      width: flick.width
      spacing: root.spacing
    }
  }

  ScrollBar {
    id: bar
    orientation: Qt.Vertical
    x: root.width - root.thickness
    width: root.thickness
    height: root.height
    padding: 0
    visible: root.overflowing
    policy: ScrollBar.AlwaysOn
    hoverEnabled: true
    size: flick.visibleArea.heightRatio
    minimumSize: Style.space(24) / Math.max(1, height)
    onPositionChanged: if (pressed) flick.contentY = position * flick.contentHeight

    Binding on position {
      value: flick.visibleArea.yPosition
      when: !bar.pressed
      restoreMode: Binding.RestoreNone
    }

    background: Rectangle {
      color: Commons.Color.track
      radius: Math.min(4, Style.cornerRadius)
    }

    contentItem: Rectangle {
      implicitWidth: root.thickness
      radius: Math.min(4, Style.cornerRadius)
      color: bar.pressed || bar.hovered ? Commons.Color.textDim : Style.normalBorderColor
    }
  }
}
