import QtQuick
import "../Theme"
import "../Theme" as Commons

// What a list or panel shows when it has nothing: a glyph, a title, an optional hint and an
// optional action, centered in the width it is given.
//
//   EmptyState { glyph: "󰖪"; title: "No networks found"; hint: "Turn on Wi-Fi to scan"; actionText: "Scan" }
//   EmptyState { size: "overlay"; glyph: "󰅌"; title: "Clipboard is empty" }
//
// `size: "panel"` (the default) is the quiet line a shell panel shows: a small dim glyph and dim
// body text. `size: "overlay"` is what the clipboard and emoji pickers show: a displayLarge glyph
// in the menu's selected text color and a title at 0.7 opacity.
Item {
  id: root

  property string glyph: ""
  property string title: ""
  property string hint: ""
  property string actionText: ""
  property string size: "panel"
  // Forces the action's hover-cursor look, for keyboard-driven panels.
  property bool hasCursor: false

  signal actionClicked()

  readonly property bool _overlay: size === "overlay"

  implicitWidth: Math.max(glyphText.visible ? glyphText.implicitWidth : 0, titleText.implicitWidth,
                          hintText.visible ? hintText.implicitWidth : 0, action.visible ? action.implicitWidth : 0)
  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: root.width
    spacing: root._overlay ? Style.spacing.lg : Style.spacing.sm

    Text {
      id: glyphText
      textFormat: Text.PlainText
      visible: root.glyph !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.glyph
      color: root._overlay ? Commons.Color.menu.selectedText : Commons.Color.textDim
      opacity: root._overlay ? 0.8 : 1
      font.family: Style.font.family
      font.pixelSize: root._overlay ? Style.font.displayLarge : Style.font.iconLarge
    }

    Text {
      id: titleText
      textFormat: Text.PlainText
      width: parent.width
      text: root.title
      color: root._overlay ? Commons.Color.foreground : Commons.Color.textDim
      opacity: root._overlay ? 0.7 : 1
      font.family: Style.font.family
      font.pixelSize: root._overlay ? Style.font.title : Style.font.body
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
    }

    Text {
      id: hintText
      textFormat: Text.PlainText
      visible: root.hint !== ""
      width: parent.width
      text: root.hint
      color: root._overlay ? Commons.Color.textDim : Commons.Color.textFaint
      font.family: Style.font.family
      font.pixelSize: root._overlay ? Style.font.body : Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
    }

    Button {
      id: action
      visible: root.actionText !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.actionText
      bordered: true
      focusable: true
      hasCursor: root.hasCursor
      onClicked: root.actionClicked()
    }
  }
}
