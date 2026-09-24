import QtQuick

Rectangle {
  id: toolbar
  required property var ctl
  color: ctl.canvasBackground
  border.width: ctl.borderWidth
  border.color: Qt.rgba(ctl.foreground.r, ctl.foreground.g, ctl.foreground.b, 0.18)
  radius: ctl.cornerRadius
  implicitHeight: content.implicitHeight + ctl.sp(24)
  MouseArea { anchors.fill: parent }
  Column {
    id: content
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: toolbar.ctl.sp(12) }
    spacing: toolbar.ctl.sp(10)
    Row {
      width: parent.width
      spacing: toolbar.ctl.sp(12)
      Column {
        width: parent.width - viewControls.width - parent.spacing
        Text {
          width: parent.width
          text: toolbar.ctl.boardTitle
          elide: Text.ElideRight
          color: toolbar.ctl.foreground
          font.family: toolbar.ctl.fontFamily
          font.pixelSize: toolbar.ctl.fontSubtitle
          MouseArea { anchors.fill: parent; onClicked: toolbar.ctl.renameBoard() }
        }
        Text {
          text: toolbar.ctl.boardState
          color: toolbar.ctl.saveError !== "" ? toolbar.ctl.urgent : toolbar.ctl.muted
          font.family: toolbar.ctl.fontFamily
          font.pixelSize: toolbar.ctl.fontBody
        }
      }
      Row {
        id: viewControls
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
    Flow {
      width: parent.width
      spacing: toolbar.ctl.sp(6)
      Repeater {
        model: ["New", "Boards", "Import", "Save copy", "Export PNG", "Help"]
        delegate: Rectangle {
          required property string modelData
          required property int index
          width: label.implicitWidth + toolbar.ctl.sp(18)
          height: label.implicitHeight + toolbar.ctl.sp(12)
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
  }
}
