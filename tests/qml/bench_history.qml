import QtQuick
import QtTest
import "@REPO@/BoardHistory.js" as History
import "@REPO@/BoardStore.js" as Store

// tests/history-bench.js in the engine the board runs in. The fixtures are the
// files that script wrote; each is a board with its history, read the way a
// board is read when it is opened. A template: the script fills in where the
// repository and the fixtures are and runs a copy, and this prints one BENCH
// line per fixture.
TestCase {
  id: bench
  name: "HistoryBench"

  ListModel { id: rows }

  // How long the shell's own thread went without a turn while the worker was
  // busy: a timer that should tick every 5ms, and the longest it waited.
  property real lastTick: 0
  property real worstGap: 0
  Timer {
    id: ticker
    interval: 5
    repeat: true
    onTriggered: {
      var t = Date.now()
      if (bench.lastTick > 0) bench.worstGap = Math.max(bench.worstGap, t - bench.lastTick)
      bench.lastTick = t
    }
  }

  property var reply: null
  WorkerScript {
    id: worker
    source: "history_worker.js"
    onMessage: function (message) { bench.reply = message }
  }

  // The shell's memory, as the kernel counts it.
  function memory() {
    var status = bench.read("/proc/self/status")
    var rss = /VmRSS:\s+(\d+)/.exec(status), peak = /VmHWM:\s+(\d+)/.exec(status)
    return { rss: rss ? Math.round(rss[1] / 1024) : -1, peak: peak ? Math.round(peak[1] / 1024) : -1 }
  }

  function read(path) {
    var request = new XMLHttpRequest()
    request.open("GET", "file://" + path, false)
    request.send(null)
    return request.responseText
  }

  function spread(samples) {
    var s = samples.slice().sort(function (a, b) { return a - b })
    return { p50: s[Math.floor(s.length * 0.5)], p95: s[Math.min(s.length - 1, Math.floor(s.length * 0.95))],
             max: s[s.length - 1] }
  }

  // Date.now() counts whole milliseconds, so anything shorter is timed as a
  // run of repeats and divided.
  function each(times, step) {
    var t0 = Date.now()
    for (var i = 0; i < times; i++) step(i)
    return (Date.now() - t0) / times
  }

  function test_history() {
    if ("@MEMORY@" === "yes") return
    var seeds = "@SEEDS@".split(",")
    for (var f = 0; f < seeds.length; f++) {
      var text = bench.read("@DIR@/" + seeds[f] + ".json")
      var t0 = Date.now()
      var parsed = JSON.parse(text)
      var parse = Date.now() - t0
      t0 = Date.now()
      var shape = History.checkShape(parsed.history)
      var shapeMs = Date.now() - t0
      var live = { items: parsed.items, links: parsed.links, nextId: parsed.nextId }
      t0 = Date.now()
      var wrong = History.verify(parsed.history, live)
      var verify = Date.now() - t0
      if (shape !== "" || wrong !== "") { console.error("FAIL: " + seeds[f] + " " + (shape || wrong)); continue }

      var h = parsed.history
      var ix = History.newIndex(h)
      var slices = []
      t0 = Date.now()
      while (true) {
        var s0 = Date.now()
        var done = History.indexSome(ix, h, 200)
        slices.push(Date.now() - s0)
        if (done) break
      }
      var index = Date.now() - t0

      var seeks = []
      var seed = 7
      for (var i = 0; i < 100; i++) {
        seed = (seed * 1103515245 + 12345) % 2147483648
        var at = seed % (h.records.length + 1)
        var q0 = Date.now()
        History.stateAt(ix, h, at)
        seeks.push(Date.now() - q0)
      }
      var seek = bench.spread(seeks)

      // Recording an edit: the patch between two neighbouring boards.
      var pairs = []
      for (var p = 0; p < 20; p++) {
        var k = Math.floor((p + 0.5) * h.records.length / 20)
        pairs.push([History.stateAt(ix, h, k), History.stateAt(ix, h, k + 1)])
      }
      var record = bench.each(20, function (n) { History.diff(pairs[n][0], pairs[n][1]) })

      t0 = Date.now()
      var historyText = JSON.stringify(h)
      var stringify = Date.now() - t0
      // What a save writes: the board as it is now, with the history after
      // it, held already as text and joined rather than written out again.
      t0 = Date.now()
      var liveText = JSON.stringify({ kind: "omarchyform.board", version: 6, nextId: parsed.nextId,
                                      items: parsed.items, links: parsed.links }, null, 2)
      var liveOnly = Date.now() - t0
      t0 = Date.now()
      var fileText = liveText.slice(0, -2) + ',\n  "history": ' + historyText + "\n}\n"
      var join = Date.now() - t0
      t0 = Date.now()
      var same = fileText === text
      var compare = Date.now() - t0

      // What every edit already costs today: the snapshot undo takes.
      rows.clear()
      for (var r = 0; r < parsed.items.length; r++) {
        var it = parsed.items[r]
        rows.append({ iid: it.id, kind: it.kind, ix: it.x, iy: it.y, iw: it.w, ih: it.h, itint: it.tint,
                      itext: it.text, ipinned: it.pinned === true, isrc: it.src })
      }
      var snapshot = bench.each(5, function () { Store.itemRows(rows) })

      console.log("BENCH " + parsed.items.length + " items, " + h.records.length + " records, "
        + (text.length / 1048576).toFixed(2) + " MiB file: parse " + parse + ", shape " + shapeMs
        + ", verify " + verify + ", index " + index + " (max slice " + Math.max.apply(null, slices) + ")"
        + ", seek p95 " + seek.p95 + " max " + seek.max + ", record " + record.toFixed(1)
        + ", undo snapshot " + snapshot.toFixed(1) + ", stringify history " + stringify
        + ", board alone " + liveOnly + ", join " + join + ", compare " + compare)
    }
  }

  // The same fixtures with the history kept off this thread: the board read
  // from the front of the file, the history handed over as text, and states
  // asked for and filled into a model the way a timeline pane would.
  function test_worker() {
    if ("@MEMORY@" === "yes") return
    var marker = '\n  "history": '
    var seeds = "@SEEDS@".split(",")
    for (var f = 0; f < seeds.length; f++) {
      var text = bench.read("@DIR@/" + seeds[f] + ".json")
      var before = bench.memory()
      // Opening a board: the board read in front of its history, the history
      // left as text — what Store.readBoardFile does, timed as it does it.
      var t0 = Date.now()
      var read = Store.readBoardFile(text)
      var split = Date.now() - t0
      var liveText = read.board
      var historyText = read.history
      var live = { items: read.data.items, links: read.data.links, nextId: read.data.nextId }
      var parseBoard = read.split ? 0 : -1
      // What opening the timeline costs on this thread: the history alone.
      t0 = Date.now()
      JSON.parse(historyText)
      var parseHistory = Date.now() - t0

      bench.reply = null
      bench.worstGap = 0
      bench.lastTick = 0
      ticker.start()
      t0 = Date.now()
      worker.sendMessage({ history: historyText, live: liveText, raw: text })
      var send = Date.now() - t0
      tryVerify(function () { return bench.reply !== null && bench.reply.kind === "ready" }, 60000)
      var ready = bench.reply
      var whileReading = bench.worstGap
      if (ready.error !== "") console.error("FAIL: " + seeds[f] + " " + ready.error)

      var arrivals = [], fills = []
      bench.worstGap = 0
      for (var i = 0; i < 10; i++) {
        bench.reply = null
        worker.sendMessage({ seek: Math.floor(ready.records * (i + 0.5) / 10) })
        tryVerify(function () { return bench.reply !== null && bench.reply.kind === "state" }, 10000)
        arrivals.push(Date.now() - bench.reply.sentAt)
        var f0 = Date.now()
        rows.clear()
        var items = bench.reply.items
        for (var r = 0; r < items.length; r++) {
          var it = items[r]
          rows.append({ iid: it.id, kind: it.kind, ix: it.x, iy: it.y, iw: it.w, ih: it.h, itint: it.tint,
                        itext: it.text, ipinned: it.pinned === true, isrc: it.src })
        }
        fills.push(Date.now() - f0)
      }
      ticker.stop()
      var after = bench.memory()
      console.log("BENCH worker, " + live.items.length + " items, " + ready.records + " records, "
        + (text.length / 1048576).toFixed(2) + " MiB file: read the board " + split + (parseBoard < 0 ? " (whole)" : "")
        + ", history here " + parseHistory + ", hand over " + send + ", worker parse " + ready.parse + " + check and index " + ready.verify
        + ", longest stall meanwhile " + whileReading + "; state arrives in p95 " + bench.spread(arrivals).p95
        + ", filled in p95 " + bench.spread(fills).p95 + ", longest stall " + bench.worstGap
        + "; memory " + before.rss + " -> " + after.rss + " MiB (peak " + after.peak + ")")
    }
  }

  // What holding a history costs, in a process that has done nothing else:
  // the board on its own, then with its history read and indexed for
  // seeking. Run once per fixture, so nothing another fixture left behind is
  // counted.
  function test_memory() {
    if ("@MEMORY@" !== "yes") return
    var marker = '\n  "history": '
    var text = bench.read("@DIR@/@SEEDS@.json")
    var at = text.lastIndexOf(marker)
    var live = JSON.parse(text.slice(0, at - 1) + "\n}\n")
    var historyText = text.slice(at + marker.length, text.length - 3)
    text = ""
    gc(); gc()
    var boardOnly = bench.memory().rss
    var h = JSON.parse(historyText)
    gc(); gc()
    var parsed = bench.memory().rss
    var ix = History.newIndex(h)
    while (!History.indexSome(ix, h, 500)) {}
    gc(); gc()
    var indexed = bench.memory().rss
    // A pane looking at an earlier board holds one state of its own.
    var shown = History.stateAt(ix, h, Math.floor(h.records.length / 2))
    gc(); gc()
    var seen = bench.memory().rss
    console.log("BENCH memory, " + live.items.length + " items, " + h.records.length + " records: board "
      + boardOnly + " MiB, + history " + (parsed - boardOnly) + ", + index of " + ix.checkpoints.length
      + " checkpoints " + (indexed - parsed) + ", + one earlier board " + (seen - indexed)
      + " = " + (seen - boardOnly) + " MiB more")
    if (shown.items.length < 0) console.log("")
  }
}
