import QtQuick
import "BoardStore.js" as Store

// The board name stays left; viewport controls stay in one predictable place.
// Between them, the line of keys or whatever the board is saying: Board lays
// it over the bar, and the bar says where it goes.
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

  // The line, as Board has it: how wide it is on one line, 0 when there is
  // none, and how tall it is where it has been put.
  property real lineWidth: 0
  property real lineHeight: 0
  readonly property real lineGap: theme.sp(16)
  // Beside the name when it fits between the name and the buttons, and on a
  // row of its own under them, wrapping, when it does not.
  readonly property real lineRoom: actions.x - (identity.x + identity.width) - 2 * lineGap
  readonly property bool lineBeside: lineWidth <= Math.max(0, lineRoom)
  // Where it goes, in the bar's own coordinates. Beside the name it is centred
  // on the bar, as it was centred under it, unless that would run it into
  // either end.
  readonly property real lineX: lineBeside
    ? content.x + Math.max(identity.x + identity.width + lineGap,
                           Math.min((content.width - lineWidth) / 2, actions.x - lineGap - lineWidth))
    : content.x
  readonly property real lineY: lineBeside
    ? content.y + (topRow.height - lineHeight) / 2
    : content.y + topRow.height + theme.sp(8)
  readonly property real lineSpan: lineBeside ? lineWidth : content.width

  Item {
    id: content
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: toolbar.theme.sp(8) }
    height: topRow.height + (toolbar.lineBeside ? 0 : toolbar.lineHeight + toolbar.theme.sp(8))
      + (menu.visible ? menu.height + toolbar.theme.sp(12) : 0)

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
            - toolbar.theme.sp(36) - saveMark.width - identity.spacing))
          text: toolbar.ctl.boardTitle
          elide: Text.ElideRight
          color: toolbar.theme.barForeground
          font.family: toolbar.theme.fontFamily
          font.pixelSize: toolbar.theme.fontSubtitle
          font.bold: true
          font.underline: titleMouse.containsMouse
          Accessible.role: Accessible.Button
          Accessible.name: "Rename " + toolbar.ctl.boardTitle
          Accessible.onPressAction: toolbar.ctl.renameBoard()
          MouseArea {
            id: titleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toolbar.ctl.renameBoard()
          }
        }
        // A disk when the board is in its file. The words it stands for are
        // still there for whatever reads the bar aloud.
        Text {
          id: saveMark
          objectName: "save-mark"
          readonly property string mark: toolbar.ctl.saveMark
          textFormat: Text.PlainText
          text: saveMark.mark === "opening" ? toolbar.ctl.boardState : Store.SAVE_GLYPHS[saveMark.mark]
          // Secondary, as the words were: the bar's own text held back, not the
          // theme's muted token, which a theme may set almost to its
          // background. Not yet written takes the accent, and cannot be
          // written the urgent colour, both at full strength.
          opacity: saveMark.mark === "saved" || saveMark.mark === "opening" ? 0.85 : 1
          color: saveMark.mark === "failed" || saveMark.mark === "readonly" ? toolbar.theme.urgent
            : saveMark.mark === "unsaved" ? toolbar.theme.accent : toolbar.theme.barForeground
          font.family: toolbar.theme.fontFamily
          font.pixelSize: saveMark.mark === "opening" ? toolbar.theme.fontBody : toolbar.theme.fontSubtitle
          anchors.verticalCenter: title.verticalCenter
          Accessible.role: Accessible.StaticText
          Accessible.name: toolbar.ctl.boardState
        }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: toolbar.theme.sp(8)
        Rectangle {
          objectName: "fit-button"
          width: height
          height: fitGlyph.implicitHeight + toolbar.theme.sp(8)
          radius: toolbar.theme.cornerRadius
          // The shell's buttons: a faint fill at rest, so it reads as something
          // to press, and a stronger one under the pointer.
          color: zoomMouse.containsMouse ? toolbar.theme.hoverFill : toolbar.theme.controlFill
          Accessible.role: Accessible.Button
          Accessible.name: "Fit board to window, zoom " + Math.round(toolbar.ctl.zoom * 100) + " percent"
          Accessible.onPressAction: toolbar.ctl.fitToItems()
          Text {
            textFormat: Text.PlainText
            id: fitGlyph
            anchors.centerIn: parent
            text: Store.FIT_GLYPH
            color: toolbar.theme.barForeground
            opacity: 0.85
            font.family: toolbar.theme.fontFamily
            font.pixelSize: toolbar.theme.fontSubtitle
          }
          MouseArea {
            id: zoomMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toolbar.ctl.fitToItems()
          }
        }
        Rectangle {
          objectName: "menu-button"
          width: height
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
            textFormat: Text.PlainText
            text: Store.MENU_GLYPH
            color: toolbar.ctl.menuVisible ? toolbar.theme.accent : toolbar.theme.barForeground
            font.family: toolbar.theme.fontFamily
            font.pixelSize: toolbar.theme.fontSubtitle
          }
          MouseArea {
            id: menuMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toolbar.ctl.toggleMenu()
          }
        }
      }
    }

    Flow {
      id: menu
      visible: toolbar.ctl.menuVisible
      anchors { left: parent.left; right: parent.right; top: topRow.bottom
                topMargin: (toolbar.lineBeside ? 0 : toolbar.lineHeight + toolbar.theme.sp(8)) + toolbar.theme.sp(12) }
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
            cursorShape: Qt.PointingHandCursor
            onClicked: toolbar.ctl.runMenu(index)
          }
        }
      }
    }
  }
}
