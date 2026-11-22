import QtQuick
import "kit/Ui" as O
import "kit/Theme" as Kit

// One hint in the header's line of keys: its icon and its key, the key in the
// accent. A click does what the key does, and resting the pointer on it says
// what that is, in the kit's tooltip. Lit on hover and pressed the way a kit
// button is, so it reads as something to press and not only to read.
Item {
  id: hint
  property string glyph: ""
  property string key: ""
  property string tip: ""
  // Words after the key, for a hint with no icon of its own.
  property string label: ""
  property color foreground: Kit.Color.bar.text
  property color keyColor: Kit.Color.accent
  // A hint with nothing a click could do (what ctrl+hjkl does is a key held
  // down, not a press) is drawn the same and takes no click.
  property bool clickable: true
  signal activated()

  readonly property real padX: Kit.Style.spacing.sm
  readonly property real padY: Kit.Style.spacing.xxs
  implicitWidth: row.implicitWidth + padX * 2
  implicitHeight: row.implicitHeight + padY * 2
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Math.min(Kit.Style.cornerRadius, height / 2)
    color: mouse.pressed ? Kit.Style.pressedFillFor(hint.foreground, Kit.Color.accent)
      : mouse.containsMouse ? Kit.Style.hoverFillFor(hint.foreground, Kit.Color.accent)
      : "transparent"
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Kit.Style.spacing.sm
    // A step over the key beside it, so a glyph reads as clearly as a letter.
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: hint.glyph !== ""
      textFormat: Text.PlainText
      text: hint.glyph
      color: hint.foreground
      font.family: Kit.Style.font.family
      font.pixelSize: Math.round(Kit.Style.font.body * 1.2)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: hint.key
      color: hint.keyColor
      font.family: Kit.Style.font.family
      font.pixelSize: Kit.Style.font.body
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: hint.label !== ""
      textFormat: Text.PlainText
      text: hint.label
      color: hint.foreground
      font.family: Kit.Style.font.family
      font.pixelSize: Kit.Style.font.body
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: hint.clickable
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: hint.activated()
  }

  readonly property alias tooltip: tooltipPopup

  O.Tooltip {
    id: tooltipPopup
    objectName: "hint-tooltip"
    visible: mouse.containsMouse && hint.tip !== ""
    text: hint.tip
    // The header sits at the top edge of the window, so the default position
    // above the button runs into the window margin and drops back over it.
    y: hint.height + Kit.Style.spacing.sm
  }

  Accessible.role: hint.clickable ? Accessible.Button : Accessible.StaticText
  Accessible.name: hint.key + " " + (hint.label !== "" ? hint.label : hint.tip)
  Accessible.onPressAction: if (hint.clickable) hint.activated()
}
