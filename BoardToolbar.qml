import QtQuick
import "BoardStore.js" as Store

// One line: the board's name, then the menu, then the zoom. Two rows of chrome
// for one board was most of this bar's height, and the commands in the menu all
// have keys of their own, so the menu is out of the way until asked for.
Rectangle {
  id: toolbar
  required property var ctl
  // The theme's bar colour, so the board's header reads as the same kind of
  // surface as the bar it was opened from. It was transparent, which let the
  // dot grid run through the chrome and made the header look like part of the
  // canvas rather than something sitting on it.
  color: ctl.barBackground
  border.width: ctl.borderWidth
  border.color: Qt.rgba(ctl.barForeground.r, ctl.barForeground.g, ctl.barForeground.b, 0.18)
  radius: ctl.cornerRadius
  implicitHeight: content.height + ctl.sp(20)
  MouseArea { anchors.fill: parent }

  Item {
    id: content
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: toolbar.ctl.sp(10) }
    height: Math.max(identity.height, viewControls.height, menu.visible ? menu.height : 0)

    readonly property int gap: toolbar.ctl.sp(14)
    // The most the name may take, leaving the zoom and whatever sits between
    // them their room. Deliberately not derived from the menu's own width: the
    // menu is anchored to the name, so measuring one from the other would be a
    // binding loop. The opener's width is only its text, so it is safe to read.
    readonly property real identityMax: Math.max(toolbar.ctl.sp(90),
      content.width - viewControls.width - content.gap * 2
      - (menu.visible ? toolbar.ctl.sp(120) : opener.implicitWidth))

    Row {
      id: identity
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: toolbar.ctl.sp(8)
      Text {
        id: title
        // Only as wide as the name actually is, so everything after it sits
        // beside the name rather than against the far edge. A long name elides
        // at the cap instead of pushing the rest off.
        width: Math.min(implicitWidth, Math.max(toolbar.ctl.sp(40),
          content.identityMax - separator.implicitWidth - state.implicitWidth - identity.spacing * 2))
        text: toolbar.ctl.boardTitle
        elide: Text.ElideRight
        color: toolbar.ctl.barForeground
        font.family: toolbar.ctl.fontFamily
        font.pixelSize: toolbar.ctl.fontSubtitle
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
        color: toolbar.ctl.barForeground
        font.family: toolbar.ctl.fontFamily
        font.pixelSize: toolbar.ctl.fontBody
        anchors.verticalCenter: title.verticalCenter
      }
      Text {
        id: state
        text: toolbar.ctl.boardState
        opacity: toolbar.ctl.saveError !== "" ? 1 : 0.85
        color: toolbar.ctl.saveError !== "" ? toolbar.ctl.urgent : toolbar.ctl.barForeground
        font.family: toolbar.ctl.fontFamily
        font.pixelSize: toolbar.ctl.fontBody
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
      color: toolbar.ctl.barForeground
      font.family: toolbar.ctl.fontFamily
      font.pixelSize: toolbar.ctl.fontBody
      MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.toggleMenu() }
    }

    Flow {
      id: menu
      visible: toolbar.ctl.menuVisible
      anchors.left: identity.right
      anchors.leftMargin: content.gap
      anchors.right: viewControls.left
      anchors.rightMargin: content.gap
      anchors.verticalCenter: parent.verticalCenter
      spacing: toolbar.ctl.sp(6)
      Repeater {
        model: Store.MENU_COMMANDS
        delegate: Rectangle {
          required property string modelData
          required property int index
          width: label.implicitWidth + toolbar.ctl.sp(14)
          height: label.implicitHeight + toolbar.ctl.sp(8)
          // Where the keyboard is, and where the pointer is, read the same.
          readonly property bool onIt: toolbar.ctl.menuIndex === index || mouse.containsMouse
          color: onIt ? Qt.rgba(toolbar.ctl.accent.r, toolbar.ctl.accent.g, toolbar.ctl.accent.b, 0.15) : "transparent"
          radius: toolbar.ctl.cornerRadius
          border.width: onIt ? toolbar.ctl.borderWidth * 2 : 1
          border.color: onIt ? toolbar.ctl.accent
            : Qt.rgba(toolbar.ctl.barForeground.r, toolbar.ctl.barForeground.g, toolbar.ctl.barForeground.b, 0.20)
          Text {
            id: label
            anchors.centerIn: parent
            text: modelData
            color: toolbar.ctl.barForeground
            font.family: toolbar.ctl.fontFamily
            font.pixelSize: toolbar.ctl.fontBody
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

    Row {
      id: viewControls
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: toolbar.ctl.sp(12)
      Text {
        text: Math.round(toolbar.ctl.zoom * 100) + "%"
        color: toolbar.ctl.barForeground
        font.family: toolbar.ctl.fontFamily
        font.pixelSize: toolbar.ctl.fontBody
        MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.resetView() }
      }
      Text {
        textFormat: Text.StyledText
        text: Store.hintMarkup("f", "Fit", toolbar.ctl.accentMarkup)
        color: toolbar.ctl.barForeground
        font.family: toolbar.ctl.fontFamily
        font.pixelSize: toolbar.ctl.fontBody
        MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.fitToItems() }
      }
    }
  }
}
