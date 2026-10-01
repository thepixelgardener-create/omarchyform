import QtQuick
import "BoardStore.js" as Store

// The board name stays left; viewport controls stay in one predictable place.
Rectangle {
  id: toolbar
  required property var ctl
  readonly property var theme: toolbar.ctl.theme
  // Solid, as the shell's bar is. It was the bar colour at 0.92, and the text of
  // a note passing under the header read through it, text over text.
  color: Qt.rgba(theme.barBackground.r, theme.barBackground.g, theme.barBackground.b, 1)
  border.width: theme.borderWidth
  border.color: Qt.rgba(theme.barForeground.r, theme.barForeground.g, theme.barForeground.b, 0.18)
  radius: theme.cornerRadius
  implicitHeight: content.height + theme.sp(16)
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  Item {
    id: content
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: toolbar.theme.sp(8) }
    height: topRow.height + (menu.visible ? menu.height + toolbar.theme.sp(12) : 0)

    Item {
      id: topRow
      width: parent.width
      height: Math.max(identity.height, actions.height)

      Row {
        id: identity
        anchors.left: parent.left
        anchors.leftMargin: toolbar.theme.sp(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: toolbar.theme.sp(10)
        Text {
          textFormat: Text.PlainText
          id: title
          objectName: "board-title"
          width: Math.min(implicitWidth, Math.max(0, topRow.width - actions.width
            - toolbar.theme.sp(36) - (saveState.visible ? saveState.width + identity.spacing : 0)))
          text: toolbar.ctl.boardTitle
          elide: Text.ElideRight
          color: toolbar.theme.barForeground
          font.family: toolbar.theme.fontFamily
          font.pixelSize: toolbar.theme.fontSubtitle
          font.bold: true
          Accessible.role: Accessible.Button
          Accessible.name: "Rename " + toolbar.ctl.boardTitle
          Accessible.onPressAction: toolbar.ctl.renameBoard()
          MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.renameBoard() }
        }
        Text {
          textFormat: Text.PlainText
          id: saveState
          // Keep failures visible even in a narrow window.
          visible: topRow.width > toolbar.theme.sp(520) || toolbar.ctl.saveError !== ""
          text: "· " + toolbar.ctl.boardState
          // Secondary text is the bar's own text held back, not the theme's
          // muted token, which a theme may set almost to its background. Held
          // back no further than 0.85 it clears 4.5:1 on every installed
          // theme; at 0.72, rose-pine and catppuccin-latte fell to 3.5:1.
          opacity: toolbar.ctl.saveError !== "" ? 1 : 0.85
          color: toolbar.ctl.saveError !== "" ? toolbar.theme.urgent : toolbar.theme.barForeground
          font.family: toolbar.theme.fontFamily
          font.pixelSize: toolbar.theme.fontBody
          anchors.verticalCenter: title.verticalCenter
        }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: toolbar.theme.sp(8)
        Rectangle {
          width: zoomLabel.implicitWidth + toolbar.theme.sp(16)
          height: zoomLabel.implicitHeight + toolbar.theme.sp(8)
          radius: toolbar.theme.cornerRadius
          // The shell's buttons: a faint fill at rest, so it reads as something
          // to press, and a stronger one under the pointer.
          color: zoomMouse.containsMouse ? toolbar.theme.hoverFill : toolbar.theme.controlFill
          Accessible.role: Accessible.Button
          Accessible.name: "Fit board to window, zoom " + Math.round(toolbar.ctl.zoom * 100) + " percent"
          Accessible.onPressAction: toolbar.ctl.fitToItems()
          Text {
            textFormat: Text.PlainText
            id: zoomLabel
            anchors.centerIn: parent
            text: Math.round(toolbar.ctl.zoom * 100) + "%"
            color: toolbar.theme.barForeground
            opacity: 0.85
            font.family: toolbar.theme.fontFamily
            font.pixelSize: toolbar.theme.fontBody
          }
          MouseArea {
            id: zoomMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: toolbar.ctl.fitToItems()
          }
        }
        Rectangle {
          width: opener.implicitWidth + toolbar.theme.sp(20)
          height: opener.implicitHeight + toolbar.theme.sp(8)
          radius: toolbar.theme.cornerRadius
          color: toolbar.ctl.menuVisible || menuMouse.containsMouse
            ? toolbar.theme.hoverFill : toolbar.theme.controlFill
          // Borderless at rest and edged when hot, as the shell's buttons are.
          border.width: toolbar.ctl.menuVisible || menuMouse.containsMouse ? toolbar.theme.borderWidth : 0
          border.color: Qt.rgba(toolbar.theme.barForeground.r, toolbar.theme.barForeground.g,
                                toolbar.theme.barForeground.b, 0.25)
          Accessible.role: Accessible.Button
          Accessible.name: toolbar.ctl.menuVisible ? "Close board menu" : "Open board menu"
          Accessible.onPressAction: toolbar.ctl.toggleMenu()
          Text {
            id: opener
            anchors.centerIn: parent
            textFormat: Text.StyledText
            text: Store.hintMarkup("m", "menu", toolbar.ctl.accentMarkup)
            color: toolbar.theme.barForeground
            font.family: toolbar.theme.fontFamily
            font.pixelSize: toolbar.theme.fontBody
          }
          MouseArea {
            id: menuMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: toolbar.ctl.toggleMenu()
          }
        }
      }
    }

    Flow {
      id: menu
      visible: toolbar.ctl.menuVisible
      anchors { left: parent.left; right: parent.right; top: topRow.bottom; topMargin: toolbar.theme.sp(12) }
      spacing: toolbar.theme.sp(6)
      Repeater {
        model: Store.menuEntries(toolbar.ctl.zoomMenuVisible)
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: label.implicitWidth + toolbar.theme.sp(14)
          height: label.implicitHeight + toolbar.theme.sp(8)
          readonly property bool onIt: toolbar.ctl.menuIndex === index || mouse.containsMouse
          // The shell's keyboard cursor, with its edge kept: a row of buttons
          // has no room for the › the lists carry, and the cursor still needs
          // a mark that is not only a colour.
          color: onIt ? toolbar.theme.cursorFill : toolbar.theme.controlFill
          Accessible.role: Accessible.Button
          Accessible.name: label.text
          Accessible.focused: toolbar.ctl.menuIndex === index
          Accessible.onPressAction: toolbar.ctl.runMenu(index)
          radius: toolbar.theme.cornerRadius
          border.width: toolbar.theme.borderWidth
          border.color: onIt ? toolbar.theme.cursorText : "transparent"
          Text {
            textFormat: Text.PlainText
            id: label
            anchors.centerIn: parent
            text: modelData.id === "zoom" ? modelData.label + " " + Math.round(toolbar.ctl.zoom * 100) + "%" : modelData.label
            color: parent.onIt ? toolbar.theme.cursorText : toolbar.theme.barForeground
            font.family: toolbar.theme.fontFamily
            font.pixelSize: toolbar.theme.fontBody
          }
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: toolbar.ctl.runMenu(index)
          }
        }
      }
    }
  }
}
