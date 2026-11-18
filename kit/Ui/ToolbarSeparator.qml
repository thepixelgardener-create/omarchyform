import QtQuick
import "../Theme"
import "../Theme" as Commons

// The vertical rule between groups in a Toolbar: 1px in the track color, sm clear on each side.
Item {
  implicitWidth: Style.spacing.sm * 2 + 1
  implicitHeight: Style.space(16)

  Rectangle {
    x: Style.spacing.sm
    width: 1
    height: parent.height
    color: Commons.Color.track
  }
}
