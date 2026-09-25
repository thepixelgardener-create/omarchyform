pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store

// The same shortcut list remains readable on small windows and large fonts.
Rectangle {
  id: help
  required property var ctl
  visible: ctl.helpVisible
  width: Math.min(parent.width - ctl.sp(32), ctl.sp(700))
  height: Math.min(parent.height - ctl.sp(32), helpColumn.height + ctl.sp(48))
  color: Qt.rgba(ctl.canvasBackground.r, ctl.canvasBackground.g, ctl.canvasBackground.b, 1)
  border.width: ctl.borderWidth
  border.color: Qt.rgba(ctl.foreground.r, ctl.foreground.g, ctl.foreground.b, 0.18)
  radius: ctl.cornerRadius

  function scroll(delta) {
    content.contentY = Math.max(0, Math.min(content.contentHeight - content.height, content.contentY + delta))
  }

  Flickable {
    id: content
    anchors.fill: parent
    anchors.margins: help.ctl.sp(24)
    contentWidth: width
    contentHeight: helpColumn.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // The key column is measured, not guessed: the widest label decides it, and
    // the rest right-align against the descriptions so the two columns meet in
    // the middle and the eye can run down either one.
    TextMetrics {
      id: widest
      font.family: help.ctl.fontFamily
      font.pixelSize: help.ctl.fontBody
      text: Store.longestKeyLabel()
    }

    Column {
      id: helpColumn
      width: content.width
      spacing: help.ctl.sp(10)
      Text {
        text: "Keyboard shortcuts"
        color: help.ctl.foreground
        font.family: help.ctl.fontFamily
        font.pixelSize: help.ctl.fontHeading
        bottomPadding: help.ctl.sp(14)
      }
      Repeater {
        model: Store.KEY_HELP
        Item {
          id: row
          required property var modelData
          width: helpColumn.width
          height: Math.max(shortcut.implicitHeight, description.implicitHeight)
          // Never wider than half the panel, so a long label cannot squeeze the
          // descriptions into a ribbon on a small window.
          // Two pixels of slack: measured exactly, the widest label rounds to a
          // pixel short of its own column and wraps.
          readonly property real keyColumn: Math.min(Math.ceil(widest.width) + 2, helpColumn.width * 0.5)
          Text {
            id: shortcut
            width: row.keyColumn
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.Wrap
            text: row.modelData[0]
            color: help.ctl.accent
            font.family: help.ctl.fontFamily
            font.pixelSize: help.ctl.fontBody
          }
          Text {
            id: description
            anchors.left: parent.left
            anchors.leftMargin: row.keyColumn + help.ctl.sp(18)
            anchors.right: parent.right
            wrapMode: Text.Wrap
            text: row.modelData[1]
            color: help.ctl.foreground
            font.family: help.ctl.fontFamily
            font.pixelSize: help.ctl.fontBody
          }
        }
      }
    }
  }
}
