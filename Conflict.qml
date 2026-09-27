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
  readonly property var theme: decision.ctl.theme

  visible: decision.ctl.conflictVisible
  width: Math.min(parent.width - decision.theme.sp(64), decision.theme.sp(640))

  readonly property var choices: [
    { name: "Keep the version from disk", cost: "what is on screen is lost" },
    { name: "Save my changes as a copy", cost: "both versions survive" },
    { name: "Replace the version on disk", cost: "the one it replaces goes to backups" }
  ]

  Text {
    id: ruler
    visible: false
    text: "Ag"
    font.family: decision.theme.fontFamily
    font.pixelSize: decision.theme.fontSubtitle
  }
  readonly property int rowHeight: ruler.implicitHeight + decision.theme.sp(10)
  // All three choices are always shown — a question with a choice missing is
  // not the question. What gives way when there is no room is the line of
  // hints and the column saying what each choice costs, in that order.
  readonly property int room: Math.max(decision.rowHeight * 3, parent.height - y - decision.theme.sp(16))
  readonly property int chrome: body.y * 2 + body.spacing * 2 + heading.implicitHeight + rule.height
  readonly property int fullHeight: decision.chrome + decision.theme.sp(10)
                                    + footer.implicitHeight + decision.rowHeight * 3
  readonly property bool compact: decision.fullHeight > decision.room
  height: decision.compact ? decision.chrome + decision.rowHeight * 3 : decision.fullHeight

  color: decision.theme.canvasBackground
  border.width: decision.theme.borderWidth
  // Not the ordinary panel edge: this one is asking a question that does not
  // go away, and the theme has a colour for exactly that.
  border.color: decision.theme.urgent
  radius: decision.theme.cornerRadius

  MouseArea { anchors.fill: parent }

  Column {
    id: body
    x: decision.theme.sp(16)
    y: decision.theme.sp(16)
    width: parent.width - decision.theme.sp(32)
    spacing: decision.theme.sp(10)

    Text {
      id: heading
      Accessible.role: Accessible.AlertMessage
      Accessible.name: heading.text
      width: parent.width
      wrapMode: Text.Wrap
      color: decision.theme.foreground
      font.family: decision.theme.fontFamily
      font.pixelSize: decision.theme.fontSubtitle
      text: decision.ctl.boardTitle + " changed on disk while you had it open."
    }

    Rectangle {
      id: rule
      width: parent.width
      height: decision.theme.borderWidth
      color: Qt.rgba(decision.theme.foreground.r, decision.theme.foreground.g,
                     decision.theme.foreground.b, 0.25)
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

        Accessible.role: Accessible.Button
        Accessible.name: row.modelData.name
        Accessible.description: row.modelData.cost
        Accessible.focused: row.current
        Accessible.onPressAction: {
          decision.ctl.conflictIndex = row.index
          decision.ctl.runConflictChoice()
        }

        Rectangle {
          anchors.fill: parent
          visible: row.current
          color: Qt.rgba(decision.theme.accent.r, decision.theme.accent.g, decision.theme.accent.b, 0.18)
        }

        // The cursor is a mark as well as a colour: a row that is only
        // highlighted is not distinguishable to everyone looking at it.
        Text {
          id: marker
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          text: (row.current ? "›" : " ") + " " + (row.index + 1) + "  "
          color: decision.theme.accent
          font.family: decision.theme.fontFamily
          font.pixelSize: decision.theme.fontSubtitle
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: marker.right
          anchors.right: cost.left
          anchors.rightMargin: decision.theme.sp(12)
          elide: Text.ElideRight
          text: row.modelData.name
          color: decision.theme.foreground
          opacity: row.current ? 1.0 : 0.8
          font.family: decision.theme.fontFamily
          font.pixelSize: decision.theme.fontSubtitle
        }

        Text {
          id: cost
          visible: !decision.compact
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          text: row.modelData.cost
          color: decision.theme.foreground
          opacity: 0.55
          font.family: decision.theme.fontFamily
          font.pixelSize: decision.theme.fontBody
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
      color: decision.theme.foreground
      opacity: 0.55
      font.family: decision.theme.fontFamily
      font.pixelSize: decision.theme.fontBody
      text: Store.hintLine(Store.CONFLICT_HINTS, decision.ctl.accentMarkup)
    }
  }
}
