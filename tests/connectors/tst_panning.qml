import QtQuick
import QtTest
import "../.."
import "../qt"

// A pan of a small board, three notes, a diamond and one connector, with the
// dot pattern: what tests/connectors.js --pan runs once per scale. Three ways
// a step can go: "camera" moves the camera and draws neither canvas, what the
// items alone cost; "drawn" asks both canvases to draw again, as a pan did
// before Board.panned; "panned" is BoardPane.panBy now. Frame: the longest
// frame from the step until what was asked has painted and one more frame is
// shown, the median of 20 steps.
TestCase {
  id: test
  name: "Panning"
  when: windowShown
  visible: true
  width: 1920
  height: 1080

  PaneStub { id: ctl; viewW: test.width; viewH: test.height; culling: true }
  Board { id: surface; ctl: ctl; width: test.width; height: test.height }

  property var frames: []
  FrameAnimation { running: true; onTriggered: test.frames.push(frameTime * 1000) }
  property int gridPaints: 0
  property int linkPaints: 0
  Connections { target: findChild(surface, "connectors"); function onPainted() { test.linkPaints += 1 } }
  Connections { target: findChild(surface, "pattern"); function onPainted() { test.gridPaints += 1 } }

  function note(id, kind, x, y) {
    return { iid: id, kind: kind, ix: x, iy: y, iw: 200, ih: 150, itint: "foreground",
             itexture: "plain", itext: "", ipinned: false, isrc: "" }
  }

  function run(w, h, mode) {
    test.width = w; test.height = h
    surface.width = w; surface.height = h
    ctl.viewW = w; ctl.viewH = h
    ctl.camX = 0; ctl.camY = 0
    surface.repaintGrid(); surface.repaintLinks()
    wait(300)
    var worst = [], drawnBefore = test.gridPaints + test.linkPaints
    for (var i = 0; i < 24; i++) {
      var from = test.frames.length, g = test.gridPaints, l = test.linkPaints
      ctl.camX += 3; ctl.camY += 2
      if (mode === "drawn") {
        surface.repaintGrid(); surface.repaintLinks()
        tryVerify(function () { return test.linkPaints > l && test.gridPaints > g }, 20000)
      } else if (mode === "panned") surface.panned()
      var shown = test.frames.length
      tryVerify(function () { return test.frames.length > shown + (mode === "drawn" ? 0 : 1) }, 20000)
      if (i >= 4) worst.push(Math.max.apply(null, test.frames.slice(from)))
    }
    worst.sort(function (a, b) { return a - b })
    return { median: Math.round(worst[worst.length >> 1]), worst: Math.round(worst[worst.length - 1]),
             paints: test.gridPaints + test.linkPaints - drawnBefore }
  }

  function test_pan() {
    ctl.canvasPattern = "Dots"
    ctl.showGrid = true
    ctl.items.append(note(1, "note", 200, 200))
    ctl.items.append(note(2, "note", 600, 200))
    ctl.items.append(note(3, "note", 200, 500))
    ctl.items.append(note(4, "diamond", 600, 500))
    ctl.links.append({ lfrom: 1, lto: 2 })
    var out = []
    for (var size of [[1100, 700], [1920, 1080]]) {
      var row = { scale: Screen.devicePixelRatio, width: size[0], height: size[1] }
      for (var mode of ["camera", "drawn", "panned"]) row[mode] = run(size[0], size[1], mode)
      out.push(row)
    }
    console.log("PANNING " + JSON.stringify(out))
  }
}
