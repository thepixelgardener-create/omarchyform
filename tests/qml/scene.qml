import QtQuick
import Quickshell
import qs.Commons
import "BoardStore.js" as Store
import "services" as Host

// What the board costs to *draw*, which tests/bench.js does not measure and
// could not: marshalling a board is arithmetic on an array, and drawing one is
// a scene of delegates, bindings and two canvases that re-run every frame.
//
// Frame time rather than a stopwatch around a call. The expensive half of a
// board edit is the binding re-evaluation that follows it, which happens after
// the function returns and so is invisible to any timer wrapped around one.
// The compositor caps a frame at vsync, so a phase that reports the refresh
// interval is one with room to spare; anything above it is dropping frames.
ShellRoot {
  id: bench

  readonly property int size: parseInt(Quickshell.env("OMARCHYFORM_BENCH_ITEMS") || "1000")
  // Every phase is measured over the same number of frames, so the columns
  // compare with each other as well as with a previous run.
  readonly property int framesPerPhase: 60
  readonly property int settleFrames: 20

  property int phase: -1
  property int seen: 0
  property var samples: []
  property var report: []

  // A board of `size` items in a broad grid, one connector per item: the shape
  // tests/bench.js builds, so the two benchmarks describe the same board.
  function build() {
    var rows = []
    var columns = Math.ceil(Math.sqrt(bench.size))
    for (var i = 0; i < bench.size; i++) {
      rows.push({
        id: i + 1, kind: i % 7 === 0 ? "ellipse" : i % 5 === 0 ? "rect" : "note",
        x: (i % columns) * 260, y: Math.floor(i / columns) * 200,
        w: 180, h: 140, tint: "foreground", text: "note " + (i + 1)
      })
    }
    var links = []
    for (var j = 1; j < bench.size; j++) links.push({ from: j, to: j + 1 })
    Store.fillItems(plugin.items, rows)
    Store.fillLinks(plugin.links, plugin.items, links)
    plugin.nextId = bench.size + 1
    plugin.selectOnly(0)
    plugin.resetView()
  }

  // Each phase leaves the board the way the next one wants it, then is
  // recorded for framesPerPhase frames.
  readonly property var phases: [
    { name: "idle", enter: function () {}, step: function () {} },
    {
      name: "pan",
      enter: function () { plugin.resetView() },
      step: function () { plugin.panBy(6, 2) }
    },
    {
      name: "zoom",
      enter: function () { plugin.resetView() },
      // Back and forth, so it stays over the board rather than zooming out of
      // it and measuring an empty screen.
      step: function () { plugin.zoomCentre(bench.seen % 40 < 20 ? 1.02 : 1 / 1.02) }
    },
    {
      name: "drag 1",
      enter: function () { plugin.resetView(); plugin.selectOnly(0) },
      step: function () { plugin.moveTargets(bench.seen % 2 ? 4 : -4, 2) }
    },
    {
      name: "drag all",
      enter: function () { plugin.resetView(); plugin.markAll() },
      step: function () { plugin.moveTargets(bench.seen % 2 ? 4 : -4, 2) }
    },
    {
      name: "mark",
      enter: function () { plugin.markedIds = [] },
      // Marking everything and dropping it again re-evaluates the marked
      // binding on every delegate, twice a cycle.
      step: function () {
        if (bench.seen % 10 === 0) plugin.markAll()
        else if (bench.seen % 10 === 5) plugin.markedIds = []
      }
    },
    {
      name: "find",
      enter: function () { plugin.markedIds = []; plugin.beginFind() },
      // A keystroke at a time, then back to nothing: every delegate re-runs
      // matchesFind on each one.
      step: function () {
        var q = ["n", "no", "not", "note"][Math.floor(Math.max(0, bench.seen) / 8) % 4]
        if (plugin.findQuery !== q) { plugin.endFind(); plugin.beginFind(); for (var i = 0; i < q.length; i++) plugin.extendFind(q[i]) }
      }
    }
  ]

  function mean(list) {
    var total = 0
    for (var i = 0; i < list.length; i++) total += list[i]
    return list.length ? total / list.length : 0
  }

  function percentile(list, p) {
    var sorted = list.slice().sort(function (a, b) { return a - b })
    return sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))] : 0
  }

  function advance() {
    if (bench.phase >= 0) {
      var m = bench.mean(bench.samples)
      bench.report.push({ name: bench.phases[bench.phase].name, mean: m, p95: bench.percentile(bench.samples, 0.95) })
    }
    bench.phase += 1
    bench.samples = []
    bench.seen = -bench.settleFrames
    if (bench.phase >= bench.phases.length) {
      console.log("BENCH items " + bench.size)
      for (var i = 0; i < bench.report.length; i++) {
        var r = bench.report[i]
        console.log("BENCH " + r.name + "\t" + r.mean.toFixed(2) + "\t" + r.p95.toFixed(2))
      }
      console.log("BENCH_DONE")
      Qt.quit()
      return
    }
    bench.phases[bench.phase].enter()
  }

  Host.PluginShellApi {
    id: facade
    pluginId: "thepixelgardener.omarchyform"
    _hide: function (id) { plugin.close(); return true }
  }
  Omarchyform { id: plugin; shell: facade; manifest: ({ id: facade.pluginId }) }

  FrameAnimation {
    id: frames
    running: true
    onTriggered: {
      if (bench.phase < -1) return
      if (bench.phase === -1) return
      bench.phases[bench.phase].step()
      bench.seen += 1
      // The settle frames are stepped but not recorded: the first frame after
      // a phase change carries the cost of the change, not of the phase.
      if (bench.seen > 0) bench.samples.push(frames.frameTime * 1000)
      if (bench.seen >= bench.framesPerPhase) bench.advance()
    }
  }

  // Opening is asynchronous, so the board is built from a timer rather than
  // from Component.onCompleted.
  Timer {
    interval: 50
    repeat: true
    running: true
    property int ticks: 0
    onTriggered: {
      ticks += 1
      if (ticks > 400) { console.error("BENCH_TIMEOUT"); Qt.quit(); return }
      if (bench.phase !== -1) return
      if (!plugin.boardLoaded) return
      if (!plugin.activeBoard) {
        plugin.windowMode = true
        plugin.open("{}")
        return
      }
      if (plugin.items.count === 0) { bench.build(); return }
      running = false
      bench.advance()
    }
  }
}
