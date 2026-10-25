import QtQuick
import QtTest
import "../.."
import "../qt"
import "../../BoardStore.js" as Store

// Connectors while the board is in use: one board from tests/connectors.js,
// panned, zoomed, selected through and dragged, one step a frame the way a
// pointer delivers them, near (100%) and far out (20%). The real Board draws
// it; the pane is a stub, so each step asks for the connectors' repaint the
// way BoardPane's panBy, zoomAt and a moving Node do.
//
// For each step, frame: the longest frame until the next one, what the eye
// sees. raster: from the end of the connector canvas's onPaint to its
// painted(), Context2D drawing the paths into the canvas's image. The script
// before it is timed apart, once per view, because nothing marks when a
// polish starts: geometry is the board's own connectorsInView walking every
// connector with nothing drawn, and paths is its paintConnectors handing what
// that walk found to a Context2D.
TestCase {
  id: test
  name: "Connectors"
  when: windowShown
  visible: true
  width: 1100
  height: 700

  PaneStub { id: ctl; viewW: test.width; viewH: test.height; culling: true }
  Board { id: surface; ctl: ctl; width: test.width; height: test.height }
  // Where paths are built to be timed, and never shown.
  Canvas { id: scratch; width: test.width; height: test.height; visible: false }

  property var frames: []
  FrameAnimation { running: true; onTriggered: test.frames.push(frameTime * 1000) }

  // Connected after the board's own onPaint, so its handler runs once that
  // script has.
  property var canvas: null
  property int paints: 0
  property real scriptDone: 0
  property real painted: 0
  Connections {
    target: test.canvas
    function onPaint(region) { test.scriptDone = Date.now() }
    function onPainted() { test.painted = Date.now(); test.paints += 1 }
  }

  function read(file) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl(file), false)
    request.send()
    return request.responseText
  }

  function load(raw) {
    var admitted = Store.admitBoard(raw)
    verify(admitted.data, "the board is refused: " + admitted.error)
    var made = Store.itemModelRows(admitted.data.items)
    var at = 0
    while (at < made.length) at = Store.appendRows(ctl.items, made, at, 1000000)
    Store.fillLinks(ctl.links, ctl.items, admitted.data.links)
  }

  // The top-left of the board just inside the window, as `0` puts it.
  function view(zoom) {
    var b = Store.bounds(ctl.items)
    ctl.zoom = zoom
    ctl.camX = 24 - b.minX * zoom
    ctl.camY = surface.canvasTop + 24 - b.minY * zoom
    test.settle()
  }

  function settle() {
    var before = test.paints
    surface.repaintLinks()
    tryVerify(function () { return test.paints > before }, 300000)
    wait(200)
  }

  function summary(values) {
    var sorted = values.slice().sort(function (a, b) { return a - b })
    return { median: Math.round(sorted[Math.floor(sorted.length / 2)]), worst: Math.round(sorted[sorted.length - 1]) }
  }

  function measure(count, step) {
    var frame = [], raster = []
    for (var i = 0; i < count; i++) {
      var from = test.frames.length, before = test.paints
      step(i)
      surface.repaintLinks()
      tryVerify(function () { return test.paints > before }, 300000)
      var drawn = test.frames.length
      tryVerify(function () { return test.frames.length > drawn }, 300000)
      raster.push(test.painted - test.scriptDone)
      frame.push(Math.max.apply(null, test.frames.slice(from)))
    }
    return { frame: summary(frame), raster: summary(raster) }
  }

  // Board.qml's onPaint, in two halves, through the board's own functions:
  // the walk up to the paths, then the paths, handed to a canvas that is
  // never drawn.
  function script() {
    var zoom = ctl.zoom, camX = ctl.camX, camY = ctl.camY
    var head = Math.max(8, 9 * zoom) / zoom
    // The board keeps its index and copies until the models change, so
    // bringing them up to date is not timed.
    surface.indexConnectors()
    var started = Date.now()
    var found = surface.connectorsInView(-camX / zoom, -camY / zoom,
      (surface.width - camX) / zoom, (surface.height - camY) / zoom, head, zoom, -1)
    var shown = found.normal.concat(found.highlighted)
    var walked = Date.now()
    var ctx = scratch.getContext("2d")
    ctx.reset()
    surface.paintConnectors(ctx, shown, zoom, camX, camY)
    var built = Date.now()
    ctx.reset()
    return { geometry: walked - started, paths: built - walked, shown: shown.length }
  }

  // Frames with nothing asked of them: what this renderer takes to draw a
  // frame at all, which the frames of a small board are read against.
  function idle(count) {
    var from = test.frames.length
    tryVerify(function () { return test.frames.length > from + count }, 60000)
    return test.summary(test.frames.slice(from + 1))
  }

  function phases(count) {
    var out = {}
    out.idle = test.idle(count)
    out.script = test.script()
    out.pan = test.measure(count, function (i) { ctl.camX += i % 2 ? -15 : 15 })
    out.zoom = test.measure(count, function (i) { ctl.zoomAt(test.width / 2, test.height / 2, i % 2 ? 1 / 1.1 : 1.1) })
    out.select = test.measure(count, function (i) { ctl.selectedIndex = i % ctl.items.count })
    ctl.selectedIndex = -1
    // The first item: in view near, and in max-links the end of 200 connectors.
    out.drag = test.measure(count, function (i) { ctl.items.setProperty(0, "ix", ctl.items.get(0).ix + (i % 2 ? -12 : 12)) })
    return out
  }

  function test_connectors() {
    var plan = JSON.parse(test.read("generated/plan.json"))
    test.canvas = findChild(surface, "connectors")
    verify(test.canvas, "Board.qml's connector canvas is named \"connectors\"")
    tryVerify(function () { return scratch.available }, 10000)
    test.load(test.read("generated/board.json"))
    compare(ctl.items.count, plan.items)
    compare(ctl.links.count, plan.links)
    test.view(1)
    var near = test.phases(plan.frames)
    test.view(0.2)
    var far = test.phases(plan.frames)
    console.log("CONNECTORS " + JSON.stringify({ name: plan.name, items: ctl.items.count, links: ctl.links.count,
      near: near, far: far }))
  }
}
