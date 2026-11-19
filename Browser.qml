pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store
import "kit/Ui" as O
import "kit/Theme" as Kit

// The board browser: a shell-like walk through the boards directory.
// j/k to move, l or Enter to descend or open, h to go up, / to search the
// whole tree, a/A to make a board or a folder, r to rename, x to delete.
//
// Drawn with the Omarchy UI kit: its card on the menu surface over the menu's
// scrim, its list rows under the keyboard cursor, the open board marked as the
// kit marks the current one. The keys and the fields stay the browser's own.
FocusScope {
  id: browser

  required property var ctl
  // What it draws. The controller is here for the words and the accent only.
  required property var library
  function sp(n) { return Kit.Style.space(n) }

  readonly property var rows: browser.library.rows
  readonly property bool searching: browser.library.searching
  readonly property bool prompting: browser.library.promptLabel !== ""
  readonly property bool typing: browser.prompting || browser.searching

  // The path line, in the shape a shell would print it.
  readonly property string here: browser.library.inTrash
    ? "~/trash/   " + browser.ctl.tn("%1 item", "%1 items", browser.rows.length)
    : "~/boards/" + (browser.library.dir ? browser.library.dir + "/" : "")

  // Whether this one is the browser on screen. With two panes there are two
  // boards and one library, and it is drawn over the pane that opened it.
  property bool shown: browser.library.showing
  visible: browser.shown
  enabled: visible
  focus: browser.shown
  onVisibleChanged: if (visible) Qt.callLater(function () { browser.forceActiveFocus() })

  anchors.fill: parent

  // Dim the board behind without hiding it entirely, by as much as the shell
  // dims the desktop behind its own menu.
  Rectangle {
    anchors.fill: parent
    color: Kit.Color.menu.scrim
  }

  // The dismiss layer, and it takes every button: the board's pan surface is
  // below this, and the canvas is not something to be dragged around behind
  // the browser covering it. Only a left click means "close".
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onClicked: function (mouse) { if (mouse.button === Qt.LeftButton) browser.library.hide() }
  }

  O.BorderSurface {
    id: panel
    objectName: "browser-panel"
    color: Kit.Color.menu.background
    borderSpec: Kit.Border.surfaceSpec("menu", "border", Kit.Color.menu.border, Math.max(1, Kit.Style.space(2)))
    radius: Kit.Style.cornerRadius
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.max(Kit.Style.spacing.md, (parent.height - browserFooter.height - browser.sp(32) - height) / 2)
    width: Math.min(parent.width - Kit.Style.spacing.panelPadding * 2, browser.sp(720))
    height: Math.max(0, Math.min(parent.height - browserFooter.height - browser.sp(48), browser.sp(560)))
    // The kit's panel padding, giving way where the panel is cramped.
    readonly property real pad: Math.min(Kit.Style.spacing.panelPadding, Math.round(panel.width * 0.05))

    // Swallow clicks so they do not reach the dismiss layer behind, whichever
    // button they are.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Column {
      anchors.fill: parent
      anchors.margins: panel.pad
      spacing: Kit.Style.spacing.md

      // A name being typed, or a query, is a real text field: a drawn cursor
      // after a string that only ever grew at the end could not be moved
      // through, selected, pasted into, or composed in a language that needs an
      // input method. The controller still owns the value — it is what commits
      // the rename — and this is the thing the keyboard actually talks to.
      Item {
        width: parent.width
        height: Math.max(line.implicitHeight, typed.implicitHeight)

        Text {
          textFormat: Text.PlainText
          id: line
          width: parent.width
          visible: !browser.typing
          elide: Text.ElideMiddle
          color: Kit.Color.menu.text
          font.family: Kit.Style.font.family
          font.pixelSize: Kit.Style.font.heading
          text: browser.library.trashIndexError !== "" ? browser.library.trashIndexError
            : browser.library.message !== "" ? browser.library.message
            : browser.here
        }

        Text {
          textFormat: Text.PlainText
          id: promptLabel
          visible: browser.typing
          text: browser.prompting ? browser.library.promptLabel + " " : "/"
          color: Kit.Color.textDim
          font.family: Kit.Style.font.family
          font.pixelSize: Kit.Style.font.heading
        }

        // The field scrolls inside this once a name is wider than the panel.
        Item {
          visible: browser.typing
          anchors.left: promptLabel.right
          anchors.right: parent.right
          height: typed.implicitHeight
          clip: true

          LineField {
            id: typed
            objectName: "browser-field"
            enabled: browser.typing
            color: Kit.Color.menu.text
            selectionColor: Kit.Color.accent
            selectedTextColor: Kit.Color.menu.background
            font.family: Kit.Style.font.family
            font.pixelSize: Kit.Style.font.heading
            Accessible.role: Accessible.EditableText
            Accessible.name: browser.prompting ? browser.library.promptLabel : browser.ctl.t("Search the boards")

            // Which field this is standing in for. Renaming opens it with the
            // current name in it and everything selected, so one keystroke
            // replaces it and an arrow key edits it instead.
            readonly property string mode: browser.prompting ? "prompt " + browser.library.promptLabel
                                           : browser.searching ? "search" : ""
            // Deferred: opening a prompt sets the label and then the name, and
            // the second of those lands in this field on its own, cursor at the
            // end and nothing selected. Selecting after both have arrived is what
            // makes one keystroke replace the name rather than extend it.
            //
            // Only the browser on screen answers: the library is shared, and the
            // other pane's board has a browser too, hidden, that hears the same
            // change and would otherwise take the keyboard into a field no one
            // can see.
            onModeChanged: {
              if (!browser.shown) return
              if (typed.mode === "") { browser.forceActiveFocus(); return }
              Qt.callLater(function () {
                if (!browser.typing || !browser.shown) return
                typed.text = browser.prompting ? browser.library.input : browser.library.query
                typed.forceActiveFocus()
                typed.selectAll()
              })
            }

            onTextChanged: {
              if (browser.prompting) browser.library.input = typed.text
              else if (browser.searching && typed.text !== browser.library.query) {
                browser.library.query = typed.text
                browser.library.index = 0
              }
            }

            // And it follows a value set from anywhere else, so the field and the
            // controller cannot show different things. Both sides check before
            // writing, so neither can chase the other.
            readonly property string held: browser.prompting ? browser.library.input
                                           : browser.searching ? browser.library.query : typed.text
            onHeldChanged: if (typed.held !== typed.text) typed.text = typed.held

            // Pasted text is read through the clipboard helper's limit rather
            // than by Qt, which reads all of it first: see BoardExchange.pasteInto.
            takesPaste: browser.typing && browser.shown
            onPasteRequested: browser.ctl.pasteInto(typed)

            // The browser decides what these mean; everything else is typing, and
            // is left to the field — including the caret keys, the selection and
            // whatever an input method is in the middle of composing.
            onKeyPressed: function (event) {
              if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                  || event.key === Qt.Key_Up || event.key === Qt.Key_Down)
                browser.library.key(event)
            }
          }
        }
      }

      // The kit's rule under a search line: one pixel of track.
      Rectangle {
        width: parent.width
        height: 1
        color: Kit.Color.track
      }

      // The list, and the rule that says how much of it you are looking at.
      // The strip down the right is left out of the list whether or not it is
      // used: a name re-wrapping the moment the list outgrew the panel would
      // be a worse answer than a few pixels of air.
      Item {
        width: parent.width
        height: parent.height - y

        ListView {
          id: list
          anchors.fill: parent
          anchors.rightMargin: browser.sp(10)
          clip: true
          model: browser.rows
          currentIndex: browser.library.index
          highlightMoveDuration: 0
          // Keep the cursor in view when it walks off the end of the list.
          onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: O.ListRow {
            id: row
            required property var modelData
            required property int index

            width: list.width
            height: browser.rowHeight

            readonly property bool atCursor: index === browser.library.index
            readonly property string folder: Store.parentOf(row.modelData.path)
            // The kit's keyboard cursor, the one highlight; the board that is
            // open now is the kit's current row, as the connected network is.
            hasCursor: row.atCursor
            current: !browser.library.inTrash && row.modelData.path === browser.library.currentBoard
            glyph: row.modelData.dir ? Store.BROWSER_GLYPHS.folder : Store.BROWSER_GLYPHS.board
            // A folder wears a trailing slash. In the trash an entry carries
            // where it came from, since that is what restoring it puts back;
            // a search says where each one it found lives.
            title: browser.library.inTrash
              ? Store.baseName(row.modelData.path).replace(/\.json$/, "") + (row.modelData.dir ? "/" : "")
              : Store.displayName(row.modelData) + (row.modelData.dir ? "/" : "")
            value: browser.library.inTrash ? (row.folder ? browser.ctl.t("from %1", row.folder + "/") : "")
              : row.current ? browser.ctl.t("open now")
              : browser.searching && row.folder ? row.folder + "/" : ""
            trailingGlyph: row.modelData.dir && !browser.library.inTrash ? "›" : ""

            Accessible.role: Accessible.ListItem
            Accessible.name: row.title + (row.value !== "" ? ", " + row.value : "")
            Accessible.focused: row.atCursor

            onClicked: {
              browser.library.index = row.index
              browser.library.enter()
            }
          }

          // Why the list is empty, in the kit's empty-state voice; the keys in
          // it are the accent's, so it stays a line of markup.
          Text {
            anchors.centerIn: parent
            width: parent.width - browser.sp(16)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            visible: list.count === 0
            color: Kit.Color.textDim
            font.family: Kit.Style.font.family
            font.pixelSize: Kit.Style.font.body
            textFormat: Text.StyledText
            text: browser.library.inTrash ? Store.escapeMarkup(browser.ctl.t("the trash is empty"))
              : browser.searching ? Store.escapeMarkup(browser.ctl.t("nothing matches"))
              : Store.escapeMarkup(browser.ctl.t("empty")) + " — " + Store.hintLine(Store.EMPTY_HINTS, browser.ctl.accentMarkup, null, browser.ctl.tv)
          }
        }

        ScrollHint {
          view: list
          anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        }
      }
    }
  }

  Text {
    id: browserFooter
    objectName: "browser-footer"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Kit.Style.spacing.panelPadding
    anchors.rightMargin: Kit.Style.spacing.panelPadding
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Kit.Style.spacing.panelPadding
    color: Kit.Color.textDim
    font.family: Kit.Style.font.family
    font.pixelSize: Kit.Style.font.body
    textFormat: Text.StyledText
    text: Store.hintLine(browser.prompting ? Store.PROMPT_HINTS
                         : browser.library.inTrash ? Store.TRASH_HINTS : Store.BROWSER_HINTS,
                         browser.ctl.accentMarkup, "  ·  ", browser.ctl.tv)
  }

  // A row is as tall as the kit's list row, measured off one.
  O.ListRow {
    id: ruler
    visible: false
    glyph: Store.BROWSER_GLYPHS.folder
    title: "Ag"
    value: "Ag"
  }
  readonly property int rowHeight: Math.ceil(ruler.implicitHeight)

  Keys.onPressed: function (event) {
    browser.library.key(event)
  }
}
