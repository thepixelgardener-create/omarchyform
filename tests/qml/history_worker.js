// The history worker, as tests/history-bench.js measures it: a board's history
// read, checked against the board, indexed and sought in on a thread of its
// own, so none of that is time the shell stands still for. A template: the
// script fills in where the repository is.
Qt.include("@REPO@/BoardHistory.js")

var history = null
var index = null

WorkerScript.onMessage = function (message) {
  if (message.history !== undefined) {
    var t0 = Date.now()
    history = JSON.parse(message.history)
    var live = JSON.parse(message.live)
    // And the file whole, as the board's worker does to prove the board read
    // in front of the history is all of it.
    if (message.raw) JSON.parse(message.raw)
    var parse = Date.now() - t0
    t0 = Date.now()
    var wrong = checkShape(history)
    index = newIndex(history, 100)
    while (!indexSome(index, history, 1000)) {}
    var end = stateAt(index, history, history.records.length)
    if (wrong === "") wrong = index.error
    if (wrong === "" && !sameState(end, { items: live.items, links: live.links, nextId: live.nextId }))
      wrong = "it does not end at the board as it is"
    WorkerScript.sendMessage({ kind: "ready", parse: parse, verify: Date.now() - t0, error: wrong,
                               records: history.records.length })
    return
  }
  if (message.seek !== undefined) {
    var s0 = Date.now()
    var state = stateAt(index, history, message.seek)
    WorkerScript.sendMessage({ kind: "state", seek: Date.now() - s0, items: state.items, links: state.links,
                               sentAt: Date.now() })
  }
}
