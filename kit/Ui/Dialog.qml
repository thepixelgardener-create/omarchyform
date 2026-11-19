import QtQuick
import "../Theme"
import "../Theme" as Commons

// A modal: the `scrim` over whatever it covers, and a card with a title, a message or any body
// (the default children), and a button row: a secondary choice and a primary one, which is
// urgent when `destructive`. ConfirmDialog is this card with no title and a destructive Confirm;
// both draw the same chrome (the accent border, 88 × 34 buttons, the selected one marked).
//
// Fill a window or panel with it and set `opened`. Escape rejects, Return takes the selected
// button (the primary by default), Left/Right/Tab move the selection. Call `handleKey(event)`
// from a panel's own key handler when the dialog doesn't hold focus itself.
Item {
  id: root

  property bool opened: false
  property string title: ""
  property string message: ""
  default property alias body: bodyColumn.data
  property string secondaryText: Commons.I18n.t("common.cancel")
  property string primaryText: Commons.I18n.t("common.confirm")
  property bool destructive: false
  // 0 for the secondary button, 1 for the primary.
  property int selectedIndex: 1
  property color background: Commons.Color.background
  property color foreground: Commons.Color.foreground
  property color scrim: Commons.Color.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.cornerRadius

  signal rejected()
  signal accepted()

  function handleKey(event) {
    if (!root.opened) return false
    if (event.key === Qt.Key_Escape) {
      root.rejected()
      return true
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.text === "h" || event.text === "l"
               || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
      return true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.selectedIndex === 0) root.rejected()
      else root.accepted()
      return true
    }
    return false
  }

  visible: opened
  focus: opened
  Keys.onPressed: function(event) { event.accepted = root.handleKey(event) }

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea { anchors.fill: parent; onClicked: root.rejected() }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(32), Style.space(370))
      height: card.contentTopInset + card.contentBottomInset + content.implicitHeight + Style.space(20) + Style.space(34)
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.flat(root.selectedText, Style.normalBorderWidth)
      padding: Style.space(18)
      radius: root.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: content
        x: card.contentLeftInset
        y: card.contentTopInset
        width: card.width - card.contentLeftInset - card.contentRightInset
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          visible: root.title !== ""
          width: parent.width
          text: root.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          visible: root.message !== ""
          width: parent.width
          text: root.message
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Column {
          id: bodyColumn
          visible: children.length > 0
          width: parent.width
          spacing: Style.space(10)
        }
      }

      Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        spacing: Style.space(10)

        Repeater {
          model: [root.secondaryText, root.primaryText]

          BorderSurface {
            required property int index
            required property string modelData

            readonly property bool selected: root.selectedIndex === index
            readonly property bool urgent: index === 1 && root.destructive

            width: Style.space(88)
            height: Style.space(34)
            color: selected
              ? (urgent ? Util.alpha(Commons.Color.urgent, 0.22) : root.selectedBackground)
              : "transparent"
            borderSpec: Border.flat(urgent
              ? (selected ? Commons.Color.urgent : Util.alpha(Commons.Color.urgent, 0.56))
              : (selected ? root.selectedText : Util.alpha(root.foreground, 0.38)), Style.normalBorderWidth)
            radius: 0

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: modelData
              color: urgent ? (selected ? Commons.Color.urgent : root.foreground) : (selected ? root.selectedText : root.foreground)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = index
              onClicked: {
                if (index === 0) root.rejected()
                else root.accepted()
              }
            }
          }
        }
      }
    }
  }
}
