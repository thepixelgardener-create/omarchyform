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
Rectangle {
  id: palette
  required property var ctl
  // The board behind it, which owns what a key means: the field hands back
  // the ones the panel uses rather than deciding them a second time.
  required property var board

  visible: palette.ctl.paletteVisible
  width: Math.min(parent.width - palette.ctl.sp(64), palette.ctl.sp(560))

  // How many rows there is room for, rather than how many there are. A list of
  // nine at a theme's large font is taller than a small window, and a panel
  // that runs off the bottom hides the very commands it exists to show.
  readonly property int room: Math.max(palette.rowHeight * 2, parent.height - y - palette.ctl.sp(24))
  // Everything in the panel that is not a row: the padding above and below, the
  // two gaps the column leaves, the line you type into and the rule under it.
  // Measured off the parts themselves, because a number guessed here crops the
  // bottom row — which is what it did.
  readonly property int chrome: body.y * 2 + body.spacing * 2 + query.implicitHeight + rule.height
  readonly property int fits: Math.max(1, Math.floor((palette.room - palette.chrome) / palette.rowHeight))
  readonly property int visibleRows: Math.max(1, Math.min(palette.ctl.paletteMatches.length,
                                                          palette.ctl.paletteRows, palette.fits))
  height: palette.chrome + palette.rowHeight * palette.visibleRows
  color: palette.ctl.canvasBackground
  border.width: palette.ctl.borderWidth
  border.color: Qt.rgba(palette.ctl.foreground.r, palette.ctl.foreground.g,
                        palette.ctl.foreground.b, 0.35)
  radius: palette.ctl.cornerRadius

  // Swallow clicks so they do not reach the board underneath.
  MouseArea { anchors.fill: parent }

  // A row is as tall as the text in it, measured rather than guessed: the theme
  // chooses the font, and a list sized from a number picked here would crop its
  // own rows the moment that font grew.
  Text {
    id: ruler
    visible: false
    text: "Ag"
    font.family: palette.ctl.fontFamily
    font.pixelSize: palette.ctl.fontSubtitle
  }
  readonly property int rowHeight: ruler.implicitHeight + palette.ctl.sp(8)

  Column {
    id: body
    y: palette.ctl.sp(16)
    x: palette.ctl.sp(16)
    width: parent.width - palette.ctl.sp(32)
    spacing: palette.ctl.sp(10)

    Row {
      width: parent.width
      spacing: 0

      Text {
        id: query
        text: "run: "
        color: palette.ctl.foreground
        font.family: palette.ctl.fontFamily
        font.pixelSize: palette.ctl.fontSubtitle
      }

      // A real field: a query that only grew at the end could not be moved
      // through, selected in, pasted into, or composed in a language that
      // needs an input method — and the commands are found by typing.
      TextInput {
        id: typed
        width: parent.width - query.width
        clip: true
        color: palette.ctl.foreground
        selectionColor: palette.ctl.accent
        selectedTextColor: palette.ctl.canvasBackground
        selectByMouse: true
        font.family: palette.ctl.fontFamily
        font.pixelSize: palette.ctl.fontSubtitle

        Accessible.role: Accessible.EditableText
        Accessible.name: "Command to run"
        Accessible.description: palette.ctl.paletteMatches.length + " commands match"

        onTextChanged: palette.ctl.setPaletteQuery(typed.text)
        readonly property string held: palette.ctl.paletteQuery
        onHeldChanged: if (typed.held !== typed.text) typed.text = typed.held

        // Deferred for the same reason the board's find field defers: whatever
        // else is set as the palette opens lands here on its own, and taking
        // the keyboard has to be the last thing that happens.
        readonly property bool wanted: palette.ctl.paletteVisible
        onWantedChanged: {
          if (!wanted) { palette.ctl.focusKeys(); return }
          Qt.callLater(function () {
            if (!palette.ctl.paletteVisible) return
            typed.text = palette.ctl.paletteQuery
            typed.forceActiveFocus()
            typed.selectAll()
          })
        }

        // The panel decides what these mean; everything else is typing.
        Keys.onPressed: function (event) { palette.board.paletteKey(event) }
      }
    }

    Rectangle {
      id: rule
      width: parent.width
      height: palette.ctl.borderWidth
      color: Qt.rgba(palette.ctl.foreground.r, palette.ctl.foreground.g,
                     palette.ctl.foreground.b, 0.25)
    }

    Item {
      width: parent.width
      height: palette.rowHeight * palette.visibleRows

      ListView {
        id: list
        anchors.fill: parent
        anchors.rightMargin: palette.ctl.sp(10)
        clip: true
        model: palette.ctl.paletteMatches
        currentIndex: palette.ctl.paletteIndex
        highlightMoveDuration: 0
        // Keep the cursor in view when the list is longer than the panel: the
        // rest are reached by typing, but walking to them has to work too.
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
          id: row
          required property var modelData
          required property int index
          width: list.width
          height: palette.rowHeight

          readonly property bool current: row.index === palette.ctl.paletteIndex

          // Named for anything reading the screen rather than looking at it:
          // what the command is, what it answers to, and why it cannot run.
          Accessible.role: Accessible.Button
          Accessible.name: row.modelData.name
                           + (row.modelData.key === "" ? "" : ", " + row.modelData.key)
          Accessible.description: row.ready ? "" : palette.ctl.commandExcuse(row.modelData.needs)
          Accessible.focused: row.current
          Accessible.onPressAction: {
            palette.ctl.paletteIndex = row.index
            palette.ctl.runPaletteChoice()
          }
          // Dimmed rather than hidden. A command that cannot run now is still
          // one this board has, and hiding it would teach that it does not
          // exist; the line below says what it is waiting for.
          readonly property bool ready: palette.ctl.commandReady(row.modelData.needs)

          Rectangle {
            anchors.fill: parent
            visible: row.current
            color: Qt.rgba(palette.ctl.accent.r, palette.ctl.accent.g, palette.ctl.accent.b, 0.18)
          }

          // The cursor is a mark as well as a colour, so which row is current
          // does not depend on seeing the tint behind it.
          Text {
            id: marker
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: palette.ctl.sp(8)
            text: row.current ? "›" : " "
            color: palette.ctl.accent
            font.family: palette.ctl.fontFamily
            font.pixelSize: palette.ctl.fontSubtitle
          }

          Text {
            id: name
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: marker.right
            anchors.leftMargin: palette.ctl.sp(6)
            anchors.right: excuse.left
            anchors.rightMargin: palette.ctl.sp(12)
            elide: Text.ElideRight
            text: row.modelData.name
            color: palette.ctl.foreground
            opacity: !row.ready ? 0.4 : row.current ? 1.0 : 0.75
            font.family: palette.ctl.fontFamily
            font.pixelSize: palette.ctl.fontSubtitle
          }

          // Why it cannot run, where the eye is already going to look for how
          // to run it. A command that does nothing and says nothing teaches
          // the wrong thing about the command.
          Text {
            id: excuse
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: shortcut.left
            anchors.rightMargin: palette.ctl.sp(10)
            visible: !row.ready
            text: palette.ctl.commandExcuse(row.modelData.needs)
            color: palette.ctl.foreground
            opacity: 0.45
            font.family: palette.ctl.fontFamily
            font.pixelSize: palette.ctl.fontBody
          }

          Text {
            id: shortcut
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: palette.ctl.sp(8)
            text: row.modelData.key
            color: palette.ctl.accent
            opacity: row.ready ? 0.9 : 0.4
            font.family: palette.ctl.fontFamily
            font.pixelSize: palette.ctl.fontSubtitle
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              palette.ctl.paletteIndex = row.index
              palette.ctl.runPaletteChoice()
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: list.count === 0
          color: palette.ctl.foreground
          opacity: 0.5
          font.family: palette.ctl.fontFamily
          font.pixelSize: palette.ctl.fontBody
          text: "nothing goes by that"
        }
      }

      ScrollHint {
        ctl: palette.ctl
        view: list
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
      }
    }
  }
}
