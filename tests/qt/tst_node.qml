import QtQuick
import QtTest
import "../.."

TestCase {
  id: test
  name: "NodeInteraction"
  when: windowShown
  visible: true
  width: 640
  height: 480
  Item {
    id: ctl
    property alias items: model
    property bool canEdit: true
    property bool showPinned: false
    property int selectedIndex: -1
    property int editIndex: -1
    property int linkingFrom: -1
    property int cornerRadius: 0
    property int borderWidth: 1
    property int minItemSize: 60
    property color foreground: "white"
    property color accent: "cyan"
    property color itemFill: "#222222"
    property string fontFamily: "monospace"
    property int fontSubtitle: 13
    property int fontBody: 11
    property color muted: "#999999"
    property color canvasBackground: "#111111"
    property int undoCount: 0
    property int saveCount: 0
    property int flushCount: 0
    function isMarked(id) { return false }
    // The camera a node culls itself against. Off by default: these tests are
    // about what one node draws, and a node outside the viewport draws itself
    // plain on purpose, which would make every appearance check here pass for
    // the wrong reason. The culling itself is checked in its own test below.
    property bool culling: false
    property real zoom: 1
    property real camX: 0
    property real camY: 0
    property real viewW: 800
    property real viewH: 600
    property bool findDimming: false
    property string findNeedle: ""
    function matchesFind(text) {
      return findDimming && findNeedle !== "" && text.toLowerCase().indexOf(findNeedle) >= 0
    }
    // A two-pixel red PNG, inline: a real decode with no file to create, clean
    // up, or have the runner refuse to read.
    readonly property string redPixels: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg=="
    function imagePath(name) {
      if (name === "") return ""
      return name === "gone.png" ? "file:///nonexistent/gone.png" : redPixels
    }
    function newBoard() {}
    function sp(n) { return n }
    function tintFill(tint, strong) { return itemFill }
    function tintBorder(tint, strong) { return "#999999" }
    function repaintLinks() {}
    function pointerSelect(index, additive) { selectedIndex = index; editIndex = -1 }
    function moveTargets(dx, dy) { model.setProperty(0, "ix", model.get(0).ix + dx); model.setProperty(0, "iy", model.get(0).iy + dy) }
    function resizeTargets(dx, dy) { model.setProperty(0, "iw", Math.max(60, model.get(0).iw + dx)); model.setProperty(0, "ih", Math.max(60, model.get(0).ih + dy)) }
    function pushUndo() { undoCount++ }
    function save() { saveCount++ }
    function scheduleSave() { saveCount++ }
    function flushSave() { flushCount++ }
    function stopEditing() { editIndex = -1 }
    function removeItem(index) { model.remove(index) }
    ListModel {
      id: model
      ListElement { ix: 100; iy: 100; iw: 180; ih: 140; itext: "" }
    }
  }
  property int backgroundDoubleClicks: 0
  MouseArea {
    anchors.fill: parent
    onDoubleClicked: test.backgroundDoubleClicks++
  }
  Node {
    id: subject
    ctl: ctl
    index: 0
    iid: 1
    ipinned: false
    kind: "note"
    ix: model.get(0).ix
    iy: model.get(0).iy
    iw: model.get(0).iw
    ih: model.get(0).ih
    itint: "foreground"
    itext: model.get(0).itext
    isrc: ""
  }
  function init() {
    backgroundDoubleClicks = 0
    subject.kind = "note"
    subject.isrc = ""
    subject.ipinned = false
    ctl.showPinned = false
    ctl.findDimming = false
    ctl.findNeedle = ""
    ctl.culling = false
    ctl.camX = 0
    ctl.camY = 0
    ctl.zoom = 1
    ctl.itemFill = "#222222"
    ctl.canEdit = true
    ctl.selectedIndex = -1
    ctl.editIndex = -1
    ctl.undoCount = 0
    ctl.saveCount = 0
    ctl.flushCount = 0
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:""})
  }
  function test_drag() {
    mousePress(test, 140, 140, Qt.LeftButton)
    mouseMove(test, 200, 160, -1, Qt.LeftButton)
    mouseRelease(test, 200, 160, Qt.LeftButton)
    compare(model.get(0).ix, 160)
    compare(model.get(0).iy, 120)
    compare(ctl.undoCount, 1)
    compare(ctl.saveCount, 1)
  }
  function test_resize() {
    mousePress(test, 272, 232, Qt.LeftButton)
    mouseMove(test, 312, 252, -1, Qt.LeftButton)
    mouseRelease(test, 312, 252, Qt.LeftButton)
    compare(model.get(0).iw, 220)
    compare(model.get(0).ih, 160)
    compare(ctl.undoCount, 1)
    compare(ctl.saveCount, 1)
  }
  function test_pinnedPointer() {
    subject.ipinned = true
    mousePress(test, 140, 140, Qt.LeftButton)
    mouseMove(test, 200, 160, -1, Qt.LeftButton)
    mouseRelease(test, 200, 160, Qt.LeftButton)
    compare(ctl.selectedIndex, -1)
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(backgroundDoubleClicks, 1)
    ctl.showPinned = true
    mouseClick(test, 140, 140, Qt.LeftButton)
    compare(ctl.selectedIndex, 0)
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, -1)
    compare(model.get(0).ix, 100)
    compare(ctl.undoCount, 0)
  }
  function test_readOnly() {
    ctl.canEdit = false
    mousePress(test, 140, 140, Qt.LeftButton)
    mouseMove(test, 200, 160, -1, Qt.LeftButton)
    mouseRelease(test, 200, 160, Qt.LeftButton)
    compare(model.get(0).ix, 100)
    compare(model.get(0).iy, 100)
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, -1)
    compare(ctl.undoCount, 0)
  }
  function test_image() {
    subject.kind = "image"
    subject.isrc = "ok.png"
    verify(waitForRendering(subject))
    // Inside the frame, and actually decoded rather than left as a tinted box.
    tryVerify(function () { return grabImage(subject).pixel(90, 70) === Qt.rgba(1, 0, 0, 1) })
  }

  function test_missingImage() {
    subject.kind = "image"
    subject.isrc = "gone.png"
    verify(waitForRendering(subject))
    // The frame stays, so a board that lost its pictures still reads as a
    // board rather than as a hole.
    tryVerify(function () { return grabImage(subject).pixel(90, 70) === Qt.rgba(34/255, 34/255, 34/255, 1) })
  }

  function test_findMatchStandsOut() {
    ctl.findDimming = true
    ctl.findNeedle = "keep"
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:"keep this one"})
    verify(waitForRendering(subject))
    compare(subject.opacity, 1, "a match stays at full strength")
    verify(subject.foundMatch)

    // What does not match recedes rather than disappearing, so the shape of
    // the board is still readable while searching.
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:"something else"})
    verify(waitForRendering(subject))
    verify(!subject.foundMatch)
    verify(subject.opacity < 0.5 && subject.opacity > 0)

    ctl.findDimming = false
    verify(waitForRendering(subject))
    compare(subject.opacity, 1, "and everything comes back when the search ends")
  }

  // An item off the edge of the screen draws itself plain, whatever the board
  // says about it: it is not there to be looked at, and asking every item on a
  // large board to restyle itself for a mark nobody can see was most of what
  // marking one cost. What it must not do is lie once it comes back into view.
  function test_offScreenItemsStayPlain() {
    ctl.culling = true
    ctl.findDimming = true
    ctl.findNeedle = "keep"
    model.set(0, {ix: 40, iy: 40, iw: 180, ih: 140, itext: "keep this one"})
    verify(waitForRendering(subject))
    verify(subject.onScreen, "an item inside the viewport is live")
    verify(subject.foundMatch, "and answers the search")

    // Well past the right-hand edge of an 800-wide viewport.
    model.set(0, {ix: 4000, iy: 40, iw: 180, ih: 140, itext: "keep this one"})
    verify(!subject.onScreen, "an item beyond the viewport is not live")
    verify(!subject.foundMatch, "and does not restyle itself for a search")
    compare(subject.opacity, 1, "nor dim itself where nobody can see it")

    // The camera catches up with it, and it tells the truth again.
    ctl.camX = -3900
    verify(waitForRendering(subject))
    verify(subject.onScreen, "panning to it brings it back")
    verify(subject.foundMatch, "and the match reads as a match again")

    ctl.camX = 0
    ctl.findDimming = false
    ctl.culling = false
    model.set(0, {ix: 100, iy: 100, iw: 180, ih: 140, itext: ""})
    verify(waitForRendering(subject))
  }

  // The edges of the rule, where an off-by-one would show as an item going
  // plain while half of it is still on the screen.
  //
  // Asserted on the property rather than after waitForRendering: culling an
  // item that was already drawing plain changes nothing on screen, so there is
  // no frame to wait for and waiting for one fails.
  function test_cullingEdges() {
    ctl.culling = true

    // Hanging off the right edge by all but a sliver: still live.
    model.set(0, {ix: ctl.viewW - 4, iy: 40, iw: 180, ih: 140, itext: ""})
    verify(subject.onScreen, "an item overlapping the right edge is live")

    // Its trailing edge exactly on the left edge: past it, and out.
    model.set(0, {ix: -180, iy: 40, iw: 180, ih: 140, itext: ""})
    verify(!subject.onScreen, "an item flush against the left edge is out")

    // Zoom counts: the same world position is off screen zoomed in.
    model.set(0, {ix: 700, iy: 40, iw: 180, ih: 140, itext: ""})
    verify(subject.onScreen, "on screen at 1:1")
    ctl.zoom = 4
    verify(!subject.onScreen, "and off it once zoomed in")

    // As does the camera, which is what a pan moves.
    ctl.camX = -2500
    verify(subject.onScreen, "panning to it brings it back")
  }

  function test_paintedShapeFollowsTheme() {
    subject.kind = "ellipse"
    verify(waitForRendering(subject))
    compare(grabImage(subject).pixel(70, 50), Qt.rgba(34/255, 34/255, 34/255, 1))
    ctl.itemFill = "#ff00ff"
    tryVerify(function() { return grabImage(subject).pixel(70, 50) === Qt.rgba(1, 0, 1, 1) })
  }
  function test_edit() {
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, 0)
    keyClick(Qt.Key_A)
    compare(model.get(0).itext, "a")
    ctl.flushCount = 0
    keyClick(Qt.Key_S, Qt.ControlModifier)
    compare(ctl.flushCount, 1)
    keyClick(Qt.Key_Escape)
    compare(ctl.editIndex, -1)
  }
}
