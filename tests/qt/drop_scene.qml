import QtQuick
import "../.."

// The two-pane surface tst_split builds, for tests/drop.js to let files go on
// as the platform does. Each step puts the keyboard in one pane and returns a
// point on the other pane's board; the board's own DropArea has to hand the
// file to the pane it belongs to, at that pane's world point.
Item {
  id: scene
  // Room for two panes either way: each needs 320.
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

  // The boards are the surface's siblings.
  function slot(index) {
    for (var i = 0; i < scene.children.length; i++)
      if (scene.children[i].objectName === "pane-slot-" + index) return scene.children[i]
    return null
  }

  // What each step should have delivered: to which pane, where.
  property var expected: []
  function on(board, x, y) {
    var at = board.mapToItem(scene, x, y)
    return { x: Math.round(at.x), y: Math.round(at.y) }
  }

  function prepare(step) {
    if (step === 0) {
      ws.layout = "side-by-side"
      right.camX = -400
      right.camY = 120
      right.zoom = 2
      ws.activePane = left
      scene.expected.push({ pane: right, x: (100 + 400) / 2, y: (80 - 120) / 2 })
      return scene.on(slot(1), 100, 80)
    }
    if (step === 1) {
      ws.activePane = right
      scene.expected.push({ pane: left, x: 50, y: 60 })
      return scene.on(slot(0), 50, 60)
    }
    if (step === 2) {
      ws.layout = "stacked"
      ws.activePane = left
      scene.expected.push({ pane: right, x: (200 + 400) / 2, y: (40 - 120) / 2 })
      return scene.on(slot(1), 200, 40)
    }
    return {}
  }

  function verdict() {
    var got = { left: left.dropped.slice(), right: right.dropped.slice() }
    for (var i = 0; i < scene.expected.length; i++) {
      var want = scene.expected[i]
      var name = want.pane === left ? "left" : "right"
      var drop = got[name].shift()
      if (!drop) return "drop " + i + " never reached the " + name + " pane: " + JSON.stringify({ left: left.dropped, right: right.dropped })
      if (String(drop.urls[0]).indexOf("file:///") !== 0) return "drop " + i + " carried " + drop.urls
      if (Math.abs(drop.x - want.x) > 0.5 || Math.abs(drop.y - want.y) > 0.5)
        return "drop " + i + " landed at " + drop.x + "," + drop.y + ", not " + want.x + "," + want.y
    }
    if (got.left.length + got.right.length > 0)
      return "a drop went to a pane it was not let go on: " + JSON.stringify(got)
    return ""
  }
}
