import QtQuick

// One line: the board's name, then the menu, then the zoom. Two rows of chrome
// for one board was most of this bar's height, and the commands in the menu all
// have keys of their own, so the menu is out of the way until asked for.
Rectangle {
  id: toolbar
  required property var ctl
  color: ctl.canvasBackground
  border.width: ctl.borderWidth
  border.color: Qt.rgba(ctl.foreground.r, ctl.foreground.g, ctl.foreground.b, 0.18)
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
        color: toolbar.ctl.foreground
        font.family: toolbar.ctl.fontFamily
        font.pixelSize: toolbar.ctl.fontSubtitle
        MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.renameBoard() }
      }
      Text {
        id: separator
        text: "·"
        color: toolbar.ctl.muted
        font.family: toolbar.ctl.fontFamily
        font.pixelSize: toolbar.ctl.fontBody
        anchors.verticalCenter: title.verticalCenter
      }
      Text {
        id: state
        text: toolbar.ctl.boardState
        color: toolbar.ctl.saveError !== "" ? toolbar.ctl.urgent : toolbar.ctl.muted
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
      text: "menu · m"
      color: toolbar.ctl.muted
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
        model: ["New", "Boards", "Import", "Save copy", "Export PNG", "Help"]
        delegate: Rectangle {
          required property string modelData
          required property int index
          width: label.implicitWidth + toolbar.ctl.sp(14)
          height: label.implicitHeight + toolbar.ctl.sp(8)
          color: mouse.containsMouse ? Qt.rgba(toolbar.ctl.accent.r, toolbar.ctl.accent.g, toolbar.ctl.accent.b, 0.15) : "transparent"
          radius: toolbar.ctl.cornerRadius
          border.width: 1
          border.color: Qt.rgba(toolbar.ctl.foreground.r, toolbar.ctl.foreground.g, toolbar.ctl.foreground.b, 0.20)
          Text {
            id: label
            anchors.centerIn: parent
            text: modelData
            color: toolbar.ctl.foreground
            font.family: toolbar.ctl.fontFamily
            font.pixelSize: toolbar.ctl.fontBody
          }
          MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
              // Picking a command closes the menu: it was asked for to reach
              // this, and leaving it open would cost the height again.
              toolbar.ctl.menuVisible = false
              if (index === 0) toolbar.ctl.newBoard()
              else if (index === 1) toolbar.ctl.openBrowser()
              else if (index === 2) toolbar.ctl.importBoard()
              else if (index === 3) toolbar.ctl.exportBoard()
              else if (index === 4) toolbar.ctl.choosePng()
              else toolbar.ctl.helpVisible = true
            }
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
        color: toolbar.ctl.foreground
        font.family: toolbar.ctl.fontFamily
        font.pixelSize: toolbar.ctl.fontBody
        MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.resetView() }
      }
      Text {
        text: "Fit · f"
        color: toolbar.ctl.accent
        font.family: toolbar.ctl.fontFamily
        font.pixelSize: toolbar.ctl.fontBody
        MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.fitToItems() }
      }
    }
  }
}
