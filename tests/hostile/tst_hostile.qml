import QtQuick
import QtTest
import "../.."
import "../qt"
import "../../BoardStore.js" as Store

// One board from tests/hostile-fixtures.js, opened the way the shell opens a
// board and drawn by the real Board, offscreen. tests/hostile.js runs each
// fixture in a process of its own, so one that never finishes cannot hide the
// rest, and holds what this reports to a budget.
//
// The time is the worst frame, not the time a call took: text is laid out
// when the frame is polished, after any call that set it returns, and a board
// filled in slices takes a while without ever holding the shell up for long.
TestCase {
  id: test
  name: "HostileBoards"
  when: windowShown
  visible: true
  width: 1100
  height: 700

  PaneStub {
    id: ctl
    viewW: test.width
    viewH: test.height
    culling: true
  }

  Board {
    id: surface
    ctl: ctl
    width: test.width
    height: test.height
  }

  property int frames: 0
  property real worst: 0
  FrameAnimation {
    running: true
    onTriggered: { test.frames++; test.worst = Math.max(test.worst, frameTime * 1000) }
  }

  function read(file) {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("generated/" + file), false)
    request.send()
    return request.responseText
  }

  // Twenty frames drawn after `step`: its wall time, and the worst frame from
  // its start, which is how long the shell was held up at once.
  function drawn(step) {
    var started = Date.now()
    test.worst = 0
    step()
    test.frames = 0
    tryVerify(function () { return test.frames >= 20 }, 600000)
    return { ms: Date.now() - started, frame: Math.round(test.worst) }
  }

  function test_open_data() {
    return JSON.parse(read("manifest.json")).map(function (f) {
      return { tag: f.name, file: f.file, opens: f.opens }
    })
  }

  // BoardSession.loadBoard, without the process that read the file: what it
  // asks of the text, then its rows added a slice at a time with the event loop
  // run between slices, as its timer does.
  function open(raw, steps) {
    var t = Date.now()
    var admitted = Store.admitBoard(raw)
    steps.admit = (steps.admit || 0) + Date.now() - t
    ctl.items.clear()
    ctl.links.clear()
    if (!admitted.data) return null
    t = Date.now()
    var made = Store.itemModelRows(admitted.data.items)
    var at = 0, slices = 0
    while (at < made.length) {
      at = Store.appendRows(ctl.items, made, at, Store.FILL_SLICE_MS)
      slices++
      wait(1)
    }
    steps.fill = (steps.fill || 0) + Date.now() - t
    steps.slices = (steps.slices || 0) + slices
    Store.fillLinks(ctl.links, ctl.items, admitted.data.links)
    return admitted.data
  }

  function test_open(row) {
    var raw = read(row.file)
    var data = null
    var saved = ""
    var steps = {}
    // Until the last slice and the connectors are in: when BoardSession would
    // set boardLoaded and the board could be edited. The worst frame is the
    // other number; a board filled in slices can be slow to finish without
    // holding the shell up for long.
    var editable = 0
    var opened = drawn(function () {
      var t = Date.now()
      data = test.open(raw, steps)
      editable = Date.now() - t
      if (data) {
        var t = Date.now()
        saved = Store.writeFile(ctl.items, ctl.links, Store.nextFreeId(ctl.items, data.nextId))
        steps.write = Date.now() - t
      }
      // BoardPane.resetView: the view a board opens at.
      var b = Store.bounds(ctl.items)
      ctl.zoom = 1
      ctl.camX = 24 - (b ? b.minX : 0)
      ctl.camY = surface.canvasTop + 24 - (b ? b.minY : 0)
      surface.repaintGrid()
      surface.repaintLinks()
    })
    // Zoomed out as far as the board goes, which puts the most on screen.
    var whole = drawn(function () {
      ctl.zoom = 0.2
      ctl.camX = 24 - (Store.bounds(ctl.items) || { minX: 0 }).minX * 0.2
      surface.repaintGrid()
      surface.repaintLinks()
    })
    // Saved, and opened again: what the next session opens. BoardSession's
    // finishLoad asks for the connectors once they are in; until this did
    // too, the board opened again here was measured without drawing them.
    var again = drawn(function () {
      if (saved !== "") test.open(saved, steps)
      surface.repaintLinks()
    })
    console.log("HOSTILE " + JSON.stringify({ name: row.tag, opens: data !== null, items: ctl.items.count,
      links: ctl.links.count, editable: editable, open: opened, whole: whole, again: again, steps: steps }))
    compare(data !== null, row.opens, "opens as tests/hostile-fixtures.js says it does")
  }
}
