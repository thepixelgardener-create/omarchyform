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
  color: ctl.canvasBackground
  border.width: ctl.borderWidth
  border.color: Qt.rgba(ctl.foreground.r, ctl.foreground.g, ctl.foreground.b, 0.35)
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

    Column {
      id: helpColumn
      width: content.width
      spacing: help.ctl.sp(6)
      Text {
        text: "Omarchyform"
        color: help.ctl.foreground
        font.family: help.ctl.fontFamily
        font.pixelSize: help.ctl.fontHeading
        bottomPadding: help.ctl.sp(8)
      }
      Repeater {
        model: Store.KEY_HELP
        Item {
          id: row
          required property var modelData
          width: helpColumn.width
          height: Math.max(shortcut.implicitHeight, description.implicitHeight)
          Text {
            id: shortcut
            width: help.ctl.sp(96)
            wrapMode: Text.Wrap
            text: row.modelData[0]
            color: help.ctl.foreground
            font.family: help.ctl.fontFamily
            font.pixelSize: help.ctl.fontBody
          }
          Text {
            id: description
            anchors.left: shortcut.right
            anchors.leftMargin: help.ctl.sp(16)
            anchors.right: parent.right
            wrapMode: Text.Wrap
            text: row.modelData[1]
            color: help.ctl.foreground
            opacity: 0.7
            font.family: help.ctl.fontFamily
            font.pixelSize: help.ctl.fontBody
          }
        }
      }
    }
  }
}
