import QtQuick

// The timeline, while a pane is in it: one line along the bottom saying which
// step is on screen, what it was and when, over a track that shows where in
// the history it is. Keys do the stepping and playing; the track is for a
// pointer, clicked or dragged to scrub. Kept to a line, like the header, so
// the board stays the thing being looked at.
Rectangle {
  id: strip
  required property var ctl
  readonly property var theme: strip.ctl.theme

  visible: strip.ctl.timeline
  implicitHeight: words.implicitHeight + track.height + strip.theme.sp(22)
  color: Qt.rgba(strip.theme.barBackground.r, strip.theme.barBackground.g, strip.theme.barBackground.b, 1)
  border.width: strip.theme.borderWidth
  // An earlier version is marked in the accent, so it is not taken for now.
  border.color: strip.ctl.lookingBack ? strip.theme.accent
    : Qt.rgba(strip.theme.barForeground.r, strip.theme.barForeground.g, strip.theme.barForeground.b, 0.18)
  radius: strip.theme.cornerRadius
  // Nothing under it is reachable through it.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  Text {
    id: words
    objectName: "timeline-words"
    textFormat: Text.PlainText
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: strip.theme.sp(10) }
    elide: Text.ElideRight
    // Whatever the pane has just said comes first: the timeline has the line
    // under the header, so this is where it is said.
    text: strip.ctl.statusText !== "" ? strip.ctl.statusText : strip.ctl.timelineSays
    color: strip.theme.barForeground
    font.family: strip.theme.fontFamily
    font.pixelSize: strip.theme.fontBody
  }

  Item {
    id: track
    objectName: "timeline-track"
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom
              leftMargin: strip.theme.sp(10); rightMargin: strip.theme.sp(10); bottomMargin: strip.theme.sp(8) }
    height: strip.theme.sp(12)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: Math.max(1, strip.theme.borderWidth)
      color: Qt.rgba(strip.theme.barForeground.r, strip.theme.barForeground.g, strip.theme.barForeground.b, 0.35)
    }
    Rectangle {
      objectName: "timeline-marker"
      anchors.verticalCenter: parent.verticalCenter
      width: strip.theme.sp(4)
      height: parent.height
      x: Math.round(strip.ctl.timelineFraction * (parent.width - width))
      color: strip.ctl.lookingBack ? strip.theme.accent : strip.theme.barForeground
    }
    MouseArea {
      anchors.fill: parent
      // Taller than the line, so it can be hit.
      anchors.topMargin: -strip.theme.sp(6)
      anchors.bottomMargin: -strip.theme.sp(6)
      preventStealing: true
      onPressed: function (mouse) { strip.ctl.scrubTo(mouse.x / Math.max(1, width)) }
      onPositionChanged: function (mouse) { if (pressed) strip.ctl.scrubTo(mouse.x / Math.max(1, width)) }
    }
  }
}
