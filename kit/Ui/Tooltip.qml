import QtQuick
import QtQuick.Controls
import "../Theme"
import "../Theme" as Commons

// A tooltip with an optional shortcut: the [tooltip] surface, bodySmall text, and the shortcut's
// Keycaps after it. Declare it inside the hovered item and bind `visible`, as PanelToolTip:
//
//   Tooltip { visible: mouse.containsMouse; text: "Save"; shortcut: "Ctrl+S" }
//
// `held` draws it open at the parent's top-left with no delay, for galleries and still renders
// (give the parent the tooltip's implicit size).
ToolTip {
  id: root

  property string shortcut: ""
  property bool held: false

  readonly property var panelBorderSpec: Border.surfaceSpec("tooltip", "border", Commons.Color.tooltip.border, Math.max(1, Style.normalBorderWidth))

  delay: held ? 0 : 400
  timeout: -1
  visible: held
  x: held ? 0 : (parent ? Math.round((parent.width - width) / 2) : 0)
  y: held ? 0 : -height - Style.spacing.sm
  margins: held ? 0 : Style.spacing.sm
  padding: 0
  closePolicy: held ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent | Popup.CloseOnReleaseOutsideParent
  enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Style.duration(120) } }
  exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Style.duration(120) } }

  background: BorderSurface {
    color: Commons.Color.tooltip.background
    borderSpec: root.panelBorderSpec
    radius: Style.cornerRadius
  }

  contentItem: Item {
    implicitWidth: row.implicitWidth + Border.left(root.panelBorderSpec) + Border.right(root.panelBorderSpec) + Style.spacing.controlPaddingX * 2
    implicitHeight: row.implicitHeight + Border.top(root.panelBorderSpec) + Border.bottom(root.panelBorderSpec) + Style.spacing.controlPaddingY * 2

    Row {
      id: row
      x: Border.left(root.panelBorderSpec) + Style.spacing.controlPaddingX
      y: Border.top(root.panelBorderSpec) + Style.spacing.controlPaddingY
      spacing: Style.spacing.controlGap

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.text
        color: Commons.Color.tooltip.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      KeyCombo {
        visible: root.shortcut !== ""
        anchors.verticalCenter: parent.verticalCenter
        keys: root.shortcut
      }
    }
  }
}
