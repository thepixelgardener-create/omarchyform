pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store

// Every command by name. The keys are quick once they are in the hands and
// useless before that, and the header menu only ever held six of them — so a
// board you have not opened in a month was a list of letters to remember.
//
// Summoned with `:` and gone again on escape, so it costs no height when it is
// not being asked for: the same bargain the menu makes. It does not take the
// keyboard focus, because the board's own key handler owns this mode the way it
// owns finding — one place where what a keystroke means is decided.
// Deliberately not called `palette`: an Item has a `palette` property of its
// own, and inside a delegate Qt 6.4 resolves that name to it rather than to
// this id — every binding in the rows then reads off undefined. Qt 6.11
// resolves the id and says nothing, so it is a name that only breaks on the
// version CI runs. The same reason this file is not called Palette.qml.
Item {
  id: panel
  required property var ctl
  readonly property var theme: panel.ctl.theme
  // The board behind it, which owns what a key means: the field hands back
  // the ones the panel uses rather than deciding them a second time.
  required property var board

  visible: panel.ctl.paletteVisible
  width: Math.min(parent.width - panel.theme.sp(64), panel.theme.sp(560))

  // How many rows there is room for, rather than how many there are. A list of
  // nine at a theme's large font is taller than a small window, and a panel
  // that runs off the bottom hides the very commands it exists to show.
  readonly property int room: Math.max(panel.rowHeight * 2, parent.height - y - panel.theme.sp(24))
  // Everything in the panel that is not a row: the padding above and below, the
  // two gaps the column leaves, the line you type into and the rule under it.
  // Measured off the parts themselves, because a number guessed here crops the
  // bottom row — which is what it did.
  readonly property int chrome: body.y * 2 + body.spacing * 2 + query.implicitHeight + rule.height
  readonly property int fits: Math.max(1, Math.floor((panel.room - panel.chrome) / panel.rowHeight))
  readonly property int visibleRows: Math.max(1, Math.min(panel.ctl.paletteMatches.length,
                                                          panel.ctl.paletteRows, panel.fits))
  height: panel.chrome + panel.rowHeight * panel.visibleRows

  // Solid, as the shell's menu is. It was the canvas at 0.92, which let the
  // board's own text read faintly through the rows of the list over it.
  Surface { anchors.fill: parent; theme: panel.theme }

  // Swallow clicks so they do not reach the board underneath — every button,
  // so a middle drag on the panel does not pan the canvas behind it.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  // A row is as tall as the text in it, measured rather than guessed: the theme
  // chooses the font, and a list sized from a number picked here would crop its
  // own rows the moment that font grew.
  Text {
    id: ruler
    visible: false
    text: "Ag"
    font.family: panel.theme.fontFamily
    font.pixelSize: panel.theme.fontSubtitle
  }
  readonly property int rowHeight: ruler.implicitHeight + panel.theme.sp(8)

  Column {
    id: body
    y: panel.theme.sp(16)
    x: panel.theme.sp(16)
    width: parent.width - panel.theme.sp(32)
    spacing: panel.theme.sp(10)

    Row {
      width: parent.width
      spacing: 0

      Text {
        id: query
        text: panel.ctl.paletteScope === "typing" ? "format: " : "run: "
        color: panel.theme.panelText
        font.family: panel.theme.fontFamily
        font.pixelSize: panel.theme.fontSubtitle
      }

      // A real field: a query that only grew at the end could not be moved
      // through, selected in, pasted into, or composed in a language that
      // needs an input method — and the commands are found by typing.
      TextInput {
        id: typed
        width: parent.width - query.width
        clip: true
        color: panel.theme.panelText
        selectionColor: panel.theme.accent
        selectedTextColor: panel.theme.panelBackground
        selectByMouse: true
        font.family: panel.theme.fontFamily
        font.pixelSize: panel.theme.fontSubtitle

        Accessible.role: Accessible.EditableText
        Accessible.name: "Command to run"
        Accessible.description: panel.ctl.paletteMatches.length + " commands match"

        onTextChanged: panel.ctl.setPaletteQuery(typed.text)
        readonly property string held: panel.ctl.paletteQuery
        onHeldChanged: if (typed.held !== typed.text) typed.text = typed.held

        // Deferred for the same reason the board's find field defers: whatever
        // else is set as the palette opens lands here on its own, and taking
        // the keyboard has to be the last thing that happens.
        readonly property bool wanted: panel.ctl.paletteVisible
        onWantedChanged: {
          if (!wanted) { panel.ctl.focusKeys(); return }
          Qt.callLater(function () {
            if (!panel.ctl.paletteVisible) return
            typed.text = panel.ctl.paletteQuery
            typed.forceActiveFocus()
            typed.selectAll()
          })
        }

        // The panel decides what these mean; everything else is typing.
        Keys.onPressed: function (event) { panel.board.paletteKey(event) }
      }
    }

    Rectangle {
      id: rule
      width: parent.width
      height: panel.theme.borderWidth
      color: Qt.rgba(panel.theme.panelText.r, panel.theme.panelText.g,
                     panel.theme.panelText.b, 0.25)
    }

    Item {
      width: parent.width
      height: panel.rowHeight * panel.visibleRows

      ListView {
        id: list
        anchors.fill: parent
        anchors.rightMargin: panel.theme.sp(10)
        clip: true
        model: panel.ctl.paletteMatches
        currentIndex: panel.ctl.paletteIndex
        highlightMoveDuration: 0
        // Keep the cursor in view when the list is longer than the panel: the
        // rest are reached by typing, but walking to them has to work too.
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
          id: row
          required property var modelData
          required property int index
          width: list.width
          height: panel.rowHeight

          readonly property bool current: row.index === panel.ctl.paletteIndex

          // Named for anything reading the screen rather than looking at it:
          // what the command is, what it answers to, and why it cannot run.
          Accessible.role: Accessible.Button
          Accessible.name: row.modelData.name
                           + (row.modelData.key === "" ? "" : ", " + row.modelData.key)
          Accessible.description: row.ready ? "" : panel.ctl.commandExcuse(row.modelData.needs)
          Accessible.focused: row.current
          Accessible.onPressAction: {
            panel.ctl.paletteIndex = row.index
            panel.ctl.runPaletteChoice()
          }
          // Dimmed rather than hidden. A command that cannot run now is still
          // one this board has, and hiding it would teach that it does not
          // exist; the line below says what it is waiting for.
          readonly property bool ready: panel.ctl.commandReady(row.modelData.needs)

          // The shell's keyboard cursor, as its menu draws one.
          Surface {
            anchors.fill: parent
            visible: row.current
            theme: panel.theme
            color: panel.theme.cursorFill
            spec: panel.theme.cursorBorder
          }

          // The cursor is a mark as well as a colour, so which row is current
          // does not depend on seeing the tint behind it.
          Text {
            id: marker
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: panel.theme.sp(8)
            text: row.current ? "›" : " "
            color: panel.theme.cursorText
            font.family: panel.theme.fontFamily
            font.pixelSize: panel.theme.fontSubtitle
          }

          Text {
            id: name
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: marker.right
            anchors.leftMargin: panel.theme.sp(6)
            anchors.right: excuse.left
            anchors.rightMargin: panel.theme.sp(12)
            elide: Text.ElideRight
            text: row.modelData.name
            color: row.current && row.ready ? panel.theme.cursorText : panel.theme.panelText
            opacity: !row.ready ? 0.4 : row.current ? 1.0 : 0.75
            font.family: panel.theme.fontFamily
            font.pixelSize: panel.theme.fontSubtitle
          }

          // Why it cannot run, where the eye is already going to look for how
          // to run it. A command that does nothing and says nothing teaches
          // the wrong thing about the command.
          Text {
            id: excuse
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: shortcut.left
            anchors.rightMargin: panel.theme.sp(10)
            visible: !row.ready
            text: panel.ctl.commandExcuse(row.modelData.needs)
            color: panel.theme.panelText
            opacity: 0.45
            font.family: panel.theme.fontFamily
            font.pixelSize: panel.theme.fontBody
          }

          Text {
            id: shortcut
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: panel.theme.sp(8)
            text: row.modelData.key
            color: panel.theme.accent
            opacity: row.ready ? 0.9 : 0.4
            font.family: panel.theme.fontFamily
            font.pixelSize: panel.theme.fontSubtitle
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              panel.ctl.paletteIndex = row.index
              panel.ctl.runPaletteChoice()
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: list.count === 0
          color: panel.theme.panelText
          opacity: 0.5
          font.family: panel.theme.fontFamily
          font.pixelSize: panel.theme.fontBody
          text: "nothing goes by that"
        }
      }

      ScrollHint {
        ctl: panel.ctl
        view: list
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
      }
    }
  }
}
