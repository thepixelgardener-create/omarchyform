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
    // Set by the surface through a Binding, which names it as a string.
    property bool squeezed: false
    property int writes: 0
    function setSplitRatio(ratio) { ws.splitRatio = Math.max(0.1, Math.min(0.9, ratio)) }
    function evenSplit() { ws.splitRatio = 0.5; ws.writes += 1 }
    function writeState() { ws.writes += 1 }
  }

  PaneStub {
    id: left
    active: ws.activePane === left
    split: ws.split
    onActivationsChanged: if (left.activations > 0) ws.activePane = left
  }
  PaneStub {
    id: right
    active: ws.activePane === right
    split: ws.split
    onActivationsChanged: if (right.activations > 0) ws.activePane = right
  }

  BoardSplit {
    id: surface
    workspace: ws
    width: test.width
    height: test.height
  }

  // The boards are the surface's siblings, so they are found from the test.
  function slot(index) { return findChild(test, "pane-slot-" + index) }

  function init() {
    surface.width = test.width
    surface.height = test.height
    ws.writes = 0
    ws.layout = "single"
    ws.splitRatio = 0.5
    left.activations = 0
    right.activations = 0
    ws.panes = [left, right]
    ws.activePane = left
    left.items.clear()
    right.items.clear()
    left.selectedIndex = -1
    right.selectedIndex = -1
  }

  function test_onePaneFillsTheSurface() {
    compare(slot(0).visible, true)
    compare(slot(1).visible, false, "the second pane's board is hidden while it is not shown")
    compare(slot(0).width, 800)
    compare(slot(0).height, 600)
    compare(findChild(surface, "split-divider").visible, false)
    compare(findChild(slot(0), "active-pane").visible, false, "no outline with one pane")
  }

  function test_sideBySideDividesTheWidth() {
    ws.layout = "side-by-side"
    compare(slot(1).visible, true)
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
    compare(slot(1).width, 399, "the board fills its pane")
    compare(slot(1).parent, surface.parent, "a sibling of the surface, at the depth one board always had")
  }

  // Tall enough for two panes of at least 320 each.
  function test_stackedDividesTheHeight() {
    surface.height = 1001
    ws.layout = "stacked"
    ws.splitRatio = 0.4
    compare(slot(0).width, 800)
    compare(slot(0).height, 400)
    compare(slot(1).y, 401)
    compare(slot(1).height, 600)
    // A ratio that would leave a pane too small to use is held to one that does.
    ws.splitRatio = 0.1
    compare(slot(0).height, 320)
  }

  // A layout change moves a board; it does not build it again, which on a
  // large board is the difference between a resize and a pause. The second
  // board is there from the start, hidden until it has a pane to show.
  function test_aBoardOutlivesLayoutChanges() {
    var first = slot(0)
    ws.layout = "side-by-side"
    compare(slot(0), first)
    ws.layout = "stacked"
    compare(slot(0), first)
    var second = slot(1)
    ws.panes = [right, left]
    compare(slot(0), first, "swapping the order moves both")
    compare(slot(1), second)
    compare(slot(1).x, 0, "the second pane is first now")
    ws.layout = "single"
    compare(slot(0).visible, false, "and alone, the pane that went first is the one shown")
    compare(slot(1).visible, true)
    compare(slot(1).width, 800)
  }

  function test_theActivePaneWearsTheAccent() {
    ws.layout = "side-by-side"
    compare(findChild(slot(0), "active-pane").visible, true)
    compare(findChild(slot(1), "active-pane").visible, false)
  }

  // A press on the other pane moves the keyboard there and still does what a
  // press there does: here, selecting the note under it.
  function test_aPressOnTheOtherPaneActivatesAndSelects() {
    ws.layout = "side-by-side"
    right.items.append({ iid: 1, kind: "note", ix: 100, iy: 200, iw: 160, ih: 120,
                         itint: "foreground", itext: "", ipinned: false, isrc: "" })
    waitForRendering(surface)
    mouseClick(slot(1), 180, 260, Qt.LeftButton)
    compare(right.activations, 1)
    compare(ws.activePane, right)
    compare(right.selectedIndex, 0, "the press carried on to the note")
    // Once active, it takes nothing: a second press is only a press.
    mouseClick(slot(1), 180, 260, Qt.LeftButton)
    compare(right.activations, 1)
    compare(left.activations, 0)
  }

  // Dragged, the line moves and the place is written down once, when it is let
  // go of. Neither pane is dragged smaller than it can be worked in.
  function test_theDividerDrags() {
    ws.layout = "side-by-side"
    var handle = findChild(surface, "split-handle")
    compare(handle.visible, true)
    mousePress(handle, 3, 300)
    mouseMove(handle, -47, 300)
    compare(ws.writes, 0, "not written on every pixel of the way")
    mouseRelease(handle, -47, 300)
    compare(ws.writes, 1)
    compare(slot(0).width, 350, "the first pane follows the pointer")
    // As far as the pointer goes, but no further than leaves the other 320.
    mousePress(handle, 3, 300)
    mouseMove(handle, 600, 300)
    mouseRelease(handle, 600, 300)
    compare(slot(1).width, 320)
    compare(slot(0).width, 800 - 1 - 320)
  }

  function test_aDoubleClickEvensItOut() {
    ws.layout = "side-by-side"
    ws.splitRatio = 0.3
    mouseDoubleClickSequence(findChild(surface, "split-handle"), 3, 300)
    compare(ws.splitRatio, 0.5)
    compare(slot(0).width, 400)
  }

  // Too narrow for two: the pane the keyboard is in has all of it, and `o`
  // changes which, until the room comes back.
  function test_aSmallWindowShowsTheActivePane() {
    ws.layout = "side-by-side"
    surface.width = 600
    compare(ws.squeezed, true)
    compare(slot(0).visible, true)
    compare(slot(1).visible, false)
    compare(slot(0).width, 600)
    compare(findChild(surface, "split-divider").visible, false)
    ws.activePane = right
    compare(slot(0).visible, false)
    compare(slot(1).visible, true)
    compare(slot(1).x, 0)
    compare(slot(1).width, 600)
    surface.width = 800
    compare(ws.squeezed, false)
    compare(slot(0).visible, true)
    compare(slot(1).x, 401)
    // Stacked, it is the height that has to fit.
    ws.layout = "stacked"
    surface.height = 500
    compare(ws.squeezed, true)
  }
}
