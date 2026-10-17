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
// The time is wall time and the worst frame, not the time a call took: text
// is laid out when the frame is polished, after any call that set it returns.
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

  // Twenty frames drawn after `step`: its wall time and the worst of them.
  function drawn(step) {
    var started = Date.now()
    step()
    test.frames = 0
    test.worst = 0
    tryVerify(function () { return test.frames >= 20 }, 600000)
    return { ms: Date.now() - started, frame: Math.round(test.worst) }
  }

  function test_open_data() {
    return JSON.parse(read("manifest.json")).map(function (f) {
      return { tag: f.name, file: f.file, opens: f.opens }
    })
  }

  function test_open(row) {
    var raw = read(row.file)
    var data = null
    var nextId = 1
    var saved = ""
    var steps = {}
    function timed(name, step) { var t = Date.now(); var r = step(); steps[name] = (steps[name] || 0) + Date.now() - t; return r }
    // BoardSession.loadBoard, without the process that read the file: what it
    // asks of the text, and what it fills the models with.
    var opened = drawn(function () {
      data = timed("parse", function () { return Store.readFile(raw) })
      var refused = timed("limit", function () {
        return data !== null ? Store.boardLimit(data) : Store.jsonFits(raw) ? "" : Store.TOO_LONG_LIST
      })
      if (refused !== "") data = null
      ctl.items.clear()
      ctl.links.clear()
      if (data) {
        timed("items", function () { Store.fillItems(ctl.items, data.items) })
        timed("links", function () { Store.fillLinks(ctl.links, ctl.items, data.links) })
        nextId = Store.nextFreeId(ctl.items, data.nextId)
        saved = timed("write", function () { return Store.writeFile(ctl.items, ctl.links, nextId) })
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
    // Saved again, and read back: what the next session opens.
    var again = drawn(function () {
      if (saved === "") return
      var back = timed("reparse", function () { return Store.readFile(saved) })
      timed("refill", function () { Store.fillItems(ctl.items, back.items) })
    })
    console.log("HOSTILE " + JSON.stringify({ name: row.tag, opens: data !== null, items: ctl.items.count,
      links: ctl.links.count, open: opened, whole: whole, again: again, steps: steps }))
    compare(data !== null, row.opens, "opens as tests/hostile-fixtures.js says it does")
  }
}
