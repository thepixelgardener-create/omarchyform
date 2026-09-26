pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store

// The board browser: a shell-like walk through the boards directory.
// j/k to move, l or Enter to descend or open, h to go up, / to search the
// whole tree, a/A to make a board or a folder, r to rename, x to delete.
FocusScope {
  id: browser

  required property var ctl

  readonly property var rows: browser.ctl.browserRows
  readonly property bool searching: browser.ctl.browserSearching
  readonly property bool prompting: browser.ctl.browserPrompt !== ""

  // The path line, in the shape a shell would print it.
  readonly property string here: browser.ctl.browserTrash
    ? "~/trash/   " + browser.rows.length + (browser.rows.length === 1 ? " item" : " items")
    : "~/boards/" + (browser.ctl.browserDir ? browser.ctl.browserDir + "/" : "")

  visible: browser.ctl.browserVisible
  enabled: visible
  focus: browser.ctl.browserVisible
  onVisibleChanged: if (visible) Qt.callLater(function () { browser.forceActiveFocus() })

  anchors.fill: parent

  // Dim the board behind without hiding it entirely.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(browser.ctl.canvasBackground.r, browser.ctl.canvasBackground.g,
                   browser.ctl.canvasBackground.b, 0.86)
  }

  MouseArea {
    anchors.fill: parent
    onClicked: browser.ctl.closeBrowser()
  }

  Rectangle {
    id: panel
    objectName: "browser-panel"
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.max(browser.ctl.sp(16), (parent.height - browserFooter.height - browser.ctl.sp(32) - height) / 2)
    width: Math.min(parent.width - browser.ctl.sp(80), browser.ctl.sp(720))
    height: Math.max(0, Math.min(parent.height - browserFooter.height - browser.ctl.sp(48), browser.ctl.sp(560)))
    color: browser.ctl.canvasBackground
    border.width: browser.ctl.borderWidth
    border.color: Qt.rgba(browser.ctl.foreground.r, browser.ctl.foreground.g,
                          browser.ctl.foreground.b, 0.35)
    radius: browser.ctl.cornerRadius

    // Swallow clicks so they do not reach the dismiss layer behind.
    MouseArea { anchors.fill: parent }

    Column {
      anchors.fill: parent
      anchors.margins: browser.ctl.sp(16)
      spacing: browser.ctl.sp(10)

      Text {
        width: parent.width
        elide: Text.ElideMiddle
        color: browser.ctl.foreground
        font.family: browser.ctl.fontFamily
        font.pixelSize: browser.ctl.fontSubtitle
        text: browser.ctl.trashIndexError !== "" ? browser.ctl.trashIndexError
          : browser.ctl.browserMessage !== ""
          ? browser.ctl.browserMessage
          : browser.prompting
            ? browser.ctl.browserPrompt + " " + browser.ctl.browserInput + "▏"
            : browser.searching
              ? "/" + browser.ctl.browserQuery + "▏"
              : browser.here
      }

      Rectangle {
        width: parent.width
        height: browser.ctl.borderWidth
        color: Qt.rgba(browser.ctl.foreground.r, browser.ctl.foreground.g,
                       browser.ctl.foreground.b, 0.25)
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
          anchors.rightMargin: browser.ctl.sp(10)
          clip: true
          model: browser.rows
          currentIndex: browser.ctl.browserIndex
          highlightMoveDuration: 0
          // Keep the cursor in view when it walks off the end of the list.
          onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            required property var modelData
            required property int index

            width: list.width
            height: label.implicitHeight + browser.ctl.sp(8)

            readonly property bool current: index === browser.ctl.browserIndex

            Rectangle {
              anchors.fill: parent
              visible: parent.current
              color: Qt.rgba(browser.ctl.accent.r, browser.ctl.accent.g, browser.ctl.accent.b, 0.18)
            }

            Text {
              id: label
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: browser.ctl.sp(8)
              anchors.rightMargin: browser.ctl.sp(8)
              elide: Text.ElideMiddle
              color: browser.ctl.foreground
              opacity: parent.current ? 1.0 : 0.75
              font.family: browser.ctl.fontFamily
              font.pixelSize: browser.ctl.fontSubtitle
              // A folder wears a trailing slash; the open board is marked.
              // In the trash an entry carries where it came from, since that is
              // what restoring it will put back.
              text: browser.ctl.browserTrash
                ? Store.baseName(parent.modelData.path).replace(/\.json$/, "")
                  + (parent.modelData.dir ? "/" : "")
                  + (Store.parentOf(parent.modelData.path)
                     ? "   from " + Store.parentOf(parent.modelData.path) + "/" : "")
                : (parent.modelData.dir ? Store.displayName(parent.modelData) + "/"
                                        : Store.displayName(parent.modelData))
                    + (browser.searching && Store.parentOf(parent.modelData.path)
                       ? "   " + Store.parentOf(parent.modelData.path) + "/" : "")
                    + (!browser.ctl.browserTrash && parent.modelData.path === browser.ctl.currentBoard
                       ? "   ·open" : "")
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                browser.ctl.browserIndex = parent.index
                browser.ctl.browserEnter()
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: list.count === 0
            color: browser.ctl.foreground
            opacity: 0.5
            font.family: browser.ctl.fontFamily
            font.pixelSize: browser.ctl.fontBody
            textFormat: Text.StyledText
            text: browser.ctl.browserTrash ? "the trash is empty"
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
    anchors.leftMargin: browser.ctl.sp(16)
    anchors.rightMargin: browser.ctl.sp(16)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.Wrap
    anchors.bottom: parent.bottom
    anchors.bottomMargin: browser.ctl.sp(16)
    color: browser.ctl.foreground
    opacity: 0.55
    font.family: browser.ctl.fontFamily
    font.pixelSize: browser.ctl.fontBody
    textFormat: Text.StyledText
    text: Store.hintLine(browser.prompting ? Store.PROMPT_HINTS
                         : browser.ctl.browserTrash ? Store.TRASH_HINTS : Store.BROWSER_HINTS,
                         browser.ctl.accentMarkup, "  ·  ")
  }

  Keys.onPressed: function (event) {
    browser.ctl.browserKey(event)
  }
}
