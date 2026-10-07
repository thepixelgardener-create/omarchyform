// A board's history, read on a thread of its own. The board keeps its history
// as text and never parses it on the shell's thread when it opens: that stood
// the shell still for up to 156ms (tests/history-bench.js). This parses it,
// plays it against the board as it is, and answers with what the board needs
// to know: how big it is, where it ends, and whether it can be added to.
// It also trims the oldest records off when a history has grown past its
// limits. Nothing here touches a file: the answers go back as messages, and
// the document decides what to write.
//
// Each request carries a token, and each answer carries it back, so an answer
// about a history the board has since replaced is recognised and dropped.
Qt.include("BoardHistory.js")

function check(message) {
  var answer = { kind: "checked", token: message.token, error: "", unreadable: false, newer: false,
                 bridge: "", count: 0, bytes: 0, last: 0, text: "", reload: false }
  // The board was read from in front of the history, which was left as text.
  // Read the file whole here and prove that was the whole canvas: a board
  // whose keys were moved after the history would have lost them. If it was
  // not, or the file is not JSON at all, the board is read again whole.
  var whole = null
  if (message.raw) {
    try { whole = JSON.parse(message.raw) } catch (e) { whole = null }
    var front = null
    try { front = JSON.parse(message.board) } catch (e) { front = null }
    var same = function (a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    if (!whole || typeof whole !== "object" || !front
        || !same(whole.items, front.items) || !same(whole.links, front.links) || whole.nextId !== front.nextId) {
      answer.reload = true
      return answer
    }
  }
  if (typeof message.history !== "string" || message.history.length > MAX_HISTORY_TEXT) {
    answer.error = "larger than a history can be"
    answer.unreadable = true
    return answer
  }
  var h
  try { h = JSON.parse(message.history) } catch (e) { h = null }
  // What was left as text did not parse, but the file did: something follows
  // the history. It is the file's history, and goes back in this writer's
  // shape.
  var reshaped = false
  if (h === null && whole && whole.history && typeof whole.history === "object") {
    h = whole.history
    reshaped = true
  }
  var shape = checkShape(h)
  if (shape !== "") {
    answer.error = shape
    answer.newer = !!h && typeof h === "object" && h.v > HISTORY_VERSION
    answer.unreadable = !answer.newer
    return answer
  }
  var live
  try { live = JSON.parse(message.board) } catch (e) { live = null }
  if (!live || !Array.isArray(live.items)) {
    answer.error = "the board it belongs to could not be read"
    answer.unreadable = true
    return answer
  }
  var state = { items: live.items, links: live.links || [], nextId: live.nextId }
  // A history laid out by hand cannot be appended to as text; it goes back
  // written the way this writes one, without the record about to be added.
  if (message.normalize || reshaped) answer.text = JSON.stringify(h)
  var w = working(h.base)
  for (var i = 0; i < h.records.length; i++) {
    var wrong = apply(w, h.records[i].p)
    if (wrong !== "") {
      answer.error = "record " + h.records[i].i + " " + wrong
      answer.unreadable = true
      return answer
    }
  }
  // Ends somewhere else: something without history changed the board. The
  // difference is one record, numbered after the last one in the file.
  if (!sameState(stateOf(w), state)) {
    var record = append(h, stateOf(w), state, OUTSIDE, message.now)
    if (record) answer.bridge = JSON.stringify(record)
  }
  var size = measure(h)
  answer.count = size.count
  answer.bytes = size.bytes
  answer.last = size.last
  return answer
}

function shorten(message) {
  var answer = { kind: "trimmed", token: message.token, error: "", text: "", dropped: 0, count: 0, bytes: 0, last: 0 }
  var h
  try { h = JSON.parse(message.history) } catch (e) { h = null }
  var shape = checkShape(h)
  if (shape !== "") { answer.error = shape; return answer }
  answer.dropped = trim(h)
  var size = measure(h)
  answer.count = size.count
  answer.bytes = size.bytes
  answer.last = size.last
  answer.text = JSON.stringify(h)
  return answer
}

WorkerScript.onMessage = function (message) {
  if (message.check !== undefined) WorkerScript.sendMessage(check(message))
  else if (message.trim !== undefined) WorkerScript.sendMessage(shorten(message))
}
