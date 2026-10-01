pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store

// Two versions of one board: the one on screen and the one something else
// wrote while it was open. Neither is thrown away by this panel appearing, and
// neither is thrown away by ignoring it — the only things that resolve it are
// the three choices here, each of which says what it costs.
Item {
  id: decision
  required property var ctl
  readonly property var theme: decision.ctl.theme

  visible: decision.ctl.conflictVisible
  width: Math.min(parent.width - decision.theme.sp(64), decision.theme.sp(640))

  readonly property string question: decision.ctl.boardTitle + " changed on disk while you had it open."
  readonly property var choices: [
    { name: "Keep the version from disk", cost: "what is on screen is lost" },
    { name: "Save my changes as a copy", cost: "both versions survive" },
    { name: "Replace the version on disk", cost: "the one it replaces goes to backups" }
  ]

  Text {
    textFormat: Text.PlainText
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
  // Everything the column stacks with the gap after each: the heading, the
  // rule and the three rows are four gaps, not two. Counting two left the
  // panel two gaps short, and the line of hints sat on its bottom edge.
  readonly property int chrome: body.y * 2 + heading.implicitHeight + rule.height
                                + decision.rowHeight * 3 + body.spacing * 4
  readonly property int fullHeight: decision.chrome + body.spacing + footer.implicitHeight
  readonly property bool compact: decision.fullHeight > decision.room
  height: decision.compact ? decision.chrome : decision.fullHeight

  // The card every summoned panel here is drawn on, with the ordinary edge, as
  // the shell's own confirmation dialog has. The question is urgent, and the
  // heading says so — in the theme's colour for it and with a mark that is not
  // only a colour — rather than an alarm-red frame round the whole panel.
  Surface { anchors.fill: parent; theme: decision.theme }

  // Every button: the pan surface on the canvas is below the panels, and a
  // question being answered should not also be moving the board behind it.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  Column {
    id: body
    objectName: "conflict-body"
    x: decision.theme.sp(16)
    y: decision.theme.sp(16)
    width: parent.width - decision.theme.sp(32)
    spacing: decision.theme.sp(10)

    Text {
      textFormat: Text.PlainText
      id: heading
      Accessible.role: Accessible.AlertMessage
      Accessible.name: decision.question
      width: parent.width
      wrapMode: Text.Wrap
      // Three lines at most. A long board name at a large size in a small
      // window wrapped to four, and then even the compact panel — the three
      // choices and nothing else — ran off the bottom. The name gives way
      // before a choice does, as it does in the header.
      maximumLineCount: 3
      elide: Text.ElideRight
      color: decision.theme.urgent
      font.family: decision.theme.fontFamily
      font.pixelSize: decision.theme.fontSubtitle
      text: "\uf071  " + decision.question
    }

    Rectangle {
      id: rule
      width: parent.width
      height: decision.theme.borderWidth
      color: Qt.rgba(decision.theme.panelText.r, decision.theme.panelText.g,
                     decision.theme.panelText.b, 0.25)
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

        // The shell's keyboard cursor, as its menu draws one.
        Surface {
          anchors.fill: parent
          visible: row.current
          theme: decision.theme
          color: decision.theme.cursorFill
          spec: decision.theme.cursorBorder
        }

        // The cursor is a mark as well as a colour: a row that is only
        // highlighted is not distinguishable to everyone looking at it.
        Text {
          textFormat: Text.PlainText
          id: marker
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          text: (row.current ? "›" : " ") + " " + (row.index + 1) + "  "
          color: row.current ? decision.theme.cursorText : decision.theme.accent
          font.family: decision.theme.fontFamily
          font.pixelSize: decision.theme.fontSubtitle
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: marker.right
          anchors.right: cost.left
          anchors.rightMargin: decision.theme.sp(12)
          elide: Text.ElideRight
          text: row.modelData.name
          color: row.current ? decision.theme.cursorText : decision.theme.panelText
          opacity: row.current ? 1.0 : 0.8
          font.family: decision.theme.fontFamily
          font.pixelSize: decision.theme.fontSubtitle
        }

        Text {
          textFormat: Text.PlainText
          id: cost
          visible: !decision.compact
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: parent.right
          text: row.modelData.cost
          color: decision.theme.panelText
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
      color: decision.theme.panelText
      opacity: 0.55
      font.family: decision.theme.fontFamily
      font.pixelSize: decision.theme.fontBody
      text: Store.hintLine(Store.CONFLICT_HINTS, decision.ctl.accentMarkup)
    }
  }
}
