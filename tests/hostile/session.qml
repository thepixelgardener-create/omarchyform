import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

// One board from tests/hostile-fixtures.js through a real BoardDocument and
// its BoardSession, the way the shell holds a board: opened, then replaced on
// disk by another process and read again. tests/hostile.js runs it in qs, in a
// scratch folder of its own, and holds what it reports to a budget.
//
// What it reports is the longest the thread was held at once: the widest gap
// between ticks of a 1 ms timer. There is no window and so no frames, and the
// session's work is all on this thread. Nothing here draws the board;
// tst_hostile.qml times that.
ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  property var doc: null
  property real last: 0
  property real worst: 0
  property real started: 0
  property real settled: 0
  property int serial: 0
  property var opened: null

  // reload: the time and the hold, or null for a board shown read-only, which
  // is not read again when its file changes, or a word for one that never
  // landed.
  function report(reload) {
    console.log("SESSION " + JSON.stringify({ open: test.opened, reload: reload, opens: test.doc.boardLoaded,
      items: test.doc.items.count, damaged: test.doc.damaged, conflict: test.doc.diskChanged,
      saveError: test.doc.saveError }))
    Qt.quit()
  }

  // Someone else's version: the command line, an editor or a sync tool,
  // landing by rename the way an atomic write does.
  Process { id: replace; command: ["mv", test.dir + "/changed.json", test.dir + "/board.json"] }

  // What a document reads off the workspace, and no panes.
  QtObject {
    id: stubWorkspace
    readonly property string boardsDir: test.dir
    readonly property string backupsDir: test.dir
    property int autosaveMs: 50
    property bool stateReady: true
    property QtObject library: QtObject {
      property bool showing: false
      property string message: ""
    }
    property var activePane: null
    function backupPathFor(relative) { return test.dir + "/bak__" + relative + ".bak" }
    function lockPathFor(relative) { return test.dir + "/lock__" + relative + ".lock" }
    function fileCommand(action, args) { return ["bash", test.dir + "/BoardFiles.sh", action].concat(args) }
    function writeState() {}
    function panesViewing(doc) { return [] }
    function recheckPictures(names) {}
  }

  Component {
    id: documents
    BoardDocument { workspace: stubWorkspace }
  }

  Timer {
    interval: 1
    repeat: true
    running: true
    onTriggered: {
      var now = Date.now()
      if (test.last > 0) test.worst = Math.max(test.worst, now - test.last)
      test.last = now
      if (test.stage === 0) {
        test.worst = 0
        test.started = now
        test.doc = documents.createObject(test, { currentBoard: "board.json" })
        test.stage = 1
      } else if (test.stage === 1 && !test.doc.opening && (test.doc.boardLoaded || test.doc.damaged)) {
        // In, or shown read-only. A moment longer, for what follows it.
        if (test.settled === 0) test.settled = now
        else if (now - test.settled > 300) {
          test.opened = { ms: test.settled - test.started, worst: test.worst }
          if (!test.doc.boardLoaded) { test.report(null); return }
          test.serial = test.doc.loadSerial
          test.worst = 0
          test.started = now
          test.settled = 0
          replace.running = true
          test.stage = 2
        }
      } else if (test.stage === 2 && (test.doc.diskChanged || test.doc.saveError !== "")) {
        test.report("refused")
      } else if (test.stage === 2 && test.doc.loadSerial > test.serial && !test.doc.opening && test.doc.boardLoaded) {
        if (test.settled === 0) test.settled = now
        else if (now - test.settled > 300) test.report({ ms: test.settled - test.started, worst: test.worst })
      } else if (test.stage === 2 && now - test.started > 120000) {
        test.report("never")
      }
    }
  }
}
