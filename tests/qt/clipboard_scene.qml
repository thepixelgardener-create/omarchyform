import QtQuick
import "../.."

// Every text field the board has, opened in turn, in one pane and in two,
// while tests/qt/clipboard_watch.cpp changes the clipboard and counts requests
// for what it holds. Nothing here pastes, so any read is one Qt made for a
// field on its own, and the test requires there are none.
Item {
  id: scene
  width: 800
  height: 800

  QtObject {
    id: ws
    readonly property var theme: left.theme
    property string layout: "single"
    readonly property bool split: ws.layout !== "single"
    property real splitRatio: 0.5
    readonly property var paneSlots: [left, right]
    property var panes: [left, right]
    property var activePane: left
    property bool squeezed: false
    function setSplitRatio(ratio) { ws.splitRatio = ratio }
    function evenSplit() { ws.splitRatio = 0.5 }
    function writeState() {}
  }

  PaneStub { id: left; active: ws.activePane === left; split: ws.split }
  PaneStub { id: right; active: ws.activePane === right; split: ws.split }

  BoardSplit {
    workspace: ws
    width: scene.width
    height: scene.height
  }

  Component.onCompleted: {
    for (const pane of [left, right])
      pane.items.append({ iid: 1, kind: "note", ix: 40, iy: 160, iw: 220, ih: 140, itint: "foreground",
                          itexture: "plain", itext: "a note", ipinned: false, isrc: "" })
  }

  function closeAll() {
    for (const pane of [left, right]) {
      pane.finding = false
      pane.paletteVisible = false
      pane.library.searching = false
      pane.library.promptLabel = ""
      pane.library.showing = false
      pane.editIndex = -1
    }
  }

  // Opens one thing and says what it is; an empty answer ends the run.
  function prepare(step) {
    scene.closeAll()
    if (step === 0) { ws.layout = "single"; ws.activePane = left; return "one pane, nothing open" }
    if (step === 1) { left.finding = true; return "find" }
    if (step === 2) { left.paletteVisible = true; return "command list" }
    if (step === 3) {
      left.library.showing = true
      left.library.searching = true
      return "board browser, searching"
    }
    if (step === 4) {
      left.library.showing = true
      left.library.input = "notes"
      left.library.promptLabel = "board name:"
      return "board browser, naming a board"
    }
    if (step === 5) {
      left.selectedIndex = 0
      left.editIndex = 0
      return "a note being typed in"
    }
    if (step === 6) {
      ws.layout = "side-by-side"
      ws.activePane = right
      right.finding = true
      left.paletteVisible = true
      return "two panes, find in one and the command list in the other"
    }
    return ""
  }
}
