import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

// Opening a board Omarchyform 0.4.7 to 0.4.10 wrote with its history, the
// whole way: a real document, its session and its writer, against boards
// written by tests/persistence.js. One this reads is editable as soon as it
// opens, is not written by opening, and loses its history at its first save.
// The file is read as JSON reads it, history and all, so one whose history is
// not even JSON is no board, and one that names a newer version after its
// history, on a line of its own or on the history's, is read-only: each of
// those files is untouched whatever is then asked of it.
ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  property int ticks: 0
  property var before: ({})
  property var future: null
  property var sameline: null
  property var known: null
  property var broken: null
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
    function recheckPictures(names) {}
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
        var kept = ["future.json", "sameline.json", "broken.json"]
        for (var k = 0; k < kept.length; k++) test.before[kept[k]] = test.read(test.dir + "/" + kept[k])
        test.future = documents.createObject(test, { currentBoard: "future.json" })
        test.sameline = documents.createObject(test, { currentBoard: "sameline.json" })
        test.broken = documents.createObject(test, { currentBoard: "broken.json" })
        test.known = documents.createObject(test, { currentBoard: "known.json" })
        test.stage = 1
      } else if (test.stage === 1 && test.future.damaged && test.sameline.damaged && test.broken.damaged
                 && test.known.items.count > 0) {
        test.check(!test.future.canEdit, "a newer version after the history makes the board read-only")
        test.check(!test.sameline.canEdit, "on the history's own line as well")
        test.check(!test.broken.canEdit, "and a history that is not JSON makes no board")
        test.check(test.known.canEdit, "a board with its history is editable as soon as it opens")
        test.check(test.known.items.get(0).itext === "one", "with its note")
        // Everything that could write the others, asked for anyway.
        var refused = [test.future, test.sameline, test.broken]
        for (var r = 0; r < refused.length; r++) {
          refused[r].items.append({ iid: 9, kind: "note", ix: 0, iy: 0, iw: 180, ih: 140, itint: "accent",
                                    itext: "written anyway", ipinned: false, isrc: "", itexture: "plain" })
          refused[r].noteEdit(null)
          refused[r].save(true)
          refused[r].flushSave()
        }
        // And an edit to the board this reads, which should be written.
        test.known.items.setProperty(0, "itint", "urgent")
        test.known.noteEdit(null)
        test.known.flushSave()
        test.ticks = 0
        test.stage = 2
      } else if (test.stage === 2 && test.ticks > 10 && !test.known.saving) {
        for (var name in test.before)
          test.check(test.read(test.dir + "/" + name) === test.before[name], name + " is untouched, byte for byte")
        var text = test.read(test.dir + "/known.json")
        var saved = JSON.parse(text)
        test.check(saved.items[0].tint === "urgent", "the edit was written")
        test.check(saved.history === undefined && text.indexOf('"history"') < 0, "and the history was left out")
        test.check(saved.version === 5, "in the plain format: " + saved.version)
        test.future.destroy()
        test.sameline.destroy()
        test.known.destroy()
        test.broken.destroy()
        test.ticks = 0
        test.stage = 3
      } else if (test.stage === 3 && test.ticks > 2) {
        console.log("LEGACY_TESTS_PASSED")
        Qt.quit()
      } else if (test.ticks > 200) test.check(false, "stuck at stage " + test.stage)
    }
  }
}
