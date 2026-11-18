pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store
import "kit/Ui" as O
import "kit/Theme" as Kit

// Every command by name. The keys are quick once they are in the hands and
// useless before that, and the header menu only ever held six of them — so a
// board you have not opened in a month was a list of letters to remember.
//
// Summoned with `:` and gone again on escape, so it costs no height when it is
// not being asked for: the same bargain the menu makes. It does not take the
// keyboard focus, because the board's own key handler owns this mode the way it
// owns finding — one place where what a keystroke means is decided.
//
// Drawn with the Omarchy UI kit, the way its SearchList is: the kit's card on
// the menu surface, a filter line over a rule, and its list rows under a
// keyboard cursor. Built from those parts rather than from SearchList itself,
// which owns the keys and types into a TextInput: here the board decides what
// a key means, and the line is a LineField, for the reasons that file gives.
//
// Deliberately not called `palette`: an Item has a `palette` property of its
// own, and inside a delegate Qt 6.4 resolves that name to it rather than to
// this id — every binding in the rows then reads off undefined. Qt 6.11
// resolves the id and says nothing, so it is a name that only breaks on the
// version CI runs. The same reason this file is not called Palette.qml.
Item {
  id: panel
  required property var ctl
  // The board behind it, which owns what a key means: the field hands back
  // the ones the panel uses rather than deciding them a second time.
  required property var board
  function sp(n) { return Kit.Style.space(n) }
  visible: panel.ctl.paletteVisible
  // A panel's padding off the window's edge, and no more: the kit's spacing
  // grows with its text, and at a large size in a narrow window a wider gap
  // would leave a sentence a word or two a line.
  width: Math.min(parent.width - Kit.Style.spacing.panelPadding, panel.sp(600))
  // How many rows there is room for, rather than how many there are. A list of
  // nine at a theme's large font is taller than a small window, and a panel
  // that runs off the bottom hides the very commands it exists to show.
  readonly property int room: Math.max(panel.rowHeight * 2, parent.height - y - Kit.Style.spacing.md)
  // The kit's panel padding, giving way only where the panel is cramped: at a
  // large size in a narrow window its padding alone took a sentence's room.
  readonly property real pad: Math.min(Kit.Style.spacing.panelPadding, Math.round(panel.width * 0.05))
  // Everything in the panel that is not a row: the padding above and below, the
  // two gaps the column leaves, the line you type into and the rule under it.
  // Measured off the parts themselves, because a number guessed here crops the
  // bottom row — which is what it did.
  readonly property int chrome: body.y * 2 + body.spacing * 2 + query.implicitHeight + rule.height
  readonly property int fits: Math.max(1, Math.floor((panel.room - panel.chrome) / panel.rowHeight))
  readonly property int visibleRows: Math.max(1, Math.min(panel.ctl.paletteMatches.length,
                                                          panel.ctl.paletteRows, panel.fits))
  // What an empty list says can be a sentence, and at a theme's large type in
  // a narrow panel a sentence is taller than a row: the list is then as tall
  // as what it says, up to the room there is.
  readonly property int emptyHeight: list.count === 0
    ? Math.min(Math.ceil(empty.implicitHeight) + panel.sp(16), Math.max(panel.rowHeight, panel.room - panel.chrome)) : 0
  readonly property int listHeight: Math.max(panel.rowHeight * panel.visibleRows, panel.emptyHeight)
  height: panel.chrome + panel.listHeight

  // The kit's card on the menu surface. Solid: the board's own text read
  // faintly through the rows when it was the canvas at 0.92.
  O.BorderSurface {
    objectName: "command-card"
    anchors.fill: parent
    color: Kit.Color.menu.background
    borderSpec: Kit.Border.surfaceSpec("menu", "border", Kit.Color.menu.border, Math.max(1, Kit.Style.space(2)))
    radius: Kit.Style.cornerRadius
  }
  // Swallow clicks so they do not reach the board underneath — every button,
  // so a middle drag on the panel does not pan the canvas behind it.
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  // A row is as tall as the kit's list row, measured off one rather than
  // guessed: the theme chooses the font, and a list sized from a number picked
  // here would crop its own rows the moment that font grew. The ruler carries
  // a key and an excuse, the tallest a row gets.
  O.ListRow {
    id: ruler
    visible: false
    width: list.width
    glyph: Store.FIT_GLYPH
    title: "Ag"
    trailing: Component { Row { KeyLabel { label: "ctrl+shift+s" } } }
  }
  readonly property int rowHeight: Math.ceil(ruler.implicitHeight)

  Column {
    id: body
    y: panel.pad
    x: panel.pad
    width: parent.width - panel.pad * 2
    spacing: Kit.Style.spacing.md

    // The line you type into, at the size the kit's search line is, with what
    // it is for written in it until something else is.
    Item {
      id: query
      width: parent.width
      implicitHeight: typed.implicitHeight
      height: query.implicitHeight
      // A query wider than the list scrolls in here.
      clip: true
      // Just after the caret rather than under it: both started at the left
      // edge, and the blinking caret sat over the first letter. Measured off
      // the caret itself, so it follows the font and any padding the field
      // is given.
      Text {
        textFormat: Text.PlainText
        objectName: "command-prompt"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        elide: Text.ElideRight
        anchors.leftMargin: typed.cursorRectangle.x + typed.cursorRectangle.width + panel.sp(4)
        visible: typed.text === ""
        text: panel.ctl.paletteGroup !== "" ? panel.ctl.t("%1 · backspace: back", Store.groupTitle(panel.ctl.paletteGroup, panel.ctl.tv))
          : panel.ctl.paletteScope === "selection" ? panel.ctl.t("Do something with it…") : panel.ctl.t("Run a command…")
        color: Kit.Color.textFaint
        font.family: Kit.Style.font.family
        font.pixelSize: Kit.Style.font.heading
      }
      // A real field: a query that only grew at the end could not be moved
      // through, selected in, pasted into, or composed in a language that
      // needs an input method — and the commands are found by typing.
      LineField {
        id: typed
        objectName: "command-query"
        anchors.verticalCenter: parent.verticalCenter
        color: Kit.Color.menu.text
        selectionColor: Kit.Color.accent
        selectedTextColor: Kit.Color.menu.background
        font.family: Kit.Style.font.family
        font.pixelSize: Kit.Style.font.heading
        Accessible.role: Accessible.EditableText
        Accessible.name: panel.ctl.t("Command to run")
        Accessible.description: panel.ctl.tn("%1 command matches", "%1 commands match", panel.ctl.paletteMatches.length)
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
        // Pasted text is read through the clipboard helper's limit rather than
        // by Qt, which reads all of it first: see BoardExchange.pasteInto.
        takesPaste: panel.ctl.paletteVisible
        onPasteRequested: panel.ctl.pasteInto(typed)
        // The panel decides what these mean; everything else is typing.
        onKeyPressed: function (event) { panel.board.paletteKey(event) }
      }
    }
    // The kit's rule under a search line: one pixel of track.
    Rectangle {
      id: rule
      width: parent.width
      height: 1
      color: Kit.Color.track
    }
    Item {
      width: parent.width
      height: panel.listHeight
      ListView {
        id: list
        anchors.fill: parent
        anchors.rightMargin: panel.sp(10)
        clip: true
        model: panel.ctl.paletteMatches
        currentIndex: panel.ctl.paletteIndex
        highlightMoveDuration: 0
        // Keep the cursor in view when the list is longer than the panel: the
        // rest are reached by typing, but walking to them has to work too.
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: O.ListRow {
          id: row
          required property var modelData
          required property int index
          width: list.width
          height: panel.rowHeight
          readonly property bool atCursor: row.index === panel.ctl.paletteIndex
          // Dimmed rather than hidden. A command that cannot run now is still
          // one this board has, and hiding it would teach that it does not
          // exist; the excuse beside it says what it is waiting for.
          readonly property bool ready: panel.ctl.commandReady(row.modelData.needs)
          readonly property string excuse: row.ready ? "" : panel.ctl.commandExcuse(row.modelData.needs)
          // The kit's keyboard cursor: one highlight, the row's fill and edge.
          hasCursor: row.atCursor
          // Dimmed by its colour and not by the kit's `disabled`, which would
          // take the click: a click on one still says why it cannot run.
          foreground: row.ready ? Kit.Color.menu.text : Kit.Color.textFaint
          glyph: Store.commandIcon(row.modelData)
          title: panel.ctl.tv(row.modelData.name)
          // A family's entry leads somewhere rather than doing something. The
          // others keep the slot empty, so every row's keys line up.
          trailingGlyph: row.modelData.opens ? "›" : " "
          // Why it cannot run, where the eye is already going to look for how
          // to run it; then the key, as key caps.
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
                visible: row.modelData.key !== ""
                label: row.modelData.key
                opacity: row.ready ? 1 : 0.5
              }
            }
          }
          // Named for anything reading the screen rather than looking at it:
          // what the command is, what it answers to, and why it cannot run.
          Accessible.role: Accessible.Button
          Accessible.name: panel.ctl.tv(row.modelData.name)
                           + (row.modelData.key === "" ? "" : ", " + row.modelData.key)
          Accessible.description: row.excuse
          Accessible.focused: row.atCursor
          Accessible.onPressAction: {
            panel.ctl.paletteIndex = row.index
            panel.ctl.runPaletteChoice()
          }
          onClicked: {
            panel.ctl.paletteIndex = row.index
            panel.ctl.runPaletteChoice()
          }
        }
        // Why the list is empty, as the kit's empty state says it. Held to the
        // list's width: one of the things it says is a sentence, and a narrow
        // panel is narrow.
        O.EmptyState {
          id: empty
          objectName: "command-empty"
          anchors.centerIn: parent
          width: parent.width - panel.sp(16)
          visible: list.count === 0
          title: panel.ctl.paletteEmpty
        }
      }
      ScrollHint {
        view: list
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
      }
    }
  }
}
