import QtQuick
import "BoardStore.js" as Store
import "kit/Ui" as O
import "kit/Theme" as Kit

// One row of the command list: the kit's list row with the command's icon and
// name, and at its end why it cannot run now, if it cannot, then its key as
// key caps.
//
// A file of its own, reading only its own properties, so that the component
// it hands the kit for its end is an ordinary one. Written inside Commands.qml
// it was bound to that file's context (`pragma ComponentBehavior: Bound`), and
// Qt 6.4 will not build a bound component in another context: the row's
// Loader, in the kit's, built nothing, and the rows lost their keys there.
O.ListRow {
  id: row
  // The command, as BoardStore's table has it.
  property var command: ({ name: "", key: "", needs: "" })
  // Whether it can run now, and if not, why not.
  property bool ready: true
  property string excuse: ""
  // What its name is said as, in the board's language.
  property string name: row.command.name

  // Dimmed by its colour and not by the kit's `disabled`, which would take
  // the click: a click on one still says why it cannot run.
  foreground: row.ready ? Kit.Color.menu.text : Kit.Color.textFaint
  glyph: Store.commandIcon(row.command)
  title: row.name
  // A family's entry leads somewhere rather than doing something. The others
  // keep the slot empty, so every row's keys line up.
  trailingGlyph: row.command.opens ? "›" : " "
  // Why it cannot run, where the eye is already going to look for how to run
  // it; then the key, as key caps. The kit's Loader builds this and hands it
  // nothing, so it reads the row by id: unqualified to qmllint, which wants a
  // bound component, and a bound one is what Qt 6.4 will not build there.
  // qmllint disable unqualified
  trailing: Component {
    Row {
      spacing: Kit.Style.spacing.md
      Text {
        textFormat: Text.PlainText
        objectName: "command-excuse"
        anchors.verticalCenter: parent.verticalCenter
        visible: row.excuse !== ""
        text: row.excuse
        color: Kit.Color.textFaint
        font.family: Kit.Style.font.family
        font.pixelSize: Kit.Style.font.bodySmall
      }
      KeyLabel {
        anchors.verticalCenter: parent.verticalCenter
        visible: row.command.key !== ""
        label: row.command.key
        opacity: row.ready ? 1 : 0.5
      }
    }
  }
  // qmllint enable unqualified
}
