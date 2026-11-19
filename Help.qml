pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store
import "kit/Ui" as O
import "kit/Theme" as Kit

// The shortcut list, drawn with the Omarchy UI kit's parts: its card on the
// menu surface, a section header and a track rule between groups, keys as key
// caps, and its scroll area. Laid out here rather than by the kit's
// ShortcutSheet, which sets each description on one line: this list has to
// stay readable in a small window at a large text size, so a description
// wraps, and a key column never takes more than half the room.
Item {
  id: help
  required property var ctl
  readonly property real pad: Kit.Style.spacing.panelPadding
  visible: ctl.helpVisible
  width: Math.min(parent.width - Kit.Style.space(32), Kit.Style.space(700))
  height: Math.min(parent.height - Kit.Style.space(32), sheet.implicitHeight + help.pad * 2)

  // The scroller the keys move and a test reads.
  readonly property alias flickable: scroller.flickable

  O.BorderSurface {
    id: card
    objectName: "help-card"
    anchors.fill: parent
    color: Kit.Color.menu.background
    borderSpec: Kit.Border.surfaceSpec("menu", "border", Kit.Color.menu.border, Math.max(1, Kit.Style.space(2)))
    radius: Kit.Style.cornerRadius
  }

  function scroll(delta) {
    var f = scroller.flickable
    f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY + delta))
  }

  // Swallow clicks so they do not reach the dismiss layer behind. Beneath the
  // scroller rather than over it, so the list keeps its drag to scroll and the
  // thumb its grab, and this catches only the margin ring.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  // The key column is measured, not guessed: an invisible column is as wide as
  // its widest row of caps and words, drawn by the same KeyLabel that draws a
  // row, so the column it sizes is exactly what a row needs.
  Column {
    id: keyRuler
    visible: false
    Repeater {
      model: Store.KEY_HELP
      KeyLabel {
        required property var modelData
        label: help.ctl.tv(modelData[0])
      }
    }
  }

  O.ScrollArea {
    id: scroller
    x: help.pad
    y: help.pad
    width: help.width - help.pad * 2
    height: help.height - help.pad * 2

    Column {
      id: sheet
      width: scroller.width
      spacing: Kit.Style.spacing.md

      // The title, and which Omarchyform this is beside it, on the next line
      // when the window is too narrow for both.
      Flow {
        width: sheet.width
        spacing: Kit.Style.spacing.lg
        bottomPadding: Kit.Style.spacing.md
        Text {
          id: title
          textFormat: Text.PlainText
          text: help.ctl.t("Keyboard shortcuts")
          color: Kit.Color.menu.text
          font.family: Kit.Style.font.family
          font.pixelSize: Kit.Style.font.heading
          font.bold: true
        }
        Text {
          objectName: "help-version"
          visible: help.ctl.pluginVersion !== ""
          textFormat: Text.PlainText
          text: help.ctl.t("Omarchyform %1", help.ctl.pluginVersion)
          color: Kit.Color.textFaint
          font.family: Kit.Style.font.family
          font.pixelSize: Kit.Style.font.body
          height: title.height
          verticalAlignment: Text.AlignBottom
        }
      }
      // In groups, the way the shell's panels break a long list: a rule, a
      // section header, then the rows.
      Repeater {
        model: Store.KEY_HELP_SECTIONS
        Column {
          id: section
          required property var modelData
          required property int index
          width: sheet.width
          spacing: Kit.Style.spacing.md

          Rectangle {
            visible: section.index > 0
            width: parent.width
            height: 1
            color: Kit.Color.track
          }
          O.PanelSectionHeader {
            objectName: "help-section"
            text: help.ctl.tv(section.modelData.title)
            topPadding: section.index > 0 ? Kit.Style.spacing.xs : 0
          }

          Repeater {
            model: section.modelData.rows
            Item {
              id: row
              required property var modelData
              // Room for the scrollbar, which lies over the content's edge.
              width: sheet.width - scroller.thickness - Kit.Style.spacing.xs
              height: Math.max(keys.height, description.implicitHeight)
              readonly property real gap: Kit.Style.spacing.xxl
              // Never more than half the room, so a long label cannot squeeze
              // the description narrower than itself in a small window.
              readonly property real keyColumn: Math.min(Math.ceil(keyRuler.implicitWidth), (row.width - row.gap) * 0.5)
              KeyLabel {
                id: keys
                width: row.keyColumn
                label: help.ctl.tv(row.modelData[0])
              }
              Text {
                id: description
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: row.keyColumn + row.gap
                anchors.right: parent.right
                wrapMode: Text.Wrap
                text: help.ctl.tv(row.modelData[1])
                color: Kit.Color.menu.text
                font.family: Kit.Style.font.family
                font.pixelSize: Kit.Style.font.body
              }
            }
          }
        }
      }
    }
  }
}
