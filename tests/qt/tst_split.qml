import QtQuick
import QtTest
import "../.."

// Two boards in one surface. BoardSplit decides where each pane's board goes
// and keeps each one built for as long as its pane is on screen; the board
// decides that a press on the pane the keyboard is not in moves the keyboard
// there and still lands on what was pressed. Two stand-in panes, and a
// workspace shaped like the parts of Omarchyform.qml the split reads.
TestCase {
  id: test
  name: "SplitView"
  when: windowShown
  visible: true
  width: 800
  height: 600

  QtObject {
    id: ws
    readonly property var theme: left.theme
    property string layout: "single"
    readonly property bool split: ws.layout !== "single"
    property real splitRatio: 0.5
    readonly property var paneSlots: [left, right]
    property var panes: [left, right]
    property var activePane: left
  }

  PaneStub {
    id: left
    active: ws.activePane === left
    split: ws.split
    onActivationsChanged: ws.activePane = left
  }
  PaneStub {
    id: right
    active: ws.activePane === right
    split: ws.split
    onActivationsChanged: ws.activePane = right
  }

  BoardSplit {
    id: surface
    workspace: ws
    width: test.width
    height: test.height
  }

  function slot(index) { return findChild(surface, "pane-slot-" + index) }

  function init() {
    ws.layout = "single"
    ws.splitRatio = 0.5
    ws.panes = [left, right]
    ws.activePane = left
    left.activations = 0
    right.activations = 0
    left.items.clear()
    right.items.clear()
    left.selectedIndex = -1
    right.selectedIndex = -1
  }

  function test_onePaneFillsTheSurface() {
    compare(slot(0).active, true)
    compare(slot(1).active, false, "the second pane builds no board while it is not shown")
    compare(slot(0).width, 800)
    compare(slot(0).height, 600)
    compare(findChild(surface, "split-divider").visible, false)
    compare(findChild(slot(0).item, "active-pane").visible, false, "no outline with one pane")
  }

  function test_sideBySideDividesTheWidth() {
    ws.layout = "side-by-side"
    compare(slot(1).active, true)
    // 799 pixels either side of a one-pixel line, the first rounded to whole.
    compare(slot(0).x, 0)
    compare(slot(0).width, 400)
    compare(slot(1).x, 401)
    compare(slot(1).width, 399)
    compare(slot(1).height, 600)
    var line = findChild(surface, "split-divider")
    compare(line.visible, true)
    compare(line.x, 400)
    compare(line.width, 1)
    compare(slot(1).item.width, 399, "the board fills its pane")
  }

  function test_stackedDividesTheHeight() {
    ws.layout = "stacked"
    ws.splitRatio = 0.25
    compare(slot(0).width, 800)
    compare(slot(0).height, Math.round(599 * 0.25))
    compare(slot(1).y, Math.round(599 * 0.25) + 1)
    compare(slot(1).height, 600 - Math.round(599 * 0.25) - 1)
  }

  // A layout change moves a board; it does not build it again, which on a
  // large board is the difference between a resize and a pause.
  function test_aBoardOutlivesLayoutChanges() {
    var first = slot(0).item
    ws.layout = "side-by-side"
    compare(slot(0).item, first)
    ws.layout = "stacked"
    compare(slot(0).item, first)
    var second = slot(1).item
    ws.panes = [right, left]
    compare(slot(0).item, first, "swapping the order moves both")
    compare(slot(1).item, second)
    compare(slot(1).x, 0, "the second pane is first now")
    ws.layout = "single"
    compare(slot(0).active, false, "and alone, the pane that went first is the one shown")
    compare(slot(1).active, true)
    compare(slot(1).width, 800)
  }

  function test_theActivePaneWearsTheAccent() {
    ws.layout = "side-by-side"
    compare(findChild(slot(0).item, "active-pane").visible, true)
    compare(findChild(slot(1).item, "active-pane").visible, false)
  }

  // A press on the other pane moves the keyboard there and still does what a
  // press there does: here, selecting the note under it.
  function test_aPressOnTheOtherPaneActivatesAndSelects() {
    ws.layout = "side-by-side"
    right.items.append({ iid: 1, kind: "note", ix: 100, iy: 200, iw: 160, ih: 120,
                         itint: "foreground", itext: "", ipinned: false, isrc: "" })
    waitForRendering(surface)
    mouseClick(slot(1).item, 180, 260, Qt.LeftButton)
    compare(right.activations, 1)
    compare(ws.activePane, right)
    compare(right.selectedIndex, 0, "the press carried on to the note")
    // Once active, it takes nothing: a second press is only a press.
    mouseClick(slot(1).item, 180, 260, Qt.LeftButton)
    compare(right.activations, 1)
    compare(left.activations, 0)
  }
}
