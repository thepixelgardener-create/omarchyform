import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../BoardHistory.js" as History

// Opening a board with a history, the whole way: a real document, its session,
// its writer and the history worker on its own thread, against boards written
// by tests/persistence.js. A history from a newer Omarchyform — pretty-printed,
// so the shell's quick look at its header cannot see the version — must end up
// read-only with its file untouched, whatever is then asked of it; one this
// reads must become editable once read, and keep its history when written.
// The edge-case run pairs a newer board version after history with a malformed
// history baseline, verifying whole-file refusal and worker-error recovery.
ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  property int ticks: 0
  property string newerBefore: ""
  readonly property bool edgeCases: Quickshell.env("OMARCHYFORM_HISTORY_EDGE") === "1"
  readonly property string refusedPath: test.edgeCases ? "future.json" : "newer.json"
  readonly property string editablePath: test.edgeCases ? "broken.json" : "known.json"
  property var newer: null
  property var known: null
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function read(path) { reader.path = ""; reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }

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
  }

  Component {
    id: documents
    BoardDocument { workspace: stubWorkspace }
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      test.ticks++
      if (test.stage === 0) {
        test.newerBefore = test.read(test.dir + "/" + test.refusedPath)
        test.newer = documents.createObject(test, { currentBoard: test.refusedPath })
        test.known = documents.createObject(test, { currentBoard: test.editablePath })
        test.stage = 1
      } else if (test.stage === 1 && test.newer.damaged && test.known.items.count > 0
                 && !test.newer.historyChecking && !test.known.historyChecking) {
        test.check(test.newer.damaged, "a newer history makes the board read-only")
        if (!test.edgeCases)
          test.check(test.newer.damageReason.indexOf("newer Omarchyform") >= 0, "and says why: " + test.newer.damageReason)
        test.check(!test.newer.canEdit, "not editable")
        test.check(test.known.canEdit, "a history this reads leaves the board editable once read")
        test.check(test.known.items.get(0).itext === "one", "loading or recovery keeps the intact live note")
        // Everything that could write the newer board, asked for anyway.
        if (test.newer.items.count > 0) test.newer.items.setProperty(0, "itext", "written anyway")
        test.newer.noteEdit(null)
        test.newer.save(true)
        test.newer.flushSave()
        test.newer.forgetHistory()
        // And an edit to the other, which should be written.
        test.known.items.setProperty(0, "itint", "urgent")
        test.known.noteEdit(null)
        test.known.flushSave()
        test.ticks = 0
        test.stage = 2
      } else if (test.stage === 2 && test.ticks > 10 && !test.known.saving) {
        test.check(test.read(test.dir + "/" + test.refusedPath) === test.newerBefore, "the newer board's file is untouched, byte for byte")
        var saved = JSON.parse(test.read(test.dir + "/" + test.editablePath))
        test.check(saved.items[0].tint === "urgent", "the edit to the other was written")
        test.check(saved.history && saved.history.records.length === (test.edgeCases ? 1 : 2), "with its history and the new record")
        test.check(History.verify(saved.history, saved) === "", "which plays back to it")
        // Release dynamic documents while the QML engine is still running.
        // At engine shutdown Qt can otherwise destroy WorkerScript after its
        // worker thread has exited and hang in the worker's destructor.
        test.newer.destroy()
        test.known.destroy()
        test.ticks = 0
        test.stage = 3
      } else if (test.stage === 3 && test.ticks > 2) {
        console.log(test.edgeCases ? "HISTORY_EDGE_TESTS_PASSED" : "HISTORY_TESTS_PASSED")
        Qt.quit()
      } else if (test.ticks > 200) test.check(false, "stuck at stage " + test.stage)
    }
  }
}
