import QtQuick
import "../.."

// Exercise the real board guard in both layouts and with either pane active.
// The native injector also verifies zero payload retrieval, before QML could
// inspect file names or apply size checks.
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
      return scene.on(slot(1), 100, 80)
    }
    if (step === 1) {
      ws.activePane = right
      return scene.on(slot(0), 50, 60)
    }
    if (step === 2) {
      ws.layout = "stacked"
      ws.activePane = left
      return scene.on(slot(1), 200, 40)
    }
    if (step === 3) {
      ws.activePane = right
      return scene.on(slot(1), 100, 80)
    }
    if (step === 4) {
      ws.layout = "single"
      ws.activePane = left
      return scene.on(slot(0), 100, 80)
    }
    return {}
  }

  function verdict() {
    if (left.dropped.length || right.dropped.length)
      return "external data reached an image import queue"
    return ""
  }
}
