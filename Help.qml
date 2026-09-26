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

  // Swallow clicks so they do not reach the dismiss layer behind. Beneath the
  // Flickable rather than over it, so the panel keeps its drag to scroll and
  // this catches only the margin ring, where a click used to fall through the
  // panel and close it.
  MouseArea { anchors.fill: parent }

  // In the margin ring rather than beside the text: the list is already
  // measured to the panel, and taking a gutter out of it for a rule three
  // pixels wide would wrap a description to save one.
  ScrollHint {
    ctl: help.ctl
    view: content
    anchors.top: content.top
    anchors.bottom: content.bottom
    anchors.right: parent.right
    anchors.rightMargin: help.ctl.sp(10)
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
    //
    // It is measured by the same Text that draws a row, and every label is
    // measured rather than the longest string being picked out. Font metrics
    // alone come out a pixel or two under what a Text of the same string needs,
    // by a margin that grows with the size, so the label the column was sized
    // from was the one that wrapped once the theme's text got large; and the
    // theme chooses the font, which need not be monospace, so the longest
    // string is not reliably the widest. An invisible Column is as wide as its
    // widest child, which is the number wanted.
    Column {
      id: keyRuler
      visible: false
      Repeater {
        model: Store.KEY_HELP
        Text {
          required property var modelData
          text: modelData[0]
          font.family: help.ctl.fontFamily
          font.pixelSize: help.ctl.fontBody
        }
      }
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
          // Never more than half the room, the gap between the columns counted
          // against the keys, so a long label cannot squeeze the descriptions
          // into something narrower than itself on a small window.
          readonly property real keyColumn: Math.min(Math.ceil(keyRuler.implicitWidth),
                                                     (helpColumn.width - help.ctl.sp(18)) * 0.5)
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
