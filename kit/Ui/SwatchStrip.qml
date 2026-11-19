import QtQuick
import "../Theme"
import "../Theme" as Commons

// A row of preset colors (a theme's palette, a set of highlight colors), one chosen. The chosen
// swatch wears an accent ring; the keyboard cursor wears the hover-cursor border in the same
// place. Left/Right (h/l) walk the cursor, Space or Return choose; picking one emits
// `picked(index)` and sets `currentIndex`.
Row {
  id: root

  property var colors: []
  property int currentIndex: -1
  // The keyboard cursor; -1 for none. Follows the pointer.
  property int cursorIndex: -1
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent

  signal picked(int index)

  readonly property int swatchSize: Style.space(22)
  readonly property int ringWidth: Math.max(1, Style.space(2))
  readonly property int ringGap: Style.spacing.xxs
  readonly property int _radius: Math.min(4, Style.cornerRadius)

  function pick(index) {
    if (index < 0 || index >= colors.length) return
    currentIndex = index
    picked(index)
  }

  spacing: Style.spacing.xxs
  activeFocusOnTab: true

  Keys.onPressed: function(event) {
    var from = cursorIndex >= 0 ? cursorIndex : Math.max(0, currentIndex)
    if (event.key === Qt.Key_Right || event.text === "l") {
      cursorIndex = Math.min(colors.length - 1, from + 1); event.accepted = true
    } else if (event.key === Qt.Key_Left || event.text === "h") {
      cursorIndex = Math.max(0, from - 1); event.accepted = true
    } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      pick(from); event.accepted = true
    }
  }

  Repeater {
    model: root.colors

    Item {
      id: cell
      required property var modelData
      required property int index

      readonly property bool chosen: index === root.currentIndex
      readonly property bool hot: index === root.cursorIndex || mouse.containsMouse

      width: root.swatchSize + (root.ringGap + root.ringWidth) * 2
      height: width

      Rectangle {
        anchors.fill: parent
        visible: cell.chosen || cell.hot
        color: "transparent"
        radius: root._radius > 0 ? root._radius + root.ringGap : 0
        border.width: root.ringWidth
        border.color: cell.chosen ? root.accent : Style.hoverBorderFor(root.foreground, root.accent)
      }

      Rectangle {
        anchors.centerIn: parent
        width: root.swatchSize
        height: root.swatchSize
        radius: root._radius
        color: cell.modelData
        border.width: 1
        border.color: Commons.Color.track
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pick(cell.index)
      }
    }
  }
}
