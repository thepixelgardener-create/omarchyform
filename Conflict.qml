pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store

// Two versions of one board: the one on screen and the one something else
// wrote while it was open. Neither is thrown away by this panel appearing, and
// neither is thrown away by ignoring it — the only things that resolve it are
// the three choices here, each of which says what it costs.
Rectangle {
  id: decision
  required property var ctl

  visible: decision.ctl.conflictVisible
  width: Math.min(parent.width - decision.ctl.sp(64), decision.ctl.sp(640))

  readonly property var choices: [
    { name: "Keep the version from disk", cost: "what is on screen is lost" },
    { name: "Save my changes as a copy", cost: "both versions survive" },
    { name: "Replace the version on disk", cost: "the one it replaces goes to backups" }
  ]

  Text {
    id: ruler
    visible: false
    text: "Ag"
    font.family: decision.ctl.fontFamily
    font.pixelSize: decision.ctl.fontSubtitle
  }
  readonly property int rowHeight: ruler.implicitHeight + decision.ctl.sp(10)
  // All three choices are always shown — a question with a choice missing is
  // not the question. What gives way when there is no room is the line of
  // hints and the column saying what each choice costs, in that order.
  readonly property int room: Math.max(decision.rowHeight * 3, parent.height - y - decision.ctl.sp(16))
  readonly property int chrome: body.y * 2 + body.spacing * 2 + heading.implicitHeight + rule.height
  readonly property int fullHeight: decision.chrome + decision.ctl.sp(10)
                                    + footer.implicitHeight + decision.rowHeight * 3
  readonly property bool compact: decision.fullHeight > decision.room
  height: decision.compact ? decision.chrome + decision.rowHeight * 3 : decision.fullHeight

  color: decision.ctl.canvasBackground
  border.width: decision.ctl.borderWidth
  // Not the ordinary panel edge: this one is asking a question that does not
  // go away, and the theme has a colour for exactly that.
  border.color: decision.ctl.urgent
  radius: decision.ctl.cornerRadius

  MouseArea { anchors.fill: parent }

  Column {
    id: body
    x: decision.ctl.sp(16)
    y: decision.ctl.sp(16)
    width: parent.width - decision.ctl.sp(32)
    spacing: decision.ctl.sp(10)

    Text {
      id: heading
      width: parent.width
      wrapMode: Text.Wrap
      color: decision.ctl.foreground
      font.family: decision.ctl.fontFamily
      font.pixelSize: decision.ctl.fontSubtitle
      text: decision.ctl.boardTitle + " changed on disk while you had it open."
    }

    Rectangle {
      id: rule
      width: parent.width
      height: decision.ctl.borderWidth
      color: Qt.rgba(decision.ctl.foreground.r, decision.ctl.foreground.g,
                     decision.ctl.foreground.b, 0.25)
    }

    Repeater {
      model: decision.choices
      Item {
        id: row
        required property var modelData
        required property int index
        width: body.width
        height: decision.rowHeight

        readonly property bool current: row.index === decision.ctl.conflictIndex

        Rectangle {
          anchors.fill: parent
          visible: row.current
          color: Qt.rgba(decision.ctl.accent.r, decision.ctl.accent.g, decision.ctl.accent.b, 0.18)
        }

        // The cursor is a mark as well as a colour: a row that is only
        // highlighted is not distinguishable to everyone looking at it.
        Text {
          id: marker
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          text: (row.current ? "›" : " ") + " " + (row.index + 1) + "  "
          color: decision.ctl.accent
          font.family: decision.ctl.fontFamily
          font.pixelSize: decision.ctl.fontSubtitle
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: marker.right
          anchors.right: cost.left
          anchors.rightMargin: decision.ctl.sp(12)
          elide: Text.ElideRight
          text: row.modelData.name
          color: decision.ctl.foreground
          opacity: row.current ? 1.0 : 0.8
          font.family: decision.ctl.fontFamily
          font.pixelSize: decision.ctl.fontSubtitle
        }

        Text {
          id: cost
          visible: !decision.compact
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          text: row.modelData.cost
          color: decision.ctl.foreground
          opacity: 0.55
          font.family: decision.ctl.fontFamily
          font.pixelSize: decision.ctl.fontBody
        }

        MouseArea {
          anchors.fill: parent
          onClicked: {
            decision.ctl.conflictIndex = row.index
            decision.ctl.runConflictChoice()
          }
        }
      }
    }

    Text {
      id: footer
      visible: !decision.compact
      width: parent.width
      wrapMode: Text.Wrap
      textFormat: Text.StyledText
      color: decision.ctl.foreground
      opacity: 0.55
      font.family: decision.ctl.fontFamily
      font.pixelSize: decision.ctl.fontBody
      text: Store.hintLine(Store.CONFLICT_HINTS, decision.ctl.accentMarkup)
    }
  }
}
