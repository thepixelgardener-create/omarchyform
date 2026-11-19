import QtQuick
import "../Theme"
import "../Theme" as Commons

// Keyboard shortcuts, grouped: each group is a section header over rows of a KeyCombo and what
// it does, the combos in a column as wide as the group's widest. Groups fill `columns` columns
// left to right, panelGap × 2 apart, and stack panelGap apart within a column.
//
//   ShortcutSheet {
//     groups: [
//       { title: "File", keys: [["Ctrl+N", "New file"], ["Ctrl+S", "Save"]] },
//       { title: "View", keys: [["F11", "Full screen"]] },
//     ]
//   }
//
// It is the sheet's content; put it on a Card or in a dialog to show it.
Row {
  id: root

  property var groups: []
  property int columns: 2

  spacing: Style.spacing.panelGap * 2

  Repeater {
    model: Math.max(1, Math.min(root.columns, root.groups.length))
    delegate: Column {
      id: column
      required property int index
      spacing: Style.spacing.panelGap

      Repeater {
        model: root.groups.filter(function(g, i) { return i % root.columns === column.index })
        delegate: Column {
          id: group
          required property var modelData
          spacing: Style.spacing.md

          PanelSectionHeader { text: group.modelData.title || "" }

          Grid {
            columns: 2
            columnSpacing: Style.spacing.xxl
            rowSpacing: Style.spacing.md
            verticalItemAlignment: Grid.AlignVCenter

            // Two cells a row, the combo then its description, so the combos share a column.
            Repeater {
              model: (group.modelData.keys || []).reduce(function(cells, k) { return cells.concat([[true, k[0]], [false, k[1]]]) }, [])
              delegate: Item {
                id: cell
                required property var modelData
                implicitWidth: modelData[0] ? combo.implicitWidth : Math.ceil(description.implicitWidth)
                implicitHeight: modelData[0] ? combo.implicitHeight : description.implicitHeight

                KeyCombo { id: combo; visible: cell.modelData[0]; keys: cell.modelData[0] ? cell.modelData[1] : "" }
                Text {
                  id: description
                  visible: !cell.modelData[0]
                  textFormat: Text.PlainText
                  text: cell.modelData[0] ? "" : cell.modelData[1]
                  color: Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }
      }
    }
  }
}
