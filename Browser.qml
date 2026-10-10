pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store

// The board browser: a shell-like walk through the boards directory.
// j/k to move, l or Enter to descend or open, h to go up, / to search the
// whole tree, a/A to make a board or a folder, r to rename, x to delete.
FocusScope {
  id: browser

  required property var ctl
  // What it draws. The controller is here for the theme and the accent only.
  required property var library
  readonly property var theme: browser.ctl.theme

  readonly property var rows: browser.library.rows
  readonly property bool searching: browser.library.searching
  readonly property bool prompting: browser.library.promptLabel !== ""
  readonly property bool typing: browser.prompting || browser.searching

  // The path line, in the shape a shell would print it.
  readonly property string here: browser.library.inTrash
    ? "~/trash/   " + browser.rows.length + (browser.rows.length === 1 ? " item" : " items")
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
    color: browser.theme.panelScrim
  }

  // The dismiss layer, and it takes every button: the board's pan surface is
  // below this, and the canvas is not something to be dragged around behind
  // the browser covering it. Only a left click means "close".
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onClicked: function (mouse) { if (mouse.button === Qt.LeftButton) browser.library.hide() }
  }

  Surface {
    id: panel
    objectName: "browser-panel"
    theme: browser.theme
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.max(browser.theme.sp(16), (parent.height - browserFooter.height - browser.theme.sp(32) - height) / 2)
    width: Math.min(parent.width - browser.theme.sp(80), browser.theme.sp(720))
    height: Math.max(0, Math.min(parent.height - browserFooter.height - browser.theme.sp(48), browser.theme.sp(560)))

    // Swallow clicks so they do not reach the dismiss layer behind, whichever
    // button they are.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Column {
      anchors.fill: parent
      anchors.margins: browser.theme.sp(18)
      spacing: browser.theme.sp(10)

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
          color: browser.theme.panelText
          font.family: browser.theme.menuFontFamily
          font.pixelSize: browser.theme.fontHeading
          text: browser.library.trashIndexError !== "" ? browser.library.trashIndexError
            : browser.library.message !== "" ? browser.library.message
            : browser.here
        }

        Text {
          textFormat: Text.PlainText
          id: promptLabel
          visible: browser.typing
          text: browser.prompting ? browser.library.promptLabel + " " : "/"
          color: browser.theme.panelText
          font.family: browser.theme.menuFontFamily
          font.pixelSize: browser.theme.fontHeading
        }

        TextInput {
          id: typed
          objectName: "browser-field"
          visible: browser.typing
          enabled: browser.typing
          anchors.left: promptLabel.right
          anchors.right: parent.right
          clip: true
          color: browser.theme.panelText
          selectionColor: browser.theme.accent
          selectedTextColor: browser.theme.panelBackground
          selectByMouse: true
          font.family: browser.theme.menuFontFamily
          font.pixelSize: browser.theme.fontHeading
          Accessible.role: Accessible.EditableText
          Accessible.name: browser.prompting ? browser.library.promptLabel : "Search the boards"

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
          readonly property bool takesPaste: browser.typing && browser.shown
          readonly property int pasteLimit: typed.maximumLength
          readonly property bool pasteLines: false
          // The middle button pastes the primary selection, read the same way.
          MouseArea { objectName: "browser-field-middle"; anchors.fill: parent; acceptedButtons: Qt.MiddleButton }

          // The browser decides what these mean; everything else is typing, and
          // is left to the field — including the caret keys, the selection and
          // whatever an input method is in the middle of composing. Except a
          // paste, which goes through the clipboard helper's limit.
          Keys.onPressed: function (event) {
            if (event.matches(StandardKey.Paste)) { event.accepted = true; browser.ctl.pasteInto(typed); return }
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Up || event.key === Qt.Key_Down)
              browser.library.key(event)
          }
        }
      }

      Rectangle {
        width: parent.width
        height: browser.theme.borderWidth
        color: Qt.rgba(browser.theme.panelText.r, browser.theme.panelText.g,
                       browser.theme.panelText.b, 0.25)
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
          anchors.rightMargin: browser.theme.sp(10)
          clip: true
          model: browser.rows
          currentIndex: browser.library.index
          highlightMoveDuration: 0
          // Keep the cursor in view when it walks off the end of the list.
          onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            required property var modelData
            required property int index

            width: list.width
            // The shell's menu rows, as the command list's are.
            height: Math.max(browser.theme.sp(50), label.implicitHeight + browser.theme.sp(24))

            readonly property bool current: index === browser.library.index

            Accessible.role: Accessible.ListItem
            Accessible.name: label.text
            Accessible.focused: current

            // The shell's keyboard cursor, as its menu draws one.
            Surface {
              anchors.fill: parent
              visible: parent.current
              theme: browser.theme
              color: browser.theme.cursorFill
              spec: browser.theme.cursorBorder
            }

            // The cursor is a mark as well as a tint, so which row it is on
            // does not depend on seeing the tint.
            Text {
              textFormat: Text.PlainText
              id: cursor
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.leftMargin: browser.theme.sp(8)
              text: parent.current ? "›" : " "
              color: browser.theme.cursorText
              font.family: browser.theme.menuFontFamily
              font.pixelSize: browser.theme.fontHeading
            }

            Text {
              textFormat: Text.PlainText
              id: label
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: cursor.right
              anchors.right: parent.right
              anchors.leftMargin: browser.theme.sp(6)
              anchors.rightMargin: browser.theme.sp(8)
              elide: Text.ElideMiddle
              color: parent.current ? browser.theme.cursorText : browser.theme.panelText
              font.family: browser.theme.menuFontFamily
              font.pixelSize: browser.theme.fontHeading
              font.weight: Font.Medium
              // A folder wears a trailing slash; the open board is marked.
              // In the trash an entry carries where it came from, since that is
              // what restoring it will put back.
              text: browser.library.inTrash
                ? Store.baseName(parent.modelData.path).replace(/\.json$/, "")
                  + (parent.modelData.dir ? "/" : "")
                  + (Store.parentOf(parent.modelData.path)
                     ? "   from " + Store.parentOf(parent.modelData.path) + "/" : "")
                : (parent.modelData.dir ? Store.displayName(parent.modelData) + "/"
                                        : Store.displayName(parent.modelData))
                    + (browser.searching && Store.parentOf(parent.modelData.path)
                       ? "   " + Store.parentOf(parent.modelData.path) + "/" : "")
                    + (!browser.library.inTrash && parent.modelData.path === browser.library.currentBoard
                       ? "   ·open" : "")
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                browser.library.index = parent.index
                browser.library.enter()
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: list.count === 0
            color: browser.theme.panelText
            opacity: 0.5
            font.family: browser.theme.menuFontFamily
            font.pixelSize: browser.theme.fontBody
            textFormat: Text.StyledText
            text: browser.library.inTrash ? "the trash is empty"
              : browser.searching ? "nothing matches"
              : "empty — " + Store.hintLine(Store.EMPTY_HINTS, browser.ctl.accentMarkup)
          }
        }

        ScrollHint {
          ctl: browser.ctl
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
    anchors.leftMargin: browser.theme.sp(16)
    anchors.rightMargin: browser.theme.sp(16)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    anchors.bottom: parent.bottom
    anchors.bottomMargin: browser.theme.sp(16)
    color: browser.theme.foreground
    opacity: 0.55
    font.family: browser.theme.menuFontFamily
    font.pixelSize: browser.theme.fontBody
    textFormat: Text.StyledText
    text: Store.hintLine(browser.prompting ? Store.PROMPT_HINTS
                         : browser.library.inTrash ? Store.TRASH_HINTS : Store.BROWSER_HINTS,
                         browser.ctl.accentMarkup, "  ·  ")
  }

  Keys.onPressed: function (event) {
    browser.library.key(event)
  }
}
