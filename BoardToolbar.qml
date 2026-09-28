import QtQuick
import "BoardStore.js" as Store

// One line: the board's name and the menu. Two rows of chrome
// for one board was most of this bar's height, and the commands in the menu all
// have keys of their own, so the menu is out of the way until asked for.
Rectangle {
  id: toolbar
  required property var ctl
  readonly property var theme: toolbar.ctl.theme
  // Keep labels crisp while letting a little of the canvas show through.
  color: Qt.rgba(theme.barBackground.r, theme.barBackground.g, theme.barBackground.b, 0.92)
  border.width: theme.borderWidth
  border.color: Qt.rgba(theme.barForeground.r, theme.barForeground.g, theme.barForeground.b, 0.18)
  radius: theme.cornerRadius
  implicitHeight: content.height + theme.sp(20)
  // The header owns everything pressed on it, every button. The pan surface
  // on the canvas is below the chrome, and the board should not slide about
  // under a bar that is being clicked.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  Item {
    id: content
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: toolbar.theme.sp(10) }
    height: Math.max(identity.height, menu.visible ? menu.height : 0)

    readonly property int gap: toolbar.theme.sp(14)
    // The most the name may take, leaving room for the menu. Deliberately not derived from the menu's own width: the
    // menu is anchored to the name, so measuring one from the other would be a
    // binding loop. The opener's width is only its text, so it is safe to read.
    readonly property real identityMax: Math.max(toolbar.theme.sp(90),
      content.width - content.gap * 2
      - (menu.visible ? toolbar.theme.sp(120) : opener.implicitWidth))

    Row {
      id: identity
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: toolbar.theme.sp(8)
      Text {
        id: title
        // Only as wide as the name actually is, so everything after it sits
        // beside the name rather than against the far edge. A long name elides
        // at the cap instead of pushing the rest off.
        width: Math.min(implicitWidth, Math.max(toolbar.theme.sp(40),
          content.identityMax - separator.implicitWidth - saveState.implicitWidth - identity.spacing * 2))
        text: toolbar.ctl.boardTitle
        elide: Text.ElideRight
        color: toolbar.theme.barForeground
        font.family: toolbar.theme.fontFamily
        font.pixelSize: toolbar.theme.fontSubtitle
        MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.renameBoard() }
      }
      // Secondary text is the bar's own text held back, not the theme's muted
      // token. A theme is free to set muted almost to its own background —
      // azure-glow does, at 1.28:1 — and then a plugin using it for text
      // writes in invisible ink. Held back like this it is 4.9:1 at worst.
      Text {
        id: separator
        text: "·"
        opacity: 0.85
        color: toolbar.theme.barForeground
        font.family: toolbar.theme.fontFamily
        font.pixelSize: toolbar.theme.fontBody
        anchors.verticalCenter: title.verticalCenter
      }
      Text {
        id: saveState
        text: toolbar.ctl.boardState
        opacity: toolbar.ctl.saveError !== "" ? 1 : 0.85
        color: toolbar.ctl.saveError !== "" ? toolbar.theme.urgent : toolbar.theme.barForeground
        font.family: toolbar.theme.fontFamily
        font.pixelSize: toolbar.theme.fontBody
        anchors.verticalCenter: title.verticalCenter
      }
    }

    // Closed, the menu leaves one word behind. Without it the commands would be
    // reachable only by someone who already knows the key, which is no way to
    // treat a pointer.
    Text {
      id: opener
      visible: !menu.visible
      anchors.left: identity.right
      anchors.leftMargin: content.gap
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.StyledText
      // btop's convention: the key is the letter it already starts with, in
      // the accent, rather than the word and then the letter again.
      text: Store.hintMarkup("m", "menu", toolbar.ctl.accentMarkup)
      opacity: 0.85
      color: toolbar.theme.barForeground
      font.family: toolbar.theme.fontFamily
      font.pixelSize: toolbar.theme.fontBody
      MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.toggleMenu() }
    }

    Flow {
      id: menu
      visible: toolbar.ctl.menuVisible
      anchors.left: identity.right
      anchors.leftMargin: content.gap
      anchors.right: parent.right
      anchors.rightMargin: content.gap
      anchors.verticalCenter: parent.verticalCenter
      spacing: toolbar.theme.sp(6)
      Repeater {
        model: Store.menuEntries(toolbar.ctl.zoomMenuVisible)
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: label.implicitWidth + toolbar.theme.sp(14)
          height: label.implicitHeight + toolbar.theme.sp(8)
          // Where the keyboard is, and where the pointer is, read the same.
          readonly property bool onIt: toolbar.ctl.menuIndex === index || mouse.containsMouse
          color: onIt ? Qt.rgba(toolbar.theme.accent.r, toolbar.theme.accent.g, toolbar.theme.accent.b, 0.15) : "transparent"
          Accessible.role: Accessible.Button
          Accessible.name: label.text
          Accessible.focused: toolbar.ctl.menuIndex === index
          Accessible.onPressAction: toolbar.ctl.runMenu(index)
          radius: toolbar.theme.cornerRadius
          border.width: onIt ? toolbar.theme.borderWidth * 2 : 1
          border.color: onIt ? toolbar.theme.accent
            : Qt.rgba(toolbar.theme.barForeground.r, toolbar.theme.barForeground.g, toolbar.theme.barForeground.b, 0.20)
          Text {
            id: label
            anchors.centerIn: parent
            text: modelData.id === "zoom" ? modelData.label + " " + Math.round(toolbar.ctl.zoom * 100) + "%" : modelData.label
            color: toolbar.theme.barForeground
            font.family: toolbar.theme.fontFamily
            font.pixelSize: toolbar.theme.fontBody
          }
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            // Picking a command closes the menu, whichever way it was picked:
            // the controller owns both, so a click and an enter cannot diverge.
            onClicked: toolbar.ctl.runMenu(index)
          }
        }
      }
    }

  }
}
