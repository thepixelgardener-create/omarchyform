pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store
import "kit/Ui" as O
import "kit/Theme" as Kit

// Two versions of one board: the one on screen and the one something else
// wrote while it was open. Neither is thrown away by this panel appearing, and
// neither is thrown away by ignoring it — the only things that resolve it are
// the three choices here, each of which says what it costs.
//
// Drawn with the Omarchy UI kit: its card with the menu's edge, the heading in
// the kit's urgent colour, and the choices as its list rows under the keyboard
// cursor, each saying its cost as the row's value. Not the kit's Dialog, which
// asks a two-way question; this one has three answers.
Item {
  id: decision
  required property var ctl
  function sp(n) { return Kit.Style.space(n) }

  visible: decision.ctl.conflictVisible
  width: Math.min(parent.width - Kit.Style.spacing.panelPadding * 2, decision.sp(640))

  readonly property string question: decision.ctl.t("%1 changed on disk while you had it open.", decision.ctl.boardTitle)
  readonly property var choices: [
    { name: decision.ctl.t("Keep the version from disk"), cost: decision.ctl.t("what is on screen is lost") },
    { name: decision.ctl.t("Save my changes as a copy"), cost: decision.ctl.t("both versions survive") },
    { name: decision.ctl.t("Replace the version on disk"), cost: decision.ctl.t("the one it replaces goes to backups") }
  ]

  // A choice is as tall as the kit's list row, measured off one.
  O.ListRow {
    id: ruler
    visible: false
    glyph: "1"
    title: "Ag"
    value: "Ag"
  }
  readonly property int rowHeight: Math.ceil(ruler.implicitHeight)
  // All three choices are always shown — a question with a choice missing is
  // not the question. What gives way when there is no room is the line of
  // hints, the column saying what each choice costs, and then the question's
  // own room: two lines and no rule, the rows closer together. The kit's rows
  // and spacing grow with its text, and at a large size in a small window the
  // whole question did not leave room for its answers.
  readonly property int room: Math.max(decision.rowHeight * 3, parent.height - y - Kit.Style.spacing.md)
  // The full layout, measured off a heading that is not drawn so it cannot
  // depend on which layout was chosen: the heading, the rule and the three
  // rows are four gaps, not two. Counting two left the panel two gaps short,
  // and the line of hints sat on its bottom edge.
  readonly property real gap: Kit.Style.spacing.md
  readonly property int fullHeight: body.y * 2 + fullHeading.implicitHeight + 1
                                    + decision.rowHeight * 3 + decision.gap * 5 + footer.implicitHeight
  readonly property bool compact: decision.fullHeight > decision.room
  readonly property int chrome: body.y * 2 + heading.implicitHeight + (rule.visible ? rule.height + body.spacing : 0)
                                + decision.rowHeight * 3 + body.spacing * 3
  height: decision.compact ? decision.chrome : decision.fullHeight
  Text {
    id: fullHeading
    visible: false
    textFormat: Text.PlainText
    width: body.width
    wrapMode: Text.Wrap
    maximumLineCount: 3
    elide: Text.ElideRight
    font: heading.font
    text: heading.text
  }

  // The card every summoned panel here is drawn on, with the ordinary edge, as
  // the shell's own confirmation dialog has. The question is urgent, and the
  // heading says so — in the theme's colour for it and with a mark that is not
  // only a colour — rather than an alarm-red frame round the whole panel.
  O.BorderSurface {
    objectName: "conflict-card"
    anchors.fill: parent
    color: Kit.Color.menu.background
    borderSpec: Kit.Border.surfaceSpec("menu", "border", Kit.Color.menu.border, Math.max(1, Kit.Style.space(2)))
    radius: Kit.Style.cornerRadius
  }

  // Every button: the pan surface on the canvas is below the panels, and a
  // question being answered should not also be moving the board behind it.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  Column {
    id: body
    objectName: "conflict-body"
    // The kit's panel padding, giving way where the panel is cramped.
    readonly property real pad: Math.min(Kit.Style.spacing.panelPadding, Math.round(decision.width * 0.05))
    x: body.pad
    y: body.pad
    width: parent.width - body.pad * 2
    spacing: decision.compact ? Kit.Style.spacing.xxs : decision.gap

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
      maximumLineCount: decision.compact ? 2 : 3
      elide: Text.ElideRight
      color: Kit.Color.urgent
      font.family: Kit.Style.font.family
      font.pixelSize: Kit.Style.font.title
      font.bold: true
      text: "\uf071  " + decision.question
    }

    Rectangle {
      id: rule
      visible: !decision.compact
      width: parent.width
      height: 1
      color: Kit.Color.track
    }

    Repeater {
      model: decision.choices
      O.ListRow {
        id: row
        required property var modelData
        required property int index
        width: body.width
        height: decision.rowHeight

        readonly property bool atCursor: row.index === decision.ctl.conflictIndex
        // The kit's keyboard cursor, its fill and edge: one highlight. The
        // number is the key that picks it.
        hasCursor: row.atCursor
        glyph: String(row.index + 1)
        glyphColor: Kit.Color.accent
        title: row.modelData.name
        // What it costs, while there is room to say it.
        value: decision.compact ? "" : row.modelData.cost

        Accessible.role: Accessible.Button
        Accessible.name: row.modelData.name
        Accessible.description: row.modelData.cost
        Accessible.focused: row.atCursor
        Accessible.onPressAction: {
          decision.ctl.conflictIndex = row.index
          decision.ctl.runConflictChoice()
        }
        onClicked: {
          decision.ctl.conflictIndex = row.index
          decision.ctl.runConflictChoice()
        }
      }
    }

    Text {
      id: footer
      visible: !decision.compact
      width: parent.width
      wrapMode: Text.Wrap
      textFormat: Text.StyledText
      color: Kit.Color.textDim
      font.family: Kit.Style.font.family
      font.pixelSize: Kit.Style.font.body
      text: Store.hintLine(Store.CONFLICT_HINTS, decision.ctl.accentMarkup, null, decision.ctl.tv)
    }
  }
}
